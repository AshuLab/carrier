import { integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';

export const sessionStates = ['working', 'waiting_approval', 'idle'] as const;

/** A user session: one conversation with a provider's agent in a folder. This slice only creates the table; the sessions slice fills it. */
export const sessions = sqliteTable('sessions', {
  id: text().primaryKey(),
  agent: text().notNull(), // the configured agent's name
  harness: text({ enum: ['claude', 'codex'] }).notNull(),
  folder: text().notNull(),
  title: text(),
  options: text({ mode: 'json' }).$type<Record<string, string>>(),
  nativeId: text(), // the provider's id for the conversation, to resume it
  state: text({ enum: sessionStates }).notNull().default('idle'),
  pid: integer(), // of the live agent process, null when closed
  pgid: integer(),
  createdAt: integer().notNull(), // ms since epoch
  lastActiveAt: integer().notNull(),
  archived: integer({ mode: 'boolean' }).notNull().default(false),
});
