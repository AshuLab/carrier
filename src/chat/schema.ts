import { index, integer, real, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import type { Plan } from './plan.ts';

export const sessionStates = ['working', 'waiting_approval', 'idle', 'preparing'] as const;

/** A user session: one conversation with a provider's agent in a folder. */
export const sessions = sqliteTable('sessions', {
  id: text().primaryKey(),
  agent: text().notNull(), // the configured agent's name
  harness: text({ enum: ['claude', 'codex'] }).notNull(),
  folder: text().notNull(), // where the agent runs: the base folder, or the worktree when there is one
  workspaceKind: text({ enum: ['folder', 'worktree'] }).notNull().default('folder'),
  worktreeBranch: text(), // the four below are set for a worktree session only
  worktreeFrom: text(), // the branch it was cut from, as `workspace` listed it
  worktreeBase: text(), // the folder it was made from
  worktreePath: text(),
  title: text(),
  options: text({ mode: 'json' }).$type<Record<string, string>>(),
  plan: text({ mode: 'json' }).$type<Plan>(), // what the host is preparing, or failed to, with the first message; null once the agent answered it
  nativeId: text(), // the provider's id for the conversation, to resume it
  state: text({ enum: sessionStates }).notNull().default('idle'),
  pid: integer(), // of the live agent process, null when closed
  pgid: integer(),
  command: text(), // what that process was started with, so a sweep knows it is still the agent
  createdAt: integer().notNull(), // ms since epoch
  lastActiveAt: integer().notNull(),
  archived: integer({ mode: 'boolean' }).notNull().default(false),
  keptAt: integer(), // ms since epoch: when the clock's delete spared this archived session for unsaved work; null otherwise
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

export const priceOverrideModes = ['zero', 'alias', 'custom'] as const;

/** What the person said a model costs, keyed by the normalized model id; it wins over the built-in price table. */
export const usagePriceOverrides = sqliteTable('usage_price_overrides', {
  model: text().primaryKey(),
  mode: text({ enum: priceOverrideModes }).notNull(),
  aliasModel: text(), // alias: the catalog model whose price applies
  inputUsdPerMillion: real(), // custom: a null cached or cache write rate falls back to the input rate
  cachedInputUsdPerMillion: real(),
  cacheWriteUsdPerMillion: real(),
  outputUsdPerMillion: real(),
  updatedAt: integer().notNull(), // ms since epoch
});
