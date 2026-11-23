import { execFileSync, spawn } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { asc } from 'drizzle-orm';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import type { AgentRun, AgentTask } from '../execution/agent-runner.ts';
import type { AgentEvent } from '../execution/events.ts';
import { openDatabase } from '../storage/db.ts';
import { executionEvents, recordEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { buildClaudeCommand, claudeAdapter } from './claude.ts';
import { buildCodexCommand, codexAdapter } from './codex.ts';
import { HostAgentRunner } from './host-runner.ts';

const fakeBinary = join(import.meta.dirname, 'fake-claude.fixture.mjs');
const fakeCodex = join(import.meta.dirname, 'fake-codex.fixture.mjs');
const fakeAgy = join(import.meta.dirname, 'fake-agy.fixture.mjs');
const holder = join(import.meta.dirname, 'orphan-holder.fixture.ts');
let dir: string;
// Ids carry this process's pid, so a second run of this file (another worktree, another agent) never shares them.
const idOf = (name: string) => `it-${process.pid}-${name}`;
const tokens: Record<string, string> = { 'author-bot': 'ghs_AUTHOR_TOKEN', 'reviewer-bot': 'ghs_REVIEWER_TOKEN' };
const runner = new HostAgentRunner({
  binaries: { claude: fakeBinary, codex: fakeCodex, agy: fakeAgy },
  graceMs: 1000,
  credentials: async (task) => ({
    githubToken: tokens[task.profile] ?? '',
    gitIdentity: { name: `${task.profile}[bot]`, email: `1+${task.profile}[bot]@users.noreply.github.com` },
  }),
});

const taskIn = (name: string, over: Partial<AgentTask> = {}): AgentTask => {
  const workspace = join(dir, name);
  mkdirSync(workspace, { recursive: true });
  return {
    executionId: idOf(name),
    repo: 'AshuLab/carrier',
    epic: 3,
    stage: 'ship',
    profile: 'author-bot',
    harness: 'claude',
    model: 'ok',
    workspace,
    resultPath: join(dir, 'results', `${name}.json`),
    timeoutMs: null,
    context: { previousSummaries: [] },
    ...over,
  };
};

// The result the caller leaves when it finished its job, whatever the tool printed on the way.
const writeResult = (task: AgentTask) => {
  mkdirSync(join(task.resultPath, '..'), { recursive: true });
  const { executionId, repo, epic, stage } = task;
  writeFileSync(task.resultPath, JSON.stringify({ executionId, repo, epic, stage, outcome: 'needs_human', summary: 'done', reason: 'a person decides' }));
};

// Collects what a run reports, the way the engine does.
const observe = (run: AgentRun) => {
  const seen = { sessions: [] as string[], output: '' };
  run.onSession((id) => seen.sessions.push(id));
  run.onOutput((_stream, chunk) => (seen.output += chunk));
  return seen;
};

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-runner-'));
  chmodSync(fakeBinary, 0o755);
  chmodSync(fakeCodex, 0o755);
  chmodSync(fakeAgy, 0o755);
});
afterAll(async () => {
  // Only the agents this run started: `listActive` reads every `carrier-exec-` process of the machine, the one running this test included.
  for (const id of await runner.listActive()) if (id.startsWith(idOf(''))) await runner.stop(id);
  rmSync(dir, { recursive: true, force: true });
});

