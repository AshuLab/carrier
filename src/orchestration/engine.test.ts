import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { eq } from 'drizzle-orm';
import { epics } from '../storage/schema.ts';
import { createEngine } from './engine.ts';
import { reserve } from './reserve.ts';
import { FakeAgentRunner, FakeWorkspaces, type Behavior } from '../execution/fake.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { epicEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { callerResults } from '../storage/caller-results.ts';
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
async function start(maxConcurrentEpics = 0, config = repos, maxExecutionHours: number | 'unlimited' = 4, maxExecutionRetries = 3) {
  const db = open();
  const engine = createEngine({
    db, github, clock, repos: config, pollIntervalMs: 5 * MIN, maxConcurrentEpics, maxExecutionHours, maxExecutionRetries,
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
const pull = (number: number, extra: Partial<{ state: 'open' | 'closed' | 'merged'; body: string; headSha: string }> = {}, issue = 1, repo = 'AshuLab/a') => {
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
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's', write: completed(task) } : { exit: 'stopped' });
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
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task, { number: task.epic === 1 ? 50 : 51, headSha: SHA }) } : { exit: 'stopped' });
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

test('a runner that is cut records it and imports nothing', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'stopped' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['interrupted']);
  expect(byStatus(engine.db, 'running')).toEqual([1]);
});

test('GitHub down while validating keeps the result for the next poll, which imports it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'stopped' });
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
  expect(runner.tasks.filter((t) => t.stage === 'ship')).toHaveLength(1);
});

test('importing the same result twice changes nothing', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  engine.db.update(executions).set({ status: 'interrupted' }).run();
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', round: 1 });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']); // no second reviewer
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

test('a result freeing a slot while another epic is still being reserved never launches its author twice', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  pull(50);
  runner.behavior = (task) => (task.epic === 1 && task.stage === 'ship' ? { write: completed(task) } : { exit: 'stopped' });
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const setLabels = github.setLabels.bind(github);
  github.setLabels = async (repo, issue, change) => {
    if (issue === 2) await gate;
    return setLabels(repo, issue, change);
  };
  const engine = await start(2);
  const advancing = clock.advance(5 * MIN);
  await new Promise((resolve) => setTimeout(resolve, 20));
  release();
  await advancing;
  await engine.idle();
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1);
});

// --- failures: retries and timeout ---

const eventsOf = (db: Db) => db.select().from(epicEvents).all();
const statuses = (db: Db) => executionsOf(db).map((e) => e.status);

test.each([
  ['the runner fails', { sessionId: 's-1', exit: 'failed' as const }],
  ['the result is broken JSON', { sessionId: 's-1', write: '{nope' }],
  ['the result is missing', { sessionId: 's-1' }],
  ['the result is for another execution', { sessionId: 's-1', write: { executionId: 'x', repo: 'AshuLab/a', epic: 1, stage: 'ship', summary: 's', outcome: 'needs_human', reason: 'r' } }],
])('%s: the stage runs again resuming the session, verifying the state first, after reading the PR without creating anything', async (_, first) => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { state: 'open' });
  runner.behavior = (task) => (task.resumeSession ? { exit: 'hang' } : first);
  const engine = await start(1);
  const created = github.created.length;
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));

  expect(runner.tasks).toHaveLength(2);
  const [initial, again] = runner.tasks as [AgentTask, AgentTask];
  expect(initial.resumeSession).toBeUndefined();
  expect(initial.context.verifyStateFirst).toBeUndefined();
  expect(again).toMatchObject({ stage: 'ship', workspace: initial.workspace, resumeSession: 's-1', context: { verifyStateFirst: true } });
  expect(again.executionId).not.toBe(initial.executionId);
  expect(statuses(engine.db)).toEqual(['exit' in first ? 'failed' : 'invalid_result', 'running']);
  expect(eventsOf(engine.db)).toMatchObject([
    { epicId: 1, at: 5 * MIN, type: 'execution_retried', data: { stage: 'ship', failed: initial.executionId, attempt: 2, pr: { number: 50, state: 'open', headSha: SHA } } },
  ]);
  // Read only, and the epic did not move: same stage, no review round.
  expect(github.created).toHaveLength(created);
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', round: null, prNumber: null });
});

test('the retry that succeeds carries the epic on', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'review' ? { exit: 'stopped' } : task.resumeSession ? { write: completed(task) } : { sessionId: 's-1', exit: 'failed' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(statuses(engine.db)).toEqual(['failed', 'finished', 'interrupted']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 1, prNumber: 50 });
  expect(eventsOf(engine.db)[0]?.data.pr).toEqual({ number: 50, state: 'open', headSha: SHA });
});

