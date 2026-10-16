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
    stage: text({ enum: ['ship', 'review', 'fix'] }), // null until the author is launched
    round: integer(), // review round, from 1 once the final PR is validated
    prNumber: integer(),
    prHeadSha: text(),
    reviewedSha: text(), // head the reviewer approved, set when the epic becomes ready_for_test
    verification: text({ mode: 'json' }).$type<{ ci: 'passed' | 'absent'; evidence: string }>(), // what the reviewer reported about the checks
    needsHumanReason: text(),
    // Set while `repo_removed`: where the epic was and why it stopped, so it goes back there when the repo returns.
    removedFrom: text({ enum: epicStates }),
    removedReason: text(),
    finishedAt: integer(), // ms since epoch, when the epic left `running`
  },
  (table) => [uniqueIndex('epics_repo_issue').on(table.repo, table.issue)],
);
