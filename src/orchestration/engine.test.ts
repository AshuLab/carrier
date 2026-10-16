import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { eq } from 'drizzle-orm';
import { epics } from '../storage/schema.ts';
import { createEngine } from './engine.ts';
import { reserve } from './reserve.ts';
import { FakeAgentRunner, FakeWorkspaces, type Behavior } from '../execution/fake.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { executions } from '../storage/executions.ts';
import { FakeClock, FakeGitHub } from './fake.ts';
import { GitHubUnavailable } from './github.ts';

const MIN = 60_000;
const agents = {
  author: { profile: 'a', provider: 'claude' as const, model: 'm' },
  reviewer: { profile: 'b', provider: 'codex' as const, model: 'm' },
};
const repos: EffectiveRepoConfig[] = ['AshuLab/a', 'AshuLab/b'].map((name) => ({ name, agents }));

let dir: string;
let dbs: Db[];
let github: FakeGitHub;
let clock: FakeClock;
let runner: FakeAgentRunner;
let workspaces: FakeWorkspaces;
beforeEach(() => {
  runner = new FakeAgentRunner();
  workspaces = new FakeWorkspaces();
  dir = mkdtempSync(join(tmpdir(), 'carrier-'));
  dbs = [];
  github = new FakeGitHub();
  clock = new FakeClock();
});
afterEach(() => {
  for (const db of dbs) db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

// Slots default to 0 so the polling tests see the queue untouched.
function open() {
  const db = openDatabase(join(dir, 'carrier.db'));
  dbs.push(db);
  return db;
}
async function start(maxConcurrentEpics = 0, config = repos, maxExecutionHours: number | 'unlimited' = 4) {
  const db = open();
  const engine = createEngine({
    db, github, clock, repos: config, pollIntervalMs: 5 * MIN, maxConcurrentEpics, maxExecutionHours,
    runner, workspaces, root: dir,
  });
  await engine.start();
  return Object.assign(engine, { db });
}
const ids = (engine: { queue: () => { repo: string; issue: number }[] }) => engine.queue().map((e) => `${e.repo}#${e.issue}`);

test('registers ready epics of every repo once, and the same issue number in two repos is two epics', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 7, title: 'x' }], 'AshuLab/b': [{ issue: 7, title: 'y' }, { issue: 8, title: 'z' }] };
  const engine = await start();

  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#7', 'AshuLab/b#7', 'AshuLab/b#8']);
  expect(engine.queue()[0]).toMatchObject({ status: 'queued', queuedAt: 5 * MIN });

  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#7', 'AshuLab/b#7', 'AshuLab/b#8']);
  expect(github.calls).toBe(4);
});

test('first poll waits one full interval, then repeats every interval', async () => {
  const engine = await start();
  await clock.advance(5 * MIN - 1);
  expect(github.calls).toBe(0);
  await clock.advance(1);
  expect(github.calls).toBe(2);
  await clock.advance(5 * MIN);
  expect(github.calls).toBe(4);
  engine.stop();
  await clock.advance(5 * MIN);
  expect(github.calls).toBe(4);
});

test('FIFO order survives a restart on the same SQLite file, and later epics go after', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 9, title: '' }], 'AshuLab/b': [{ issue: 2, title: '' }] };
  const first = await start();
  await clock.advance(5 * MIN);
  first.stop();
  dbs.pop()!.$client.close();

  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 9, title: '' }], 'AshuLab/b': [{ issue: 2, title: '' }] };
  const second = await start();
  expect(ids(second)).toEqual(['AshuLab/a#9', 'AshuLab/b#2']);
  await clock.advance(5 * MIN);
  expect(ids(second)).toEqual(['AshuLab/a#9', 'AshuLab/b#2', 'AshuLab/a#1']);
});

