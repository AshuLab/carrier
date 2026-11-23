import { expect, test } from 'vitest';
import { isOfAttempt, retryWait } from './retry.ts';

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
