import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { executions } from './executions.ts';
import { epics } from './schema.ts';

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-'));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

test('applies the Drizzle Kit migration to a temp SQLite file and reads a row back', () => {
  const sqlite = new Database(join(dir, 'test.db'));
  const db = drizzle(sqlite);
  migrate(db, { migrationsFolder: join(import.meta.dirname, 'migrations') });

  db.insert(epics).values({ repo: 'AshuLab/carrier', issue: 3 }).run();

  expect(db.select().from(epics).all()).toEqual([{ id: 1, repo: 'AshuLab/carrier', issue: 3, status: 'queued', queuedAt: 0, startedAt: null, config: null, cancelReason: null, labelPending: false, stage: null, stageStartedAt: null, workspace: null, lastActivityAt: null, lastError: null, round: null, prNumber: null, prHeadSha: null, reviewedSha: null, verification: null, needsHumanReason: null, needsHumanKind: null, title: null, labels: null, branch: null, removedFrom: null, removedReason: null, finishedAt: null }]);
  sqlite.close();
});

test('the executions migration applies to a database that already holds executions: their new columns are null', () => {
  // The migrations up to the one before the agent columns, as a database of an older version has them.
  const full = join(import.meta.dirname, 'migrations');
  const old = join(dir, 'old');
  cpSync(full, old, { recursive: true });
  const journal = JSON.parse(readFileSync(join(full, 'meta', '_journal.json'), 'utf8')) as { entries: { tag: string }[] };
  const index = journal.entries.findIndex((e) => e.tag.startsWith('0009_'));
  writeFileSync(join(old, 'meta', '_journal.json'), JSON.stringify({ ...journal, entries: journal.entries.slice(0, index) }));

  const sqlite = new Database(join(dir, 'old.db'));
  const db = drizzle(sqlite);
  migrate(db, { migrationsFolder: old });
  sqlite.exec(`INSERT INTO epics (repo, issue) VALUES ('AshuLab/carrier', 3);
    INSERT INTO executions (executionId, epicId, stage, status, sessionId, resultPath, startedAt) VALUES ('e1', 1, 'ship', 'finished', 's1', '/r.json', 5)`);

  migrate(db, { migrationsFolder: full });
  expect(db.select().from(executions).all()).toEqual([
    { executionId: 'e1', epicId: 1, stage: 'ship', status: 'finished', sessionId: 's1', error: null, harness: null, model: null, provider: null, workspace: null, round: null, resultPath: '/r.json', startedAt: 5, finishedAt: null },
  ]);
  sqlite.close();
});

test('the epics migration applies to a database that already holds epics: their title, labels, branch and kind are null', () => {
  const full = join(import.meta.dirname, 'migrations');
  const old = join(dir, 'old');
  cpSync(full, old, { recursive: true });
  const journal = JSON.parse(readFileSync(join(full, 'meta', '_journal.json'), 'utf8')) as { entries: { tag: string }[] };
  const index = journal.entries.findIndex((e) => e.tag.startsWith('0010_'));
  writeFileSync(join(old, 'meta', '_journal.json'), JSON.stringify({ ...journal, entries: journal.entries.slice(0, index) }));

  const sqlite = new Database(join(dir, 'old.db'));
  const db = drizzle(sqlite);
  migrate(db, { migrationsFolder: old });
  sqlite.exec(`INSERT INTO epics (repo, issue, status, needsHumanReason) VALUES ('AshuLab/carrier', 3, 'needs_human', 'stuck')`);

  migrate(db, { migrationsFolder: full });
  expect(db.select().from(epics).all()).toMatchObject([{ repo: 'AshuLab/carrier', issue: 3, status: 'needs_human', needsHumanReason: 'stuck', needsHumanKind: null, title: null, labels: null, branch: null }]);
  sqlite.close();
});
