import { expect, test } from 'vitest';
import { countPorcelain } from './workspace.ts';
import { parseCount } from './worktree.ts';

test('parseCount reads the number rev-list --count printed, and 0 for anything else', () => {
  expect(parseCount('3\n')).toBe(3);
  expect(parseCount('0\n')).toBe(0);
  expect(parseCount('')).toBe(0);
  expect(parseCount('fatal')).toBe(0);
});

test('dirty is the number of lines git status --porcelain prints', () => {
  expect(countPorcelain('')).toBe(0);
  expect(countPorcelain(' M a.ts\n?? b.ts\nA  c.ts\n')).toBe(3);
});
