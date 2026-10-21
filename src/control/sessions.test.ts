import { mkdtempSync, rmSync } from 'node:fs';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { startControlServer } from './server.ts';
import { sessionsOf } from './sessions.ts';

// The sessions request over a real socket, answered from a real (temp) SQLite.
let dir: string;
let db: Db;
let close: () => void;
beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), 'cs-')); // short: a socket path holds 103 bytes on macOS
  db = openDatabase(join(dir, 'carrier.db'));
  const controls = {
    poll: () => {},
    setPaused: () => {},
    logs: () => [],
    sessions: (repo: string, issue: number) => sessionsOf(db, repo, issue, { claude: '/cfg/claude' }),
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
const epic = (issue: number, status: (typeof epics.$inferInsert)['status']) =>
  db.insert(epics).values({ repo: 'AshuLab/a', issue, status, config }).returning({ id: epics.id }).get().id;
const execution = (epicId: number, n: number, extra: Partial<typeof executions.$inferInsert>) =>
  db.insert(executions).values({ executionId: `00000000-0000-4000-8000-00000000000${n}`, epicId, stage: 'ship', resultPath: '/r.json', startedAt: n * 1000, ...extra }).run();
const ran = { harness: 'claude', model: 'opus', provider: null, workspace: '/work/clone', sessionId: 'sess-1' };

async function ask(issue: number) {
  const socket = connect(join(dir, 'control.sock'));
  socket.setEncoding('utf8');
  const lines: string[] = [];
  const waiting: ((line: string) => void)[] = [];
  let buffer = '';
  socket.on('data', (chunk: string) => {
    buffer += chunk;
    for (let end = buffer.indexOf('\n'); end >= 0; end = buffer.indexOf('\n')) {
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 1);
      (waiting.shift() ?? ((l) => lines.push(l)))(line);
    }
  });
  const next = () => new Promise<string>((resolve) => (lines.length ? resolve(lines.shift()!) : waiting.push(resolve)));
  const hello = JSON.parse(await next());
  socket.write(`${JSON.stringify({ id: 1, cmd: 'sessions', repo: 'AshuLab/a', issue })}\n`);
  const reply = JSON.parse(await next());
  socket.destroy();
  return { hello, reply };
}

test('the hello lists sessions', async () => {
  expect((await ask(1)).hello.capabilities).toContain('sessions');
});

test('a queued epic has no sessions, and an unknown one is an error', async () => {
  epic(1, 'queued');
  expect((await ask(1)).reply).toEqual({ id: 1, ok: true, data: { sessions: [] } });
  expect((await ask(99)).reply).toEqual({ id: 1, ok: false, error: 'unknown epic' });
});

test('a running epic lists its session newest first, with no descriptor while it runs', async () => {
  const id = epic(2, 'running');
  execution(id, 1, { ...ran, status: 'finished', finishedAt: 1500 });
  execution(id, 2, { ...ran, stage: 'review', harness: 'codex', model: 'gpt', provider: 'ollama', status: 'running', round: 1, sessionId: 'sess-2' });
  const { sessions } = (await ask(2)).reply.data;
  expect(sessions.map((s: { executionId: string }) => s.executionId.slice(-1))).toEqual(['2', '1']);
  expect(sessions[0]).toEqual({
    executionId: '00000000-0000-4000-8000-000000000002', stage: 'review', role: 'reviewer', round: 1,
    agent: { harness: 'codex', model: 'gpt', provider: 'ollama' }, status: 'running', startedAt: 2000, finishedAt: null, resume: null,
  });
  expect(sessions[1].resume).toEqual({ harness: 'claude', sessionId: 'sess-1', cwd: '/work/clone', configDir: '/cfg/claude' });
});

test('a stopped epic: the interrupted and failed sessions carry a descriptor with exactly the harness, id, folder and configuration folder', async () => {
  const id = epic(3, 'needs_human');
  execution(id, 1, { ...ran, status: 'failed', finishedAt: 1500, error: 'boom' });
  execution(id, 2, { ...ran, stage: 'fix', round: 2, status: 'interrupted', finishedAt: 2500, sessionId: 'sess-3' });
  const { sessions } = (await ask(3)).reply.data;
  expect(sessions.map((s: { status: string }) => s.status)).toEqual(['interrupted', 'failed']);
  for (const s of sessions) expect(Object.keys(s.resume).sort()).toEqual(['configDir', 'cwd', 'harness', 'sessionId']);
  expect(sessions[0]).toMatchObject({ stage: 'fix', role: 'author', round: 2, resume: { sessionId: 'sess-3' } });
});

test('a finished epic lists the descriptors; a harness with no configuration folder omits it, and a session without an id or folder has none', async () => {
  const id = epic(4, 'ready_for_test');
  execution(id, 1, { ...ran, harness: 'codex', status: 'finished', finishedAt: 1500 });
  execution(id, 2, { ...ran, status: 'finished', finishedAt: 2500, sessionId: null });
  execution(id, 3, { ...ran, status: 'finished', finishedAt: 3500, workspace: null });
  const { sessions } = (await ask(4)).reply.data;
  expect(sessions.map((s: { resume: unknown }) => s.resume)).toEqual([null, null, { harness: 'codex', sessionId: 'sess-1', cwd: '/work/clone' }]);
});

test('an execution from before the agent was recorded takes the agent from the epic\'s frozen configuration and has no descriptor', async () => {
  const id = epic(5, 'ready_for_test');
  execution(id, 1, { stage: 'review', status: 'finished', finishedAt: 1500, sessionId: 'sess-1' });
  const { sessions } = (await ask(5)).reply.data;
  expect(sessions[0]).toMatchObject({ role: 'reviewer', round: null, agent: { harness: 'codex', model: 'm', provider: null }, resume: null });
});