describe('host runner with a fake claude binary', () => {
  test('reports the session while running and the output', async () => {
    const run = runner.run(taskIn('basic'));
    const seen = observe(run);
    const { exit, sessionId } = await run.done;
    expect(exit).toBe('ok');
    expect(seen.sessions).toHaveLength(1);
    expect(sessionId).toBe(seen.sessions[0]);
    expect(seen.output).toContain('"subtype":"init"');
  });

  test('the events of a run are reported per chunk and stored; the rows match the stream', async () => {
    const run = runner.run(taskIn('events', { model: 'stream' }));
    const batches: AgentEvent[][] = [];
    run.onEvent((events) => batches.push(events));
    expect((await run.done).exit).toBe('ok');
    expect(batches.length).toBeGreaterThan(0);

    const db = openDatabase(join(dir, 'events.db'));
    const epic = db.insert(epics).values({ repo: 'AshuLab/a', issue: 1 }).returning().get();
    db.insert(executions).values({ executionId: 'it-events', epicId: epic.id, stage: 'ship', resultPath: 'r', startedAt: 0 }).run();
    for (const batch of batches) recordEvents(db, 'it-events', batch, 1);
    const rows = db.select().from(executionEvents).orderBy(asc(executionEvents.id)).all();
    db.$client.close();

    // The stream of claude-events.fixture.jsonl, in order: thinking, hooks and the unknown and garbage lines are not rows.
    expect(rows.map((row) => [row.kind, row.tool ?? row.agentId])).toEqual([
      ['say', null],
      ['tool_start', 'Read'],
      ['tool_end', 'Read'],
      ['tool_start', 'Edit'],
      ['tool_end', 'Edit'],
      ['tool_start', 'Bash'],
      ['tool_end', 'Bash'],
      ['note', null],
      ['tool_start', 'Agent'],
      ['task', 'agent-1'],
      ['tool_start', 'Bash'],
      ['tool_end', 'Bash'],
      ['task', 'agent-1'],
      ['error', null],
    ]);
    expect(rows.filter((row) => row.kind === 'tool_end').map((row) => [row.callId, row.status, row.durationMs])).toEqual([
      ['toolu_read', 'ok', 150],
      ['toolu_edit', 'ok', 200],
      ['toolu_bash', 'err', 7000],
      ['toolu_sub', 'ok', 300],
    ]);
    expect(rows.find((row) => row.callId === 'toolu_edit' && row.kind === 'tool_end')?.payload?.diff).toHaveLength(3);
  });

  const hostClues = { hostFreeMemMb: expect.any(Number), hostLoad: expect.any(Number) };

  test('a nonzero exit is crashed, with the code and the host', async () => {
    expect(await runner.run(taskIn('fail', { model: 'fail' })).done).toMatchObject({
      exit: 'failed',
      failure: { kind: 'crashed', detail: 'exit code 3', exitCode: 3, signal: null, ...hostClues },
    });
  });

  test('a process that kills itself with SIGKILL is killed, with the signal and the host', async () => {
    const { exit, failure } = await runner.run(taskIn('kill', { model: 'kill' })).done;
    expect(exit).toBe('failed');
    expect(failure).toEqual({ kind: 'killed', detail: 'SIGKILL', exitCode: null, signal: 'SIGKILL', hostFreeMemMb: expect.any(Number), hostLoad: expect.any(Number) });
    expect(failure!.hostFreeMemMb).toBeGreaterThan(0);
  });

  test('a usage limit printed by claude is usage_limit and not crashed, with the exit code', async () => {
    expect(await runner.run(taskIn('usage-limit', { model: 'usage_limit' })).done).toEqual({
      exit: 'failed',
      sessionId: expect.any(String),
      usage: expect.any(Object),
      failure: { kind: 'usage_limit', detail: "You've hit your session limit · resets 12:40pm (America/Montevideo)", exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null },
    });
  });

  test('a binary that does not exist is spawn_error, without host clues', async () => {
    const missing = new HostAgentRunner({ binaries: { claude: join(dir, 'no-such-binary') }, credentials: async () => ({ githubToken: 't' }) });
    const run = missing.run(taskIn('missing'));
    const seen = observe(run);
    expect(await run.done).toMatchObject({
      exit: 'failed',
      failure: { kind: 'spawn_error', exitCode: null, signal: null, hostFreeMemMb: null, hostLoad: null },
    });
    expect(seen.output).toContain('cannot start');
  });

  test('a token in the final output, or in the path of a binary, is in no part of the failure', async () => {
    const token = `ghp_${'a'.repeat(36)}`;
    const crashed = await runner.run(taskIn('token', { model: 'token' })).done;
    const missing = new HostAgentRunner({ binaries: { claude: join(dir, 'p'.repeat(265 - dir.length), token) }, credentials: async () => ({ githubToken: 't' }) });
    const spawnFailed = await missing.run(taskIn('token-path')).done;
    expect(spawnFailed.failure!.kind).toBe('spawn_error');
    for (const { failure } of [crashed, spawnFailed]) expect(JSON.stringify(failure)).not.toMatch(/ghp_|aaaa/);
  });

  test('two parallel runs with different profiles do not share the GitHub token, and it is not in the output', async () => {
    const a = taskIn('par-a', { model: 'env', profile: 'author-bot' });
    const b = taskIn('par-b', { model: 'env', profile: 'reviewer-bot' });
    const [runA, runB] = [runner.run(a), runner.run(b)];
    const seen = [observe(runA), observe(runB)];
    expect(await Promise.all([runA.done, runB.done])).toMatchObject([{ exit: 'ok' }, { exit: 'ok' }]);
    const envOf = (t: AgentTask) => JSON.parse(readFileSync(join(t.workspace, 'env.json'), 'utf8'));
    expect(envOf(a)).toMatchObject({ GH_TOKEN: tokens['author-bot'], GITHUB_TOKEN: tokens['author-bot'], GIT_AUTHOR_NAME: 'author-bot[bot]' });
    expect(envOf(b)).toMatchObject({ GH_TOKEN: tokens['reviewer-bot'], GITHUB_TOKEN: tokens['reviewer-bot'], GIT_AUTHOR_NAME: 'reviewer-bot[bot]' });
    expect(JSON.stringify(envOf(a).args)).not.toContain('ghs_');
    for (const { output } of seen) expect(output).not.toMatch(/ghs_/);
  });

  test('stop() ends the agent', async () => {
    const run = runner.run(taskIn('stop', { model: 'hang' }));
    const seen = observe(run);
    await expect.poll(() => seen.sessions.length).toBe(1);
    const pid = Number(seen.sessions[0]!.replace('session-', ''));
    await run.stop();
    expect(await run.done).toMatchObject({ exit: 'stopped' });
    expect(() => process.kill(pid, 0)).toThrow();
    expect(await runner.listActive()).not.toContain(idOf('stop'));
  });

  test('timeoutMs gives timed_out', async () => {
    const run = runner.run(taskIn('timeout', { model: 'hang', timeoutMs: 500 }));
    const started = Date.now();
    expect(await run.done).toMatchObject({ exit: 'timed_out' });
    expect(Date.now() - started).toBeLessThan(5000);
  });

  test('idleMs kills a process that writes nothing for that long, as a technical failure with its session', async () => {
    const run = runner.run(taskIn('idle', { model: 'hang', idleMs: 500 }));
    const seen = observe(run);
    const started = Date.now();
    const done = await run.done;
    expect(done).toMatchObject({ exit: 'failed', failure: { kind: 'killed', detail: 'no output for 0.5 seconds' }, sessionId: seen.sessions[0] });
    expect(Date.now() - started).toBeLessThan(5000);
    expect(() => process.kill(Number(seen.sessions[0]!.replace('session-', '')), 0)).toThrow();
  });

  test('a process that keeps writing is not idle, and one with no idleMs is never touched', async () => {
    expect((await runner.run(taskIn('chatty', { model: 'chatty', idleMs: 600 })).done).exit).toBe('ok');
    const silent = runner.run(taskIn('silent', { model: 'hang' }));
    const seen = observe(silent);
    await expect.poll(() => seen.sessions.length).toBe(1);
    await new Promise((r) => setTimeout(r, 1500));
    expect(await runner.listActive()).toContain(idOf('silent'));
    await silent.stop();
  });

  test('a login error shaped like the real one is auth_failed', async () => {
    expect((await runner.run(taskIn('auth', { model: 'auth' })).done).exit).toBe('auth_failed');
  });

  const childPid = (task: AgentTask) => Number(readFileSync(join(task.workspace, 'child.pid'), 'utf8'));
  const gone = (pid: number) => () => {
    try {
      process.kill(pid, 0);
      return false;
    } catch {
      return true;
    }
  };

  test('a leader that exits leaves no process of its group alive', async () => {
    const task = taskIn('group-exit', { model: 'child' });
    expect((await runner.run(task).done).exit).toBe('ok');
    await expect.poll(gone(childPid(task))).toBe(true);
  });

  test('stop() kills the child of a leader that already exited on SIGTERM', async () => {
    const task = taskIn('group-term', { model: 'child-term' });
    const run = runner.run(task);
    const seen = observe(run);
    await expect.poll(() => seen.sessions.length).toBe(1);
    await run.stop();
    await expect.poll(gone(childPid(task))).toBe(true);
  });

  test('a leader that exits while a child outside its group holds its stdout ends the run without waiting for the pipe', async () => {
    const task = taskIn('pipe-held', { model: 'child-escaped' });
    const started = Date.now();
    try {
      expect((await runner.run(task).done).exit).toBe('ok');
      expect(Date.now() - started).toBeLessThan(4000);
      expect(gone(childPid(task))()).toBe(false);
    } finally {
      process.kill(childPid(task), 'SIGKILL');
    }
  });

  test('no token for the profile is auth_failed and does not start the agent', async () => {
    const failing = new HostAgentRunner({ binaries: { claude: fakeBinary }, credentials: async () => { throw new Error('Agent not found: x'); } });
    const run = failing.run(taskIn('no-token'));
    const seen = observe(run);
    expect((await run.done).exit).toBe('auth_failed');
    expect(seen.output).toContain('Agent not found: x');
  });

  test.each([
    ['claude', fakeBinary],
    ['codex', fakeCodex],
  ] as const)('listActive sees a %s execution orphaned by kill -9 of its carrier, and stop(id) ends it', async (harness, binary) => {
    const id = idOf(`orphan-${harness}`);
    const workspace = join(dir, id);
    mkdirSync(workspace);
    const carrier = spawn(process.execPath, [holder, binary, workspace, harness, id], { stdio: ['ignore', 'pipe', 'inherit'] });
    await new Promise<void>((resolve, reject) => {
      carrier.stdout.on('data', (d: Buffer) => d.toString().includes('ready') && resolve());
      carrier.on('exit', () => reject(new Error('holder exited before ready')));
    });
    carrier.kill('SIGKILL');
    await new Promise((r) => carrier.on('exit', r));
    // A new carrier process: no handle, only what the OS shows.
    expect(await runner.listActive()).toContain(id);
    await runner.stop(id);
    expect(await runner.listActive()).not.toContain(id);
  });
});

