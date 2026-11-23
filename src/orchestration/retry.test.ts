import { expect, test } from 'vitest';
import { isOfAttempt } from './retry.ts';

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
