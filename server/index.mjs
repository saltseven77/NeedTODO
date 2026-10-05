import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes, scrypt as scryptCallback, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isIP } from 'node:net';
const scrypt = promisify(scryptCallback);
const random = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('hex');
const fail = (status, message) => Object.assign(new Error(message), { status });
// OWASP's 32 MiB scrypt profile keeps memory bounded on small instances.
const passwordSettings = Object.freeze({ N: 32768, r: 8, p: 3 });
const legacyPasswordSettings = Object.freeze({ N: 16384, r: 8, p: 1 });

export function service({ database = process.env.DATABASE || './data/needtodo.sqlite', githubFetch = fetch, trustProxy = process.env.TRUST_PROXY === 'true' } = {}) {
  if (database !== ':memory:') mkdirSync(dirname(resolve(database)), { recursive: true });
  const db = new DatabaseSync(database);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000; PRAGMA secure_delete=ON;
    CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, salt TEXT NOT NULL, password TEXT NOT NULL, github_id TEXT UNIQUE, github_login TEXT);
    CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, uid TEXT NOT NULL REFERENCES users(id), expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS documents(uid TEXT PRIMARY KEY REFERENCES users(id), revision INTEGER NOT NULL, body TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS bindings(state TEXT PRIMARY KEY, uid TEXT NOT NULL REFERENCES users(id), ticket TEXT UNIQUE NOT NULL, expires INTEGER NOT NULL, status TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS recoveries(state TEXT PRIMARY KEY, ticket TEXT UNIQUE NOT NULL, uid TEXT REFERENCES users(id), expires INTEGER NOT NULL, status TEXT NOT NULL, verifier TEXT NOT NULL);
  `);
  if (!db.prepare('PRAGMA table_info(users)').all().some(column => column.name === 'password_params')) {
    db.exec('ALTER TABLE users ADD COLUMN password_params TEXT');
  }
  if (!db.prepare('PRAGMA table_info(bindings)').all().some(column => column.name === 'verifier')) {
    db.exec('ALTER TABLE bindings ADD COLUMN verifier TEXT');
  }
  const limits = new Map();
  let hashing = 0;
  async function passwordDigest(password, salt, settings = passwordSettings) {
    if (hashing >= 2) throw fail(429, '登录请求较多，请稍后再试');
    hashing++;
    try { return await scrypt(password, salt, 64, { ...settings, maxmem: 64 * 1024 * 1024 }); }
    finally { hashing--; }
  }
  function clientAddress(req) {
    // Only enable behind our private proxy, which overwrites this header.
    const forwarded = req.headers['x-forwarded-for'];
    if (trustProxy && typeof forwarded === 'string' && isIP(forwarded.trim())) return forwarded.trim();
    return req.socket.remoteAddress;
  }
  function throttle(req, bucket, limit = 25, identity = clientAddress(req)) {
    const key = `${bucket}:${identity}`, now = Date.now();
    let entry = limits.get(key); if (!entry || entry.until < now) { entry = { count: 0, until: now + 60000 }; limits.set(key, entry); }
    if (++entry.count > limit) throw fail(429, '请稍后再试');
    if (limits.size > 10000) for (const [k, v] of limits) if (v.until < now) limits.delete(k);
  }
  function user(req) {
    const bearer = req.headers.authorization;
    if (!bearer?.startsWith('Bearer ')) throw fail(401, '请重新登录');
    const found = db.prepare('SELECT u.* FROM users u JOIN sessions s ON s.uid=u.id WHERE s.token=? AND s.expires>?').get(hash(bearer.slice(7)), Date.now());
    if (!found) throw fail(401, '请重新登录'); return found;
  }
  const account = u => ({ id: u.id, username: u.username, githubLogin: u.github_login || null });
  function session(u) {
    db.prepare('DELETE FROM sessions WHERE expires<=?').run(Date.now());
    const token = random(); db.prepare('INSERT INTO sessions VALUES(?,?,?)').run(hash(token), u.id, Date.now() + 30 * 86400000);
    return { token, account: account(u) };
  }
  async function body(req, maxSize = 16 * 1024) {
    let size = 0; const chunks = [];
    for await (const chunk of req) { size += chunk.length; if (size > maxSize) throw fail(413, '数据过大'); chunks.push(chunk); }
    try { const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw Error(); return parsed; } catch { throw fail(400, '请求无效'); }
  }
  function credentials(b) {
    if (typeof b.username !== 'string' || typeof b.password !== 'string') throw fail(400, '请输入账号和密码');
    const username = b.username.trim().toLowerCase();
    if (!/^[a-z0-9_.-]{3,32}$/.test(username) || b.password.length < 8 || b.password.length > 128) throw fail(400, '账号需为 3–32 位字母、数字或 _ . -，密码需为 8–128 位');
    return { username, password: b.password };
  }
  function validateDocument(d) {
    if (!d || d.version !== 2 || !Array.isArray(d.tasks) || d.tasks.length > 50000 || !d.list || !d.calendar) throw fail(400, '日程数据无效');
    const ids = new Set();
    const tasks = [];
    for (const t of d.tasks) {
      if (!t || typeof t.id !== 'string' || !t.id || t.id.length > 100 || ids.has(t.id) || !Number.isFinite(Date.parse(t.updated))) throw fail(400, '日程数据无效');
      ids.add(t.id);
      if (t.deleted === true) {
        tasks.push({ id: t.id, deleted: true, updated: t.updated });
        continue;
      }
      if (typeof t.title !== 'string' || t.title.length > 160 || !['day','week','month'].includes(t.scope) || !/^\d{4}-\d{2}-\d{2}$/.test(t.date)) throw fail(400, '日程数据无效');
      tasks.push(t);
    }
    const journals=d.journals, dateHeaders=d.dateHeaders;
    const record=value=>value&&typeof value==='object'&&!Array.isArray(value);
    if(journals!==undefined){
      if(!record(journals)||Object.keys(journals).length>5200)throw fail(400,'日记数据无效');
      const stickers=values=>{
        const seen=new Set();
        return values.map(item=>{
          if(!record(item)||typeof item.id!=='string'||!item.id||item.id.length>100||seen.has(item.id)||!Number.isFinite(Date.parse(item.updated)))throw fail(400,'贴纸数据无效');
          seen.add(item.id);
          if(item.deleted===true)return{id:item.id,deleted:true,updated:item.updated};
          if(!['text','image','rect','circle','line','grid','dots','note','list','highlight'].includes(item.kind)||typeof item.text!=='string'||item.text.length>50000||typeof item.image!=='string')throw fail(400,'贴纸数据无效');
          if(item.rotation!==undefined&&(!Number.isFinite(item.rotation)||Math.abs(item.rotation)>360))throw fail(400,'旋转角度无效');
          if(item.layer!==undefined&&(!Number.isSafeInteger(item.layer)||Math.abs(item.layer)>1000000))throw fail(400,'图层无效');
          if(item.points!==undefined&&(!Array.isArray(item.points)||item.points.length>8000||item.points.some(p=>!Array.isArray(p)||p.length!==2||p.some(n=>!Number.isFinite(n)||n<0||n>1))))throw fail(400,'荧光笔数据无效');
          for(const key of ['x','y','width','height'])if(!Number.isFinite(item[key]))throw fail(400,'贴纸位置无效');
          return item;
        });
      };
      for(const [week,page] of Object.entries(journals)){
        if(!/^\d{4}-\d{2}-\d{2}$/.test(week)||!record(page)||!record(page.days)||!Array.isArray(page.board)||page.board.length>2000)throw fail(400,'日记数据无效');
        page.board=stickers(page.board);
        for(const [date,day] of Object.entries(page.days)){
          if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!record(day)||typeof day.text!=='string'||day.text.length>50000||!Array.isArray(day.stickers)||day.stickers.length>1000)throw fail(400,'日记数据无效');
          day.stickers=stickers(day.stickers);
        }
      }
    }
    if(dateHeaders!==undefined){
      if(!record(dateHeaders)||Object.keys(dateHeaders).length>50000)throw fail(400,'日期颜色无效');
      for(const [date,style] of Object.entries(dateHeaders))if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!record(style)||!Number.isFinite(Date.parse(style.updated))||(style.color!==null&&(!Number.isSafeInteger(style.color)||style.color<0||style.color>0xffffffff)))throw fail(400,'日期颜色无效');
    }
    // Client account/token/roles and desktop geometry never enter the document.
    return { version: 2, tasks, list: d.list, calendar: d.calendar, reminders: d.reminders, holidays: d.holidays, appearanceUpdated: d.appearanceUpdated,...(journals!==undefined?{journals}:{}),...(dateHeaders!==undefined?{dateHeaders}:{}) };
  }
  async function route(req, res) {
    const url = new URL(req.url, 'http://localhost');
    const reply = (status, data) => { res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', 'x-content-type-options': 'nosniff' }); res.end(JSON.stringify(data)); };
    if (req.method === 'GET' && url.pathname === '/health') return reply(200, { ok: true, version: 2 });
    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, {'content-type':'text/html; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','content-security-policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"});
      return res.end('<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>泥土豆 · NeedTODO</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#fff;color:#292c32;font:15px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}main{padding:40px}h1{font-size:28px;font-weight:400;letter-spacing:.02em}p{color:#858b94;line-height:1.8}a{color:#477cae;text-decoration:none;font-size:13px}</style><main><h1>泥土豆</h1><p>清单 · 日记 · 跨设备同步</p><a href="/health">账号服务状态</a></main></html>');
    }
    if (req.method === 'POST' && ['/v2/auth/register', '/v2/auth/login'].includes(url.pathname)) {
      throttle(req, 'auth'); const { username, password } = credentials(await body(req));
      if (url.pathname.endsWith('/register')) {
        const salt = random(); const derived = (await passwordDigest(password, salt)).toString('hex'); const id = random();
        try { db.prepare('INSERT INTO users(id,username,salt,password,password_params) VALUES(?,?,?,?,?)').run(id, username, salt, derived, JSON.stringify(passwordSettings)); } catch (e) { if (String(e).includes('UNIQUE')) throw fail(409, '账号已存在'); throw e; }
        return reply(201, session(db.prepare('SELECT * FROM users WHERE id=?').get(id)));
      }
      // Also bound guesses against one account from rotating source addresses.
      throttle(req, 'login-account', 15, hash(username));
      const u = db.prepare('SELECT * FROM users WHERE username=?').get(username);
      const settings = u ? (u.password_params ? JSON.parse(u.password_params) : legacyPasswordSettings) : passwordSettings;
      const derived = await passwordDigest(password, u?.salt ?? 'invalid-user-salt', settings);
      if (!u || !timingSafeEqual(derived, Buffer.from(u.password, 'hex'))) throw fail(401, '账号或密码错误');
      if (!u.password_params) {
        const salt = random(), upgraded = await passwordDigest(password, salt);
        const changed = db.prepare('UPDATE users SET salt=?,password=?,password_params=? WHERE id=? AND password=?').run(salt, upgraded.toString('hex'), JSON.stringify(passwordSettings), u.id, u.password).changes;
        if (!changed) throw fail(401, '账号或密码已更新，请重新登录');
      } else if (db.prepare('SELECT password FROM users WHERE id=?').get(u.id)?.password !== u.password) {
        throw fail(401, '账号或密码已更新，请重新登录');
      }
      return reply(200, session(u));
    }
    if (url.pathname === '/v2/account' && req.method === 'GET') return reply(200, { account: account(user(req)) });
    if (url.pathname === '/v2/auth/logout' && req.method === 'POST') { user(req); db.prepare('DELETE FROM sessions WHERE token=?').run(hash(req.headers.authorization.slice(7))); return reply(200, { ok: true }); }
    if (url.pathname === '/v2/sync' && ['GET','PUT'].includes(req.method)) {
      const u = user(req); throttle(req, 'sync', 240);
      if (!u.github_id) throw fail(403, '绑定 GitHub 后可开启云同步');
      if (req.method === 'GET') { const row = db.prepare('SELECT * FROM documents WHERE uid=?').get(u.id); return reply(200, { revision: row?.revision ?? 0, document: row ? JSON.parse(row.body) : null }); }
      const b = await body(req, 24 * 1024 * 1024); const doc = validateDocument(b.document);
      if (!Number.isSafeInteger(b.revision) || b.revision < 0) throw fail(400, '同步版本无效');
      db.exec('BEGIN IMMEDIATE');
      try {
        const current = db.prepare('SELECT * FROM documents WHERE uid=?').get(u.id);
        if ((current?.revision ?? 0) !== b.revision) { db.exec('ROLLBACK'); return reply(409, { revision: current?.revision ?? 0, document: current ? JSON.parse(current.body) : null }); }
        // Older clients don't know these fields; their sync must not erase them.
        if(current){
          const previous=JSON.parse(current.body);
          for(const key of ['journals','dateHeaders'])if(doc[key]===undefined&&previous[key]!==undefined)doc[key]=previous[key];
          if(doc.journals&&previous.journals){
            const preserve=(incoming,old=[])=>{
              const known=new Map(old.map(item=>[item.id,item]));
              return incoming.map(item=>{
                const existing=known.get(item.id);
                if(!existing||item.deleted)return item;
                // An unchanged object from an older client may have lost fields it cannot read.
                if(item.updated===existing.updated)return existing;
                const merged={...existing,...item,style:{...existing.style,...item.style}};
                if(['note','list','highlight'].includes(existing.kind)&&item.kind==='text'&&item.points===undefined)merged.kind=existing.kind;
                return merged;
              });
            };
            for(const [week,page] of Object.entries(doc.journals)){
              const old=previous.journals[week];if(!old)continue;
              page.board=preserve(page.board,old.board);
              for(const [date,day] of Object.entries(page.days))day.stickers=preserve(day.stickers,old.days?.[date]?.stickers);
            }
          }
        }
        const revision = b.revision + 1; db.prepare('INSERT INTO documents VALUES(?,?,?) ON CONFLICT(uid) DO UPDATE SET revision=excluded.revision,body=excluded.body').run(u.id, revision, JSON.stringify(doc)); db.exec('COMMIT'); return reply(200, { revision, document: doc });
      } catch (e) { if (db.isTransaction) db.exec('ROLLBACK'); throw e; }
    }
    if (['/v2/github/bind', '/v2/github/recover'].includes(url.pathname) && req.method === 'POST') {
      const recovering = url.pathname.endsWith('/recover');
      const u = recovering ? null : user(req); throttle(req, recovering ? 'recover' : 'bind', 10);
      if (u?.github_id) throw fail(409, '此账号已绑定 GitHub');
      if (!process.env.GITHUB_CLIENT_ID || !process.env.GITHUB_CLIENT_SECRET || !process.env.PUBLIC_URL) throw fail(503, 'GitHub 绑定暂未开放');
      const state = random(), ticket = random(), verifier = random();
      const table = recovering ? 'recoveries' : 'bindings';
      db.prepare(`DELETE FROM ${table} WHERE expires<?`).run(Date.now());
      db.prepare(`INSERT INTO ${table}(state,uid,ticket,expires,status,verifier) VALUES(?,?,?,?,?,?)`).run(hash(state), u?.id ?? null, hash(ticket), Date.now()+600000, 'pending', verifier);
      const target = new URL('https://github.com/login/oauth/authorize'); target.searchParams.set('client_id', process.env.GITHUB_CLIENT_ID); target.searchParams.set('redirect_uri', `${process.env.PUBLIC_URL}/v2/github/callback`); target.searchParams.set('state', state); target.searchParams.set('scope', 'read:user');
      target.searchParams.set('code_challenge', createHash('sha256').update(verifier).digest('base64url'));
      target.searchParams.set('code_challenge_method','S256');
      target.searchParams.set('prompt','select_account');
      return reply(200, { url: target.toString(), ticket });
    }
    if (url.pathname === '/v2/github/recovery-status' && req.method === 'POST') {
      throttle(req, 'recovery-poll', 180);
      const b = await body(req);
      if (typeof b.ticket !== 'string') throw fail(400, '授权无效');
      const pending = db.prepare('SELECT * FROM recoveries WHERE ticket=? AND expires>?').get(hash(b.ticket), Date.now());
      if (!pending) throw fail(410, '授权已过期');
      const u = pending.status === 'complete' ? db.prepare('SELECT * FROM users WHERE id=?').get(pending.uid) : null;
      return reply(200, {status: pending.status, ...(u ? {username: u.username} : {})});
    }
    if (url.pathname === '/v2/auth/reset' && req.method === 'POST') {
      throttle(req, 'reset', 10);
      const b = await body(req);
      if (typeof b.ticket !== 'string') throw fail(400, '授权无效');
      const pending = db.prepare('SELECT * FROM recoveries WHERE ticket=? AND expires>? AND status=?').get(hash(b.ticket), Date.now(), 'complete');
      if (!pending) throw fail(410, '请重新通过 GitHub 验证身份');
      const u = db.prepare('SELECT * FROM users WHERE id=?').get(pending.uid);
      const {password} = credentials({username: u.username, password: b.password});
      // Claim before hashing: a recovery ticket can reset a password only once.
      db.prepare('UPDATE recoveries SET status=? WHERE state=?').run('resetting', pending.state);
      try {
        const salt = random(), derived = await passwordDigest(password, salt);
        db.exec('BEGIN IMMEDIATE');
        db.prepare('UPDATE users SET salt=?,password=?,password_params=? WHERE id=?').run(salt, derived.toString('hex'), JSON.stringify(passwordSettings), u.id);
        db.prepare('DELETE FROM sessions WHERE uid=?').run(u.id);
        db.prepare('UPDATE recoveries SET status=? WHERE uid=?').run('consumed', u.id);
        db.exec('COMMIT');
        return reply(200, {username: u.username});
      } catch (e) {
        if (db.isTransaction) db.exec('ROLLBACK');
        db.prepare('UPDATE recoveries SET status=? WHERE state=? AND status=?').run('failed', pending.state, 'resetting');
        throw e;
      }
    }
    if (url.pathname === '/v2/github/status' && req.method === 'POST') {
      const u = user(req), b = await body(req); if (typeof b.ticket !== 'string') throw fail(400, '授权无效');
      const pending = db.prepare('SELECT * FROM bindings WHERE ticket=? AND uid=? AND expires>?').get(hash(b.ticket), u.id, Date.now());
      if (!pending) throw fail(410, '授权已过期'); return reply(200, { status: pending.status, account: account(u) });
    }
    if (url.pathname === '/v2/github/callback' && req.method === 'GET') {
      const key = hash(url.searchParams.get('state') ?? '');
      let table = 'bindings';
      let pending = db.prepare('SELECT * FROM bindings WHERE state=? AND expires>? AND status=?').get(key, Date.now(), 'pending');
      if (!pending) {
        table = 'recoveries';
        pending = db.prepare('SELECT * FROM recoveries WHERE state=? AND expires>? AND status=?').get(key, Date.now(), 'pending');
      }
      if (!pending) throw fail(400, '授权已过期');
      // Consume state before the first network await, preventing callback replay.
      db.prepare(`UPDATE ${table} SET status=? WHERE state=?`).run('processing', key);
      try {
        if (url.searchParams.has('error') || !url.searchParams.get('code')) throw fail(400, '已取消授权');
        const response = await githubFetch('https://github.com/login/oauth/access_token', { method:'POST', headers: { accept:'application/json', 'content-type':'application/json' }, body: JSON.stringify({client_id:process.env.GITHUB_CLIENT_ID,client_secret:process.env.GITHUB_CLIENT_SECRET,code:url.searchParams.get('code'),redirect_uri:`${process.env.PUBLIC_URL}/v2/github/callback`,...(pending.verifier?{code_verifier:pending.verifier}:{})}), signal:AbortSignal.timeout(15000) });
        const token = await response.json(); if (!response.ok || typeof token.access_token !== 'string') throw fail(502, 'GitHub 授权失败');
        const result = await githubFetch('https://api.github.com/user', {headers:{authorization:`Bearer ${token.access_token}`,accept:'application/vnd.github+json','user-agent':'NeedTODO'}, signal:AbortSignal.timeout(15000)});
        const profile = await result.json(); if (!result.ok || !Number.isSafeInteger(profile.id) || typeof profile.login !== 'string') throw fail(502, 'GitHub 账号无效');
        if (table === 'recoveries') {
          const u = db.prepare('SELECT id FROM users WHERE github_id=?').get(String(profile.id));
          if (!u) throw fail(404, '此 GitHub 尚未绑定泥土豆账号');
          db.prepare('UPDATE recoveries SET uid=?,status=? WHERE state=?').run(u.id, 'complete', key);
        } else {
          let changed;
          try { changed = db.prepare('UPDATE users SET github_id=?,github_login=? WHERE id=? AND github_id IS NULL').run(String(profile.id),profile.login,pending.uid).changes; } catch { throw fail(409, '该 GitHub 已绑定其他账号'); }
          if (!changed) throw fail(409, '此账号已绑定 GitHub');
          db.prepare('UPDATE bindings SET status=? WHERE state=?').run('complete',key);
        }
        res.writeHead(200, {'content-type':'text/html; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','referrer-policy':'no-referrer','content-security-policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"});
        return res.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>泥土豆</title><style>body{font:15px system-ui;display:grid;place-content:center;height:80vh;background:#fff;color:#292c32}</style><p>${table === 'recoveries' ? '身份验证完成，请返回泥土豆设置新密码。' : '已绑定 GitHub，可返回泥土豆。'}</p>`);
      } catch(e) { db.prepare(`UPDATE ${table} SET status=? WHERE state=?`).run('failed',key); throw e; }
    }
    throw fail(404, '接口不存在');
  }
  const server = createServer((req,res) => { route(req,res).catch(e => { if (!res.headersSent) { res.writeHead(e.status || 500, {'content-type':'application/json; charset=utf-8','cache-control':'no-store'}); res.end(JSON.stringify({message: e.status ? e.message : '服务暂不可用'})); } }); });
  server.on('close', () => db.close()); server.requestTimeout = 30000;
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const server = service();
  server.listen(Number(process.env.PORT || 8787), process.env.HOST || '127.0.0.1', () => console.log('NeedTODO account service ready'));
  const shutdown = () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  };
  process.once('SIGTERM', shutdown);
  process.once('SIGINT', shutdown);
}