// An exit 0 after an error the adapter recognizes is a failure of that error's kind, unless the caller left a valid result.
describe('a process that exits 0 after printing an error', () => {
  const printed = [
    { harness: 'claude', model: 'usage_limit_exit0', kind: 'usage_limit' },
    { harness: 'codex', model: 'usage_not_included', kind: 'usage_limit' },
    { harness: 'codex', model: 'api_error_exit0', kind: 'api_error' },
    { harness: 'agy', model: 'any', kind: 'usage_limit' },
  ] as const;

  test.each(printed)('$harness $model with no result file is a failure of kind $kind', async ({ harness, model, kind }) => {
    const done = await runner.run(taskIn(`exit0-${harness}-${model}`, { harness, model })).done;
    expect(done).toMatchObject({ exit: 'failed', failure: { kind, exitCode: 0, signal: null } });
  });

  test.each(printed)('$harness $model with an invalid result file is still a failure', async ({ harness, model, kind }) => {
    const task = taskIn(`exit0-invalid-${harness}-${model}`, { harness, model });
    mkdirSync(join(task.resultPath, '..'), { recursive: true });
    writeFileSync(task.resultPath, '{"outcome":"completed"}');
    expect(await runner.run(task).done).toMatchObject({ exit: 'failed', failure: { kind } });
  });

  test.each(printed)('$harness $model with a valid result file is a success', async ({ harness, model }) => {
    const task = taskIn(`exit0-recovered-${harness}-${model}`, { harness, model });
    writeResult(task);
    expect(await runner.run(task).done).toMatchObject({ exit: 'ok' });
  });
});

