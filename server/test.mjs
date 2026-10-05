import test from 'node:test';
import assert from 'node:assert/strict';
import { service } from './index.mjs';
import { backupDatabase } from './backup.mjs';
import { DatabaseSync } from 'node:sqlite';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { scryptSync, createHash } from 'node:crypto';

test('accounts isolate documents, reject stale writes, revoke sessions, and bind GitHub once', async t=>{
  process.env.GITHUB_CLIENT_ID='test';process.env.GITHUB_CLIENT_SECRET='test';process.env.PUBLIC_URL='https://api.example.test';
  let challenge;
  const server=service({database:':memory:',githubFetch:async (url,options)=>{
    if(url.includes('access_token')){const payload=JSON.parse(options.body);assert.equal(createHash('sha256').update(payload.code_verifier).digest('base64url'),challenge);assert.equal(payload.redirect_uri,'https://api.example.test/v2/github/callback');}
    return new Response(JSON.stringify(url.includes('access_token')?{access_token:'mock'}:{id:42,login:'octo'}),{status:200});
  }});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));t.after(()=>new Promise(r=>server.close(r)));
  const base=`http://127.0.0.1:${server.address().port}`;
  async function req(path, method='GET',body,token){const r=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:body?JSON.stringify(body):undefined,redirect:'manual'});let data;try{data=await r.json();}catch{}return {status:r.status,data};}
  const first=await req('/v2/auth/register','POST',{username:'alice',password:'password-safe-123'});assert.equal(first.status,201);assert.ok(first.data.token);assert.equal(first.data.account.password,undefined);
  const a=first.data.token;const second=await req('/v2/auth/register','POST',{username:'bob',password:'another-safe-123'});const b=second.data.token;
  assert.equal((await req('/v2/auth/register','POST',{username:'ALICE',password:'password-safe-123'})).status,409);
  assert.equal((await req('/v2/auth/login','POST',{username:'alice',password:'invalid-pass'})).status,401);
  assert.equal((await req('/v2/auth/login','POST',{username:'alice',password:'password-safe-123'})).data.account.id,first.data.account.id);
  assert.equal((await req('/v2/sync','GET',undefined,a)).status,403);
  assert.equal((await req('/v2/sync','PUT',{revision:0,document:{}},a)).status,403);
  const start=await req('/v2/github/bind','POST',{},a);assert.equal(start.status,200);assert.ok(!start.data.url.includes(a));const state=new URL(start.data.url).searchParams.get('state');
  challenge=new URL(start.data.url).searchParams.get('code_challenge');assert.equal(challenge.length,43);assert.equal(new URL(start.data.url).searchParams.get('code_challenge_method'),'S256');
  const callback=await fetch(`${base}/v2/github/callback?state=${state}&code=mock`);assert.equal(callback.status,200);
  assert.equal((await req('/v2/github/callback?state='+state+'&code=mock')).status,400);
  const status=await req('/v2/github/status','POST',{ticket:start.data.ticket},a);assert.equal(status.data.status,'complete');assert.equal(status.data.account.id,first.data.account.id);assert.equal(status.data.account.githubLogin,'octo');
  assert.equal((await req('/v2/github/bind','POST',{},a)).status,409);
  const document={version:2,tasks:[],list:{name:'Alice'},calendar:{name:'Alice Calendar'},reminders:{avatar:'',background:'',message:'独立提醒'},holidays:[{id:'h1',name:'休假',start:'2026-10-01',end:'2026-10-03'}],appearanceUpdated:new Date().toISOString()};
  assert.equal((await req('/v2/sync','PUT',{revision:0,document},a)).status,200);
  const saved=(await req('/v2/sync','GET',undefined,a)).data.document;
  assert.deepEqual(saved.reminders,document.reminders);assert.deepEqual(saved.holidays,document.holidays);
  assert.equal((await req('/v2/sync','PUT',{revision:0,document},a)).status,409);
  assert.equal((await req('/v2/sync','GET',undefined,b)).status,403);
  assert.equal((await req('/v2/sync','GET')).status,401);
  assert.equal((await req('/v2/sync','PUT',{revision:1,document:{...document,tasks:[{id:'bad'}]}},a)).status,400);
  assert.equal((await req('/v2/sync','PUT',{revision:1,document:{...document,tasks:[null]}},a)).status,400);
  const deleted={id:'gone',deleted:true,updated:new Date().toISOString()};
  const compacted=await req('/v2/sync','PUT',{revision:1,document:{...document,tasks:[{...deleted,title:'private deleted text',date:'2026-10-04',scope:'day'}]}},a);
  assert.equal(compacted.status,200);assert.deepEqual(compacted.data.document.tasks,[deleted]);
  const marker={id:'marker',kind:'highlight',text:'',image:'',x:10,y:10,width:100,height:20,rotation:30,layer:-2,points:[[0,.5],[1,.5]],strokeWidth:18,updated:new Date().toISOString(),style:{ink:0x66ffda77}};
  const journal={days:{'2026-10-04':{text:'日记同步',stickers:[],updated:new Date().toISOString()}},board:[marker],style:{pattern:'grid'},height:600,updated:new Date().toISOString()};
  const dateHeaders={'2026-10-04':{color:0x804d83a3,updated:new Date().toISOString()}};
  const extra=await req('/v2/sync','PUT',{revision:2,document:{...document,journals:{'2026-09-28':journal},dateHeaders}},a);
  assert.equal(extra.status,200);
  const legacy=await req('/v2/sync','PUT',{revision:3,document},a);
  assert.equal(legacy.status,200);assert.deepEqual(legacy.data.document.journals,{'2026-09-28':journal});assert.deepEqual(legacy.data.document.dateHeaders,dateHeaders);
  const degraded={...marker,kind:'text'};
  for(const field of ['rotation','layer','points','strokeWidth'])delete degraded[field];
  const compatible=await req('/v2/sync','PUT',{revision:4,document:{...document,journals:{'2026-09-28':{...journal,board:[degraded]}}}},a);
  assert.equal(compatible.status,200);assert.deepEqual(compatible.data.document.journals['2026-09-28'].board,[marker]);
  assert.equal((await req('/v2/auth/login','POST',{username:'alice',password:'x'.repeat(17000)})).status,413);
  const bindB=await req('/v2/github/bind','POST',{},b);challenge=new URL(bindB.data.url).searchParams.get('code_challenge');const stateB=new URL(bindB.data.url).searchParams.get('state');assert.equal((await req('/v2/github/callback?state='+stateB+'&code=mock')).status,409);
  assert.equal((await req('/v2/github/status','POST',{ticket:start.data.ticket},b)).status,410);
  await req('/v2/auth/logout','POST',{},a);assert.equal((await req('/v2/account','GET',undefined,a)).status,401);
});

