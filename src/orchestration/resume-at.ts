import type { QuotaSnapshot } from '../usage/types.ts';

/** An option the epic ran out of: the model it ran and what the probe said about its account right after. */
export type RanOut = { model: string | null; snapshot: QuotaSnapshot };

// `agy` has one pool per model family, named like "Gemini Models", "Claude and GPT models" or "Gemini 4 Argon": a Claude or GPT model is in the pool that names them,
// any other in the pool whose name (without "models") starts its id, the longest name first, so `gemini-4-argon-high` is not in "Gemini Models".
function agyGroupOf(model: string, groups: (string | undefined)[]) {
  const id = model.toLowerCase();
  const names = [...new Set(groups.filter((g) => g !== undefined))];
  if (/^(claude|gpt)/.test(id)) return names.find((g) => /claude|gpt/i.test(g));
  const key = (name: string) => name.toLowerCase().replace(/ models$/, '').replace(/[^a-z0-9.]+/g, '-');
  return names.filter((g) => id.startsWith(key(g))).sort((a, b) => key(b).length - key(a).length)[0];
}

// The windows that count for one option: those of its account, and for `agy` those of the group of its model. Nothing when the probe did not answer
// or the group is not found.
function windowsOf({ model, snapshot }: RanOut) {
  if (snapshot.status !== 'ok') return undefined;
  const group = snapshot.provider === 'agy' ? agyGroupOf(model ?? '', snapshot.windows.map((w) => w.group)) : undefined;
  if (snapshot.provider === 'agy' && group === undefined) return undefined;
  return snapshot.windows.filter((w) => group === undefined || w.group === group);
}

// When one option's exhausted windows are all back: the latest of the windows at 100%. Nothing when the probe did not answer, no window is full,
// or a full one gives no time (a time is never guessed).
function backAt(ranOut: RanOut) {
  const full = windowsOf(ranOut)?.filter((w) => w.usedPercent >= 100) ?? [];
  if (full.length === 0 || full.some((w) => w.resetsAt === undefined)) return undefined;
  return Math.max(...full.map((w) => w.resetsAt!));
}

/** Whether a fresh read of an option's account shows its window back: it answered, it has windows and none is at 100%. Anything else is not back. */
export function isBack(ranOut: RanOut) {
  const windows = windowsOf(ranOut);
  return windows !== undefined && windows.length > 0 && windows.every((w) => w.usedPercent < 100);
}

/** When an epic stopped on its quota may go on: the earliest time one of the options it ran out of comes back, or undefined when no option says. */
export function resumeAtOf(ranOut: RanOut[]): number | undefined {
  const times = ranOut.map(backAt).filter((t) => t !== undefined);
  return times.length === 0 ? undefined : Math.min(...times);
}
