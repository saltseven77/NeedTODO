import { backup, DatabaseSync } from 'node:sqlite';
import { mkdirSync, chmodSync, existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function backupDatabase(source, destination) {
  const from = resolve(source), to = resolve(destination);
  if (from === to || existsSync(to)) throw new Error('备份目标必须是新的文件');
  mkdirSync(dirname(to), { recursive: true });
  const db = new DatabaseSync(from, { readOnly: true });
  try {
    await backup(db, to);
    chmodSync(to, 0o600);
  } finally {
    db.close();
  }
  return to;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const source = process.env.DATABASE || './data/needtodo.sqlite';
  const destination = process.argv[2] || `${dirname(source)}/backups/needtodo-${new Date().toISOString().replaceAll(':', '-')}.sqlite`;
  console.log(`备份完成：${await backupDatabase(source, destination)}`);
}
