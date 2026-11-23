import { desc, eq, sql } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';

/**
 * Is the execution of the epic's current attempt? The attempt starts when the engine reserves the epic, and a resume reserves it again,
 * so what ran before that start is another attempt's. An epic with no start has no attempt yet, and nothing is of it.
 */
export function isOfAttempt(execution: { startedAt: number }, epic: { startedAt: number | null }) {
  return epic.startedAt !== null && execution.startedAt >= epic.startedAt;
}

/**
 * The epic's latest executions of its current attempt that ended in a retryable technical failure, newest first. The streak
 * stops at the first execution without `error` (a finished one, or one that is not retried) or of an earlier attempt, so
 * findings, rounds and GitHub query errors never count: only technical failures do.
 */
export function failureStreak(db: Db, epic: { id: number; startedAt: number | null }) {
  const streak = [];
  for (const execution of db.select().from(executions).where(eq(executions.epicId, epic.id)).orderBy(desc(sql`rowid`)).all()) {
    if (execution.error === null || !isOfAttempt(execution, epic)) break;
    streak.push(execution);
  }
  return streak;
}

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
