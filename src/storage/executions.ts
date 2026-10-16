import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import { epics } from './schema.ts';

export const executionStates = ['running', 'finished', 'failed', 'timed_out', 'interrupted', 'invalid_result'] as const;

export const executions = sqliteTable('executions', {
  executionId: text().primaryKey(),
  epicId: integer().notNull().references(() => epics.id),
  stage: text({ enum: ['ship', 'review', 'fix'] }).notNull(),
  status: text({ enum: executionStates }).notNull().default('running'),
  sessionId: text(), // saved as soon as the runner reports it, not when it ends
  resultPath: text().notNull(),
  startedAt: integer().notNull(),
  finishedAt: integer(),
});
