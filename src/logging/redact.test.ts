import { expect, test } from 'vitest';
import { redact } from './redact.ts';
import { secretFixtures } from './secrets.fixture.ts';

test.each(Object.entries(secretFixtures))('redacts %s', (_shape, { text, secret }) => {
  const out = redact(text);
  expect(out).not.toContain(secret);
  expect(out).toContain('[redacted]');
});

test('leaves ordinary text alone', () => {
  expect(redact('ghost_town epic 7 github.com')).toBe('ghost_town epic 7 github.com');
  expect(redact('if (key === "a") { return tokens.length }')).toBe('if (key === "a") { return tokens.length }');
  expect(redact('skip-this-task and sk-short')).toBe('skip-this-task and sk-short');
});
