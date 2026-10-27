import { expect, test } from 'vitest';
import { failureDetail } from './failure.ts';

test('a token that a plain cut at 300 characters would split leaves nothing behind', () => {
  const token = `ghp_${'a'.repeat(36)}`;
  const detail = failureDetail(`${'x '.repeat(145)}${token} tail`);
  expect(detail).not.toMatch(/ghp_|aaaa/);
  expect(detail.length).toBeLessThanOrEqual(300);
});

test('the detail is one line', () => {
  expect(failureDetail('  one\n\ttwo\r\n three  ')).toBe('one two three');
});
