import { expect, test } from 'vitest';
import { cancelFor } from './keys.ts';
import { Back, Cancelled } from './types.ts';

test('Esc goes back where the caller can go back', () => {
  expect(cancelFor({ name: 'escape' }, true)).toBeInstanceOf(Back);
});

test('Ctrl+C leaves, whether or not the caller can go back', () => {
  expect(cancelFor({ name: 'c', ctrl: true }, true)).toBeInstanceOf(Cancelled);
  expect(cancelFor({ name: 'c', ctrl: true }, false)).toBeInstanceOf(Cancelled);
});

test('Esc leaves where the caller cannot go back, as it always did', () => {
  expect(cancelFor({ name: 'escape' }, false)).toBeInstanceOf(Cancelled);
});

test('no key seen is a plain cancel', () => {
  expect(cancelFor(undefined, true)).toBeInstanceOf(Cancelled);
});
