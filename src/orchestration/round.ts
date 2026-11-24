import { asc, and, eq, gte, inArray, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { executions, slotOf, type Slot } from '../storage/executions.ts';

type Verdicts = Extract<CallerResult, { outcome: 'completed' | 'changes_requested' }>;
/** What a slot of the round concluded: the stored result of its review on the round's head. */
export type Verdict = { slot: Slot; result: Verdicts };
export type Finding = { id?: string; title: string; url?: string };

export type RoundDecision =
  | { kind: 'waiting' }
  | { kind: 'changes_requested' }
  /** Every verdict is a completed review: the observations of all, each with its slot, and the mandatory reviewer's verification (the first slot's). */
  | { kind: 'completed'; observations: (Finding & { slot: Slot })[]; verification: Extract<Verdicts, { outcome: 'completed' }>['verification'] };

/**
 * What a review round comes to, from the verdicts it has on its head, a pure function of the stored results (ADR 0048).
 * It waits while a slot has none; any verdict that asks for changes asks for them, and only when every verdict is a completed review is the round agreed.
 */
export function decideRound(slots: Slot[], verdicts: Verdict[]): RoundDecision {
  if (!slots.every((slot) => verdicts.some((v) => v.slot === slot))) return { kind: 'waiting' };
  const given = slots.map((slot) => verdicts.findLast((v) => v.slot === slot)!);
  const completed = given.flatMap(({ slot, result }) => (result.outcome === 'completed' ? [{ slot, result }] : []));
  if (completed.length < given.length) return { kind: 'changes_requested' };
  return { kind: 'completed', observations: completed.flatMap(({ slot, result }) => (result.observations ?? []).map((o) => ({ ...o, slot }))), verification: completed[0]!.result.verification };
}

/**
 * The verdicts of the round the execution belongs to, read where they are decided: its round and head, in the epic's current attempt, never one set aside.
 * An epic with one reviewer has the execution's own result, as it always did.
 */
export function roundVerdicts(db: Pick<Db, 'select'>, epic: { id: number; startedAt: number | null }, execution: { stage: string; reviewer?: Slot | null; round: number | null; headSha: string | null }, result: Verdicts, several: boolean): Verdict[] {
  if (!several) return [{ slot: slotOf(execution)!, result }];
  return db
    .select({ reviewer: executions.reviewer, result: callerResults.result })
    .from(callerResults)
    .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
    .where(and(eq(executions.epicId, epic.id), eq(executions.stage, 'review'), eq(executions.round, execution.round!), eq(executions.headSha, execution.headSha!), gte(executions.startedAt, epic.startedAt!), inArray(callerResults.outcome, ['completed', 'changes_requested'])))
    .orderBy(asc(sql`executions.rowid`))
    .all()
    .map((row) => ({ slot: slotOf({ stage: 'review', reviewer: row.reviewer })!, result: JSON.parse(row.result) as Verdicts }));
}