describe('host runner with a fake codex binary', () => {
  const codexTask = (name: string, over: Partial<AgentTask> = {}) => taskIn(name, { harness: 'codex', ...over });

  test('reports the thread as session while running, the output, and resumes by id', async () => {
    const run = runner.run(codexTask('codex-basic'));
    const seen = observe(run);
    const { exit, sessionId } = await run.done;
    expect(exit).toBe('ok');
    expect(seen.sessions).toEqual([sessionId]);
    expect(seen.output).toContain('"type":"thread.started"');

    const again = runner.run(codexTask('codex-resume', { resumeSession: sessionId }));
    const seenAgain = observe(again);
    expect(await again.done).toEqual({ exit: 'ok', sessionId });
    expect(seenAgain.sessions).toEqual([sessionId]);
  });

  test('the events of a recorded run are reported per chunk, in the order of the stream', async () => {
    const run = runner.run(codexTask('codex-events', { model: 'stream' }));
    const batches: AgentEvent[][] = [];
    run.onEvent((events) => batches.push(events));
    expect((await run.done).exit).toBe('ok');
    expect(batches.flat().map((e) => [e.kind, e.callId])).toEqual([
      ['note', undefined],
      ['note', undefined],
      ['say', undefined],
      ...['item_3', 'item_4', 'item_5', 'item_6'].flatMap((id) => [['tool_start', id], ['tool_end', id]]),
      ['say', undefined],
    ]);
  });

  test('a nonzero exit is failed', async () => {
    expect((await runner.run(codexTask('codex-fail', { model: 'fail' })).done).exit).toBe('failed');
  });

  test('the GitHub token reaches the child env only, not argv or output', async () => {
    const task = codexTask('codex-env', { model: 'env' });
    const run = runner.run(task);
    const seen = observe(run);
    expect((await run.done).exit).toBe('ok');
    const env = JSON.parse(readFileSync(join(task.workspace, 'env.json'), 'utf8'));
    expect(env).toMatchObject({ GH_TOKEN: tokens['author-bot'], GITHUB_TOKEN: tokens['author-bot'], GIT_AUTHOR_NAME: 'author-bot[bot]' });
    expect(JSON.stringify(env.args)).not.toContain('ghs_');
    expect(seen.output).not.toMatch(/ghs_/);
  });

  test('stop() ends the agent', async () => {
    const run = runner.run(codexTask('codex-stop', { model: 'hang' }));
    const seen = observe(run);
    await expect.poll(() => seen.sessions.length).toBe(1);
    const pid = Number(seen.sessions[0]!.replace('session-', ''));
    expect(await runner.listActive()).toContain(idOf('codex-stop'));
    await run.stop();
    expect(await run.done).toMatchObject({ exit: 'stopped' });
    expect(() => process.kill(pid, 0)).toThrow();
    expect(await runner.listActive()).not.toContain(idOf('codex-stop'));
  });

  test('timeoutMs gives timed_out', async () => {
    const run = runner.run(codexTask('codex-timeout', { model: 'hang', timeoutMs: 500 }));
    const started = Date.now();
    expect(await run.done).toMatchObject({ exit: 'timed_out' });
    expect(Date.now() - started).toBeLessThan(5000);
  });

  test('a login error shaped like the real one is auth_failed, a 401 retry that recovers is not', async () => {
    expect((await runner.run(codexTask('codex-auth', { model: 'auth' })).done).exit).toBe('auth_failed');
    expect((await runner.run(codexTask('codex-retry', { model: 'retry' })).done).exit).toBe('ok');
  });

  test('a lost session, reported only on stderr, is session_unavailable', async () => {
    expect((await runner.run(codexTask('codex-lost', { model: 'lost', resumeSession: 'x' })).done).exit).toBe('session_unavailable');
  });
});

