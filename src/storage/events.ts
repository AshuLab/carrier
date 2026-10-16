import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import { epics } from './schema.ts';

// Append-only history of what the engine did to an epic; the autoincrement id keeps the order.
export const epicEvents = sqliteTable('epic_events', {
  id: integer().primaryKey({ autoIncrement: true }),
  epicId: integer().notNull().references(() => epics.id),
  at: integer().notNull(), // ms since epoch
  type: text().notNull(),
  data: text({ mode: 'json' }).$type<Record<string, unknown>>().notNull(),
});
