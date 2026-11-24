import { index, integer, real, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import { epics } from './schema.ts';

export const executionStates = ['running', 'finished', 'failed', 'timed_out', 'interrupted', 'invalid_result'] as const;

/** The slot of a review execution: the mandatory reviewer, up to three more, and the lead (ADR 0048). */
export const reviewerSlots = ['reviewer', 'reviewer-2', 'reviewer-3', 'reviewer-4', 'lead'] as const;
export type Slot = (typeof reviewerSlots)[number];

/** The slot an execution or its task belongs to: null for the author (ship and fix), and a review with no slot written is the mandatory reviewer's. */
export const slotOf = ({ stage, reviewer }: { stage: string; reviewer?: Slot | null }): Slot | null => reviewer ?? (stage === 'review' ? 'reviewer' : null);

export const failureKinds = ['usage_limit', 'api_error', 'killed', 'crashed', 'spawn_error', 'auth', 'session_lost', 'timeout', 'invalid_result', 'unknown'] as const;

/** Tokens and cost of one model's share of a run; costUsd is null when the CLI reported none. */
export type ModelUsage = { inputTokens: number; cachedInputTokens: number; cacheWriteTokens: number; outputTokens: number; reasoningTokens: number; costUsd: number | null };

/** What a run used, normalized across harnesses; inputTokens excludes the cached ones. */
export type ExecutionUsage = ModelUsage & { byModel?: Record<string, ModelUsage> };

export const executions = sqliteTable('executions', {
  executionId: text().primaryKey(),
  epicId: integer().notNull().references(() => epics.id),
  stage: text({ enum: ['ship', 'review', 'fix', 'lead'] }).notNull(),
  reviewer: text({ enum: reviewerSlots }), // a review's slot; null for ship and fix, and on rows from before it was recorded (read as `reviewer`: see `slotOf`)
  status: text({ enum: executionStates }).notNull().default('running'),
  sessionId: text(), // saved as soon as the runner reports it, not when it ends
  // Why a technical failure ended it; set only for the ones the engine retries or stops for a person (auth_failed).
  error: text(),
  // Why it ended badly (glossary: Failure kind); all null on an execution that ended ok, that Carrier stopped, or that predates them.
  failureKind: text({ enum: failureKinds }),
  failureDetail: text(),
  exitCode: integer(),
  signal: text(),
  hostFreeMemMb: integer(), // only for killed, crashed and unknown
  hostLoad: real(), // one-minute load average, same cases
  // The agent and the folder this execution ran with, written when the row is inserted; null on rows from before they were recorded.
  harness: text(),
  model: text(),
  provider: text(),
  option: text(), // the agent option the role ran on
  configDir: text(), // that option's config folder, absolute; null when it had none
  workspace: text(), // the cwd of the session: what resuming it needs
  round: integer(), // the review round, null for ship
  headSha: text(), // a review's: the commit its checkout was made at, which its result must carry; null for the others and from before it was recorded
  usage: text({ mode: 'json' }).$type<ExecutionUsage>(), // null on a run that reported none, or from before it was recorded
  resultPath: text().notNull(),
  startedAt: integer().notNull(),
  finishedAt: integer(),
}, (table) => [
  // the last execution of an epic is asked for about forty times a snapshot, and the table is never pruned: by epic and start, newest first without a sort
  index('executions_epic').on(table.epicId, table.startedAt),
]);