test('proxy limits isolate clients, and direct connections cannot forge their source', async t => {
  for (const trustProxy of [false, true]) {
    const server = service({ database: ':memory:', trustProxy });
    await new Promise(r => server.listen(0, '127.0.0.1', r));
    t.after(() => new Promise(r => server.close(r)));
    const attempt = async ip => (await fetch(`http://127.0.0.1:${server.address().port}/v2/auth/login`, {
      method: 'POST', headers: { 'content-type': 'application/json', 'x-forwarded-for': ip }, body: '{}',
    })).status;
    for (let i = 0; i < 25; i++) assert.equal(await attempt('192.0.2.1'), 400);
    assert.equal(await attempt('192.0.2.1'), 429);
    assert.equal(await attempt('192.0.2.2'), trustProxy ? 400 : 429);
    // Forwarding chains aren't accepted as a trusted single proxy address.
    assert.equal(await attempt('192.0.2.3, 192.0.2.1'), trustProxy ? 400 : 429);
  }
});

test('GitHub recovery proves identity, preserves data, resets once and revokes every old session', async t => {
  process.env.GITHUB_CLIENT_ID='test';process.env.GITHUB_CLIENT_SECRET='test';process.env.PUBLIC_URL='https://api.example.test';
  let profile = {id: 71, login: 'linked-user'};
  const server=service({database:':memory:',githubFetch: async url => new Response(JSON.stringify(url.includes('access_token') ? {access_token:'mock'} : profile))});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  t.after(()=>new Promise(r=>{server.closeAllConnections();server.close(r);}));
  const base=`http://127.0.0.1:${server.address().port}`;
  const req=async (path,method='GET',body,token)=>{
    const response=await fetch(base+path,{method,headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{})},body:body?JSON.stringify(body):undefined});
    return {status:response.status,data:(response.headers.get('content-type')||'').includes('application/json')?await response.json():await response.text()};
  };
  const callback=flow=>req('/v2/github/callback?state='+new URL(flow.data.url).searchParams.get('state')+'&code=mock');
  const registered=await req('/v2/auth/register','POST',{username:'recovery_user',password:'original-password'});
  const token=registered.data.token, id=registered.data.account.id;
  const second=(await req('/v2/auth/login','POST',{username:'recovery_user',password:'original-password'})).data.token;
  const unbound=await req('/v2/github/recover','POST',{});
  assert.equal((await callback(unbound)).status,404);
  assert.equal((await req('/v2/github/recovery-status','POST',{ticket:unbound.data.ticket})).data.status,'failed');
  const bind=await req('/v2/github/bind','POST',{},token);
  const racing=await req('/v2/github/bind','POST',{},token);
  assert.equal((await callback(bind)).status,200);
  profile={id:72,login:'other-user'};
  assert.equal((await callback(racing)).status,409);
  assert.equal((await req('/v2/account','GET',undefined,token)).data.account.githubLogin,'linked-user');
  profile={id:71,login:'renamed-user'};
  const document={version:2,tasks:[],list:{name:'Keep my notes'},calendar:{name:'Calendar'}};
  assert.equal((await req('/v2/sync','PUT',{revision:0,document},token)).status,200);
  const flow=await req('/v2/github/recover','POST',{});
  assert.equal((await req('/v2/github/recovery-status','POST',{ticket:flow.data.ticket})).data.username,undefined);
  assert.equal((await req('/v2/auth/reset','POST',{ticket:flow.data.ticket,password:'new-password-123'})).status,410);
  assert.equal((await callback(flow)).status,200);
  assert.equal((await callback(flow)).status,400);
  assert.equal((await req('/v2/github/recovery-status','POST',{ticket:flow.data.ticket})).data.username,'recovery_user');
  assert.equal((await req('/v2/auth/reset','POST',{ticket:flow.data.ticket,password:'short'})).status,400);
  const outcomes=await Promise.all([1,2].map(()=>req('/v2/auth/reset','POST',{ticket:flow.data.ticket,password:'new-password-123'})));
  assert.deepEqual(outcomes.map(r=>r.status).sort(),[200,410]);
  for (const old of [token,second]) assert.equal((await req('/v2/account','GET',undefined,old)).status,401);
  assert.equal((await req('/v2/auth/reset','POST',{ticket:flow.data.ticket,password:'replayed-password'})).status,410);
  assert.equal((await req('/v2/auth/login','POST',{username:'recovery_user',password:'original-password'})).status,401);
  const login=await req('/v2/auth/login','POST',{username:'recovery_user',password:'new-password-123'});
  assert.equal(login.data.account.id,id);
  assert.equal((await req('/v2/sync','GET',undefined,login.data.token)).data.document.list.name,'Keep my notes');
  assert.equal((await req('/v2/github/recovery-status','POST',{ticket:'guessed-ticket'})).status,410);
  const cancelled=await req('/v2/github/recover','POST',{});
  assert.equal((await req('/v2/github/callback?state='+new URL(cancelled.data.url).searchParams.get('state')+'&error=access_denied')).status,400);
  assert.equal((await callback(cancelled)).status,400);
});

