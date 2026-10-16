import { sqliteTable, text } from 'drizzle-orm/sqlite-core';

// One row per execution: the primary key is what makes importing a result idempotent.
export const callerResults = sqliteTable('caller_results', {
  executionId: text().primaryKey(),
  outcome: text().notNull(),
  result: text().notNull(), // the validated JSON
});
