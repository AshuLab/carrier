import { expect, test } from 'vitest';
import { addUsage } from './usage.ts';

const m = (n: number, costUsd: number | null) => ({ inputTokens: n, cachedInputTokens: n, cacheWriteTokens: n, outputTokens: n, reasoningTokens: n, costUsd });

test('addUsage sums fields, merges byModel by model and keeps cost null only when no side had one', () => {
  expect(addUsage(undefined, undefined)).toBeUndefined();
  expect(addUsage(m(1, null), undefined)).toEqual(m(1, null));
  expect(addUsage(m(1, null), m(2, null))).toEqual(m(3, null));
  expect(addUsage(m(1, null), m(2, 0.5))?.costUsd).toBe(0.5);
  const sum = addUsage({ ...m(1, 1), byModel: { a: m(1, 1) } }, { ...m(2, 1), byModel: { a: m(2, 1), b: m(0, 0) } });
  expect(sum).toEqual({ ...m(3, 2), byModel: { a: m(3, 2), b: m(0, 0) } });
});
