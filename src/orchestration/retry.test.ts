import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { earliestRetryDue, failingBesides, failureStreak, isOfAttempt, lastBySlot, retryDue, retryWait } from './retry.ts';

test('an epic with no start has no attempt: no execution is of it', () => {
  expect(isOfAttempt({ startedAt: 0 }, { startedAt: null })).toBe(false);
  expect(isOfAttempt({ startedAt: 100 }, { startedAt: null })).toBe(false);
});

test('an execution exactly at the start of the epic is of its attempt, one before it is not', () => {
  expect(isOfAttempt({ startedAt: 100 }, { startedAt: 100 })).toBe(true);
  expect(isOfAttempt({ startedAt: 99 }, { startedAt: 100 })).toBe(false);
  expect(isOfAttempt({ startedAt: 101 }, { startedAt: 100 })).toBe(true);
});

test('a restarted epic starts a new attempt: what ran before its new start is no longer of it', () => {
  const execution = { startedAt: 100 };
  expect(isOfAttempt(execution, { startedAt: 50 })).toBe(true);
  expect(isOfAttempt(execution, { startedAt: 200 })).toBe(false);
});

const streakOf = (...kinds: (string | null)[]) => kinds.map((failureKind) => ({ failureKind }));

test('the n-th retry of an api_error waits 30 seconds, 2 minutes, then 10 minutes, and the last wait repeats', () => {
  const waits = [1, 2, 3, 4, 5].map((n) => retryWait(streakOf(...Array(n).fill('api_error'))));
  expect(waits).toEqual([30_000, 120_000, 600_000, 600_000, 600_000]);
});

test('a process that died, or any failure that is not an api_error, waits nothing at any position', () => {
  for (const kind of ['killed', 'crashed', 'spawn_error', 'session_lost', 'invalid_result', 'unknown', null]) {
    expect([1, 2, 3, 4].map((n) => retryWait(streakOf(...Array(n).fill(kind))))).toEqual([0, 0, 0, 0]);
  }
});

test('when failures of different kinds mix, the wait is by the kind of the one that just ended and its position in the streak', () => {
  expect(retryWait(streakOf('api_error', 'crashed'))).toBe(120_000);
  expect(retryWait(streakOf('api_error', 'crashed', 'killed'))).toBe(600_000);
  expect(retryWait(streakOf('crashed', 'api_error', 'api_error'))).toBe(0);
  expect(retryWait(streakOf('killed', 'api_error'))).toBe(0);
  expect(retryWait([])).toBe(0);
});

// The retry streak is of the slot: rows of two review slots interleave in the table, and neither extends or breaks the other's.
let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-retry-'));
  db = openDatabase(join(dir, 'carrier.db'));
  db.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'running', startedAt: 100 }).run();
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});
const epic = { id: 1, startedAt: 100 };
const failed = { status: 'failed', error: 'boom', failureKind: 'crashed' } as const;
const row = (executionId: string, reviewer: 'reviewer' | 'reviewer-2' | null, extra: Partial<typeof executions.$inferInsert> = {}) =>
  db.insert(executions).values({ executionId, epicId: 1, stage: reviewer === null ? 'ship' : 'review', reviewer, status: 'finished', resultPath: '/r.json', startedAt: 100, ...extra }).run();
const idsOf = (list: { executionId: string }[]) => list.map((e) => e.executionId);

test('the streak of a slot is not extended by the failures of another slot, and not broken by what another slot did well', () => {
  row('a1', 'reviewer', failed);
  row('b1', 'reviewer-2', failed);
  row('a2', 'reviewer', failed);
  row('b2', 'reviewer-2'); // the extra reviewer recovered: its streak ends
  row('a3', 'reviewer', failed);
  row('b3', 'reviewer-2', failed);

  expect(idsOf(failureStreak(db, epic, 'reviewer'))).toEqual(['a3', 'a2', 'a1']);
  expect(idsOf(failureStreak(db, epic, 'reviewer-2'))).toEqual(['b3']);
});

test('a slot that ended well has no streak whatever the other slots did after, and the author is a slot of its own', () => {
  row('a1', 'reviewer', failed);
  row('a2', 'reviewer');
  row('b1', 'reviewer-2', failed);
  row('s1', null, failed);

  expect(failureStreak(db, epic, 'reviewer')).toEqual([]);
  expect(idsOf(failureStreak(db, epic, null))).toEqual(['s1']);
  expect(idsOf(failureStreak(db, epic))).toEqual(['s1']); // the author's by default
});

test('a review row with no slot written is the mandatory reviewer\'s, and an execution of an earlier attempt is of no streak', () => {
  row('old', 'reviewer', { ...failed, startedAt: 99 });
  row('a1', null, { ...failed, stage: 'review' });
  expect(idsOf(failureStreak(db, epic, 'reviewer'))).toEqual(['a1']);
});

test('the last execution of each slot is of the attempt, the author first, and a running retry does not hide the failure it replaces', () => {
  row('s1', null);
  row('b1', 'reviewer-2', failed);
  row('a1', 'reviewer', { startedAt: 99 }); // another attempt's
  row('a2', 'reviewer', { status: 'running' });

  expect(idsOf(lastBySlot(db, epic))).toEqual(['s1', 'a2', 'b1']);
  expect(idsOf(lastBySlot(db, epic, { ended: true }))).toEqual(['s1', 'b1']);
  expect(failingBesides(db, epic, 'reviewer')).toBe(true); // reviewer-2 is still recovering
  expect(failingBesides(db, epic, 'reviewer-2')).toBe(false);
});

test('the due time of each slot is its own, and an epic shows the earliest of the slots that wait for one', () => {
  const apiError = { ...failed, failureKind: 'api_error' } as const;
  row('a1', 'reviewer', { ...apiError, finishedAt: 1_000 }); // first failure of the streak: 30 s
  row('b1', 'reviewer-2', { ...apiError, finishedAt: 500 });
  row('b2', 'reviewer-2', { ...apiError, finishedAt: 600 }); // second: 2 min
  row('s1', null, { ...failed, finishedAt: 50 }); // a crash waits nothing

  expect(retryDue(db, epic, 'reviewer')).toBe(31_000);
  expect(retryDue(db, epic, 'reviewer-2')).toBe(120_600);
  expect(retryDue(db, epic, null)).toBeNull();
  expect(earliestRetryDue(db, epic)).toBe(31_000);
  expect(earliestRetryDue(db, epic, ['reviewer'])).toBe(120_600);
  expect(earliestRetryDue(db, epic, ['reviewer', 'reviewer-2'])).toBeNull();
});
