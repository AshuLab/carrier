import { desc, eq, sql } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executions, reviewerSlots, slotOf, type Slot } from '../storage/executions.ts';

/**
 * Is the execution of the epic's current attempt? The attempt starts when the engine reserves the epic, and a resume reserves it again,
 * so what ran before that start is another attempt's. An epic with no start has no attempt yet, and nothing is of it.
 */
export function isOfAttempt(execution: { startedAt: number }, epic: { startedAt: number | null }) {
  return epic.startedAt !== null && execution.startedAt >= epic.startedAt;
}

/**
 * The latest executions of the slot (the author's by default) in the epic's current attempt that ended in a retryable technical failure, newest first.
 * The streak stops at the slot's first execution without `error` (a finished one, or one that is not retried) or of an earlier attempt, so
 * findings, rounds and GitHub query errors never count: only technical failures do. An execution of another slot neither extends nor breaks it.
 */
export function failureStreak(db: Db, epic: { id: number; startedAt: number | null }, slot: Slot | null = null) {
  const streak = [];
  for (const execution of db.select().from(executions).where(eq(executions.epicId, epic.id)).orderBy(desc(sql`rowid`)).all()) {
    if (slotOf(execution) !== slot) continue;
    if (execution.error === null || !isOfAttempt(execution, epic)) break;
    streak.push(execution);
  }
  return streak;
}

const slotRank = (slot: Slot | null) => (slot === null ? -1 : reviewerSlots.indexOf(slot));

/** The newest execution of each slot in the epic's current attempt (`ended`: leaving out one still running), the author's first, then by slot. */
export function lastBySlot(db: Db, epic: { id: number; startedAt: number | null }, { ended = false } = {}) {
  const last = new Map<Slot | null, typeof executions.$inferSelect>();
  for (const execution of db.select().from(executions).where(eq(executions.epicId, epic.id)).orderBy(desc(sql`rowid`)).all()) {
    const slot = slotOf(execution);
    if (isOfAttempt(execution, epic) && !(ended && execution.status === 'running') && !last.has(slot)) last.set(slot, execution);
  }
  return [...last.values()].sort((a, b) => slotRank(slotOf(a)) - slotRank(slotOf(b)));
}

/**
 * Is a slot other than `except` still recovering from a failure? Its newest execution that has ended (a retry that is running does not count) failed.
 * An epic with one reviewer runs one slot at a time, so for it nothing else fails: what a slot that ends well resets is what another slot's recovery counts.
 */
export const failingBesides = (db: Db, epic: { id: number; startedAt: number | null }, except: Slot | null) =>
  lastBySlot(db, epic, { ended: true }).some((last) => slotOf(last) !== except && last.failureKind !== null);

const apiErrorWaits = [30_000, 120_000, 600_000];

/**
 * How long the retry that follows a failure waits, in milliseconds. `streak` is the epic's failure streak (newest first), so its length is the
 * position of the retry: an `api_error` waits 30 s, then 2 min, then 10 min (the last wait repeats), and a failure of any other kind, a process
 * that died among them, waits nothing. The wait is by the kind of the failure that just ended and its position in the streak, whatever kinds came before.
 */
export function retryWait(streak: { failureKind: string | null }[]) {
  if (streak[0]?.failureKind !== 'api_error') return 0;
  return apiErrorWaits[Math.min(streak.length, apiErrorWaits.length) - 1] ?? 0;
}

/**
 * When the retry of the slot's last failure may start (ms since epoch), none when it waits for nothing: the failure's end plus the wait its streak asks.
 * Read from the rows and not kept, so a restart of the engine finds it, and each slot has its own.
 */
export function retryDue(db: Db, epic: { id: number; startedAt: number | null }, slot: Slot | null) {
  const streak = failureStreak(db, epic, slot);
  const wait = retryWait(streak);
  return wait > 0 ? (streak[0]!.finishedAt ?? 0) + wait : null;
}

/** The due time an epic shows: the earliest of the slots that wait for one, leaving out the ones in `ignoring` (a retry that is launching). */
export function earliestRetryDue(db: Db, epic: { id: number; startedAt: number | null }, ignoring: (Slot | null)[] = []) {
  const dues = lastBySlot(db, epic).map(slotOf).filter((slot) => !ignoring.includes(slot)).map((slot) => retryDue(db, epic, slot)).filter((due) => due !== null);
  return dues.length === 0 ? null : Math.min(...dues);
}
