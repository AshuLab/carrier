import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { integer, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

export const epicStates = ['queued', 'running', 'ready_for_test', 'needs_human', 'cancelled', 'merged', 'repo_removed'] as const;

export const epics = sqliteTable(
  'epics',
  {
    // Autoincrement id is the stable queue order: rows are never reused or reordered.
    id: integer().primaryKey({ autoIncrement: true }),
    repo: text().notNull(),
    issue: integer().notNull(),
    status: text({ enum: epicStates }).notNull().default('queued'),
    queuedAt: integer().notNull().default(0), // ms since epoch, when the poll registered it
    startedAt: integer(), // ms since epoch, when the scheduler reserved it
    // Effective repo config frozen at reservation: later config changes do not touch a running epic.
    config: text({ mode: 'json' }).$type<EffectiveRepoConfig>(),
    cancelReason: text(),
    // The running label is a reflection of SQLite: true while it has not reached GitHub yet.
    labelPending: integer({ mode: 'boolean' }).notNull().default(false),
  },
  (table) => [uniqueIndex('epics_repo_issue').on(table.repo, table.issue)],
);
