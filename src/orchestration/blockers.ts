import { and, desc, eq, inArray, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';

/** The blockers of the epic's latest review that asked for changes, none when a review completed after it: what the fix turn and the next review have to answer. */
export function latestBlockers(db: Db, epicId: number) {
  const last = db
    .select({ outcome: callerResults.outcome, result: callerResults.result })
    .from(callerResults)
    .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
    .where(and(eq(executions.epicId, epicId), eq(executions.stage, 'review'), inArray(callerResults.outcome, ['changes_requested', 'completed'])))
    .orderBy(desc(sql`executions.rowid`))
    .get();
  return last?.outcome === 'changes_requested' ? (JSON.parse(last.result) as Extract<CallerResult, { outcome: 'changes_requested' }>).blockers : [];
}

/** The observations of the epic's latest review when it completed: a fix right after it is the observations pass, null otherwise (that fix is for blockers). */
export function latestObservations(db: Db, epicId: number) {
  const last = db
    .select({ outcome: callerResults.outcome, result: callerResults.result })
    .from(callerResults)
    .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
    .where(and(eq(executions.epicId, epicId), eq(executions.stage, 'review')))
    .orderBy(desc(sql`executions.rowid`))
    .get();
  return last?.outcome === 'completed' ? ((JSON.parse(last.result) as Extract<CallerResult, { outcome: 'completed' }>).observations ?? []) : null;
}
