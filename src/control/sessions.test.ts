import { mkdtempSync, rmSync } from 'node:fs';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase, type Db } from '../storage/db.ts';
import { callerResults } from '../storage/caller-results.ts';
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
    epic: () => null,
    events: () => null,
    files: () => null, fileDiff: () => null,
    availableRepos: () => Promise.resolve({ repos: [], hasMore: false }), resumeEpic: () => Promise.resolve(),
  };
  close = (await startControlServer({ orchestratorDir: dir, snapshot: () => ({}), startedAt: 1, controls, stop: async () => {} })).close;
});
afterEach(() => {
  close();
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const agent = { profile: 'p', option: 'o', harness: 'claude' as const, model: 'm' };
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
    agent: { harness: 'codex', model: 'gpt', provider: 'ollama' }, status: 'running', startedAt: 2000, finishedAt: null, resume: null, result: null, failure: null,
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

const sha = 'a'.repeat(40);
const imported = (n: number, result: object) =>
  db.insert(callerResults).values({ executionId: `00000000-0000-4000-8000-00000000000${n}`, outcome: (result as { outcome: string }).outcome, result: JSON.stringify(result) }).run();
const common = { repo: 'AshuLab/a', epic: 6, summary: 'Did the work.' };

test('each outcome returns its result; a running session and one with no imported result have none', async () => {
  const id = epic(6, 'ready_for_test');
  execution(id, 1, { ...ran, status: 'finished', finishedAt: 1500 });
  execution(id, 2, { ...ran, stage: 'review', status: 'finished', finishedAt: 2500 });
  execution(id, 3, { ...ran, stage: 'review', status: 'finished', finishedAt: 3500 });
  execution(id, 4, { ...ran, status: 'finished', finishedAt: 4500 });
  execution(id, 5, { ...ran, status: 'running' });
  imported(1, { ...common, executionId: '00000000-0000-4000-8000-000000000001', stage: 'ship', outcome: 'completed', pr: { number: 7, headSha: sha }, verification: { ci: 'absent', evidence: 'No CI configured.' } });
  imported(2, { ...common, executionId: '00000000-0000-4000-8000-000000000002', stage: 'review', outcome: 'changes_requested', pr: { number: 7, headSha: sha }, blockers: [{ title: 'Missing test' }] });
  imported(3, { ...common, executionId: '00000000-0000-4000-8000-000000000003', stage: 'review', outcome: 'needs_human', reason: 'Which of the two wins?' });
  const { sessions } = (await ask(6)).reply.data;
  expect(sessions.map((s: { result: unknown }) => s.result)).toEqual([
    null, // running
    null, // finished, no result imported
    { outcome: 'needs_human', summary: 'Did the work.', verification: null, reason: 'Which of the two wins?' },
    { outcome: 'changes_requested', summary: 'Did the work.', verification: null, reason: null },
    { outcome: 'completed', summary: 'Did the work.', verification: { ci: 'absent', evidence: 'No CI configured.' }, reason: null },
  ]);
});

test('a token in the summary, the evidence or the reason is redacted, and each field is cut at its limit', async () => {
  const id = epic(7, 'needs_human');
  const token = `ghp_${'x'.repeat(30)}`;
  execution(id, 1, { ...ran, status: 'finished', finishedAt: 1500 });
  execution(id, 2, { ...ran, stage: 'review', status: 'finished', finishedAt: 2500 });
  imported(1, {
    ...common, epic: 7, executionId: '00000000-0000-4000-8000-000000000001', stage: 'ship', outcome: 'completed', pr: { number: 7, headSha: sha },
    summary: `${token} ${'s'.repeat(2000)}`, verification: { ci: 'passed', evidence: `${token} ${'e'.repeat(1000)}` },
  });
  imported(2, { ...common, epic: 7, executionId: '00000000-0000-4000-8000-000000000002', stage: 'review', outcome: 'needs_human', summary: 'Stopped.', reason: `${token} ${'r'.repeat(1000)}` });
  const [needsHuman, completed] = (await ask(7)).reply.data.sessions.map((s: { result: object }) => s.result) as any[];
  expect(completed.summary).toBe(`[redacted] ${'s'.repeat(1500 - '[redacted] '.length)}`);
  expect(completed.verification.evidence).toBe(`[redacted] ${'e'.repeat(600 - '[redacted] '.length)}`);
  expect(needsHuman.reason).toBe(`[redacted] ${'r'.repeat(600 - '[redacted] '.length)}`);
  expect(JSON.stringify([needsHuman, completed])).not.toContain('ghp_');
});

test('a failed execution serves its kind after the retry cleared the epic\'s last error; one with no kind, and one that ended ok, serve null', async () => {
  const id = epic(8, 'ready_for_test');
  execution(id, 1, { ...ran, status: 'failed', finishedAt: 1500, error: 'the agent process ended with an error (killed: SIGKILL)', failureKind: 'killed', failureDetail: 'SIGKILL', signal: 'SIGKILL', hostFreeMemMb: 812, hostLoad: 6.4 });
  execution(id, 2, { ...ran, status: 'failed', finishedAt: 2500, error: 'boom' }); // written before the kind existed
  execution(id, 3, { ...ran, status: 'finished', finishedAt: 3500 });
  db.update(epics).set({ lastError: null }).where(eq(epics.id, id)).run();
  const { sessions } = (await ask(8)).reply.data;
  expect(sessions.map((s: { failure: unknown }) => s.failure)).toEqual([null, null, { kind: 'killed', detail: 'SIGKILL', exitCode: null, signal: 'SIGKILL', hostFreeMemMb: 812, hostLoad: 6.4 }]);
});

test('a failure detail that holds a token and runs past 300 characters is served redacted and cut', async () => {
  const id = epic(9, 'needs_human');
  const token = `ghp_${'x'.repeat(30)}`;
  execution(id, 1, { ...ran, status: 'failed', finishedAt: 1500, failureKind: 'unknown', failureDetail: `${token} ${'d'.repeat(400)}` });
  const [{ failure }] = (await ask(9)).reply.data.sessions;
  expect(failure.detail).toBe(`[redacted] ${'d'.repeat(300 - '[redacted] '.length)}`);
});
