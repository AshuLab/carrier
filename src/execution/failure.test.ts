import { expect, test } from 'vitest';
import { failureDetail } from './failure.ts';

// `ghp_` is matched at any length, so only a pattern with a minimum length (`sk-`) shows that the cut comes after the redaction.
test.each([`ghp_${'a'.repeat(36)}`, `sk-${'a'.repeat(40)}`])('a token that a plain cut at 300 characters would split leaves nothing behind (%s)', (token) => {
  const detail = failureDetail(`${'x '.repeat(145)}${token} tail`);
  expect(detail).not.toMatch(/ghp_|sk-|aaaa/);
  expect(detail.length).toBeLessThanOrEqual(300);
});

test('the detail is one line', () => {
  expect(failureDetail('  one\n\ttwo\r\n three  ')).toBe('one two three');
});
