import { expect, test } from 'vitest';
import { formatDuration } from './duration.ts';

test.each([
  [0, '0s'],
  [-5000, '0s'],
  [999, '0s'],
  [45_000, '45s'],
  [185_000, '3m 05s'],
  [3_600_000, '1h 00m'],
  [7_380_000, '2h 03m'],
  [93_600_000, '1d 2h'],
])('formatDuration(%i) is %s', (ms, text) => {
  expect(formatDuration(ms)).toBe(text);
});
