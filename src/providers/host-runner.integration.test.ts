import { execFileSync, spawn } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import type { AgentRun, AgentTask } from '../execution/agent-runner.ts';
import { buildClaudeCommand, claudeAdapter } from './claude.ts';
import { HostAgentRunner } from './host-runner.ts';

const fakeBinary = join(import.meta.dirname, 'fake-claude.fixture.mjs');
const holder = join(import.meta.dirname, 'orphan-holder.fixture.ts');
let dir: string;
const tokens: Record<string, string> = { 'author-bot': 'ghs_AUTHOR_TOKEN', 'reviewer-bot': 'ghs_REVIEWER_TOKEN' };
const runner = new HostAgentRunner({
  binaries: { claude: fakeBinary },
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
    executionId: `it-${name}`,
    repo: 'AshuLab/carrier',
    epic: 3,
    stage: 'ship',
    profile: 'author-bot',
    provider: 'claude',
    model: 'ok',
    workspace,
    resultPath: join(dir, 'results', `${name}.json`),
    timeoutMs: null,
    context: { previousSummaries: [] },
    ...over,
  };
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
});
afterAll(async () => {
  for (const id of await runner.listActive()) await runner.stop(id);
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

  test('a nonzero exit is failed', async () => {
    expect((await runner.run(taskIn('fail', { model: 'fail' })).done).exit).toBe('failed');
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
    expect(await runner.listActive()).not.toContain('it-stop');
  });

  test('timeoutMs gives timed_out', async () => {
    const run = runner.run(taskIn('timeout', { model: 'hang', timeoutMs: 500 }));
    const started = Date.now();
    expect(await run.done).toMatchObject({ exit: 'timed_out' });
    expect(Date.now() - started).toBeLessThan(5000);
  });

  test('a login error shaped like the real one is auth_failed', async () => {
    expect((await runner.run(taskIn('auth', { model: 'auth' })).done).exit).toBe('auth_failed');
  });

  test('no token for the profile is auth_failed and does not start the agent', async () => {
    const failing = new HostAgentRunner({ binaries: { claude: fakeBinary }, credentials: async () => { throw new Error('Agent not found: x'); } });
    const run = failing.run(taskIn('no-token'));
    const seen = observe(run);
    expect((await run.done).exit).toBe('auth_failed');
    expect(seen.output).toContain('Agent not found: x');
  });

  test('listActive sees an execution orphaned by kill -9 of its carrier, and stop(id) ends it', async () => {
    const workspace = join(dir, 'orphan');
    mkdirSync(workspace);
    const carrier = spawn(process.execPath, [holder, fakeBinary, workspace], { stdio: ['ignore', 'pipe', 'inherit'] });
    await new Promise<void>((resolve, reject) => {
      carrier.stdout.on('data', (d: Buffer) => d.toString().includes('ready') && resolve());
      carrier.on('exit', () => reject(new Error('holder exited before ready')));
    });
    carrier.kill('SIGKILL');
    await new Promise((r) => carrier.on('exit', r));
    // A new carrier process: no handle, only what the OS shows.
    expect(await runner.listActive()).toContain('orphan-1');
    await runner.stop('orphan-1');
    expect(await runner.listActive()).not.toContain('orphan-1');
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