test('GitHubUnavailable keeps queue and state, exposes the error and backs off to max(interval, retryAfter)', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }], 'AshuLab/b': [] };
  const engine = await start();
  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#1']);

  github.ready = { 'AshuLab/a': [], 'AshuLab/b': [{ issue: 2, title: '' }] };
  github.unavailable = new GitHubUnavailable(12 * MIN);
  const calls = github.calls;
  await clock.advance(5 * MIN);
  expect(engine.error).toBe(github.unavailable);
  expect(ids(engine)).toEqual(['AshuLab/a#1']);
  expect(engine.queue()[0]?.status).toBe('queued');

  await clock.advance(12 * MIN - 1);
  expect(github.calls).toBe(calls + 1);
  github.unavailable = new GitHubUnavailable(); // no retryAfter: falls back to the interval
  await clock.advance(1);
  expect(github.calls).toBe(calls + 2);

  await clock.advance(5 * MIN);
  expect(github.calls).toBe(calls + 3);

  github.unavailable = null;
  await clock.advance(5 * MIN);
  expect(engine.error).toBeNull();
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/b#2']);
});

test('a failure in one repo registers nothing from the other repos in that poll', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  const fail = new GitHubUnavailable();
  github.listReadyEpics = async (repo) => {
    if (repo === 'AshuLab/b') throw fail;
    return [{ issue: 1, title: '' }];
  };
  const engine = await start();
  await clock.advance(5 * MIN);
  expect(engine.queue()).toEqual([]);
  expect(engine.error).toBe(fail);
});

const ready = (...issues: number[]) => issues.map((issue) => ({ issue, title: '' }));
const rows = (db: Db) => db.select().from(epics).all();
const byStatus = (db: Db, status: string) => rows(db).filter((e) => e.status === status).map((e) => e.issue);
const labelsOf = (issue: number, repo = 'AshuLab/a') => github.issue(repo, issue).labels;

test('with N queued and concurrency C, never more than C running and always the oldest', async () => {
  github.ready = { 'AshuLab/a': ready(5, 3, 9, 1) };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([5, 3]);
  expect(ids(engine)).toEqual(['AshuLab/a#9', 'AshuLab/a#1']);

  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([5, 3]);

  // A freed slot goes to the oldest queued epic.
  engine.db.update(epics).set({ status: 'merged' }).where(eq(epics.issue, 5)).run();
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([3, 9]);
});

test('two connections to the same database never reserve the same epic nor exceed the limit', async () => {
  const a = open();
  const b = open();
  a.insert(epics).values([{ repo: 'AshuLab/a', issue: 1 }, { repo: 'AshuLab/a', issue: 2 }, { repo: 'AshuLab/a', issue: 3 }]).run();
  const opts = { now: 7, repos };

  const first = reserve(a, { ...opts, maxConcurrent: 2 });
  const second = reserve(b, { ...opts, maxConcurrent: 2 });
  expect([first?.issue, second?.issue]).toEqual([1, 2]);
  expect(reserve(a, { ...opts, maxConcurrent: 2 })).toBeNull();
  expect(reserve(b, { ...opts, maxConcurrent: 2 })).toBeNull();

  // Running epics are never reserved again, even with free slots.
  expect(reserve(b, { ...opts, maxConcurrent: 3 })?.issue).toBe(3);
  expect(reserve(a, { ...opts, maxConcurrent: 9 })).toBeNull();
  expect(byStatus(a, 'running')).toEqual([1, 2, 3]);
});

test('reservation freezes the effective repo config, later config changes do not touch it', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', startedAt: 5 * MIN, config: { name: 'AshuLab/a', agents } });

  // Restart with a changed config: the running row keeps the old one, the next reservation takes the new one.
  engine.stop();
  engine.db.update(epics).set({ status: 'merged' }).where(eq(epics.issue, 1)).run();
  const changed = [{ name: 'AshuLab/a', agents: { ...agents, author: { ...agents.author, model: 'other' } } }];
  const next = await start(1, changed);
  await clock.advance(5 * MIN);
  expect(rows(next.db).map((e) => e.config?.agents.author.model)).toEqual(['m', 'other']);
});

