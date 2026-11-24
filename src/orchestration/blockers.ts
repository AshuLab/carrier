import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { executions, slotOf, type Slot } from '../storage/executions.ts';

/** The newest review of each slot, in the order they came: the ones that gave a verdict only, or (`any`) whatever its outcome, a review of a head that moved included. */
function lastReviews(db: Db, epicId: number, any = false) {
  const last = new Map<Slot, { outcome: string; result: CallerResult }>(); // the outcome is the column's: a result of a head that moved keeps its own in the JSON
  for (const row of db
    .select({ reviewer: executions.reviewer, outcome: callerResults.outcome, result: callerResults.result })
    .from(callerResults)
    .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
    .where(and(eq(executions.epicId, epicId), eq(executions.stage, 'review'), any ? undefined : inArray(callerResults.outcome, ['changes_requested', 'completed'])))
    .orderBy(asc(sql`executions.rowid`))
    .all()) {
    last.set(slotOf({ stage: 'review', reviewer: row.reviewer })!, { outcome: row.outcome, result: JSON.parse(row.result) as CallerResult });
  }
  return last;
}

/**
 * The blockers still open: those of each reviewer's latest review that asked for changes, none for one whose latest review completed after it: what the fix turn
 * and the next review have to answer. `slot` keeps one reviewer's own, which is what its next review is given; `tagged` says whose each one is (an epic with several reviewers).
 */
export function latestBlockers(db: Db, epicId: number, { slot, tagged = false }: { slot?: Slot; tagged?: boolean } = {}) {
  return [...lastReviews(db, epicId)]
    .filter(([reviewer]) => slot === undefined || reviewer === slot)
    .flatMap(([reviewer, { outcome, result }]) => (outcome === 'changes_requested' ? (result as Extract<CallerResult, { outcome: 'changes_requested' }>).blockers.map((blocker) => (tagged ? { ...blocker, reviewer } : blocker)) : []));
}

/**
 * The observations of the epic's latest reviews when every reviewer's completed (one that gave none, or whose head moved, is not): a fix right after them is the observations pass, null otherwise (that fix is for blockers).
 * `tagged` says which reviewer each one is from (an epic with several reviewers).
 */
export function latestObservations(db: Db, epicId: number, { tagged = false }: { tagged?: boolean } = {}) {
  const last = [...lastReviews(db, epicId, true)];
  if (last.length === 0 || !last.every(([, { outcome }]) => outcome === 'completed')) return null;
  return last.flatMap(([reviewer, { result }]) => ((result as Extract<CallerResult, { outcome: 'completed' }>).observations ?? []).map((o) => (tagged ? { ...o, reviewer } : o)));
}
