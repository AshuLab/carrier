import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { loadWithProviders } from '../../config/testing.ts';
import type { Config } from '../../config/schema.ts';
import { FakeAgentRunner, FakeWorkspaces } from '../../execution/fake.ts';
import type { GitWorkspacesOptions } from '../../execution/git-workspaces.ts';
import type { GhGitHubOptions } from '../../integrations/github.ts';
import { FakeClock, FakeGitHub } from '../../orchestration/fake.ts';
import type { HostRunnerOptions } from '../../harnesses/host-runner.ts';
import { acquireLock } from '../../storage/lock.ts';
import { CliError } from './cli-error.ts';
import { connectControl } from './control-client.ts';
import type { ControlSnapshot } from '../../status/types.ts';
import { epics } from '../../storage/schema.ts';
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
  const result = loadWithProviders({
    pollIntervalMinutes: 1,
    logLevel: 'debug',
    repos: [{ name: 'AshuLab/a', agents: { reviewer: { provider: 'override', model: 'override' } } }, { name: 'AshuLab/b' }],
    profiles: { orchestrator: { kind: 'gh' }, 'author-bot': { kind: 'forge', agent: 'artanis-agent' }, 'reviewer-bot': { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'orchestrator',
    providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' }, override: { harness: 'codex' } },
    agents: {
      author: { profile: 'author-bot', provider: 'claude', model: 'm' },
      reviewer: { profile: 'reviewer-bot', provider: 'codex', model: 'm' },
    },
    limits: { maxConcurrentEpics: 2, maxReviews: 4, maxExecutionRetries: 1, maxExecutionHours: 2, githubCallTimeoutSeconds: 7 },
    ...user,
  });
  if (!result.ok) throw new Error(JSON.stringify(result.errors));
  return result.config;
};

const sameConfig = () => config();

// Fakes in every seam: nothing here reaches GitHub, Forge or a real agent.
function fakes() {
  const seen = { logging: [] as [string, string][], levels: [] as string[], github: undefined as GhGitHubOptions | undefined, workspaces: undefined as GitWorkspacesOptions | undefined, runner: undefined as HostRunnerOptions | undefined, minted: [] as string[], sigint: 0, panel: [] as string[] };
  const github = new FakeGitHub();
  const runner = new FakeAgentRunner();
  const clock = new FakeClock();
  const deps: Partial<CarrierDeps> = {
    installLogging: (file, level) => seen.logging.push([file, level]),
    setLogLevel: (level) => seen.levels.push(level),
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
  const app = await startCarrier(config(), root, sameConfig, deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  // Logging goes to the orchestrator log at the configured level, and the instance lock is held.
  expect(seen.logging).toEqual([[join(root, 'engine', 'logs', 'orchestrator.log'), 'debug']]);
  expect(acquireLock(join(root, 'engine', 'state'))).toEqual({ ok: false });
  expect(seen.sigint).toBe(1);
  // It started without asking GitHub for any repo's labels.
  expect(github.created).toHaveLength(0);

  // Limits and effective repos: two epics at once, the repo override reaches the reviewer, the time limit is in ms.
  await clock.advance(MIN);
  // two accounts are declared and the epics start at once
  expect(runner.tasks.map((t) => [t.epic, t.stage, t.timeoutMs])).toEqual([[1, 'ship', 2 * 3_600_000], [2, 'ship', 2 * 3_600_000]]);
  expect(app.db.$client.prepare('select config from epics order by id').pluck().get()).toContain('"model":"override"');
  // Taking the epics of AshuLab/a created that repo's labels, and only that repo's.
  expect(github.created.map((c) => c.split(':')[0])).toEqual(['AshuLab/a', 'AshuLab/a', 'AshuLab/a']);
});

test('GitHub acts as the orchestrator\'s profile from inside a clone-shaped folder under the Carrier folder, with the configured timeout', async () => {
  const { seen, deps } = fakes();
  const app = await startCarrier(config(), root, sameConfig, deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  expect({ profile: seen.github!.profile(), timeoutMs: seen.github!.timeoutMs() }).toMatchObject({ profile: { kind: 'gh' }, timeoutMs: 7000 });
  // Before the clone exists: a stub whose origin is the repo (what Forge reads). Once cloned: the clone.
  const stub = seen.github!.cwd('AshuLab/a');
  expect(stub).toBe(join(root, 'engine', 'state', 'forge-cwd', 'AshuLab', 'a'));
  expect(execFileSync('git', ['remote', 'get-url', 'origin'], { cwd: stub, encoding: 'utf8' }).trim()).toBe('https://github.com/AshuLab/a.git');
  const clone = join(root, 'engine', 'repos', 'AshuLab', 'a');
  mkdirSync(clone, { recursive: true });
  execFileSync('git', ['init', '-q'], { cwd: clone });
  expect(seen.github!.cwd('AshuLab/a')).toBe(clone);
});

test('workspaces use the engine\'s repos and reviews folders and mint the repo\'s author profile; the runner mints the execution\'s own profile', async () => {
  const { seen, deps } = fakes();
  const app = await startCarrier(config({ repos: [{ name: 'AshuLab/a', agents: { author: { profile: 'reviewer-bot' }, reviewer: { profile: 'author-bot' } } }, { name: 'AshuLab/b' }] }), root, sameConfig, deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  expect(seen.workspaces!.places).toMatchObject({ repos: join(root, 'engine', 'repos'), reviews: join(root, 'engine', 'reviews') });
  expect(await seen.workspaces!.token!('AshuLab/a')).toBe('ghs_fake');
  expect(await seen.workspaces!.token!('AshuLab/b')).toBe('ghs_fake');
  expect(seen.minted).toEqual(['tassadar-agent@AshuLab/a', 'artanis-agent@AshuLab/b']);

  const credentials = await seen.runner!.credentials({ profile: 'author-bot', repo: 'AshuLab/b' } as never);
  expect(credentials).toEqual({ githubToken: 'ghs_fake', forgeAgent: 'artanis-agent', gitIdentity: { name: 'artanis-agent[bot]', email: '99+artanis-agent[bot]@users.noreply.github.com' } });
});

test('a reload reaches the GitHub client and its timeout, the repo listing, the workspaces\' token and the runner\'s credentials; a removed profile is refused naming it', async () => {
  const { seen, deps } = fakes();
  const listed: number[] = [];
  deps.listRepos = async (_page, timeoutMs) => (listed.push(timeoutMs), { repos: [], hasMore: false });
  let next = config();
  const app = await startCarrier(config(), root, () => next, deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  const client = await connectControl(join(root, 'engine', 'state', 'control.sock'));
  closers.push(async () => client.close());
  expect({ profile: seen.github!.profile(), timeoutMs: seen.github!.timeoutMs() }).toMatchObject({ profile: { kind: 'gh' }, timeoutMs: 7000 });
  await client.request('availableRepos');

  next = config({
    profiles: { 'new-orchestrator': { kind: 'forge', agent: 'fenix-agent' }, 'author-bot': { kind: 'forge', agent: 'zeratul-agent' }, 'reviewer-bot': { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'new-orchestrator',
    limits: { maxConcurrentEpics: 2, maxReviews: 4, maxExecutionRetries: 1, maxExecutionHours: 2, githubCallTimeoutSeconds: 30 },
  });
  await client.request('reload');
  expect({ profile: seen.github!.profile(), timeoutMs: seen.github!.timeoutMs() }).toMatchObject({ profile: { kind: 'forge', agent: 'fenix-agent' }, timeoutMs: 30_000 });
  await client.request('availableRepos');
  expect(listed).toEqual([7000, 30_000]);
  await seen.workspaces!.token!('AshuLab/b');
  expect(seen.minted).toEqual(['zeratul-agent@AshuLab/b']);
  expect(await seen.runner!.credentials({ profile: 'author-bot', repo: 'AshuLab/b' } as never)).toMatchObject({ forgeAgent: 'zeratul-agent' });

  // a profile that a stored epic still names but the file no longer has: the token for the run is refused naming it
  next = { ...next, profiles: { 'new-orchestrator': { kind: 'gh' } } };
  await client.request('reload');
  await expect(seen.workspaces!.token!('AshuLab/b')).rejects.toThrow('profile "author-bot" is not declared');
  await expect(seen.runner!.credentials({ profile: 'reviewer-bot', repo: 'AshuLab/b' } as never)).rejects.toThrow('profile "reviewer-bot" is not declared');
  // a repo the file no longer has: its clone or fetch fails with a message, not a TypeError on a missing entry
  await expect(seen.workspaces!.token!('AshuLab/gone')).rejects.toThrow('repo "AshuLab/gone" is not in the configuration');
});

test('the panel is drawn from SQLite: slots and the running epic show up', async () => {
  const { seen, github, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 5, title: '' }] };
  const app = await startCarrier(config(), root, sameConfig, deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));

  expect(seen.panel.join('')).toContain('slots 0/2');
  await clock.advance(MIN);
  await vi.waitFor(() => expect(seen.panel.join('')).toContain('AshuLab/a#5'));
  expect(seen.panel.join('')).toContain('slots 1/2');
});

test('the foreground panel is fed the control snapshot: an epic shows its title', async () => {
  const { seen, github, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 5, title: 'Menu bar' }] };
  const app = await startCarrier(config(), root, sameConfig, { ...deps, panelOut: { write: (t) => seen.panel.push(String(t)), isTTY: true }, panelIntervalMs: 10 });
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  await clock.advance(MIN);
  await vi.waitFor(() => expect(seen.panel.join('').replace(/\x1b\[[0-9;]*m/g, '')).toContain('AshuLab/a #5  Menu bar'));
});

test('the foreground panel is given the in-process provider: a running epic lists its stages', async () => {
  const { seen, github, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 5, title: 'Menu bar' }] };
  const app = await startCarrier(config(), root, sameConfig, { ...deps, panelOut: { write: (t) => seen.panel.push(String(t)), isTTY: true }, panelIntervalMs: 10 });
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  await clock.advance(MIN + 1000);
  await vi.waitFor(() => expect(seen.panel.join('').replace(/\x1b\[[0-9;]*m/g, '')).toMatch(/┃ \[ship\] \d+s\n/));
});

test('a second instance on the same Carrier folder gets InstanceBusy before anything else happens', async () => {
  const { seen, deps } = fakes();
  const lock = acquireLock(join(root, 'engine', 'state'));
  expect(lock.ok).toBe(true);
  await expect(startCarrier(config(), root, sameConfig, deps)).rejects.toThrow(InstanceBusy);
  expect(seen.logging).toEqual([]);
  expect(existsSync(join(root, 'engine', 'state', 'carrier.db'))).toBe(false);
  if (lock.ok) lock.release();
});

test('a startup failure releases the lock', async () => {
  const { runner, deps } = fakes();
  runner.listActive = async () => {
    throw new Error('boom');
  };
  await expect(startCarrier(config(), root, sameConfig, deps)).rejects.toThrow('boom');
  const again = acquireLock(join(root, 'engine', 'state'));
  expect(again.ok).toBe(true);
  if (again.ok) again.release();
});

test('onArrived fires once the engine is up and before the panel draws; a startup failure never announces it', async () => {
  const order: string[] = [];
  const { seen, deps } = fakes();
  const app = await startCarrier(config(), root, sameConfig, { ...deps, onArrived: () => order.push(`arrived (panel drawn: ${seen.panel.length > 0})`) });
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  expect(order).toEqual(['arrived (panel drawn: false)']);
  await vi.waitFor(() => expect(seen.panel.length).toBeGreaterThan(0)); // and the panel does start

  const failing = fakes();
  failing.runner.listActive = async () => {
    throw new Error('boom');
  };
  const announced = vi.fn();
  await expect(startCarrier(config(), mkdtempSync(join(tmpdir(), 'carrier-compose2-')), sameConfig, { ...failing.deps, onArrived: announced })).rejects.toThrow('boom');
  expect(announced).not.toHaveBeenCalled();
});

test('with a terminal on both sides the panel takes keys: r polls now, p pauses intake, q quits, and nothing else changes without one', async () => {
  const { github, seen, deps } = fakes();
  const { EventEmitter } = await import('node:events');
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const quit = vi.fn();
  const app = await startCarrier(config(), root, sameConfig, { ...deps, stdin: stdin as never, quit, openUrl: vi.fn(), panelOut: { write: (t) => seen.panel.push(String(t)), isTTY: true }, panelIntervalMs: 3_600_000 });
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  expect(stdin.setRawMode).toHaveBeenLastCalledWith(true);

  const calls = github.calls;
  stdin.emit('keypress', 'r', { name: 'r' });
  await vi.waitFor(() => expect(github.calls).toBeGreaterThan(calls)); // polled without waiting for the interval
  await app.engine.pollNow(); // joins that poll: the database is not closed under it
  stdin.emit('keypress', 'p', { name: 'p' });
  expect(app.engine.paused).toBe(true);
  stdin.emit('keypress', 'q', { name: 'q' });
  expect(quit).toHaveBeenCalledTimes(1);

  app.close();
  expect(stdin.setRawMode).toHaveBeenLastCalledWith(false); // the terminal is given back
  closers.pop();

  const plain = fakes();
  const stdin2 = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const app2 = await startCarrier(config(), mkdtempSync(join(tmpdir(), 'carrier-compose3-')), sameConfig, { ...plain.deps, stdin: stdin2 as never }); // its panel output is not a terminal
  closers.push(async () => (await app2.engine.shutdown(), app2.close()));
  expect(stdin2.setRawMode).not.toHaveBeenCalled();
});

test('a reload through the control socket applies the loader\'s next config, and a refused one leaves every setting as it was and carries the problem', async () => {
  const { seen, github, runner, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 2, title: '' }, { issue: 3, title: '' }] };
  let next: () => Config = () => config({ pollIntervalMinutes: 3, logLevel: 'warn', finishedWindowDays: 9, limits: { maxConcurrentEpics: 1, maxReviews: 8, maxExecutionRetries: 1, maxExecutionHours: 6, githubCallTimeoutSeconds: 7 } });
  const app = await startCarrier(config(), root, () => next(), deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  const client = await connectControl(join(root, 'engine', 'state', 'control.sock'));
  closers.push(async () => client.close());
  expect(client.hello.capabilities).toContain('reload');
  // what the panel and `carrier watch` show: the numbers, and the finished window (an epic merged 12 days ago, inside 15 and outside 9)
  app.db.insert(epics).values({ repo: 'AshuLab/b', issue: 99, status: 'merged', finishedAt: -12 * 86_400_000 }).run();
  const snapshot = async () => {
    const shown = (await client.request('snapshot')) as ControlSnapshot;
    return { pollIntervalMs: shown.engine.pollIntervalMs, slots: shown.slots.total, maxReviews: shown.epics[0]?.maxReviews, finished: shown.finished?.length };
  };

  // a first poll takes two epics at once, with the run limit it started with
  await clock.advance(MIN);
  expect(runner.tasks.map((t) => t.timeoutMs)).toEqual([2 * 3_600_000, 2 * 3_600_000]);
  expect(await snapshot()).toEqual({ pollIntervalMs: MIN, slots: 2, maxReviews: 4, finished: 1 });

  await client.request('reload');
  expect(seen.levels).toEqual(['warn']);
  expect(await snapshot()).toEqual({ pollIntervalMs: 3 * MIN, slots: 1, maxReviews: 8, finished: 0 });
  expect(runner.tasks).toHaveLength(2); // the runs launched keep their timeout, and the lowered limit starts no new epic

  // an invalid one: nothing changes, and the reply is the lines a start prints
  next = () => {
    throw new CliError(1, 'Invalid config /c/config.json:', '  limits.maxReviews: Too small');
  };
  await expect(client.request('reload')).rejects.toThrow('Invalid config /c/config.json:\n  limits.maxReviews: Too small');
  expect(seen.levels).toEqual(['warn']);
  expect(await snapshot()).toEqual({ pollIntervalMs: 3 * MIN, slots: 1, maxReviews: 8, finished: 0 });
});

test('a reload through the control socket changes the repos the engine watches: the one removed has its epic parked, and the workspaces mint the new author profile', async () => {
  const { seen, github, runner, clock, deps } = fakes();
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }], 'AshuLab/b': [{ issue: 2, title: '' }] };
  let next = sameConfig;
  const app = await startCarrier(config(), root, () => next(), deps);
  closers.push(async () => (await app.engine.shutdown(), app.close()));
  const client = await connectControl(join(root, 'engine', 'state', 'control.sock'));
  closers.push(async () => client.close());
  await clock.advance(MIN);
  expect(runner.tasks.map((t) => t.repo)).toEqual(['AshuLab/a', 'AshuLab/b']);

  next = () => config({ repos: [{ name: 'AshuLab/b', agents: { author: { profile: 'reviewer-bot' } } }] });
  await client.request('reload');
  const shown = (await client.request('snapshot')) as ControlSnapshot;
  expect(shown.watched.map((w) => w.repo)).toEqual(['AshuLab/b']);
  expect(app.db.$client.prepare("select repo, status from epics order by id").all()).toEqual([{ repo: 'AshuLab/a', status: 'repo_removed' }, { repo: 'AshuLab/b', status: 'running' }]);
  await seen.workspaces!.token!('AshuLab/b');
  expect(seen.minted).toEqual(['tassadar-agent@AshuLab/b']);
});
