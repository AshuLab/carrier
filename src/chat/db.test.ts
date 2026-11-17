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

test('the turn migration gives every existing turn its session\'s harness, agent and native id', () => {
  // the database as it was before the turns kept them: every migration before theirs applied
  const before = join(dir, 'migrations');
  cpSync(join(import.meta.dirname, 'migrations'), before, { recursive: true });
  const journalPath = join(before, 'meta', '_journal.json');
  const journal = JSON.parse(readFileSync(journalPath, 'utf8')) as { entries: { tag: string }[] };
  const turnMigration = journal.entries.findIndex((entry) => entry.tag.startsWith('0007_'));
  expect(turnMigration).toBeGreaterThan(0);
  journal.entries = journal.entries.slice(0, turnMigration);
  writeFileSync(journalPath, JSON.stringify(journal));
  const file = join(dir, 'chat.db');
  const old = new Database(file);
  migrate(drizzle(old), { migrationsFolder: before });
  old.prepare("insert into sessions (id, agent, harness, folder, nativeId, createdAt, lastActiveAt) values ('s1', 'coder', 'codex', '/work', 'N1', 1, 2), ('s2', 'claude', 'claude', '/work', null, 1, 2)").run();
  old.prepare("insert into chat_turns (sessionId, startedAt, outcome, durationMs, toolCalls) values ('s1', 5, 'ok', 1, 0), ('s1', 6, 'ok', 1, 0), ('s2', 7, 'ok', 1, 0)").run();
  old.close();

  const db = openChatDatabase(file);
  const rows = db.$client.prepare('select sessionId, harness, agent, nativeId from chat_turns order by id').all();
  expect(rows).toEqual([
    { sessionId: 's1', harness: 'codex', agent: 'coder', nativeId: 'N1' },
    { sessionId: 's1', harness: 'codex', agent: 'coder', nativeId: 'N1' },
    { sessionId: 's2', harness: 'claude', agent: 'claude', nativeId: null },
  ]);
  db.$client.close();
});

test('the delegation migration adds the parent and the request id to the sessions, which a parent\'s children share only once per request id', () => {
  const db = openChatDatabase(join(dir, 'chat.db'));
  const insert = db.$client.prepare('insert into sessions (id, agent, harness, folder, createdAt, lastActiveAt, parentSessionId, delegationRequestId) values (?, \'a\', \'claude\', \'/w\', 1, 1, ?, ?)');
  insert.run('p', null, null);
  insert.run('p2', null, null);
  insert.run('c1', 'p', 'r1');
  insert.run('c2', 'p', 'r2');
  insert.run('c3', 'p', null); // no request id, as many as it likes
  insert.run('c4', 'p', null);
  insert.run('c5', 'p2', 'r1'); // another parent's request
  expect(() => insert.run('c6', 'p', 'r1')).toThrow(/UNIQUE/);
  expect(() => insert.run('c7', 'ghost', null)).toThrow(/FOREIGN KEY/);
  db.$client.close();
});