// Real claude against a throwaway local repo: costs a few cents of haiku, so it is opt-in.
describe.skipIf(!process.env.CARRIER_TEST_CLAUDE)('real claude CLI (set CARRIER_TEST_CLAUDE=1 to run)', () => {
  let repo: string;
  let prompt = '';
  // The real prompt invokes the ship skill; a tiny one keeps the run cheap. Everything else is the real command.
  const real = new HostAgentRunner({
    adapters: { claude: { ...claudeAdapter, command: (task, ctx) => { const c = buildClaudeCommand(task, ctx); c.args[1] = prompt; return c; } } },
    credentials: async () => ({ githubToken: 'ghs_NOT_A_REAL_TOKEN' }),
  });

  beforeAll(() => {
    repo = join(dir, 'real-repo');
    mkdirSync(repo);
    execFileSync('git', ['init', '-q'], { cwd: repo });
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'init'], { cwd: repo });
  });
  afterAll(() => {
    // Sessions this test created live in a folder named after the throwaway repo's path.
    const sessions = join(process.env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude'), 'projects', realpathSync(repo).replace(/[^a-zA-Z0-9]/g, '-'));
    rmSync(sessions, { recursive: true, force: true });
  });

  test('runs headless, reports the session while running, then resumes it and remembers', async () => {
    const codeword = `TANGERINE-${Math.floor(Math.random() * 1e6)}`;
    const base = { model: 'haiku', workspace: repo, timeoutMs: 180_000 };

    prompt = `Remember the codeword ${codeword}. Reply only OK.`;
    const first = real.run(taskIn('real-1', base));
    const seen = observe(first);
    const { exit, sessionId } = await first.done;
    expect(exit).toBe('ok');
    expect(seen.sessions).toEqual([sessionId]);
    expect(seen.output).toContain('"type":"result"');

    prompt = 'What was the codeword? Reply with only the codeword.';
    const second = real.run(taskIn('real-2', { ...base, resumeSession: sessionId }));
    const again = observe(second);
    expect((await second.done).exit).toBe('ok');
    expect(again.sessions).toEqual([sessionId]);
    const result = again.output.split('\n').find((l) => l.includes('"type":"result"'))!;
    expect(JSON.parse(result).result).toContain(codeword);
  }, 400_000);

  test('a resume of a session that does not exist is session_unavailable', async () => {
    prompt = 'hi';
    const run = real.run(taskIn('real-lost', { model: 'haiku', workspace: repo, resumeSession: '00000000-0000-4000-8000-000000000000', timeoutMs: 60_000 }));
    expect((await run.done).exit).toBe('session_unavailable');
  });
});