test('reserving flips ready to running on the issue', async () => {
  github.ready = { 'AshuLab/a': ready(4) };
  github.issue('AshuLab/a', 4).labels = ['solve:epic:ready', 'bug'];
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(labelsOf(4)).toEqual(['bug', 'solve:epic:running']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: false });
});

test('GitHubUnavailable on the label change keeps the epic reserved and the next cycle reconciles it once', async () => {
  github.ready = { 'AshuLab/a': ready(4) };
  github.setLabelsUnavailable = new GitHubUnavailable();
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: true });
  expect(labelsOf(4)).toEqual(['solve:epic:ready']);
  expect(engine.error).toBe(github.setLabelsUnavailable);

  github.setLabelsUnavailable = null;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: false });
  expect(labelsOf(4)).toEqual(['solve:epic:running']);
  await clock.advance(5 * MIN);
  expect(labelsOf(4)).toEqual(['solve:epic:running']);
});

test('a closed issue is cancelled, a lost ready too, and the slot goes to the next epic', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  github.issue('AshuLab/a', 1).state = 'closed';
  github.issue('AshuLab/a', 2).labels = [];
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason])).toEqual([
    [1, 'cancelled', 'cerrada antes de iniciar'],
    [2, 'cancelled', 'ready removido'],
    [3, 'running', null],
  ]);
});

test('an issue that cannot be checked goes back to the queue in its place', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const engine = await start(1);
  github.getIssue = async () => {
    throw new GitHubUnavailable();
  };
  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/a#2']);
  expect(rows(engine.db)[0]).toMatchObject({ startedAt: null, config: null });
});

test('startup creates only the missing owned labels, never ready, and repeating changes nothing', async () => {
  github.repoLabels = { 'AshuLab/a': ['solve:epic:running', 'bug'] };
  await start();
  expect(github.created).toEqual([
    'AshuLab/a:solve:epic:ready-for-test',
    'AshuLab/a:solve:epic:needs-human',
    'AshuLab/b:solve:epic:running',
    'AshuLab/b:solve:epic:ready-for-test',
    'AshuLab/b:solve:epic:needs-human',
  ]);
  await start();
  expect(github.created).toHaveLength(5);
  expect(github.repoLabels['AshuLab/a']).toEqual(['solve:epic:running', 'bug', 'solve:epic:ready-for-test', 'solve:epic:needs-human']);
});

// --- ship stage ---

const SHA = 'a'.repeat(40);
const result = (task: AgentTask, extra: object): Behavior['write'] => ({
  executionId: task.executionId, repo: task.repo, epic: task.epic, stage: task.stage, summary: 'done', ...extra,
});
const completed = (task: AgentTask, pr = { number: 50, headSha: SHA }) =>
  result(task, { outcome: 'completed', pr, verification: { ci: 'absent', evidence: 'no CI' } });
const pull = (number: number, extra: Partial<{ state: 'open' | 'closed'; body: string; headSha: string }> = {}, issue = 1, repo = 'AshuLab/a') => {
  github.pulls[`${repo}#${number}`] = { state: 'open', body: `Final PR\n\nCloses #${issue}`, headSha: SHA, ...extra };
};
const executionsOf = (db: Db) => db.select().from(executions).all();

