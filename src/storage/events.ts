import { index, integer, sqliteTable, text } from 'drizzle-orm/sqlite-core';
import type { AgentEvent } from '../execution/events.ts';
import type { Db } from './db.ts';
import { executions } from './executions.ts';
import { epics } from './schema.ts';

// Append-only history of what the engine did to an epic; the autoincrement id keeps the order.
export const epicEvents = sqliteTable('epic_events', {
  id: integer().primaryKey({ autoIncrement: true }),
  epicId: integer().notNull().references(() => epics.id),
  at: integer().notNull(), // ms since epoch
  type: text().notNull(),
  data: text({ mode: 'json' }).$type<Record<string, unknown>>().notNull(),
});

export type EventPayload = Pick<AgentEvent, 'text' | 'output' | 'diff' | 'slice' | 'lane'>;

// What an agent did during an execution (ADR 0006), already bounded and redacted. The id is the cursor of the `events` request.
// A tool call is two rows with the same callId. Deleted with the logs, 30 days after the epic ends.
export const executionEvents = sqliteTable(
  'execution_events',
  {
    id: integer().primaryKey({ autoIncrement: true }),
    executionId: text().notNull().references(() => executions.executionId),
    at: integer().notNull(), // ms since epoch: the line's own time, else when it arrived
    kind: text({ enum: ['say', 'tool_start', 'tool_end', 'note', 'error', 'task'] }).notNull(),
    callId: text(),
    agentId: text(), // the Claude subagent that did it
    tool: text(),
    arg: text(),
    summary: text(),
    status: text({ enum: ['ok', 'err'] }),
    durationMs: integer(),
    payload: text({ mode: 'json' }).$type<EventPayload>(), // the text of a message, a command's output, a diff, the slice and lane hints
  },
  (table) => [index('execution_events_execution').on(table.executionId, table.id)],
);

/** Stores the events of one output chunk in a single transaction; `arrival` is the time of those without their own. */
export function recordEvents(db: Db, executionId: string, events: AgentEvent[], arrival: number): void {
  if (events.length === 0) return;
  db.transaction((tx) => {
    for (const { at, kind, callId, agentId, tool, arg, summary, status, durationMs, ...rest } of events) {
      const payload = Object.fromEntries(Object.entries(rest).filter(([, value]) => value !== undefined)) as EventPayload;
      tx.insert(executionEvents)
        .values({
          executionId,
          at: at ?? arrival,
          kind,
          callId: callId ?? null,
          agentId: agentId ?? null,
          tool: tool ?? null,
          arg: arg ?? null,
          summary: summary ?? null,
          status: status ?? null,
          durationMs: durationMs ?? null,
          payload: Object.keys(payload).length > 0 ? payload : null,
        })
        .run();
    }
  });
}
