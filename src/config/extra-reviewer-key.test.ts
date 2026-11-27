import { expect, test } from 'vitest';
import { extraReviewerKey, slugPattern } from './extra-reviewer-key.ts';

test.each([
  ['Seguridad API', 'seguridad-api'],
  ['Ñandú', 'nandu'],
  ['123', 'r-123'],
  ['!!!', 'extra'],
  ['Lead', 'lead-2'],
  ['', 'extra'],
  ['  --UX & a11y--  ', 'ux-a11y'],
  ['Revisión de Diseño', 'revision-de-diseno'],
  ['Author', 'author-2'],
  ['Reviewer', 'reviewer-2'],
  ['Lead Reviewer', 'lead-reviewer-2'],
  ['日本語', 'extra'],
])('the name "%s" gives the key "%s"', (name, key) => {
  expect(extraReviewerKey(name)).toBe(key);
});

test('a key that is taken gets -2, then -3, and a reserved word skips to the first free suffix', () => {
  expect(extraReviewerKey('Seguridad API', ['seguridad-api'])).toBe('seguridad-api-2');
  expect(extraReviewerKey('Seguridad API', ['seguridad-api', 'seguridad-api-2'])).toBe('seguridad-api-3');
  expect(extraReviewerKey('Lead', ['lead-2'])).toBe('lead-3');
  expect(extraReviewerKey('Seguridad API', new Set(['other']))).toBe('seguridad-api');
});

test('a long name is cut so the key, suffix included, is at most 40 characters', () => {
  const name = 'a'.repeat(60);
  const first = extraReviewerKey(name);
  expect(first).toBe('a'.repeat(40));
  const second = extraReviewerKey(name, [first]);
  expect(second).toBe(`${'a'.repeat(38)}-2`);
  const tenth = extraReviewerKey(name, [first, second, ...Array.from({ length: 7 }, (_, i) => `${'a'.repeat(38)}-${i + 3}`)]);
  expect(tenth).toBe(`${'a'.repeat(37)}-10`);
  for (const key of [first, second, tenth, extraReviewerKey('123'.repeat(30))]) expect(key).toMatch(slugPattern);
});