test('with maxExecutionRetries 3 there are four attempts, then the epic needs a human with the last error and the slot moves on', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => (task.epic === 1 ? { sessionId: 's', exit: 'failed' } : { exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.some((t) => t.epic === 2)).toBe(true));

  expect(runner.tasks.filter((t) => t.epic === 1)).toHaveLength(4);
  expect(executionsOf(engine.db).filter((e) => e.epicId === 1).map((e) => e.status)).toEqual(['failed', 'failed', 'failed', 'failed']);
  expect(eventsOf(engine.db).map((e) => e.data.attempt)).toEqual([2, 3, 4]);
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, status: 'needs_human', round: null, finishedAt: 5 * MIN });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe('se agotaron los reintentos de ship (4 intentos): el proceso del agente terminó con error');
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });

  await clock.advance(5 * MIN);
  expect(runner.tasks.filter((t) => t.epic === 1)).toHaveLength(4);
});

test('maxExecutionRetries 0 means a single attempt', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'failed' });
  const engine = await start(1, repos, 4, 0);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
});

test('a GitHub query error before a relaunch is not an attempt: the poll relaunches it once GitHub answers', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed' });
  const down = new GitHubUnavailable();
  const find = github.findPullRequest.bind(github);
  github.findPullRequest = async () => {
    throw down;
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  for (let i = 0; i < 5; i++) await clock.advance(5 * MIN);
  expect(engine.error).toBe(down);
  expect(runner.tasks).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running' });

  github.findPullRequest = find;
  await clock.advance(5 * MIN);
  await engine.idle();
  // The five failed queries consumed nothing: the epic still got all four attempts.
  expect(runner.tasks).toHaveLength(4);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
});

test('an execution that did not fail resets the failure streak', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1, repos, 4, 1);
  await clock.advance(5 * MIN);
  const base = { epicId: 1, stage: 'ship' as const, resultPath: '/r', startedAt: 0 };
  engine.db.update(executions).set({ status: 'interrupted' }).run();
  engine.db.insert(executions).values([
    { ...base, executionId: 'f1', status: 'failed', error: 'x' },
    { ...base, executionId: 'f2', status: 'failed', error: 'x' },
    { ...base, executionId: 'ok', status: 'interrupted' },
    { ...base, executionId: 'f3', status: 'failed', error: 'x' },
  ]).run();
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  // Three failures in all but one since the last execution that did not fail, and one retry allowed: it goes out.
  expect(runner.tasks).toHaveLength(2);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running' });
});

test('timed_out keeps the session, needs a human with the reason and launches nothing new', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => (task.epic === 1 ? { sessionId: 's-1', exit: 'timed_out' } : { exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.some((t) => t.epic === 2)).toBe(true));

  expect(executionsOf(engine.db)[0]).toMatchObject({ epicId: 1, status: 'timed_out', sessionId: 's-1', finishedAt: 5 * MIN });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'la ejecución de ship superó el límite de tiempo' });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  expect(eventsOf(engine.db)).toEqual([]);
  await clock.advance(10 * MIN);
  expect(runner.tasks.filter((t) => t.epic === 1)).toHaveLength(1);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });
});

test('with unlimited the engine never times an execution out by itself', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'hang' });
  const engine = await start(1, repos, 'unlimited');
  await clock.advance(5 * MIN);
  engine.stop(); // no more polls: a single jump of the clock
  await clock.advance(1000 * 3_600_000);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]?.timeoutMs).toBeNull();
  expect(runner.stopped).toEqual([]);
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'running', finishedAt: null });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running' });
});

test('after a restart a review failure is retried as a review, with its PR and round', async () => {
  const first = open();
  first.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'running', config: repos[0], stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA, startedAt: 0 }).run();
  first.insert(executions).values({ executionId: 'e0', epicId: 1, stage: 'review', status: 'failed', error: 'boom', sessionId: 's-r', resultPath: '/r', startedAt: 0 }).run();
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  expect(runner.tasks[0]).toMatchObject({
    stage: 'review', profile: 'b', provider: 'codex', workspace: '/work/AshuLab/a/1/reviewer-50', resumeSession: 's-r',
    context: { pr: { number: 50, headSha: SHA }, round: 2, verifyStateFirst: true },
  });
});

// --- review stage ---

