import { desc, eq, sql } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';

/**
 * The epic's latest executions that ended in a retryable technical failure, newest first. The streak
 * stops at the first execution without `error` (a finished one, or one that is not retried), so
 * findings, rounds and GitHub query errors never count: only technical failures do.
 */
export function failureStreak(db: Db, epicId: number) {
  const streak = [];
  for (const execution of db.select().from(executions).where(eq(executions.epicId, epicId)).orderBy(desc(sql`rowid`)).all()) {
    if (execution.error === null) break;
    streak.push(execution);
  }
  return streak;
}
