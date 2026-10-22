import { and, asc, desc, eq, gt } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { PanelSession } from '../status/types.ts';
import { agentOf } from './sessions.ts';
import type { EventsReply, ExecEvent } from './replies.ts';

type Row = typeof executionEvents.$inferSelect;

// Only what ExecEvent names leaves: the slice and lane hints in the payload are for the engine.
const wire = (row: Row): ExecEvent => ({
  id: row.id,
  at: row.at,
  kind: row.kind,
  ...(row.payload?.text !== undefined && { text: row.payload.text }),
  ...(row.callId !== null && { callId: row.callId }),
  ...(row.agentId !== null && { agentId: row.agentId }),
  ...(row.tool !== null && { tool: row.tool }),
  ...(row.arg !== null && { arg: row.arg }),
  ...(row.summary !== null && { summary: row.summary }),
  ...(row.status !== null && { status: row.status }),
  ...(row.durationMs !== null && { durationMs: row.durationMs }),
  ...(row.payload?.output !== undefined && { output: row.payload.output }),
  ...(row.payload?.diff !== undefined && { diff: row.payload.diff }),
});

// The harnesses that have an events parser.
const structuredHarnesses = ['claude', 'codex', 'agy'];

/**
 * The events of an execution after the cursor, oldest first, at most `limit`; null for an execution the engine does not know.
 * A harness with no parser yet (a future one; today all three have one) answers `structured: false` and no events.
 */
export function eventsOf(db: Db, executionId: string, after: number, limit: number): EventsReply | null {
  const row = db.select({ execution: executions, config: epics.config }).from(executions).innerJoin(epics, eq(epics.id, executions.epicId)).where(eq(executions.executionId, executionId)).get();
  if (row === undefined) return null;
  const running = row.execution.status === 'running';
  if (!structuredHarnesses.includes(agentOf(row.execution, row.config).harness)) return { events: [], next: after, running, structured: false };
  const events = db.select().from(executionEvents).where(and(eq(executionEvents.executionId, executionId), gt(executionEvents.id, after))).orderBy(asc(executionEvents.id)).limit(limit).all().map(wire);
  return { events, next: events.at(-1)?.id ?? after, running, structured: true };
}

// A line of the Overview: what the agent is doing now, in the words of its newest event.
const describe = (row: Row) => {
  const call = [row.tool, row.arg].filter((part) => part !== null).join(' ');
  return (row.kind === 'tool_start' ? call : row.kind === 'tool_end' ? [row.tool, row.summary].filter((part) => part !== null).join(' ') : (row.payload?.text ?? '')).slice(0, 200);
};

/** The newest event of an execution for the snapshot; null while it has none. */
export function lastEventOf(db: Db, executionId: string): PanelSession['last'] {
  const row = db.select().from(executionEvents).where(eq(executionEvents.executionId, executionId)).orderBy(desc(executionEvents.id)).limit(1).get();
  return row === undefined ? null : { kind: row.kind, text: describe(row), at: row.at };
}
