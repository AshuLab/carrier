import { z } from 'zod';

const Sha = z.string().regex(/^[0-9a-f]{40}$/);
const Pr = z.object({ number: z.number().int().positive(), headSha: Sha });
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
  }),
  z.object({
    ...Common,
    outcome: z.literal('changes_requested'),
    stage: z.literal('review'),
    pr: Pr,
    blockers: z.array(z.object({ title: z.string().min(1), url: z.string().url().optional() })).min(1),
  }),
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
