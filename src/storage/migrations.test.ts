import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import { afterEach, beforeEach, expect, test } from 'vitest';
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

  expect(db.select().from(epics).all()).toEqual([{ id: 1, repo: 'AshuLab/carrier', issue: 3, status: 'queued', queuedAt: 0, startedAt: null, config: null, cancelReason: null, labelPending: false, stage: null, round: null, prNumber: null, prHeadSha: null, reviewedSha: null, verification: null, needsHumanReason: null, finishedAt: null }]);
  sqlite.close();
});
