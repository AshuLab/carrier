import { integer, primaryKey, sqliteTable, text } from 'drizzle-orm/sqlite-core';

// A cache of what GitHub said about an epic's slices the last time the poll asked (ADR 0008). Never read to decide anything.
export const epicSlices = sqliteTable(
  'epic_slices',
  {
    epicId: integer().notNull(),
    number: integer().notNull(),
    title: text().notNull(),
    state: text({ enum: ['closed', 'skipped', 'in_progress', 'waiting', 'ready'] }).notNull(),
    blockedBy: text({ mode: 'json' }).$type<number[]>().notNull(), // the numbers of the blockers still open
    assignee: text(),
    prNumber: integer(),
    prState: text({ enum: ['open', 'draft', 'merged', 'closed'] }),
    prMergedAt: integer(), // ms since epoch
    closedAt: integer(), // ms since epoch
    readAt: integer().notNull(), // ms since epoch
    // Only the first hundred slices are read; the same on every row of an epic. ponytail: per row, a column of its own if more flags ever join it.
    truncated: integer({ mode: 'boolean' }).notNull().default(false),
  },
  (table) => [primaryKey({ columns: [table.epicId, table.number] })],
);
