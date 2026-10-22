import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { createEventState, type AgentEvent } from '../execution/events.ts';
import { agyAdapter } from '../harnesses/agy.ts';
import { claudeAdapter } from '../harnesses/claude.ts';
import { codexAdapter } from '../harnesses/codex.ts';
import { replayEvents } from '../harnesses/replay-events.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { recordEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { eventsOf, lastEventOf } from './events.ts';
import type { EventsReply } from './replies.ts';
import { startControlServer } from './server.ts';
import { sessionsOf } from './sessions.ts';

// The events request over a real socket, answered from a real (temp) SQLite.
let dir: string;
let db: Db;
let close: () => void;
beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), 'ce-')); // short: a socket path holds 103 bytes on macOS
  db = openDatabase(join(dir, 'carrier.db'));
  const controls = {
    poll: () => {},
    setPaused: () => {},
    logs: () => [],
    sessions: (repo: string, issue: number) => sessionsOf(db, repo, issue, {}),
    events: (executionId: string, after: number, limit: number) => eventsOf(db, executionId, after, limit),
    epic: () => null,
    files: () => null,
  };
  close = (await startControlServer({ orchestratorDir: dir, snapshot: () => ({}), startedAt: 1, controls, stop: async () => {} })).close;
});
afterEach(() => {
  close();
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const agent = { profile: 'p', harness: 'claude' as const, model: 'm' };
const config = { name: 'AshuLab/a', agents: { author: agent, reviewer: { ...agent, harness: 'codex' as const } } };
const epicId = (db_: Db) => db_.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'running', config }).returning({ id: epics.id }).get().id;
const run = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
const codexRun = '00000000-0000-4000-8000-000000000003';
const agyRun = '00000000-0000-4000-8000-000000000004';
function seed() {
  const id = epicId(db);
  const base = { epicId: id, resultPath: '/r.json', startedAt: 1000 };
  db.insert(executions).values({ ...base, executionId: run, stage: 'ship', status: 'running' }).run();
  db.insert(executions).values({ ...base, executionId: other, stage: 'ship', status: 'finished' }).run();
  db.insert(executions).values({ ...base, executionId: codexRun, stage: 'review', status: 'finished' }).run();
  db.insert(executions).values({ ...base, executionId: agyRun, stage: 'review', status: 'finished', harness: 'agy', model: 'm', provider: null }).run();
}

async function ask(request: object) {
  const socket = connect(join(dir, 'control.sock'));
  socket.setEncoding('utf8');
  let text = '';
  const reply = await new Promise<{ id: number; ok: boolean; data?: EventsReply; error?: string }>((resolve) => {
    socket.on('data', (chunk: string) => {
      text += chunk;
      const lines = text.split('\n');
      if (lines.length > 2) resolve(JSON.parse(lines[1]!));
      if (lines.length === 2 && !text.includes('"event":"hello"')) resolve(JSON.parse(lines[0]!));
    });
    socket.write(`${JSON.stringify(request)}\n`);
  });
  socket.destroy();
  return reply;
}
const events = (extra: object) => ask({ id: 1, cmd: 'events', executionId: run, limit: 200, ...extra });
const say = (n: number): AgentEvent => ({ at: n, kind: 'say', text: `m${n}` });

test('pages with the cursor: from the start, the middle, past the end, and a limit', async () => {
  seed();
  recordEvents(db, run, [1, 2, 3, 4, 5].map(say), 0);
  recordEvents(db, other, [say(99)], 0); // another execution's rows never show

  const all = (await events({})).data!;
  expect(all.events.map((e) => e.text)).toEqual(['m1', 'm2', 'm3', 'm4', 'm5']);
  expect(all).toMatchObject({ next: all.events[4]!.id, running: true, structured: true });

  const middle = (await events({ after: all.events[1]!.id })).data!;
  expect(middle.events.map((e) => e.text)).toEqual(['m3', 'm4', 'm5']);

  const limited = (await events({ limit: 2 })).data!;
  expect(limited.events.map((e) => e.text)).toEqual(['m1', 'm2']);
  expect(limited.next).toBe(all.events[1]!.id);

  const end = (await events({ after: all.next })).data!;
  expect(end).toEqual({ events: [], next: all.next, running: true, structured: true });
  expect((await events({ after: 0, limit: 1 })).data!.events).toHaveLength(1);
});

test('an execution with no events answers an empty page with the cursor it was given; a finished one is not running', async () => {
  seed();
  expect((await events({})).data).toEqual({ events: [], next: 0, running: true, structured: true });
  expect((await ask({ id: 1, cmd: 'events', executionId: other, after: 7, limit: 5 })).data).toEqual({ events: [], next: 7, running: false, structured: true });
});

test('an unknown execution is an error', async () => {
  seed();
  expect(await ask({ id: 4, cmd: 'events', executionId: '00000000-0000-4000-8000-0000000000ff', limit: 5 })).toEqual({ id: 4, ok: false, error: 'unknown execution' });
});

