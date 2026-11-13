import { eq } from 'drizzle-orm';
import type { ChatDb } from '../chat/db.ts';
import { usagePriceOverrides } from '../chat/schema.ts';

/** US dollars per million tokens. */
export interface Rates {
  input: number;
  cachedInput: number;
  cacheWrite: number;
  output: number;
}

/** The channels of a turn; `input` excludes the cached ones and `reasoning` is a part of `output`, so neither is added twice. */
export interface Tokens {
  input: number;
  cachedInput: number;
  cacheWrite: number;
  output: number;
  reasoning: number;
}

export type PriceOverride = typeof usagePriceOverrides.$inferSelect;

/** What a person sent that cannot be saved as a price: expected, so the caller reports it as is. */
export class PriceOverrideInvalid extends Error {}

/** A model id as the price table and the overrides know it: no provider prefix, context tag, date or effort suffix, dots as dashes. */
export function normalizeModel(model: string): string {
  return model
    .trim()
    .toLowerCase()
    .replace(/^[a-z0-9_-]+\//, '')
    .replace(/\[[^\]]*\]$/, '')
    .replace(/\./g, '-')
    .replace(/-(?:\d{8}|\d{4}-\d{2}-\d{2}|latest)$/, '')
    .replace(/-(?:extra-low|low|medium|high|xhigh|tiered|thinking)$/, '');
}

const rate = (input: number, cachedInput: number, cacheWrite: number, output: number): Rates => ({ input, cachedInput, cacheWrite, output });
const opus = rate(15, 1.5, 18.75, 75);
const sonnet = rate(3, 0.3, 3.75, 15);
const gpt5 = rate(1.25, 0.125, 1.25, 10);
const gemini25Pro = rate(1.25, 0.31, 1.25, 10);

/**
 * The built-in table, by normalized id. A model that is not here is `unpriced` and stays visible: the person maps it or prices it
 * (ponytail: a short list of the common models; a bundled LiteLLM-style catalog replaces it when this one proves too short).
 */
export const catalog: Readonly<Record<string, Rates>> = {
  'claude-opus-4-5': rate(5, 0.5, 6.25, 25),
  'claude-opus-4-1': opus,
  'claude-opus-4': opus,
  'claude-sonnet-4-5': sonnet,
  'claude-sonnet-4': sonnet,
  'claude-haiku-4-5': rate(1, 0.1, 1.25, 5),
  'claude-3-5-haiku': rate(0.8, 0.08, 1, 4),
  'gpt-5': gpt5,
  'gpt-5-codex': gpt5,
  'gpt-5-1': gpt5,
  'gpt-5-1-codex': gpt5,
  'gpt-5-mini': rate(0.25, 0.025, 0.25, 2),
  'gpt-5-nano': rate(0.05, 0.005, 0.05, 0.4),
  'gemini-2-5-pro': gemini25Pro,
  'gemini-2-5-flash': rate(0.3, 0.03, 0.3, 2.5),
  'gemini-2-5-flash-lite': rate(0.1, 0.01, 0.1, 0.4),
  'gemini-3-pro': rate(2, 0.2, 2, 12),
  'gemini-3-flash': rate(0.5, 0.05, 0.5, 3),
};

/** A turn's price: a local model is `$0.00`, an unpriced one has no cost to add up and says so. */
export type Priced = { costUsd: number; status: 'priced' | 'local' } | { costUsd: 0; status: 'unpriced' };

const money = (tokens: Tokens, r: Rates) => (tokens.input * r.input + tokens.cachedInput * r.cachedInput + tokens.cacheWrite * r.cacheWrite + tokens.output * r.output) / 1_000_000;

/** The person's override first, then what the CLI reported, then the table. */
export function priceOf(model: string, tokens: Tokens, overrides: ReadonlyMap<string, PriceOverride>, reportedCostUsd: number | null): Priced {
  const override = overrides.get(normalizeModel(model));
  let rates: Rates | undefined;
  if (override?.mode === 'zero') return { costUsd: 0, status: 'local' };
  if (override?.mode === 'alias') rates = catalog[normalizeModel(override.aliasModel ?? '')];
  else if (override?.mode === 'custom') {
    const input = override.inputUsdPerMillion ?? 0;
    rates = { input, cachedInput: override.cachedInputUsdPerMillion ?? input, cacheWrite: override.cacheWriteUsdPerMillion ?? input, output: override.outputUsdPerMillion ?? 0 };
  } else if (reportedCostUsd !== null) return { costUsd: reportedCostUsd, status: 'priced' };
  else rates = catalog[normalizeModel(model)];
  return rates === undefined ? { costUsd: 0, status: 'unpriced' } : { costUsd: money(tokens, rates), status: 'priced' };
}

export type OverrideRequest =
  | { model: string; action: 'zero' | 'clear' }
  | { model: string; action: 'alias'; aliasModel: string }
  | { model: string; action: 'custom'; inputUsdPerMillion: number; outputUsdPerMillion: number; cachedInputUsdPerMillion?: number; cacheWriteUsdPerMillion?: number };

const validRate = (value: number | undefined) => value === undefined || (Number.isFinite(value) && value >= 0);

/** The overrides saved in `chat.db`; `set` validates before it writes, so the table never holds a rate the pricing cannot use. */
export function createPriceOverrides(db: ChatDb, now: () => number) {
  return {
    list: (): Map<string, PriceOverride> => new Map(db.select().from(usagePriceOverrides).all().map((row) => [row.model, row])),
    set(request: OverrideRequest): void {
      const model = normalizeModel(request.model);
      if (model === '') throw new PriceOverrideInvalid('the model is empty');
      if (request.action === 'clear') return void db.delete(usagePriceOverrides).where(eq(usagePriceOverrides.model, model)).run();
      let values: Partial<PriceOverride> = { mode: 'zero' };
      if (request.action === 'alias') {
        const aliasModel = normalizeModel(request.aliasModel);
        if (aliasModel === '') throw new PriceOverrideInvalid('the alias target is empty');
        values = { mode: 'alias', aliasModel };
      } else if (request.action === 'custom') {
        const { inputUsdPerMillion, outputUsdPerMillion, cachedInputUsdPerMillion, cacheWriteUsdPerMillion } = request;
        if (![inputUsdPerMillion, outputUsdPerMillion].every((rate) => typeof rate === 'number') || ![inputUsdPerMillion, outputUsdPerMillion, cachedInputUsdPerMillion, cacheWriteUsdPerMillion].every(validRate)) throw new PriceOverrideInvalid('the input and output rates are required, and a rate is a finite number, zero or more');
        values = { mode: 'custom', inputUsdPerMillion, outputUsdPerMillion, cachedInputUsdPerMillion: cachedInputUsdPerMillion ?? null, cacheWriteUsdPerMillion: cacheWriteUsdPerMillion ?? null };
      }
      const row = { aliasModel: null, inputUsdPerMillion: null, cachedInputUsdPerMillion: null, cacheWriteUsdPerMillion: null, outputUsdPerMillion: null, mode: 'zero' as const, ...values, model, updatedAt: now() };
      db.insert(usagePriceOverrides).values(row).onConflictDoUpdate({ target: usagePriceOverrides.model, set: row }).run();
    },
  };
}
