import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openChatDatabase } from './db.ts';

let dir: string;
beforeEach(() => void (dir = mkdtempSync(join(tmpdir(), 'db-'))));
afterEach(() => rmSync(dir, { recursive: true, force: true }));

test('the worktree migration leaves every existing session a folder session', () => {
  // the database as it was before the worktree columns: only the first three migrations applied
  const before = join(dir, 'migrations');
  cpSync(join(import.meta.dirname, 'migrations'), before, { recursive: true });
  const journalPath = join(before, 'meta', '_journal.json');
  const journal = JSON.parse(readFileSync(journalPath, 'utf8')) as { entries: { tag: string }[] };
  expect(journal.entries.length).toBeGreaterThan(3);
  journal.entries = journal.entries.slice(0, 3);
  writeFileSync(journalPath, JSON.stringify(journal));
  const file = join(dir, 'chat.db');
  const old = new Database(file);
  migrate(drizzle(old), { migrationsFolder: before });
  old.prepare("insert into sessions (id, agent, harness, folder, createdAt, lastActiveAt) values ('s1', 'claude', 'claude', '/work', 1, 2)").run();
  old.close();

  const db = openChatDatabase(file);
  const row = db.$client.prepare('select * from sessions').get();
  expect(row).toMatchObject({ id: 's1', folder: '/work', workspaceKind: 'folder', worktreeBranch: null, worktreeFrom: null, worktreeBase: null, worktreePath: null });
  db.$client.close();
});
