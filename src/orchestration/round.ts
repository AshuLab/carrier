import { asc, and, eq, gte, inArray, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { epicEvents } from '../storage/events.ts';
import { executions, slotOf, type Slot } from '../storage/executions.ts';

type Verdicts = Extract<CallerResult, { outcome: 'completed' | 'changes_requested' }>;
/** What a slot of the round concluded: the stored result of its review on the round's head. */
export type Verdict = { slot: Slot; result: Verdicts };
export type Finding = { id?: string; title: string; url?: string };

/** Why a slot of the round settled with no verdict, in the cases that stop an epic with one reviewer: its `kind` is the kind of that stop. */
export type NoVerdict = { slot: Slot; kind: 'agent_needs_human' | 'retries_exhausted' | 'usage_limit' | 'skill_missing'; why: string; executionId?: string };

export type RoundDecision =
  | { kind: 'waiting' }
  /** No slot gave a verdict: each one's reason. */
  | { kind: 'failed'; none: NoVerdict[] }
  | { kind: 'changes_requested' }
  /** Every verdict is a completed review, but a slot that asked for changes in an earlier round gave none in this one: its blockers are still open, so the round is not agreement. */
  | { kind: 'open_blockers'; none: NoVerdict[] }
  /** Every verdict is a completed review: the observations of all, each with its slot, and the mandatory reviewer's verification (the first slot's). */
  | { kind: 'completed'; observations: (Finding & { slot: Slot })[]; verification: Extract<Verdicts, { outcome: 'completed' }>['verification'] };

/**
 * What a review round comes to, from the verdicts and the slots with no verdict it has on its head, a pure function of the stored rows (ADR 0048).
 * It waits while a slot has neither; a slot with no verdict is absent, and with none at all the round failed. Any verdict that asks for changes asks for them,
 * and only when every verdict is a completed review is the round agreed, unless a slot with no verdict still has blockers open from an earlier round (`open`):
 * its silence is not agreement, and the round is not decided (a fix goes ahead, as it answers them too, when another slot asks for changes).
 */
export function decideRound(slots: Slot[], verdicts: Verdict[], none: NoVerdict[] = [], open: Slot[] = []): RoundDecision {
  if (!slots.every((slot) => verdicts.some((v) => v.slot === slot) || none.some((n) => n.slot === slot))) return { kind: 'waiting' };
  const given = slots.flatMap((slot) => verdicts.findLast((v) => v.slot === slot) ?? []);
  if (given.length === 0) return { kind: 'failed', none: slots.map((slot) => none.findLast((n) => n.slot === slot)!) };
  const completed = given.flatMap(({ slot, result }) => (result.outcome === 'completed' ? [{ slot, result }] : []));
  if (completed.length < given.length) return { kind: 'changes_requested' };
  const silent = slots.filter((slot) => open.includes(slot) && !given.some((v) => v.slot === slot));
  if (silent.length > 0) return { kind: 'open_blockers', none: silent.map((slot) => none.findLast((n) => n.slot === slot)!) };
  return { kind: 'completed', observations: completed.flatMap(({ slot, result }) => (result.observations ?? []).map((o) => ({ ...o, slot }))), verification: completed[0]!.result.verification };
}

/**
 * The verdicts of the round the execution belongs to, read where they are decided: its round and head, in the epic's current attempt, never one set aside.
 * An epic with one reviewer has the execution's own result, as it always did.
 */
export function roundVerdicts(db: Pick<Db, 'select'>, epic: { id: number; startedAt: number | null }, execution: { stage: string; reviewer?: Slot | null; round: number | null; headSha: string | null }, result: Verdicts | null, several: boolean): Verdict[] {
  if (!several) return [{ slot: slotOf(execution)!, result: result! }]; // an epic with one reviewer has a verdict only from its own result
  return db
    .select({ reviewer: executions.reviewer, result: callerResults.result })
    .from(callerResults)
    .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
    .where(and(eq(executions.epicId, epic.id), eq(executions.stage, 'review'), eq(executions.round, execution.round!), eq(executions.headSha, execution.headSha!), gte(executions.startedAt, epic.startedAt!), inArray(callerResults.outcome, ['completed', 'changes_requested'])))
    .orderBy(asc(sql`executions.rowid`))
    .all()
    .map((row) => ({ slot: slotOf({ stage: 'review', reviewer: row.reviewer })!, result: JSON.parse(row.result) as Verdicts }));
}

const noVerdictEvent = 'reviewer_no_verdict';
type RoundHead = { round: number | null; headSha: string };

/** The slots of the round on that head that settled with no verdict, in the epic's current attempt: stored as events of the epic, so a restart reads the same. */
export function roundNones(db: Pick<Db, 'select'>, epic: { id: number; startedAt: number | null }, { round, headSha }: RoundHead): NoVerdict[] {
  return db.select().from(epicEvents).where(and(eq(epicEvents.epicId, epic.id), eq(epicEvents.type, noVerdictEvent), gte(epicEvents.at, epic.startedAt ?? Number.MAX_SAFE_INTEGER))).orderBy(asc(epicEvents.id)).all()
    .filter((event) => event.data.round === round && event.data.headSha === headSha)
    .map((event) => event.data.none as NoVerdict);
}

/** Stores that a slot settled with no verdict on the round's head; once per slot and head, so a repeat of the read that found it changes nothing. */
export function recordNoVerdict(db: Pick<Db, 'select' | 'insert'>, epic: { id: number; startedAt: number | null }, { round, headSha }: RoundHead, none: NoVerdict, at: number) {
  if (roundNones(db, epic, { round, headSha }).some((n) => n.slot === none.slot)) return;
  db.insert(epicEvents).values({ epicId: epic.id, at, type: noVerdictEvent, data: { round, headSha, none } }).run();
}
