import { and, desc, eq, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';

/** The blockers of the epic's latest review that asked for changes: what the fix turn has to answer. */
export function latestBlockers(db: Db, epicId: number) {
  const last = db
    .select({ result: callerResults.result })
    .from(callerResults)
    .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
    .where(and(eq(executions.epicId, epicId), eq(executions.stage, 'review'), eq(callerResults.outcome, 'changes_requested')))
    .orderBy(desc(sql`executions.rowid`))
    .get();
  return last ? (JSON.parse(last.result) as Extract<CallerResult, { outcome: 'changes_requested' }>).blockers : [];
}