test('online backup includes committed WAL data and refuses to overwrite existing files', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'needtodo-backup-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const source = join(dir, 'source.sqlite'), target = join(dir, 'backup.sqlite');
  const writer = new DatabaseSync(source);
  try {
    writer.exec("PRAGMA journal_mode=WAL; CREATE TABLE documents(body TEXT); INSERT INTO documents VALUES('saved task');");
    await backupDatabase(source, target);
    const restored = new DatabaseSync(target, { readOnly: true });
    try {
      assert.equal(restored.prepare('SELECT body FROM documents').get().body, 'saved task');
    } finally { restored.close(); }
    await assert.rejects(backupDatabase(source, target), /新的文件/);
    await assert.rejects(backupDatabase(source, source), /新的文件/);
  } finally { writer.close(); }
});

test('existing passwords upgrade after successful login without changing user identity or documents', async t => {
  const dir=mkdtempSync(join(tmpdir(),'needtodo-auth-upgrade-'));
  const path=join(dir,'old.sqlite'), salt='old-random-salt', password='existing-password-123';
  const original=scryptSync(password,salt,64).toString('hex');
  const seed=new DatabaseSync(path);
  seed.exec('CREATE TABLE users(id TEXT PRIMARY KEY,username TEXT NOT NULL UNIQUE,salt TEXT NOT NULL,password TEXT NOT NULL,github_id TEXT UNIQUE,github_login TEXT)');
  seed.prepare('INSERT INTO users(id,username,salt,password,github_id,github_login) VALUES(?,?,?,?,?,?)').run('existing-id','existing_user',salt,original,'old-github-id','octo');
  seed.close();
  const server=service({database:path,trustProxy:true});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  t.after(()=>new Promise(r=>{
    server.closeAllConnections();
    server.close(()=>{rmSync(dir,{recursive:true,force:true});r();});
  }));
  const base=`http://127.0.0.1:${server.address().port}`;
  const login=async (value,ip='192.0.2.1')=>{
    const r=await fetch(base+'/v2/auth/login',{method:'POST',headers:{'content-type':'application/json','x-forwarded-for':ip},body:JSON.stringify({username:'existing_user',password:value})});
    return {status:r.status,data:await r.json()};
  };
  const inspect=new DatabaseSync(path);
  try {
    assert.equal((await login('incorrect-password')).status,401);
    assert.equal(inspect.prepare('SELECT password_params FROM users').get().password_params,null);
    const good=await login(password);
    assert.equal(good.status,200);assert.equal(good.data.account.id,'existing-id');
    const row=inspect.prepare('SELECT password,password_params FROM users').get();
    assert.notEqual(row.password,original);
    assert.deepEqual(JSON.parse(row.password_params),{N:32768,r:8,p:3});
    assert.equal((await login(password)).status,200);
    const document={version:2,tasks:[],list:{name:'preserved'},calendar:{name:'calendar'}};
    const saved=await fetch(base+'/v2/sync',{method:'PUT',headers:{'content-type':'application/json',authorization:`Bearer ${good.data.token}`},body:JSON.stringify({revision:0,document})});
    assert.equal(saved.status,200);
    await saved.arrayBuffer();
    for(let i=0;i<12;i++)assert.equal((await login('incorrect-password',`192.0.2.${i+2}`)).status,401);
    assert.equal((await login(password,'198.51.100.1')).status,429);
    assert.equal(JSON.parse(inspect.prepare('SELECT body FROM documents').get().body).list.name,'preserved');
  }finally{inspect.close();}
});
