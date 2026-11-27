import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { asc } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase, type Db } from './db.ts';
import { executions, slotOf } from './executions.ts';
import { epics } from './schema.ts';

let dir: string;
let db: Db;
let epicId: number;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-executions-'));
  db = openDatabase(join(dir, 'carrier.db'));
  epicId = db.insert(epics).values({ repo: 'AshuLab/a', issue: 1 }).returning().get().id;
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const store = (executionId: string, reviewer: string | null, stage: 'ship' | 'review' | 'lead' = 'review') =>
  db.insert(executions).values({ executionId, epicId, stage, reviewer, resultPath: `/r/${executionId}.json`, startedAt: 1 }).run();

test('an execution stored with the key of an extra reviewer gives the same slot when it is read back', () => {
  store('m', 'reviewer');
  store('s', 'seguridad-api');
  store('u', 'usabilidad');
  store('l', 'lead', 'lead');
  const read = db.select().from(executions).orderBy(asc(executions.startedAt), asc(executions.executionId)).all();
  expect(read.map(slotOf)).toEqual(['lead', 'reviewer', 'seguridad-api', 'usabilidad']);
});

test('the author has no slot, and a review with none written is the mandatory reviewer\'s', () => {
  store('a', null, 'ship');
  store('r', null);
  const [author, review] = db.select().from(executions).orderBy(asc(executions.executionId)).all();
  expect([slotOf(author!), slotOf(review!)]).toEqual([null, 'reviewer']);
});

test('a slot stored with the name of an old position keeps its text: nothing migrates it', () => {
  store('old', 'reviewer-2');
  expect(db.select().from(executions).get()!.reviewer).toBe('reviewer-2');
});
