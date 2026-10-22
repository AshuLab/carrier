import { z } from 'zod';

const Sha = z.string().regex(/^[0-9a-f]{40}$/);
const Pr = z.object({ number: z.number().int().positive(), headSha: Sha });
const Id = z.string().min(1).max(64);
const MAX_LIST = 50; // the same cap the `epic` reply puts on a round's blockers
const Resolved = z.array(Id).max(MAX_LIST).optional();
const distinct = (ids: string[]) => new Set(ids).size === ids.length;
const Common = {
  executionId: z.string().min(1),
  repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/),
  epic: z.number().int().positive(),
  stage: z.enum(['ship', 'review', 'fix']),
  summary: z.string().min(1),
};

export const CallerResult = z.discriminatedUnion('outcome', [
  z.object({
    ...Common,
    outcome: z.literal('completed'),
    pr: Pr,
    verification: z.object({ ci: z.enum(['passed', 'absent']), evidence: z.string().min(1) }),
    /** Reviewer only: ids of earlier blockers it considers fixed. Optional, so results that predate it still validate. */
    resolved: Resolved,
  }).refine((r) => distinct(r.resolved ?? []), { message: 'resolved has a duplicate id' }),
  z.object({
    ...Common,
    outcome: z.literal('changes_requested'),
    stage: z.literal('review'),
    pr: Pr,
    // `id` is stable across rounds: the reviewer reuses it when a finding persists. Optional, like `resolved`.
    blockers: z.array(z.object({ id: Id.optional(), title: z.string().min(1), url: z.string().url().optional() })).min(1).max(MAX_LIST),
    resolved: Resolved,
  }).refine((r) => distinct(r.blockers.flatMap(({ id }) => id ?? [])), { message: 'two blockers share an id' })
    .refine((r) => distinct([...r.blockers.flatMap(({ id }) => id ?? []), ...(r.resolved ?? [])]), { message: 'resolved has a duplicate id or one that is still a blocker' }),
  z.object({ ...Common, outcome: z.literal('needs_human'), reason: z.string().min(1) }),
]);
export type CallerResult = z.infer<typeof CallerResult>;

/** What the engine expected when it launched the execution; the caller repeats it back. */
export type Expected = Pick<CallerResult, 'executionId' | 'repo' | 'epic' | 'stage'>;

export type ParseOutcome =
  | { ok: true; result: CallerResult }
  // invalid: not a usable result at all. mismatch: well-formed but for a different execution.
  | { ok: false; kind: 'invalid' | 'mismatch'; message: string };

/** `raw` is the file content, or null when the caller left no file. */
export function parseCallerResult(raw: string | null, expected: Expected): ParseOutcome {
  if (raw === null) return { ok: false, kind: 'invalid', message: 'result file is missing' };
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return { ok: false, kind: 'invalid', message: 'result is not valid JSON' };
  }
  const parsed = CallerResult.safeParse(json);
  if (!parsed.success) return { ok: false, kind: 'invalid', message: z.prettifyError(parsed.error) };
  const result = parsed.data;
  for (const key of ['executionId', 'repo', 'epic', 'stage'] as const) {
    if (result[key] !== expected[key]) {
      return { ok: false, kind: 'mismatch', message: `${key} is ${result[key]}, expected ${expected[key]}` };
    }
  }
  return { ok: true, result };
}
