import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';

export const epics = sqliteTable('epics', {
  id: integer().primaryKey({ autoIncrement: true }),
  repo: text().notNull(),
  issue: integer().notNull(),
});
