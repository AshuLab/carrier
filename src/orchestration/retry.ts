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
