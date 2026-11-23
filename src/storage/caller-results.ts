import { sqliteTable, text } from 'drizzle-orm/sqlite-core';

// One row per execution: the primary key is what makes importing a result idempotent.
export const callerResults = sqliteTable('caller_results', {
  executionId: text().primaryKey(),
  outcome: text().notNull(),
  result: text().notNull(), // the validated JSON
});

/** The outcome kept for a review of a head that moved while it ran: stored like any result, never read for what the next round carries. */
export const supersededOutcome = 'superseded';