// Real codex against a throwaway local repo: spends a little of the cheapest model, so it is opt-in.
describe.skipIf(!process.env.CARRIER_TEST_CODEX)('real codex CLI (set CARRIER_TEST_CODEX=1 to run)', () => {
  let repo: string;
  let prompt = '';
  let codexHome: string | undefined;
  // The real prompt invokes the ship skill; a tiny one keeps the run cheap. Everything else is the real command.
  const real = new HostAgentRunner({
    adapters: {
      codex: {
        ...codexAdapter,
        command: (task, ctx) => {
          const c = buildCodexCommand(task, ctx);
          c.args[c.args.indexOf(buildPrompt(task))] = prompt;
          c.args.push('-c', 'model_reasoning_effort="low"');
          if (codexHome) c.env.CODEX_HOME = codexHome;
          return c;
        },
      },
    },
    credentials: async () => ({ githubToken: 'ghs_NOT_A_REAL_TOKEN' }),
  });
  const sessionIds: string[] = [];

  beforeAll(() => {
    repo = join(dir, 'real-codex-repo');
    mkdirSync(repo);
    execFileSync('git', ['init', '-q'], { cwd: repo });
    execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', 'commit', '-q', '--allow-empty', '-m', 'init'], { cwd: repo });
  });
  afterAll(() => {
    // Rollouts this test created are named after their thread id.
    const sessions = join(process.env.CODEX_HOME ?? join(homedir(), '.codex'), 'sessions');
    for (const id of sessionIds) execFileSync('find', [sessions, '-name', `rollout-*-${id}.jsonl`, '-delete']);
  });

  const codexModel = 'gpt-5.6-luna';
  const base = () => ({ harness: 'codex' as const, model: codexModel, workspace: repo, timeoutMs: 180_000 });

  test('runs headless, reports the session while running, writes outside the workspace, then resumes and remembers', async () => {
    const codeword = `TANGERINE-${Math.floor(Math.random() * 1e6)}`;
    const first = taskIn('codex-real-1', base());
    prompt = `Remember the codeword ${codeword}. Write the text OK to the file ${first.resultPath} (create its folder if needed), then reply only OK.`;
    const run = real.run(first);
    const seen = observe(run);
    const { exit, sessionId } = await run.done;
    sessionIds.push(sessionId!);
    expect(exit).toBe('ok');
    expect(seen.sessions).toEqual([sessionId]);
    expect(seen.output).toContain('"type":"turn.completed"');
    expect(readFileSync(first.resultPath, 'utf8')).toContain('OK');

    prompt = 'What was the codeword? Reply with only the codeword.';
    const second = real.run(taskIn('codex-real-2', { ...base(), resumeSession: sessionId }));
    const again = observe(second);
    expect((await second.done).exit).toBe('ok');
    expect(again.sessions).toEqual([sessionId]);
    expect(again.output).toContain(codeword);
  }, 400_000);

  test('a resume of a thread that does not exist is session_unavailable', async () => {
    prompt = 'hi';
    const run = real.run(taskIn('codex-real-lost', { ...base(), resumeSession: '00000000-0000-4000-8000-000000000000', timeoutMs: 60_000 }));
    expect((await run.done).exit).toBe('session_unavailable');
  });

  test('a CODEX_HOME without login is auth_failed', async () => {
    codexHome = mkdtempSync(join(tmpdir(), 'carrier-codex-home-'));
    prompt = 'hi';
    try {
      const run = real.run(taskIn('codex-real-auth', { ...base(), timeoutMs: 150_000 }));
      const seen = observe(run);
      const { exit, sessionId } = await run.done;
      if (sessionId) sessionIds.push(sessionId);
      expect(exit).toBe('auth_failed');
      expect(seen.output).not.toContain('ghs_');
    } finally {
      rmSync(codexHome, { recursive: true, force: true });
      codexHome = undefined;
    }
  }, 200_000);
});
