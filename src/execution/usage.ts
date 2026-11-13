import type { ExecutionUsage, ModelUsage } from '../storage/executions.ts';

/** A token count read from a CLI's JSON: a finite number, never negative; anything else is 0 and does not fail the run. */
export const tokens = (value: unknown): number => (typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : 0);

/** A cost read from a CLI's JSON: null when it reported none. */
export const cost = (value: unknown): number | null => (typeof value === 'number' && Number.isFinite(value) ? Math.max(0, value) : null);

export const obj = (value: unknown): Record<string, unknown> => (typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {});

const sumCost = (a: number | null, b: number | null) => (a === null && b === null ? null : (a ?? 0) + (b ?? 0));

const addModel = (a: ModelUsage, b: ModelUsage): ModelUsage => ({
  inputTokens: a.inputTokens + b.inputTokens,
  cachedInputTokens: a.cachedInputTokens + b.cachedInputTokens,
  cacheWriteTokens: a.cacheWriteTokens + b.cacheWriteTokens,
  outputTokens: a.outputTokens + b.outputTokens,
  reasoningTokens: a.reasoningTokens + b.reasoningTokens,
  costUsd: sumCost(a.costUsd, b.costUsd),
});

/** The sum of the usage of a run's lines (Codex reports one per turn); undefined only when no line had any. */
export function addUsage(a: ExecutionUsage | undefined, b: ExecutionUsage | undefined): ExecutionUsage | undefined {
  if (a === undefined || b === undefined) return a ?? b;
  const byModel = { ...a.byModel };
  for (const [model, usage] of Object.entries(b.byModel ?? {})) byModel[model] = model in byModel ? addModel(byModel[model]!, usage) : usage;
  return { ...addModel(a, b), ...(Object.keys(byModel).length > 0 && { byModel }) };
}