const HEAD2 = 'c'.repeat(40);
// The author ships PR 50; the reviewer answers with `review(task)`.
async function reviewing(review: (task: AgentTask) => Behavior, count = 1) {
  github.ready = { 'AshuLab/a': ready(...Array.from({ length: count }, (_, i) => i + 1)) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : review(task));
  const engine = await start(count);
  await clock.advance(5 * MIN);
  await engine.idle();
  return engine;
}
const reviewerTask = () => runner.tasks.find((t) => t.stage === 'review')!;

test('after ship the reviewer runs with its own profile, a separate workspace, the PR, the round and no previous summaries', async () => {
  const config = [{ name: 'AshuLab/a', agents: { ...agents, reviewer: { profile: 'rev', provider: 'codex' as const, model: 'r' } } }];
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1, config);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(reviewerTask()).toMatchObject({
    profile: 'rev', provider: 'codex', model: 'r', workspace: '/work/AshuLab/a/1/reviewer-50',
    context: { pr: { number: 50, headSha: SHA }, round: 1, previousSummaries: [] },
  });
  expect(reviewerTask().resultPath).not.toBe(runner.tasks[0]!.resultPath);
  expect(executionsOf(engine.db).map((e) => [e.stage, e.status])).toEqual([['ship', 'finished'], ['review', 'interrupted']]);
});

test('a concluding review on the current head leaves the epic ready for test with the reviewed SHA and verification', async () => {
  const engine = await reviewing((task) => ({
    write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'pnpm test ok, repo sin CI' } }),
  }));
  expect(rows(engine.db)[0]).toMatchObject({
    status: 'ready_for_test', reviewedSha: SHA, verification: { ci: 'absent', evidence: 'pnpm test ok, repo sin CI' },
    finishedAt: 5 * MIN, labelPending: false, needsHumanReason: null,
  });
  expect(labelsOf(1)).toEqual(['solve:epic:ready-for-test']);
});

test('a ready epic frees its slot for the next one', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  pull(50);
  pull(51, {}, 2);
  runner.behavior = (task) =>
    task.stage === 'ship'
      ? { write: completed(task, { number: 49 + task.epic, headSha: SHA }) }
      : task.epic === 1 ? { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } }) } : { exit: 'stopped' };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db).map((e) => e.status)).toEqual(['ready_for_test', 'running']);
});

test('a head that changed during the review sends the epic to needs_human, never ready', async () => {
  const engine = await reviewing((task) => {
    pull(50, { headSha: HEAD2 }); // a commit lands while the reviewer works
    return { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } }) };
  });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'el head cambió durante la revisión', reviewedSha: null });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('a needs_human review, an inconclusive one included, stops the epic with its reason', async () => {
  const engine = await reviewing((task) => ({ write: result(task, { outcome: 'needs_human', reason: 'revisión inconclusa: falta contexto' }) }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'revisión inconclusa: falta contexto', reviewedSha: null });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('changes_requested is imported and moves the epic to fix on the same round, with no launch and no label change', async () => {
  const engine = await reviewing((task) => ({
    write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'falta validar la entrada' }] }),
  }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 1, finishedAt: null });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
  expect(engine.db.select().from(callerResults).all().map((r) => r.outcome)).toEqual(['completed', 'changes_requested']);
});

test('a technical failure of the reviewer keeps the round, imports nothing and relaunches the review', async () => {
  const engine = await reviewing((task) => (task.resumeSession ? { exit: 'stopped' } : { sessionId: 's-r', exit: 'failed' }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 1 });
  expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['finished', 'failed', 'interrupted']);
  expect(engine.db.select().from(callerResults).all()).toHaveLength(1);
});

test('a review for a PR that no longer references the epic goes to needs_human', async () => {
  const engine = await reviewing((task) => {
    pull(50, { state: 'closed' });
    return { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } }) };
  });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'el PR #50 no está abierto' });
});

test('a reviewer workspace that cannot be prepared leaves the epic in needs_human', async () => {
  workspaces.prepareReviewer = async () => {
    throw new Error('checkout failed');
  };
  const engine = await reviewing(() => ({}));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'no se pudo preparar el workspace: checkout failed' });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('a ready label that did not reach GitHub is retried on the next poll', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { write: completed(task) } : { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } }) };
  const engine = await start(1);
  const setLabels = github.setLabels.bind(github);
  github.setLabels = async (repo, issue, change) => {
    if (change.add.includes('solve:epic:ready-for-test')) throw new GitHubUnavailable();
    return setLabels(repo, issue, change);
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', labelPending: true });

  github.setLabels = setLabels;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ labelPending: false });
  expect(labelsOf(1)).toEqual(['solve:epic:ready-for-test']);
});

