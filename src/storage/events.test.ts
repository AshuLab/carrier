import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { asc, eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { createEventState, type AgentEvent } from '../execution/events.ts';
import { parseClaudeEvents } from '../harnesses/claude.ts';
import { secretFixtures } from '../logging/secrets.fixture.ts';
import { openDatabase, type Db } from './db.ts';
import { executionEvents, recordEvents } from './events.ts';
import { executions } from './executions.ts';
import { epics } from './schema.ts';

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-events-'));
  db = openDatabase(join(dir, 'carrier.db'));
  const epic = db.insert(epics).values({ repo: 'AshuLab/a', issue: 1 }).returning().get();
  db.insert(executions).values({ executionId: 'x1', epicId: epic.id, stage: 'ship', resultPath: 'r', startedAt: 0 }).run();
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const rows = () => db.select().from(executionEvents).orderBy(asc(executionEvents.id)).all();

test('a row per event, in order; the time is the event own or the arrival; text, output, diff and hints go to the payload', () => {
  recordEvents(
    db,
    'x1',
    [
      { at: 5, kind: 'say', text: 'hello' },
      { kind: 'tool_start', callId: 'c', tool: 'Bash', arg: 'ls', agentId: 'a1' },
      { kind: 'tool_end', callId: 'c', tool: 'Bash', status: 'err', durationMs: 7, summary: 'boom', output: ['x'], diff: [{ sign: '+', text: 'y' }] },
      { kind: 'task', text: 'Build slice #3', slice: 3, lane: 2 },
    ],
    1000,
  );
  expect(rows().map(({ id: _, ...row }) => row)).toEqual([
    { executionId: 'x1', at: 5, kind: 'say', callId: null, agentId: null, tool: null, arg: null, summary: null, status: null, durationMs: null, payload: { text: 'hello' } },
    { executionId: 'x1', at: 1000, kind: 'tool_start', callId: 'c', agentId: 'a1', tool: 'Bash', arg: 'ls', summary: null, status: null, durationMs: null, payload: null },
    { executionId: 'x1', at: 1000, kind: 'tool_end', callId: 'c', agentId: null, tool: 'Bash', arg: null, summary: 'boom', status: 'err', durationMs: 7, payload: { output: ['x'], diff: [{ sign: '+', text: 'y' }] } },
    { executionId: 'x1', at: 1000, kind: 'task', callId: null, agentId: null, tool: null, arg: null, summary: null, status: null, durationMs: null, payload: { text: 'Build slice #3', slice: 3, lane: 2 } },
  ]);
  const ids = rows().map((row) => row.id);
  expect(ids).toEqual([...ids].sort((a, b) => a - b));
});

test('a thousand calls in one chunk are one transaction, and a chunk with nothing opens none', () => {
  const calls: AgentEvent[] = Array.from({ length: 1000 }, (_, i): AgentEvent[] => [
    { kind: 'tool_start', callId: `c${i}`, tool: 'Read', arg: `/f${i}` },
    { kind: 'tool_end', callId: `c${i}`, tool: 'Read', status: 'ok' },
  ]).flat();
  const transaction = vi.spyOn(db, 'transaction');
  recordEvents(db, 'x1', calls, 1);
  expect(transaction).toHaveBeenCalledTimes(1);
  expect(rows()).toHaveLength(2000);
  recordEvents(db, 'x1', [], 2);
  recordEvents(db, 'x1', calls.slice(0, 2), 3);
  expect(transaction).toHaveBeenCalledTimes(2);
});

test('a failure inside a chunk leaves none of its rows', () => {
  // NaN is stored as NULL and `at` is NOT NULL: the second event fails, the first must not stay.
  const chunk: AgentEvent[] = [{ kind: 'say', text: 'first' }, { at: Number.NaN, kind: 'say', text: 'second' }];
  expect(() => recordEvents(db, 'x1', chunk, 1)).toThrow();
  expect(rows()).toHaveLength(0);
});

test.each(Object.entries(secretFixtures))('no stored row keeps %s', (_shape, { text, secret }) => {
  const state = createEventState();
  const line = (o: unknown) => JSON.stringify(o);
  const stream = [
    line({ type: 'assistant', message: { content: [{ type: 'text', text }, { type: 'tool_use', id: 'c1', name: 'Bash', input: { command: `env ${text}` } }] } }),
    line({ type: 'user', message: { content: [{ type: 'tool_result', tool_use_id: 'c1', content: `a\n${text}\nz` }] }, tool_use_result: { structuredPatch: [{ lines: [`+${text}`] }] } }),
    line({ type: 'system', subtype: 'task_started', task_id: 't', task_type: 'local_agent', description: text }),
    line({ type: 'result', is_error: true, result: text }),
  ];
  recordEvents(db, 'x1', stream.flatMap((l) => parseClaudeEvents(l, state)), 1);
  const stored = db.$client.prepare('select * from execution_events').all();
  expect(stored.length).toBeGreaterThanOrEqual(5);
  expect(JSON.stringify(stored)).not.toContain(secret);
  expect(db.select().from(executionEvents).where(eq(executionEvents.executionId, 'x1')).all()).toHaveLength(stored.length);
});
