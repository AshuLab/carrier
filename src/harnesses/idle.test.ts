import { expect, test } from 'vitest';
import { isIdle } from './idle.ts';

test('idle only once the silence reaches the limit', () => {
  expect(isIdle(1000 + 59_999, 1000, 60_000)).toBe(false); // just under
  expect(isIdle(1000 + 60_000, 1000, 60_000)).toBe(true); // exactly at
  expect(isIdle(1000 + 60_001, 1000, 60_000)).toBe(true); // just over
});

test('without the setting it is never idle', () => {
  expect(isIdle(10 ** 12, 0, undefined)).toBe(false);
});
