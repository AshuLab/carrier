import { index, integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';

export const sessionStates = ['working', 'waiting_approval', 'idle'] as const;

/** A user session: one conversation with a provider's agent in a folder. */
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

/**
 * What was said and done in a session, already redacted and bounded (`transcript.ts`). The id is the cursor of the `events`
 * request. A `delta` is never stored. `data` holds the event's fields other than its kind.
 */
export const chatEvents = sqliteTable(
  'chat_events',
  {
    id: integer().primaryKey({ autoIncrement: true }),
    sessionId: text().notNull().references(() => sessions.id),
    at: integer().notNull(), // ms since epoch
    kind: text().notNull(),
    data: text({ mode: 'json' }).$type<Record<string, unknown>>().notNull(),
  },
  (table) => [index('chat_events_session').on(table.sessionId, table.id)],
);

/** One row per finished turn, so statistics can be built later without touching the transcripts. */
export const chatTurns = sqliteTable(
  'chat_turns',
  {
    id: integer().primaryKey({ autoIncrement: true }),
    sessionId: text().notNull().references(() => sessions.id),
    startedAt: integer().notNull(),
    model: text(),
    outcome: text({ enum: ['ok', 'interrupted', 'error'] }).notNull(),
    durationMs: integer().notNull(),
    toolCalls: integer().notNull(),
    usage: text({ mode: 'json' }).$type<Record<string, number>>(), // as the provider gave it
  },
  (table) => [index('chat_turns_session').on(table.sessionId)],
);
