import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { openBlockerSlots } from './blockers.ts';

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-blockers-'));
  db = openDatabase(join(dir, 'carrier.db'));
  db.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'running', stage: 'review', startedAt: 10 }).run();
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

const review = (executionId: string, reviewer: 'reviewer' | 'reviewer-2', outcome: 'changes_requested' | 'completed' | 'needs_human', startedAt: number) => {
  db.insert(executions).values({ executionId, epicId: 1, stage: 'review', reviewer, status: 'finished', resultPath: join(dir, executionId), startedAt }).run();
  db.insert(callerResults).values({ executionId, outcome, result: JSON.stringify({ summary: 's', ...(outcome === 'changes_requested' && { blockers: [{ title: 'fix it' }] }) }) }).run();
};

test('the slots whose latest review asked for changes have blockers still open, one that completed after asking does not', () => {
  review('a', 'reviewer', 'changes_requested', 11);
  review('b', 'reviewer-2', 'changes_requested', 12);
  review('c', 'reviewer', 'completed', 13);
  expect(openBlockerSlots(db, { id: 1, startedAt: 10 })).toEqual(['reviewer-2']);
});

test('an answer that cannot conclude is no verdict, so it leaves the blockers of the slot open', () => {
  review('a', 'reviewer-2', 'changes_requested', 11);
  review('b', 'reviewer-2', 'needs_human', 12);
  expect(openBlockerSlots(db, { id: 1, startedAt: 10 })).toEqual(['reviewer-2']);
});

test('the blockers of an earlier attempt of the epic are not open in the one that began after them', () => {
  review('a', 'reviewer-2', 'changes_requested', 5);
  expect(openBlockerSlots(db, { id: 1, startedAt: 10 })).toEqual([]);
});