test('a reserved epic launches the author with its effective config, a unique result path and the time limit', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const config = [{ name: 'AshuLab/a', agents: { ...agents, author: { profile: 'p', provider: 'codex' as const, model: 'x' } } }];
  const engine = await start(2, config, 2);
  await clock.advance(5 * MIN);

  expect(runner.tasks).toHaveLength(2);
  const [task, other] = runner.tasks as [AgentTask, AgentTask];
  expect(task).toMatchObject({
    repo: 'AshuLab/a', epic: 1, stage: 'ship', profile: 'p', provider: 'codex', model: 'x',
    workspace: '/work/AshuLab/a/1/author', timeoutMs: 2 * 3_600_000, context: { previousSummaries: [] },
  });
  expect(task.resultPath).toContain(join(dir, 'orchestrator', 'results'));
  expect(new Set([task.executionId, other.executionId, task.resultPath, other.resultPath]).size).toBe(4);
  expect(executionsOf(engine.db).map((e) => [e.epicId, e.stage, e.status])).toEqual([[1, 'ship', 'running'], [2, 'ship', 'running']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
});

test('unlimited means no timeout', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  await start(1, repos, 'unlimited');
  await clock.advance(5 * MIN);
  expect(runner.tasks[0]?.timeoutMs).toBeNull();
});

test('the session id is saved as soon as the runner reports it, while the execution still runs', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's-1', exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'running', sessionId: 's-1', finishedAt: null });
});

test('a valid completed result moves the epic to review round 1 and records the final PR', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => ({ sessionId: 's', write: completed(task) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA, finishedAt: null });
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'finished', sessionId: 's' });
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
});

test.each([
  ['a missing PR', undefined, 'no existe'],
  ['a closed PR', { state: 'closed' as const }, 'no está abierto'],
  ['a PR that does not reference the epic', { body: 'Closes #2' }, 'no referencia la épica'],
  ['a PR with another head', { headSha: 'b'.repeat(40) }, 'head del PR #50'],
])('%s leaves only that epic in needs_human with the reason, and the slot goes to the next one', async (_, change, reason) => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  if (change) pull(50, change);
  pull(51, {}, 2);
  runner.behavior = (task) => ({ write: completed(task, { number: task.epic === 1 ? 50 : 51, headSha: SHA }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  const [first, second] = rows(engine.db);
  expect(first).toMatchObject({ issue: 1, status: 'needs_human', finishedAt: 5 * MIN, labelPending: false });
  expect(first?.needsHumanReason).toContain(reason);
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  // The second one started right away, with no new poll, and was not affected.
  expect(second).toMatchObject({ issue: 2, status: 'running', stage: 'review' });
  expect(labelsOf(2)).toEqual(['solve:epic:running']);
});

test('a needs_human result stops the epic with the caller reason and label', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'falta una credencial' }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'falta una credencial', finishedAt: 5 * MIN });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('an invalid or missing result is recorded on the execution and does not move the epic', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => (task.epic === 1 ? { write: '{nope' } : {});
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['invalid_result', 'invalid_result']);
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]);
});

test('a runner that fails or is cut records it and imports nothing', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  runner.behavior = (task) => ({ exit: (['failed', 'timed_out', 'stopped'] as const)[task.epic - 1] });
  const engine = await start(3);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['failed', 'timed_out', 'interrupted']);
  expect(byStatus(engine.db, 'running')).toEqual([1, 2, 3]);
});

test('GitHub down while validating keeps the result for the next poll, which imports it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => ({ write: completed(task) });
  const engine = await start(1);
  github.getPullRequest = async () => {
    throw new GitHubUnavailable();
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(engine.error).toBeInstanceOf(GitHubUnavailable);
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'ship' });

  github.getPullRequest = FakeGitHub.prototype.getPullRequest.bind(github);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', round: 1 });
  expect(runner.tasks).toHaveLength(1);
});

test('importing the same result twice changes nothing', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => ({ write: completed(task) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  engine.db.update(executions).set({ status: 'finished' }).run();
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', round: 1 });
  expect(runner.tasks).toHaveLength(1);
});

test('a workspace that cannot be prepared leaves the epic in needs_human and frees the slot', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const engine = await start(1);
  const prepare = workspaces.prepareAuthor.bind(workspaces);
  workspaces.prepareAuthor = async (repo, epic) => {
    if (epic === 1) throw new Error('clone failed');
    return prepare(repo, epic);
  };
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'no se pudo preparar el workspace: clone failed' });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });
});
