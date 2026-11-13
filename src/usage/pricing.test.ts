import { expect, test } from 'vitest';
import { openChatDatabase } from '../chat/db.ts';
import { PriceOverrideInvalid, createPriceOverrides, normalizeModel, priceOf, type Tokens } from './pricing.ts';

const million: Tokens = { input: 1_000_000, cachedInput: 1_000_000, cacheWrite: 1_000_000, output: 1_000_000, reasoning: 0 };
const overridesIn = () => {
  const db = openChatDatabase(':memory:');
  let now = 1000;
  return createPriceOverrides(db, () => now++);
};

test('a model id loses its prefix, date, context tag and effort suffix', () => {
  expect(normalizeModel('anthropic/Claude-Sonnet-4.5-20250929')).toBe('claude-sonnet-4-5');
  expect(normalizeModel('claude-opus-4-5[1m]')).toBe('claude-opus-4-5');
  expect(normalizeModel('gemini-3.7-flash-high')).toBe('gemini-3-7-flash');
  expect(normalizeModel('gpt-5-2025-08-07')).toBe('gpt-5');
});

test('the table prices a known model and an unknown cloud model is unpriced, not $0.00', () => {
  expect(priceOf('claude-sonnet-4-5-20250929', million, new Map(), null)).toEqual({ costUsd: 3 + 0.3 + 3.75 + 15, status: 'priced' });
  expect(priceOf('some-new-model', million, new Map(), null)).toEqual({ costUsd: 0, status: 'unpriced' });
});

test('zero, alias and custom overrides are applied ahead of the table and of a reported cost; clear takes them back', () => {
  const overrides = overridesIn();
  overrides.set({ model: 'claude-sonnet-4-5', action: 'zero' });
  expect(priceOf('claude-sonnet-4-5', million, overrides.list(), 9)).toEqual({ costUsd: 0, status: 'local' });

  overrides.set({ model: 'some-new-model', action: 'alias', aliasModel: 'Claude-Haiku-4-5' });
  expect(priceOf('some-new-model', million, overrides.list(), null)).toEqual({ costUsd: 1 + 0.1 + 1.25 + 5, status: 'priced' });
  overrides.set({ model: 'some-new-model', action: 'alias', aliasModel: 'not-in-the-table' });
  expect(priceOf('some-new-model', million, overrides.list(), null).status).toBe('unpriced');

  overrides.set({ model: 'some-new-model', action: 'custom', inputUsdPerMillion: 2, outputUsdPerMillion: 4 });
  expect(priceOf('some-new-model', million, overrides.list(), null)).toEqual({ costUsd: 2 + 2 + 2 + 4, status: 'priced' }); // cached and cache write fall back to the input rate
  overrides.set({ model: 'some-new-model', action: 'custom', inputUsdPerMillion: 2, outputUsdPerMillion: 4, cachedInputUsdPerMillion: 0.5, cacheWriteUsdPerMillion: 1 });
  expect(priceOf('some-new-model', million, overrides.list(), null).costUsd).toBe(2 + 0.5 + 1 + 4);
  expect(overrides.list().size).toBe(2);

  overrides.set({ model: 'some-new-model', action: 'clear' });
  overrides.set({ model: 'claude-sonnet-4-5', action: 'clear' });
  expect(overrides.list().size).toBe(0);
  expect(priceOf('some-new-model', million, overrides.list(), null).status).toBe('unpriced');
});

test('an invalid override is refused and nothing is saved', () => {
  const overrides = overridesIn();
  const refused = (request: Parameters<typeof overrides.set>[0]) => expect(() => overrides.set(request)).toThrow(PriceOverrideInvalid);
  refused({ model: '  ', action: 'zero' });
  refused({ model: 'm', action: 'alias', aliasModel: '  ' });
  refused({ model: 'm', action: 'custom', inputUsdPerMillion: -1, outputUsdPerMillion: 1 });
  refused({ model: 'm', action: 'custom', inputUsdPerMillion: 1, outputUsdPerMillion: Number.NaN });
  refused({ model: 'm', action: 'custom', inputUsdPerMillion: 1, outputUsdPerMillion: Number.POSITIVE_INFINITY });
  refused({ model: 'm', action: 'custom', inputUsdPerMillion: 1, outputUsdPerMillion: 1, cacheWriteUsdPerMillion: -0.1 });
  refused({ model: 'm', action: 'custom', inputUsdPerMillion: 1 } as never);
  expect(overrides.list().size).toBe(0);
});
