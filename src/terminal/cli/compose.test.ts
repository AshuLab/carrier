import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { loadConfig, defaults } from '../../config/load.ts';
import type { Config } from '../../config/schema.ts';
import { FakeAgentRunner, FakeWorkspaces } from '../../execution/fake.ts';
import type { GitWorkspacesOptions } from '../../execution/git-workspaces.ts';
import type { GhGitHubOptions } from '../../integrations/github.ts';
import { FakeClock, FakeGitHub } from '../../orchestration/fake.ts';
import type { HostRunnerOptions } from '../../harnesses/host-runner.ts';
import { acquireLock } from '../../storage/lock.ts';
import { InstanceBusy, startCarrier, type CarrierDeps } from './compose.ts';

const MIN = 60_000;
let root: string;
let closers: (() => Promise<void>)[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'carrier-compose-'));
  closers = [];
});
afterEach(async () => {
  for (const close of closers) await close();
  rmSync(root, { recursive: true, force: true });
});

const config = (user: object = {}): Config => {
  const result = loadConfig(defaults, {
    root,
    pollIntervalMinutes: 1,
    logLevel: 'debug',
    repos: [{ name: 'AshuLab/a', agents: { reviewer: { model: 'override' } } }, { name: 'AshuLab/b' }],
    profiles: { orchestrator: { kind: 'gh' }, 'author-bot': { kind: 'forge', agent: 'artanis-agent' }, 'reviewer-bot': { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'orchestrator',
    agents: {
      author: { profile: 'author-bot', harness: 'claude', model: 'm' },
      reviewer: { profile: 'reviewer-bot', harness: 'codex', model: 'm' },
    },
    limits: { maxConcurrentEpics: 2, maxReviews: 4, maxExecutionRetries: 1, maxExecutionHours: 2, githubCallTimeoutSeconds: 7 },
    ...user,
  });
  if (!result.ok) throw new Error(JSON.stringify(result.errors));
  return result.config;
};

// Fakes in every seam: nothing here reaches GitHub, Forge or a real agent.
function fakes() {
  const seen = { logging: [] as [string, string][], github: undefined as GhGitHubOptions | undefined, workspaces: undefined as GitWorkspacesOptions | undefined, runner: undefined as HostRunnerOptions | undefined, minted: [] as string[], sigint: 0, panel: [] as string[] };
  const github = new FakeGitHub();
  const runner = new FakeAgentRunner();
  const clock = new FakeClock();
  const deps: Partial<CarrierDeps> = {
    installLogging: (file, level) => seen.logging.push([file, level]),
    clock,
    makeGitHub: (options) => ((seen.github = options), github),
    makeWorkspaces: (options) => ((seen.workspaces = options), new FakeWorkspaces()),
    makeRunner: (options) => ((seen.runner = options), runner),
    mint: async (profile, repo) => (seen.minted.push(`${profile.kind === 'forge' ? profile.agent : 'gh'}@${repo}`), 'ghs_fake'),
    botId: async () => 99,
    sessionDirs: { claude: join(root, 'claude'), codex: join(root, 'codex') },
    panelOut: { write: (text) => seen.panel.push(String(text)), isTTY: false },
    panelIntervalMs: 10,
    onSigint: () => (seen.sigint++, async () => {}),
  };
  return { seen, github, runner, clock, deps };
}

test('builds the engine with the config\'s limits, effective repos and the real seams, and starts it', async () => {
  const { seen, github, runner, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 2, title: '' }, { issue: 3, title: '' }] };
  const app = await startCarrier(config(), deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  // Logging goes to the orchestrator log at the configured level, and the instance lock is held.
  expect(seen.logging).toEqual([[join(root, 'orchestrator', 'logs', 'orchestrator.log'), 'debug']]);
  expect(acquireLock(join(root, 'orchestrator'))).toEqual({ ok: false });
  expect(seen.sigint).toBe(1);
  // It started: the labels of every configured repo were checked.
  expect(github.created).toHaveLength(6);

  // Limits and effective repos: two epics at once, the repo override reaches the reviewer, the time limit is in ms.
  await clock.advance(MIN);
  expect(runner.tasks.map((t) => [t.epic, t.stage, t.timeoutMs])).toEqual([[1, 'ship', 2 * 3_600_000], [2, 'ship', 2 * 3_600_000]]);
  expect(app.db.$client.prepare('select config from epics order by id').pluck().get()).toContain('"model":"override"');
});

test('GitHub acts as the orchestrator\'s profile from inside a clone-shaped folder under the root, with the configured timeout', async () => {
  const { seen, deps } = fakes();
  const app = await startCarrier(config(), deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  expect(seen.github).toMatchObject({ profile: { kind: 'gh' }, timeoutMs: 7000 });
  // Before the clone exists: a stub whose origin is the repo (what Forge reads). Once cloned: the clone.
  const stub = seen.github!.cwd('AshuLab/a');
  expect(execFileSync('git', ['remote', 'get-url', 'origin'], { cwd: stub, encoding: 'utf8' }).trim()).toBe('https://github.com/AshuLab/a.git');
  const clone = join(root, 'repos', 'AshuLab', 'a');
  mkdirSync(clone, { recursive: true });
  execFileSync('git', ['init', '-q'], { cwd: clone });
  expect(seen.github!.cwd('AshuLab/a')).toBe(clone);
});

test('workspaces use the root and mint the repo\'s author profile; the runner mints the execution\'s own profile', async () => {
  const { seen, deps } = fakes();
  const app = await startCarrier(config({ repos: [{ name: 'AshuLab/a', agents: { author: { profile: 'reviewer-bot' }, reviewer: { profile: 'author-bot' } } }, { name: 'AshuLab/b' }] }), deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  expect(seen.workspaces!.root).toBe(root);
  expect(await seen.workspaces!.token!('AshuLab/a')).toBe('ghs_fake');
  expect(await seen.workspaces!.token!('AshuLab/b')).toBe('ghs_fake');
  expect(seen.minted).toEqual(['tassadar-agent@AshuLab/a', 'artanis-agent@AshuLab/b']);

  const credentials = await seen.runner!.credentials({ profile: 'author-bot', repo: 'AshuLab/b' } as never);
  expect(credentials).toEqual({ githubToken: 'ghs_fake', gitIdentity: { name: 'artanis-agent[bot]', email: '99+artanis-agent[bot]@users.noreply.github.com' } });
});

test('the panel is drawn from SQLite: slots and the running epic show up', async () => {
  const { seen, github, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 5, title: '' }] };
  const app = await startCarrier(config(), deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  expect(seen.panel.join('')).toContain('slots 0/2');
  await clock.advance(MIN);
  await vi.waitFor(() => expect(seen.panel.join('')).toContain('AshuLab/a#5'));
  expect(seen.panel.join('')).toContain('slots 1/2');
});

test('a second instance on the same root gets InstanceBusy before anything else happens', async () => {
  const { seen, deps } = fakes();
  const lock = acquireLock(join(root, 'orchestrator'));
  expect(lock.ok).toBe(true);
  await expect(startCarrier(config(), deps)).rejects.toThrow(InstanceBusy);
  expect(seen.logging).toEqual([]);
  expect(existsSync(join(root, 'orchestrator', 'carrier.db'))).toBe(false);
  if (lock.ok) lock.release();
});

test('a startup failure releases the lock', async () => {
  const { github, deps } = fakes();
  github.listLabels = async () => {
    throw new Error('boom');
  };
  await expect(startCarrier(config(), deps)).rejects.toThrow('boom');
  const again = acquireLock(join(root, 'orchestrator'));
  expect(again.ok).toBe(true);
  if (again.ok) again.release();
});

test('onArrived fires once the engine is up and before the panel draws; a startup failure never announces it', async () => {
  const order: string[] = [];
  const { seen, deps } = fakes();
  const app = await startCarrier(config(), { ...deps, onArrived: () => order.push(`arrived (panel drawn: ${seen.panel.length > 0})`) });
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  expect(order).toEqual(['arrived (panel drawn: false)']);
  await vi.waitFor(() => expect(seen.panel.length).toBeGreaterThan(0)); // and the panel does start

  const failing = fakes();
  failing.github.listLabels = async () => {
    throw new Error('boom');
  };
  const announced = vi.fn();
  await expect(startCarrier(config({ root: mkdtempSync(join(tmpdir(), 'carrier-compose2-')) }), { ...failing.deps, onArrived: announced })).rejects.toThrow('boom');
  expect(announced).not.toHaveBeenCalled();
});

test('with a terminal on both sides the panel takes keys: r polls now, p pauses intake, q quits, and nothing else changes without one', async () => {
  const { github, seen, deps } = fakes();
  const { EventEmitter } = await import('node:events');
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const quit = vi.fn();
  const app = await startCarrier(config(), { ...deps, stdin: stdin as never, quit, openUrl: vi.fn(), panelOut: { write: (t) => seen.panel.push(String(t)), isTTY: true }, panelIntervalMs: 3_600_000 });
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  expect(stdin.setRawMode).toHaveBeenLastCalledWith(true);

  const calls = github.calls;
  stdin.emit('keypress', 'r', { name: 'r' });
  await vi.waitFor(() => expect(github.calls).toBeGreaterThan(calls)); // polled without waiting for the interval
  stdin.emit('keypress', 'p', { name: 'p' });
  expect(app.engine.paused).toBe(true);
  stdin.emit('keypress', 'q', { name: 'q' });
  expect(quit).toHaveBeenCalledTimes(1);

  app.close();
  expect(stdin.setRawMode).toHaveBeenLastCalledWith(false); // the terminal is given back
  closers.pop();

  const plain = fakes();
  const stdin2 = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const app2 = await startCarrier(config({ root: mkdtempSync(join(tmpdir(), 'carrier-compose3-')) }), { ...plain.deps, stdin: stdin2 as never }); // its panel output is not a terminal
  closers.push(async () => (await app2.engine.shutdown(), app2.close()));
  expect(stdin2.setRawMode).not.toHaveBeenCalled();
});
