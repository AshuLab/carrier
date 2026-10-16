import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { epics } from '../storage/schema.ts';
import type { Expected } from './caller-result.ts';
import { importResult } from './import-result.ts';

const expected: Expected = { executionId: 'e1', repo: 'AshuLab/carrier', epic: 3, stage: 'ship' };
const raw = JSON.stringify({
  ...expected,
  outcome: 'completed',
  summary: 'done',
  pr: { number: 7, headSha: 'a'.repeat(40) },
  verification: { ci: 'absent', evidence: 'no CI' },
});

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-'));
  db = openDatabase(join(dir, 'carrier.db'));
  db.insert(epics).values({ repo: 'AshuLab/carrier', issue: 3, status: 'running' }).run();
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const status = () => db.select().from(epics).get()?.status;
const advance = (tx: Parameters<Parameters<Db['transaction']>[0]>[0]): void => {
  tx.update(epics).set({ status: 'ready_for_test' }).where(eq(epics.issue, 3)).run();
};

test('stores the result and runs the transition together', () => {
  expect(importResult(db, raw, expected, advance)).toMatchObject({ ok: true });
  const rows = db.select().from(callerResults).all();
  expect(rows).toHaveLength(1);
  expect(rows[0]).toMatchObject({ executionId: 'e1', outcome: 'completed' });
  expect(JSON.parse(rows[0]!.result)).toEqual(JSON.parse(raw));
  expect(status()).toBe('ready_for_test');
});

test('a failing transition leaves neither the result nor the change', () => {
  const fail: typeof advance = (tx) => {
    advance(tx);
    throw new Error('boom');
  };
  expect(() => importResult(db, raw, expected, fail)).toThrow('boom');
  expect(db.select().from(callerResults).all()).toEqual([]);
  expect(status()).toBe('running');
});

test('importing the same execution twice keeps one row and one transition', () => {
  let transitions = 0;
  const count: typeof advance = (tx) => {
    transitions++;
    advance(tx);
  };
  expect(importResult(db, raw, expected, count)).toMatchObject({ ok: true });
  expect(importResult(db, raw, expected, count)).toMatchObject({ ok: true, duplicate: true });
  expect(db.select().from(callerResults).all()).toHaveLength(1);
  expect(transitions).toBe(1);
});

test.each([null, '', '{"outcome":"comp', 'nope'])('invalid file %j persists nothing and does not transition', (bad) => {
  expect(importResult(db, bad, expected, advance)).toMatchObject({ ok: false, kind: 'invalid' });
  expect(db.select().from(callerResults).all()).toEqual([]);
  expect(status()).toBe('running');
});

test('a mismatch persists nothing and does not transition', () => {
  expect(importResult(db, raw, { ...expected, epic: 4 }, advance)).toMatchObject({ ok: false, kind: 'mismatch' });
  expect(db.select().from(callerResults).all()).toEqual([]);
  expect(status()).toBe('running');
});
