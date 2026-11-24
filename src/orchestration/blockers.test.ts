import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { latestBlockers, latestObservations, openBlockerSlots } from './blockers.ts';

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
  db.insert(callerResults).values({ executionId, outcome, result: JSON.stringify({ summary: 's', ...(outcome === 'changes_requested' && { blockers: [{ title: `${executionId} blocks` }] }), ...(outcome === 'completed' && { observations: [{ title: `${executionId} observes` }] }) }) }).run();
};
const ship = (executionId: string, startedAt: number) => db.insert(executions).values({ executionId, epicId: 1, stage: 'ship', status: 'finished', resultPath: join(dir, executionId), startedAt }).run();
const two = { agents: { extraReviewers: [{}] } } as unknown as EffectiveRepoConfig;
const one = { agents: {} } as unknown as EffectiveRepoConfig;

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

test('a resume at review or fix keeps the blockers of the attempt it resumes: the epic starts again later, its ship did not', () => {
  ship('s', 1);
  review('a', 'reviewer-2', 'changes_requested', 11);
  expect(openBlockerSlots(db, { id: 1, startedAt: 50 })).toEqual(['reviewer-2']);
  expect(latestBlockers(db, { id: 1, startedAt: 50, config: two }).map((b) => b.title)).toEqual(['a blocks']);
});

test('a restart from ship leaves the blockers and the observations of the attempt before it behind', () => {
  ship('s1', 1);
  review('a', 'reviewer', 'changes_requested', 11);
  review('b', 'reviewer-2', 'changes_requested', 12);
  review('c', 'reviewer', 'completed', 13);
  ship('s2', 50);
  review('d', 'reviewer', 'completed', 51); // reviewer-2 gave no verdict in the new attempt
  const epic = { id: 1, startedAt: 49, config: two };
  expect(openBlockerSlots(db, epic)).toEqual([]);
  expect(latestBlockers(db, epic)).toEqual([]);
  expect(latestObservations(db, epic)?.map((o) => o.title)).toEqual(['d observes']);
});

test('the reviews of a reviewer removed from the configuration are not the round\'s', () => {
  ship('s', 1);
  review('a', 'reviewer', 'completed', 11);
  review('b', 'reviewer-2', 'changes_requested', 12);
  expect(latestBlockers(db, { id: 1, startedAt: 10, config: one })).toEqual([]);
  expect(latestObservations(db, { id: 1, startedAt: 10, config: one })?.map((o) => o.title)).toEqual(['a observes']);
  expect(latestBlockers(db, { id: 1, startedAt: 10, config: two }).map((b) => b.title)).toEqual(['b blocks']);
});