test('a harness with no parser yet answers structured:false and no events, even if rows exist', async () => {
  seed();
  const futureRun = '00000000-0000-4000-8000-000000000005';
  db.insert(executions).values({ epicId: db.select({ id: epics.id }).from(epics).get()!.id, executionId: futureRun, stage: 'review', status: 'finished', resultPath: '/r.json', startedAt: 1000, harness: 'future' as never, model: 'm', provider: null }).run();
  recordEvents(db, futureRun, [say(1)], 0);
  expect((await ask({ id: 1, cmd: 'events', executionId: futureRun, limit: 5 })).data).toEqual({ events: [], next: 0, running: false, structured: false });
});

test('a Codex execution answers structured events, stamped with their arrival', async () => {
  seed();
  const log = readFileSync(new URL('../harnesses/codex-exec.fixture.jsonl', import.meta.url), 'utf8');
  const state = createEventState();
  for (const line of log.trimEnd().split('\n')) recordEvents(db, codexRun, codexAdapter.parseEvents!(line, state), 700);
  const { data } = await ask({ id: 1, cmd: 'events', executionId: codexRun, limit: 200 });
  expect(data).toMatchObject({ next: 12, running: false, structured: true });
  expect(data!.events.map((e) => [e.kind, e.tool, e.callId, e.at])).toEqual([
    ['note', undefined, undefined, 700],
    ['note', undefined, undefined, 700],
    ['say', undefined, undefined, 700],
    ['tool_start', 'shell', 'item_3', 700],
    ['tool_end', 'shell', 'item_3', 700],
    ['tool_start', 'shell', 'item_4', 700],
    ['tool_end', 'shell', 'item_4', 700],
    ['tool_start', 'shell', 'item_5', 700],
    ['tool_end', 'shell', 'item_5', 700],
    ['tool_start', 'Edit', 'item_6', 700],
    ['tool_end', 'Edit', 'item_6', 700],
    ['say', undefined, undefined, 700],
  ]);
  expect(data!.events[8]).toMatchObject({ status: 'err', summary: 'Exit code 1', output: ['ls: /no/such/dir: No such file or directory'] });
});

test('an Antigravity execution answers structured events: the fixture, parsed as the runner does and read over the socket', async () => {
  const id = epicId(db);
  db.insert(executions).values({ epicId: id, executionId: agyRun, stage: 'ship', status: 'running', resultPath: '/r.json', startedAt: 1000, harness: 'agy', model: 'm', provider: null }).run();
  const state = createEventState();
  for (const line of readFileSync(new URL('../harnesses/agy-stream.fixture.jsonl', import.meta.url), 'utf8').split('\n')) recordEvents(db, agyRun, agyAdapter.parseEvents!(line, state), 500);
  const { data } = await ask({ id: 1, cmd: 'events', executionId: agyRun, limit: 200 });
  expect(data).toMatchObject({ running: true, structured: true });
  expect(data!.events.map((e) => [e.kind, e.tool, e.status, e.durationMs])).toContainEqual(['tool_end', 'run_command', 'err', 114]);
  expect(data!.events.at(-1)).toMatchObject({ kind: 'say', at: 500 }); // no line carries a time: the arrival stamps it
});

test('the wire shape is the golden file: every field of every kind, and nothing else', async () => {
  seed();
  const golden: EventsReply = JSON.parse(readFileSync(new URL('../../macos/Tests/Fixtures/reply-events.json', import.meta.url), 'utf8'));
  recordEvents(db, run, golden.events.map(({ id: _, ...rest }) => ({ ...rest, slice: 1, lane: 2 })), 0);
  const { data } = await events({});
  expect(data!.events).toEqual(golden.events.map((e, i) => ({ ...e, id: i + 1 })));
});

test('replaying a log gives the events live capture stores, chunk by chunk', () => {
  seed();
  const log = readFileSync(new URL('../harnesses/claude-events.fixture.jsonl', import.meta.url), 'utf8');
  const state = createEventState();
  for (const line of log.split('\n')) recordEvents(db, run, claudeAdapter.parseEvents!(line, state), 500);
  recordEvents(db, other, replayEvents(log), 500);

  const strip = (id: string) => eventsOf(db, id, 0, 200)!.events.map(({ id: _, ...rest }) => rest);
  expect(strip(other)).toEqual(strip(run));
  expect(strip(run).length).toBeGreaterThan(0);
});

test('the newest event of an execution is described in a line; none yet is null', () => {
  seed();
  expect(lastEventOf(db, run)).toBeNull();
  recordEvents(db, run, [{ at: 5, kind: 'tool_start', tool: 'Bash', arg: 'pnpm test', callId: 'c' }], 0);
  expect(lastEventOf(db, run)).toEqual({ kind: 'tool_start', text: 'Bash pnpm test', at: 5 });
  recordEvents(db, run, [{ at: 6, kind: 'tool_end', tool: 'Bash', summary: '2 failed', callId: 'c' }], 0);
  expect(lastEventOf(db, run)).toEqual({ kind: 'tool_end', text: 'Bash 2 failed', at: 6 });
  recordEvents(db, run, [{ at: 7, kind: 'say', text: 'x'.repeat(500) }], 0);
  expect(lastEventOf(db, run)).toMatchObject({ kind: 'say', at: 7 });
  expect(lastEventOf(db, run)!.text).toHaveLength(200);
  expect(lastEventOf(db, other)).toBeNull();
});