test('the reviewer receives the summaries of earlier review and fix turns, oldest first', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => {
    if (task.stage !== 'ship') return {};
    const db = dbs[0]!; // history left by turns before this review
    db.insert(executions).values([
      { executionId: 'e-fix', epicId: 1, stage: 'fix', resultPath: 'y', startedAt: 2 },
      { executionId: 'e-old', epicId: 1, stage: 'review', resultPath: 'x', startedAt: 1 },
    ]).run();
    db.insert(callerResults).values([
      { executionId: 'e-fix', outcome: 'completed', result: JSON.stringify({ summary: 'corregido' }) },
      { executionId: 'e-old', outcome: 'changes_requested', result: JSON.stringify({ summary: 'ronda uno' }) },
    ]).run();
    return { write: completed(task) };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(reviewerTask().context.previousSummaries).toEqual(['ronda uno', 'corregido']);
});

// The epic ends from outside: its final PR is merged or closed, or its issue is closed.
// idle() would wait forever for the hung reviewer, so wait for its launch instead.
async function reviewingHung() {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { sessionId: 's-r', exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']));
  return engine;
}

test('a merged final PR stops the running executions and leaves the epic merged, keeping sessions and history, with no new turn', async () => {
  const engine = await reviewingHung();
  const tasks = runner.tasks.length;
  pull(50, { state: 'merged' });
  github.issue('AshuLab/a', 1).state = 'closed'; // merging the final PR closes the epic issue too
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged', cancelReason: null, finishedAt: 10 * MIN, labelPending: false, stage: 'review', prNumber: 50 });
  expect(runner.stopped).toEqual([runner.tasks[1]!.executionId]);
  expect(runner.tasks).toHaveLength(tasks);
  expect(executionsOf(engine.db).map((e) => [e.status, e.sessionId])).toEqual([['finished', null], ['interrupted', 's-r']]);
  expect(eventsOf(engine.db).map((e) => e.type)).toEqual(['epic_merged']);
  expect(labelsOf(1)).toEqual([]); // running removed, nothing added
});

test('a final PR closed without merge cancels the epic with the reason and stops its executions', async () => {
  const engine = await reviewingHung();
  pull(50, { state: 'closed' });
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelReason: 'el PR final #50 se cerró sin merge', finishedAt: 10 * MIN });
  expect(runner.stopped).toHaveLength(1);
  expect(labelsOf(1)).toEqual([]);
});

test('a closed epic issue cancels the epic even before it has a final PR', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', prNumber: null });

  github.issue('AshuLab/a', 1).state = 'closed';
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelReason: 'el issue de la épica se cerró sin merge', finishedAt: 10 * MIN });
  expect(runner.stopped).toHaveLength(1);
  expect(labelsOf(1)).toEqual([]);
});

test('a merged slice PR or a closed slice issue during ship never ends the epic', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);

  pull(60, { state: 'merged', body: 'Slice\n\nCloses #9' }, 9);
  github.issue('AshuLab/a', 9).state = 'closed';
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', finishedAt: null });
  expect(runner.stopped).toEqual([]);
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
});

test('an epic that ends from outside frees its slot and the other epics keep going in the same cycle', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  pull(50);
  pull(51, {}, 2);
  runner.behavior = (task) => (task.stage === 'ship' && task.epic < 3 ? { write: completed(task, { number: 49 + task.epic, headSha: SHA }) } : { exit: 'hang' });
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2));
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]);

  pull(50, { state: 'merged' });
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'merged')).toEqual([1]);
  expect(byStatus(engine.db, 'running')).toEqual([2, 3]);
  expect(runner.stopped).toEqual([runner.tasks.find((t) => t.epic === 1 && t.stage === 'review')!.executionId]);
});

test('a review result still waiting for GitHub is not imported once the epic was merged', async () => {
  const getPullRequest = github.getPullRequest.bind(github);
  const engine = await reviewing((task) => {
    github.getPullRequest = async () => {
      throw new GitHubUnavailable();
    };
    return { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } }) };
  });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review' });

  github.getPullRequest = getPullRequest;
  pull(50, { state: 'merged' });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged', reviewedSha: null, needsHumanReason: null });
  expect(engine.db.select().from(callerResults).all().map((r) => r.outcome)).toEqual(['completed']); // only ship's
});
