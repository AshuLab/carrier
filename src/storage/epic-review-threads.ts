import { integer, primaryKey, sqliteTable, text } from 'drizzle-orm/sqlite-core';

// A cache of what GitHub said about the final pull request's review threads the last time the poll asked (ADR 0008). Never read to decide anything.
export const epicReviewThreads = sqliteTable(
  'epic_review_threads',
  {
    epicId: integer().notNull(),
    id: text().notNull(), // GraphQL node id
    position: integer().notNull(), // GitHub's order
    path: text().notNull(),
    line: integer(),
    resolved: integer({ mode: 'boolean' }).notNull(),
    outdated: integer({ mode: 'boolean' }).notNull(),
    author: text(),
    bot: integer({ mode: 'boolean' }).notNull(),
    firstLine: text().notNull(),
    commentCount: integer().notNull(),
    url: text().notNull(),
    readAt: integer().notNull(), // ms since epoch
    // Only the first hundred threads are read; the same on every row of an epic, like epic_slices.
    truncated: integer({ mode: 'boolean' }).notNull().default(false),
  },
  (table) => [primaryKey({ columns: [table.epicId, table.id] })],
);
