import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { eq } from 'drizzle-orm';
import { epics } from '../storage/schema.ts';
import { createEngine, type ResumeRefused } from './engine.ts';
import { reserve } from './reserve.ts';
import { FakeAgentRunner, FakeWorkspaces, type Behavior } from '../execution/fake.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { lastEventOf } from '../control/events.ts';
import { buildSnapshot } from '../status/snapshot.ts';
import { epicEvents, executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { callerResults } from '../storage/caller-results.ts';
import { FakeClock, FakeGitHub } from './fake.ts';
import { AuthError, GitHubUnavailable, type EpicSlice, type PullRequestBlock, type ReviewThread } from './github.ts';
import { epicReviewThreads } from '../storage/epic-review-threads.ts';
import { epicSlices } from '../storage/epic-slices.ts';

const MIN = 60_000;
const agents = {
  author: { profile: 'a', harness: 'claude' as const, model: 'm' },
  reviewer: { profile: 'b', harness: 'codex' as const, model: 'm' },
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
async function start(maxConcurrentEpics = 0, config = repos, maxExecutionHours: number | 'unlimited' = 4, maxExecutionRetries = 3, maxReviews = 5) {
  const db = open();
  const engine = createEngine({
    db, github, clock, repos: config, pollIntervalMs: 5 * MIN, maxConcurrentEpics, maxExecutionHours, maxExecutionRetries, maxReviews,
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

test('the poll keeps the title and labels of a ready epic and refreshes them, and those of a running one from the open list, with no extra request', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: 'First' }] };
  github.issue('AshuLab/a', 1).labels = ['solve:epic', 'solve:epic:ready', 'bug'];
  const engine = await start();
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, title: 'First', labels: ['solve:epic', 'solve:epic:ready', 'bug'], branch: null, needsHumanKind: null });
  expect(github.calls).toBe(2); // one ready list per repo: the title and labels came with it

  github.ready = { 'AshuLab/a': [{ issue: 1, title: 'First, renamed' }] };
  github.issue('AshuLab/a', 1).labels.push('p1');
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ title: 'First, renamed', labels: ['solve:epic', 'solve:epic:ready', 'bug', 'p1'] });

  // Once running the epic is no longer listed as ready: the open list carries them.
  github.ready = {};
  github.openEpics = { 'AshuLab/a': [{ issue: 1, title: 'Renamed again', slices: null }] };
  github.issue('AshuLab/a', 1).labels = ['solve:epic', 'solve:epic:running'];
  await clock.advance(5 * MIN);
  expect(rows(engine.db)).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ title: 'Renamed again', labels: ['solve:epic', 'solve:epic:running'] });
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

test('every poll refreshes the slice progress by repo and issue; a failed read keeps the last values and the epics are still picked up', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  github.openEpics = { 'AshuLab/a': [{ issue: 1, slices: { done: 1, total: 3 } }, { issue: 2, slices: null }], 'AshuLab/b': [{ issue: 1, slices: { done: 0, total: 0 } }] };
  const engine = await start();
  expect(engine.slices('AshuLab/a', 1)).toBeNull(); // before the first read

  await clock.advance(5 * MIN);
  expect(engine.slices('AshuLab/a', 1)).toEqual({ done: 1, total: 3 });
  expect(engine.slices('AshuLab/a', 2)).toBeNull();
  expect(engine.slices('AshuLab/b', 1)).toEqual({ done: 0, total: 0 });

  github.openEpics['AshuLab/a'] = [{ issue: 1, slices: { done: 2, total: 3 } }];
  await clock.advance(5 * MIN);
  expect(engine.slices('AshuLab/a', 1)).toEqual({ done: 2, total: 3 });

  github.openEpicsUnavailable = new GitHubUnavailable();
  github.openEpics['AshuLab/a'] = [{ issue: 1, slices: { done: 3, total: 3 } }];
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 5, title: '' }] };
  await clock.advance(5 * MIN);
  expect(engine.slices('AshuLab/a', 1)).toEqual({ done: 2, total: 3 }); // the stale value stays
  expect(engine.error).toBeNull();
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/a#5']); // and the poll went on

  github.openEpicsUnavailable = null;
  await clock.advance(5 * MIN);
  expect(engine.slices('AshuLab/a', 1)).toEqual({ done: 3, total: 3 });
});

test('a rejected profile on the progress read still suspends the poll', async () => {
  const engine = await start();
  const rejected = new AuthError('a');
  github.listOpenEpics = async () => {
    throw rejected;
  };
  await clock.advance(5 * MIN);
  expect(engine.error).toBe(rejected);
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
    return [{ issue: 1, title: '', labels: [] }];
  };
  const engine = await start();
  await clock.advance(5 * MIN);
  expect(engine.queue()).toEqual([]);
  expect(engine.error).toBe(fail);
});

test('each repo keeps its last check: when, whether it worked and why not, from a failure to its recovery', async () => {
  const engine = await start();
  expect(engine.lastCheck('AshuLab/a')).toBeUndefined();

  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 5 * MIN, ok: true, error: null });

  // b fails: a was read in that cycle, b was not.
  github.listReadyEpics = async (repo) => {
    if (repo === 'AshuLab/b') throw new GitHubUnavailable();
    return [];
  };
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 10 * MIN, ok: true, error: null });
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 10 * MIN, ok: false, error: 'GitHub is unavailable' });

  github.listReadyEpics = async () => [];
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 15 * MIN, ok: true, error: null });

  // A rejected profile fails every repo, naming the profile and nothing else.
  github.authError = new AuthError('orchestrator');
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 20 * MIN, ok: false, error: 'authentication error for profile orchestrator' });
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
  const list = github.listReadyEpics.bind(github);
  github.listReadyEpics = async (repo) => {
    const listed = await list(repo);
    github.issue('AshuLab/a', 2).labels = []; // the label goes after the listing, before the slot is reserved
    return listed;
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason])).toEqual([
    [1, 'cancelled', 'closed before it started'],
    [2, 'cancelled', 'ready label removed'],
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
  expect(github.styles['solve:epic:needs-human']).toEqual({ color: 'd93f0b', description: expect.stringContaining('person') }); // created with a colour and a description
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
const pull = (number: number, extra: Partial<{ state: 'open' | 'closed' | 'merged'; body: string; headSha: string; headRef: string }> = {}, issue = 1, repo = 'AshuLab/a') => {
  github.pulls[`${repo}#${number}`] = { state: 'open', body: `Final PR\n\nCloses #${issue}`, headSha: SHA, ...extra };
};
const executionsOf = (db: Db) => db.select().from(executions).all();

test('a reserved epic launches the author with its effective config, a unique result path and the time limit', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const config = [{ name: 'AshuLab/a', agents: { ...agents, author: { profile: 'p', harness: 'codex' as const, model: 'x' } } }];
  const engine = await start(2, config, 2);
  await clock.advance(5 * MIN);

  expect(runner.tasks).toHaveLength(2);
  const [task, other] = runner.tasks as [AgentTask, AgentTask];
  expect(task).toMatchObject({
    repo: 'AshuLab/a', epic: 1, stage: 'ship', profile: 'p', harness: 'codex', model: 'x',
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

test('the whole output of an execution is saved per stream under its logs folder', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ output: [['stdout', 'one\n'], ['stderr', 'oops\n'], ['stdout', 'two\n']], exit: 'hang' });
  await start(1);
  await clock.advance(5 * MIN);
  const folder = join(dir, 'orchestrator', 'logs', 'executions', runner.tasks[0]!.executionId);
  expect(readFileSync(join(folder, 'stdout.log'), 'utf8')).toBe('one\ntwo\n');
  expect(readFileSync(join(folder, 'stderr.log'), 'utf8')).toBe('oops\n');
});

test('the events a run reports are stored per chunk with the execution, the arrival time for those without their own', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({
    events: [
      [{ at: 42, kind: 'say', text: 'hi' }, { kind: 'tool_start', callId: 'c', tool: 'Bash', arg: 'ls' }],
      [{ kind: 'tool_end', callId: 'c', tool: 'Bash', status: 'ok', output: ['a'] }],
    ],
    exit: 'hang',
  });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  const stored = engine.db.select().from(executionEvents).all();
  expect(stored.map((e) => [e.executionId, e.at - clock.now() === 0 ? 'arrival' : e.at, e.kind])).toEqual([
    [runner.tasks[0]!.executionId, 42, 'say'],
    [runner.tasks[0]!.executionId, 'arrival', 'tool_start'],
    [runner.tasks[0]!.executionId, 'arrival', 'tool_end'],
  ]);
  expect(stored[2]!.payload).toEqual({ output: ['a'] });
});

test('the snapshot gives a running session its newest event as soon as the chunk that carried it is read', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ events: [[{ at: 42, kind: 'say', text: 'hi' }], [{ at: 43, kind: 'tool_start', callId: 'c', tool: 'Bash', arg: 'ls' }]], exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  const snapshot = buildSnapshot(engine.db, {
    now: clock.now(), maxConcurrentEpics: 1, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false,
    slices: engine.slices, version: '0', pollIntervalMs: 1, lastEvent: (id) => lastEventOf(engine.db, id),
  });
  expect(snapshot.sessions).toMatchObject([{ executionId: runner.tasks[0]!.executionId, last: { kind: 'tool_start', text: 'Bash ls', at: 43 } }]);
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
  ['a missing PR', undefined, 'does not exist'],
  ['a closed PR', { state: 'closed' as const }, 'is not open'],
  ['a PR that does not reference the epic', { body: 'Closes #2' }, 'does not reference the epic'],
  ['a PR with another head', { headSha: 'b'.repeat(40) }, 'head of PR #50'],
])('%s leaves only that epic in needs_human with the reason, and the slot goes to the next one', async (_, change, reason) => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  if (change) pull(50, change);
  pull(51, {}, 2);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task, { number: task.epic === 1 ? 50 : 51, headSha: SHA }) } : { exit: 'stopped' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  const [first, second] = rows(engine.db);
  expect(first).toMatchObject({ issue: 1, status: 'needs_human', needsHumanKind: 'pr_invalid', finishedAt: 5 * MIN, labelPending: false });
  expect(first?.needsHumanReason).toContain(reason);
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  // The second one started right away, with no new poll, and was not affected.
  expect(second).toMatchObject({ issue: 2, status: 'running', stage: 'review' });
  expect(labelsOf(2)).toEqual(['solve:epic:running']);
});

test('a needs_human result stops the epic with the caller reason and label', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'a credential is missing' }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'a credential is missing', finishedAt: 5 * MIN });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('`ready` put back on a needs_human epic starts it again from ship, and a stopped one without it stays stopped', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'the CI is red' }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });

  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'the CI is red' });

  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'still red' }) });
  github.issues['AshuLab/a#1']!.labels.push('solve:epic:ready');
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'still red', stage: 'ship' });
  expect(runner.tasks.filter((t) => t.stage === 'ship')).toHaveLength(2);
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'workspace', needsHumanReason: 'could not prepare the workspace: clone failed' });
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
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, status: 'needs_human', needsHumanKind: 'retries_exhausted', round: null, finishedAt: 5 * MIN });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe('ran out of ship retries (4 attempts): the agent process ended with an error');
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'timeout', needsHumanReason: 'the ship execution exceeded the time limit' });
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
    stage: 'review', profile: 'b', harness: 'codex', workspace: '/work/AshuLab/a/1/reviewer-50', resumeSession: 's-r',
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
  const config = [{ name: 'AshuLab/a', agents: { ...agents, reviewer: { profile: 'rev', harness: 'codex' as const, model: 'r' } } }];
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1, config);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(reviewerTask()).toMatchObject({
    profile: 'rev', harness: 'codex', model: 'r', workspace: '/work/AshuLab/a/1/reviewer-50',
    context: { pr: { number: 50, headSha: SHA }, round: 1, previousSummaries: [] },
  });
  expect(reviewerTask().resultPath).not.toBe(runner.tasks[0]!.resultPath);
  expect(executionsOf(engine.db).map((e) => [e.stage, e.status])).toEqual([['ship', 'finished'], ['review', 'interrupted']]);
});

test('a concluding review on the current head leaves the epic ready for test with the reviewed SHA and verification', async () => {
  const engine = await reviewing((task) => ({
    write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'pnpm test ok, repo without CI' } }),
  }));
  expect(rows(engine.db)[0]).toMatchObject({
    status: 'ready_for_test', reviewedSha: SHA, verification: { ci: 'absent', evidence: 'pnpm test ok, repo without CI' },
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'the head changed during the review', reviewedSha: null });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('a needs_human review, an inconclusive one included, stops the epic with its reason', async () => {
  const engine = await reviewing((task) => ({ write: result(task, { outcome: 'needs_human', reason: 'inconclusive review: missing context' }) }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'inconclusive review: missing context', reviewedSha: null });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('changes_requested below the limit keeps the round and launches the author fix with its identity, its session and the blockers', async () => {
  const blockers = [{ title: 'input validation missing', url: 'https://github.com/AshuLab/a/pull/50#discussion_r1' }, { title: 'no test' }];
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers }) }
    : { exit: 'stopped' };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix']);
  expect(runner.tasks[2]).toMatchObject({
    profile: 'a', harness: 'claude', workspace: '/work/AshuLab/a/worktrees/feat/epic/epic', resumeSession: 's-ship',
    context: { pr: { number: 50, headSha: SHA }, round: 1, blockers },
  });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 1, finishedAt: null });
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
});

test('the epic worktree is read back from git after ship and kept: the fix turns, retries included, run in it; ship ran in the clone', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  const blockers = [{ title: 'x' }];
  let fixes = 0;
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers }) }
    : ++fixes === 1 ? { exit: 'failed' } : { exit: 'stopped' };
  const asked: string[] = [];
  workspaces.findWorktree = async (repo, branch) => (asked.push(`${repo}:${branch}`), '/home/me/.solve/worktrees/a/demo');
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(asked).toEqual(['AshuLab/a:feat/demo/epic']);
  expect(rows(engine.db)[0]).toMatchObject({ workspace: '/home/me/.solve/worktrees/a/demo' });
  expect(runner.tasks.map((t) => [t.stage, t.workspace])).toEqual([
    ['ship', '/work/AshuLab/a/1/author'],
    ['review', '/work/AshuLab/a/1/reviewer-50'],
    ['fix', '/home/me/.solve/worktrees/a/demo'],
    ['fix', '/home/me/.solve/worktrees/a/demo'],
  ]);
});

test('every execution row records its agent, folder and round: author, reviewer, fix, and a retry is its own row', async () => {
  const config = [{ name: 'AshuLab/a', agents: { ...agents, author: { ...agents.author, provider: 'ollama' as const } } }];
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  let fixes = 0;
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }) }
    : ++fixes === 1 ? { exit: 'failed' } : { exit: 'stopped' };
  workspaces.findWorktree = async () => '/home/me/.solve/worktrees/a/demo';
  const engine = await start(1, config);
  await clock.advance(5 * MIN);
  await engine.idle();

  const worktree = '/home/me/.solve/worktrees/a/demo';
  expect(executionsOf(engine.db).map((e) => [e.stage, e.harness, e.model, e.provider, e.workspace, e.round])).toEqual([
    ['ship', 'claude', 'm', 'ollama', '/work/AshuLab/a/1/author', null],
    ['review', 'codex', 'm', null, '/work/AshuLab/a/1/reviewer-50', 1],
    ['fix', 'claude', 'm', 'ollama', worktree, 1],
    ['fix', 'claude', 'm', 'ollama', worktree, 1],
  ]);
});

test('a fix turn for an epic with no saved workspace goes to needs_human instead of running in another cwd', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let engine!: Awaited<ReturnType<typeof start>>;
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { write: completed(task) };
    engine.db.update(epics).set({ workspace: null }).run(); // as if the row never got it
    return { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }) };
  };
  engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'could not prepare the workspace: the epic has no saved worktree' });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
});

test('the final PR\'s branch is kept when ship is validated, and a restart from needs_human clears the kind', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task, { number: 50, headSha: SHA }) } : { write: result(task, { outcome: 'needs_human', reason: 'unclear' }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', branch: 'feat/demo/epic', needsHumanKind: 'agent_needs_human' });

  github.issue('AshuLab/a', 1).labels.push('solve:epic:ready');
  runner.behavior = () => ({ exit: 'stopped' });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', needsHumanKind: null });
});

test('a ship result whose epic worktree git does not list sends the epic to needs_human with the branch', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  pull(50, { headRef: 'feat/demo/epic' });
  pull(51, { headRef: 'feat/other/epic' }, 2);
  runner.behavior = (task) => ({ write: completed(task, { number: 49 + task.epic, headSha: SHA }) });
  workspaces.findWorktree = async (_repo, branch) => {
    if (branch === 'feat/other/epic') throw new Error('git broke');
    return null;
  };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db).map((e) => [e.status, e.needsHumanKind, e.needsHumanReason, e.workspace, e.prNumber])).toEqual([
    ['needs_human', 'workspace', 'could not find the worktree for branch feat/demo/epic in the clone of AshuLab/a', null, null],
    ['needs_human', 'workspace', 'could not find the worktree for branch feat/other/epic in the clone of AshuLab/a', null, null],
  ]);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'ship']);
});

test('last activity is written from the first output and then at most once every 10 s; stage start and last error follow the stage', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let emit!: (stream: 'stdout' | 'stderr', chunk: string) => void;
  let finish!: (exit: 'failed' | 'ok') => void;
  runner.run = (task) => {
    runner.tasks.push(task);
    return {
      onSession() {},
      onOutput: (cb) => void (emit = cb),
      onEvent() {},
      done: new Promise((resolve) => (finish = (exit) => resolve({ exit }))),
      stop: async () => {},
    };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  const row = () => rows(engine.db)[0]!;
  expect(row()).toMatchObject({ stage: 'ship', stageStartedAt: 5 * MIN, lastActivityAt: null, lastError: null });

  emit('stdout', 'a\n');
  expect(row().lastActivityAt).toBe(5 * MIN);
  await clock.advance(9_999);
  emit('stdout', 'b\n');
  expect(row().lastActivityAt).toBe(5 * MIN);
  await clock.advance(1);
  emit('stderr', 'c');
  expect(row().lastActivityAt).toBe(5 * MIN + 10_000);
  expect(readFileSync(join(dir, 'orchestrator', 'logs', 'executions', runner.tasks[0]!.executionId, 'stdout.log'), 'utf8')).toBe('a\nb\n'); // every chunk is logged, only the write is limited

  finish('failed');
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2)); // the retry
  expect(row()).toMatchObject({ lastError: 'the agent process ended with an error', stage: 'ship', stageStartedAt: 5 * MIN });
});

test('an invalid result is a retried failure; importing the next result clears the last error and starts the review stage', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let attempt = 0;
  runner.behavior = (task) =>
    task.stage === 'ship' ? (++attempt === 1 ? { write: '{broken' } : { write: completed(task) }) : { exit: 'stopped' };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'ship', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', stageStartedAt: 5 * MIN, lastError: null });
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'invalid_result' });
});

// ship -> review (changes_requested up to round `asking`, then it stops) -> fix -> review ...
async function fixing(fix: (task: AgentTask) => Behavior, maxReviews = 5, asking = 1) {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? task.context.round! > asking ? { exit: 'stopped' } : { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: `round ${task.context.round}` }] }) }
    : fix(task);
  const engine = await start(1, repos, 4, 3, maxReviews);
  await clock.advance(5 * MIN);
  await engine.idle();
  return engine;
}
const fixDone = (task: AgentTask, headSha = SHA) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha }, verification: { ci: 'absent', evidence: 'ok' } }) });

test('a completed fix launches a new review execution with round + 1 and the previous summaries', async () => {
  const engine = await fixing((task) => (task.context.round === 1 ? fixDone(task) : { exit: 'stopped' }));
  expect(runner.tasks.map((t) => [t.stage, t.context.round])).toEqual([['ship', undefined], ['review', 1], ['fix', 1], ['review', 2]]);
  const [, review1, , review2] = runner.tasks as AgentTask[];
  expect(review2!.executionId).not.toBe(review1!.executionId);
  expect(review2).toMatchObject({ profile: 'b', workspace: '/work/AshuLab/a/1/reviewer-50', context: { round: 2, previousSummaries: ['done', 'done'] } });
  expect(review2!.resumeSession).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2 });
});

test('a fix that answers without new commits is valid while its head is the current head', async () => {
  const engine = await fixing((task) => (task.context.round === 1 ? fixDone(task, SHA) : { exit: 'stopped' }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, prHeadSha: SHA });
});

test('a fix with new commits records the new head for the next review', async () => {
  const engine = await fixing((task) => {
    if (task.context.round !== 1) return { exit: 'stopped' };
    pull(50, { headSha: HEAD2 });
    return fixDone(task, HEAD2);
  });
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', round: 2, prHeadSha: HEAD2 });
  expect(runner.tasks[3]!.context.pr).toEqual({ number: 50, headSha: HEAD2 });
});

test('a fix whose head is not the current one goes to needs_human', async () => {
  const engine = await fixing((task) => {
    pull(50, { headSha: HEAD2 });
    return fixDone(task, SHA);
  });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('head of PR #50');
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix']);
});

test('with maxReviews 2 a changes_requested on the second review needs a human and no third review runs', async () => {
  const engine = await fixing((task) => fixDone(task), 2, 2);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'review_limit', round: 2, finishedAt: 5 * MIN, labelPending: false });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('review limit');
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('with maxReviews 1 the first changes_requested is already the limit', async () => {
  const engine = await fixing((task) => fixDone(task), 1);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', round: 1 });
});

test('a needs_human of the author in fix stops the epic with its reason', async () => {
  const engine = await fixing((task) => ({ write: result(task, { outcome: 'needs_human', reason: 'the finding contradicts the spec' }) }));
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'the finding contradicts the spec' });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('fix turns and technical retries do not consume rounds: only reviews count', async () => {
  // Round 1 review -> fix fails once and is retried -> round 2 review is still within maxReviews 2.
  let fixes = 0;
  const engine = await fixing((task) => (++fixes === 1 ? { sessionId: 's-fix', exit: 'failed' } : task.context.round === 1 ? fixDone(task) : { exit: 'stopped' }), 2);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix', 'fix', 'review']);
  expect(runner.tasks[3]).toMatchObject({ resumeSession: 's-fix', context: { round: 1, verifyStateFirst: true, blockers: [{ title: 'round 1' }] } });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2 });
});

// --- the observations pass ---

const observations = [{ id: 'o1', title: 'rename the helper', url: 'https://github.com/AshuLab/a/pull/50#discussion_r9' }, { title: 'typo in a comment' }];
const reviewerVerification = { ci: 'passed', evidence: 'pnpm test ok' } as const;
// ship -> review round 1 completed with `listed` observations -> the pass (`fix`) -> reviews of the next rounds answer with `later`.
async function passing(fix: (task: AgentTask) => Behavior, { listed = observations as object[] | undefined, later = (() => ({ exit: 'stopped' })) as (task: AgentTask) => Behavior, maxReviews = 5 } = {}) {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? task.context.round === 1 ? { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: reviewerVerification, ...(listed && { observations: listed }) }) } : later(task)
    : fix(task);
  const engine = await start(1, repos, 4, 3, maxReviews);
  await clock.advance(5 * MIN);
  await engine.idle();
  return engine;
}

test('a review completed with observations below the limit starts the author on the same round with them, and records the pass; the epic stays running', async () => {
  const engine = await passing(() => ({ exit: 'stopped' }));
  expect(runner.tasks.map((t) => [t.stage, t.context.round])).toEqual([['ship', undefined], ['review', 1], ['fix', 1]]);
  expect(runner.tasks[2]).toMatchObject({ resumeSession: 's-ship', context: { observations, round: 1 } });
  expect(runner.tasks[2]!.context.blockers).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({
    status: 'running', stage: 'fix', round: 1, observationsPassAt: 5 * MIN, reviewedSha: SHA, verification: reviewerVerification, finishedAt: null, labelPending: false,
  });
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
});

test('a pass that ends with the reviewed head sends the epic to ready for test with the reviewed head and the reviewer\'s verification', async () => {
  const engine = await passing((task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'the author says so' } }) }));
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, verification: reviewerVerification, finishedAt: 5 * MIN, labelPending: false });
  expect(labelsOf(1)).toEqual(['solve:epic:ready-for-test']);
});

test('a pass that ends with a new head starts the next review round, counted against the limit, and leaves no reviewed head for the new commit', async () => {
  const engine = await passing((task) => {
    pull(50, { headSha: HEAD2 });
    return fixDone(task, HEAD2);
  });
  expect(runner.tasks.map((t) => [t.stage, t.context.round])).toEqual([['ship', undefined], ['review', 1], ['fix', 1], ['review', 2]]);
  expect(runner.tasks[3]!.context.pr).toEqual({ number: 50, headSha: HEAD2 });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, prHeadSha: HEAD2, reviewedSha: SHA, finishedAt: null });
});

test('with maxReviews 2 the review after a pass with a new head is the last one: observations there go to ready for test, changes_requested to a person', async () => {
  const commit = (task: AgentTask) => {
    pull(50, { headSha: HEAD2 });
    return fixDone(task, HEAD2);
  };
  const engine = await passing(commit, {
    maxReviews: 2,
    later: (task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: HEAD2 }, verification: { ci: 'passed', evidence: 'second look' }, observations: [{ title: 'one more' }] }) }),
  });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 2, reviewedSha: HEAD2, verification: { ci: 'passed', evidence: 'second look' } });
});

test('a review completed with observations after the pass was taken goes to ready for test without a second pass', async () => {
  const engine = await passing(
    (task) => {
      pull(50, { headSha: HEAD2 });
      return fixDone(task, HEAD2);
    },
    { later: (task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: HEAD2 }, verification: reviewerVerification, observations: [{ title: 'again' }] }) }) },
  );
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 2, reviewedSha: HEAD2, observationsPassAt: 5 * MIN });
});

test('a review completed with observations at the last round goes to ready for test without a pass', async () => {
  const engine = await passing(() => ({ exit: 'stopped' }), { maxReviews: 1 });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, reviewedSha: SHA, verification: reviewerVerification, observationsPassAt: null });
});

test('a review completed with an empty list of observations goes to ready for test as before', async () => {
  const engine = await passing(() => ({ exit: 'stopped' }), { listed: [] });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, observationsPassAt: null });
});

test('a fix for blockers carries the blockers and no observations, and still goes to the next review', async () => {
  const engine = await fixing((task) => (task.context.round === 1 ? fixDone(task) : { exit: 'stopped' }));
  expect(runner.tasks[2]!.context).toMatchObject({ blockers: [{ title: 'round 1' }] });
  expect(runner.tasks[2]!.context.observations).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, observationsPassAt: null });
});

test('a technical retry of the pass resumes it as a pass with the same observations', async () => {
  let fixes = 0;
  const engine = await passing((task) => (++fixes === 1 ? { sessionId: 's-fix', exit: 'failed' } : { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'ok' } }) }));
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix', 'fix']);
  expect(runner.tasks[3]).toMatchObject({ resumeSession: 's-fix', context: { observations, round: 1, verifyStateFirst: true } });
  expect(runner.tasks[3]!.context.blockers).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, verification: reviewerVerification });
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'PR #50 is not open' });
});

test('a reviewer workspace that cannot be prepared leaves the epic in needs_human', async () => {
  workspaces.prepareReviewer = async () => {
    throw new Error('checkout failed');
  };
  const engine = await reviewing(() => ({}));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'could not prepare the workspace: checkout failed' });
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
      { executionId: 'e-fix', outcome: 'completed', result: JSON.stringify({ summary: 'fixed' }) },
      { executionId: 'e-old', outcome: 'changes_requested', result: JSON.stringify({ summary: 'round one' }) },
    ]).run();
    return { write: completed(task) };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(reviewerTask().context.previousSummaries).toEqual(['round one', 'fixed']);
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

test.each(['ready_for_test', 'needs_human'] as const)('a %s epic whose final PR is merged or whose issue is closed ends too', async (parked) => {
  const engine = await reviewingHung();
  engine.db.update(epics).set({ status: parked }).where(eq(epics.issue, 1)).run();
  pull(50, { state: 'merged' });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged', labelPending: false });

  engine.db.update(epics).set({ status: parked, cancelReason: null }).where(eq(epics.issue, 1)).run();
  pull(50, { state: 'open' });
  github.issue('AshuLab/a', 1).state = 'closed';
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelReason: 'the epic issue was closed without merging' });
});

test('a final PR closed without merge cancels the epic with the reason and stops its executions', async () => {
  const engine = await reviewingHung();
  pull(50, { state: 'closed' });
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelReason: 'the final PR #50 was closed without merging', finishedAt: 10 * MIN });
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelReason: 'the epic issue was closed without merging', finishedAt: 10 * MIN });
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

test('shutdown stops every active run without waiting for its stage, keeps the epics running and writes nothing to GitHub', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  runner.behavior = (task) => ({ sessionId: `s-${task.epic}`, exit: 'hang' });
  const engine = await start(2);
  await clock.advance(5 * MIN);
  const calls = github.calls;
  const labels = [labelsOf(1), labelsOf(2), labelsOf(3)].map((l) => [...l]);

  await engine.shutdown();

  expect(runner.stopped).toHaveLength(2);
  expect(executionsOf(engine.db).map((e) => [e.status, e.sessionId])).toEqual([['interrupted', 's-1'], ['interrupted', 's-2']]);
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]);
  expect(byStatus(engine.db, 'queued')).toEqual([3]);

  // Nothing wakes up afterwards: no poll, no reservation, no GitHub call or label change.
  await clock.advance(20 * MIN);
  expect(github.calls).toBe(calls);
  expect(runner.tasks).toHaveLength(2);
  expect([labelsOf(1), labelsOf(2), labelsOf(3)]).toEqual(labels);
  expect(byStatus(engine.db, 'queued')).toEqual([3]);
});

// --- restart: reconcile and resume ---

const seedEpic = (db: Db, issue: number, extra: Partial<typeof epics.$inferInsert> = {}) =>
  db.insert(epics).values({ repo: 'AshuLab/a', issue, status: 'running', config: repos[0], stage: 'ship', startedAt: 0, ...extra }).run();
const seedExecution = (db: Db, executionId: string, epicId: number, extra: Partial<typeof executions.$inferInsert> = {}) =>
  db.insert(executions).values({ executionId, epicId, stage: 'ship', status: 'running', sessionId: `s-${executionId}`, resultPath: join(dir, `${executionId}.json`), startedAt: 0, ...extra }).run();
const statusOf = (db: Db, executionId: string) => db.select().from(executions).where(eq(executions.executionId, executionId)).get()!.status;
const eventTypes = (db: Db) => db.select().from(epicEvents).all().map((e) => e.type);

test('a restart stops the live orphan before launching, resumes its session and reserves the next epic after that', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1);
  runner.alive.add('e0'); // the previous process's agent is still running
  const aliveAtLaunch: string[][] = [];
  runner.behavior = () => (aliveAtLaunch.push([...runner.alive]), { exit: 'hang' });
  github.ready = { 'AshuLab/a': ready(2) };

  const engine = await start(2);
  expect(runner.stopped).toEqual(['e0']);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ epic: 1, stage: 'ship', resumeSession: 's-e0', context: { verifyStateFirst: true } });
  expect(aliveAtLaunch).toEqual([[runner.tasks[0]!.executionId]]); // only the new agent is alive on the workspace
  expect(statusOf(engine.db, 'e0')).toBe('interrupted');

  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.epic)).toEqual([1, 2]);
});

test('a restart leaves alone a live agent this root never launched', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1);
  runner.alive.add('e0');
  runner.alive.add('another-carriers-agent'); // marked like ours, found in the machine's process list, absent from this SQLite
  await start(1);
  expect(runner.stopped).toEqual(['e0']);
});

test('a Ctrl+C then a restart resumes each interrupted execution as a new one with its session, never starting the stage over', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => ({ sessionId: `s-${task.epic}`, exit: 'hang' });
  const first = await start(2);
  await clock.advance(5 * MIN);
  await first.shutdown();
  dbs.pop()!.$client.close();

  const second = await start(2);
  expect(runner.tasks).toHaveLength(4);
  expect(runner.tasks.slice(2)).toMatchObject([
    { epic: 1, stage: 'ship', resumeSession: 's-1', context: { verifyStateFirst: true } },
    { epic: 2, stage: 'ship', resumeSession: 's-2', context: { verifyStateFirst: true } },
  ]);
  expect(executionsOf(second.db).map((e) => e.status)).toEqual(['interrupted', 'interrupted', 'running', 'running']);
  expect(byStatus(second.db, 'running')).toEqual([1, 2]);
});

test('a running execution a dead process left behind counts as interrupted and is resumed', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA });
  seedExecution(db, 'e0', 1, { stage: 'review' });
  await start(1);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ stage: 'review', resumeSession: 's-e0', context: { round: 2, pr: { number: 50, headSha: SHA }, verifyStateFirst: true } });
});

test('a lost session starts a new one with the same profile and the context rebuilt from SQLite and GitHub, and leaves session_rebuilt', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA });
  seedExecution(db, 'old', 1, { stage: 'review', status: 'finished' });
  db.insert(callerResults).values({ executionId: 'old', outcome: 'changes_requested', result: JSON.stringify({ summary: 'round 1 findings' }) }).run();
  seedExecution(db, 'e0', 1, { stage: 'review', status: 'interrupted' });
  pull(50, { headSha: HEAD2 }); // the author pushed while the review was cut
  runner.behavior = (task) => (task.resumeSession ? { exit: 'session_unavailable' } : { exit: 'hang' });

  const engine = await start(1);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(runner.tasks[0]).toMatchObject({ resumeSession: 's-e0' });
  expect(runner.tasks[1]).toMatchObject({
    stage: 'review', profile: 'b', harness: 'codex', workspace: '/work/AshuLab/a/1/reviewer-50',
    context: { pr: { number: 50, headSha: HEAD2 }, round: 2, previousSummaries: ['round 1 findings'], verifyStateFirst: true },
  });
  expect(runner.tasks[1]!.resumeSession).toBeUndefined();
  expect(eventTypes(engine.db)).toEqual(['session_rebuilt']);
  expect(engine.db.select().from(epicEvents).get()!.data).toMatchObject({ stage: 'review', pr: { number: 50, headSha: HEAD2 } });
  expect(byStatus(engine.db, 'running')).toEqual([1]);
});

test('a lost author session is rebuilt too, with the PR GitHub has now', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'interrupted' });
  pull(50);
  runner.behavior = (task) => (task.resumeSession ? { exit: 'session_unavailable' } : { exit: 'hang' });
  await start(1);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(runner.tasks[1]).toMatchObject({ stage: 'ship', profile: 'a', context: { pr: { number: 50, headSha: SHA }, verifyStateFirst: true } });
  expect(runner.tasks[1]!.resumeSession).toBeUndefined();
});

test('a result the interrupted agent had written is imported exactly once and the agent is not launched again', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'interrupted' });
  writeFileSync(join(dir, 'e0.json'), JSON.stringify({
    executionId: 'e0', repo: 'AshuLab/a', epic: 1, stage: 'ship', summary: 'done', outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'no CI' },
  }));
  pull(50);

  const first = await start(1);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['review']); // the next stage, not ship again
  expect(first.db.select().from(callerResults).all().map((r) => r.executionId)).toEqual(['e0']);
  expect(rows(first.db)[0]).toMatchObject({ stage: 'review', round: 1, prNumber: 50 });
  first.stop();
  dbs.pop()!.$client.close();

  const second = await start(1); // restarting again imports nothing more
  expect(runner.tasks.map((t) => t.stage)).toEqual(['review', 'review']); // the interrupted review is resumed
  expect(second.db.select().from(callerResults).all()).toHaveLength(1);
});

test('an incomplete result of an interrupted agent is not imported nor counted as a failure: the session is resumed', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'interrupted' });
  writeFileSync(join(dir, 'e0.json'), '{"outcome": "compl');
  const engine = await start(1, repos, 4, 0); // no technical retries at all
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ resumeSession: 's-e0', context: { verifyStateFirst: true } });
  expect(statusOf(engine.db, 'e0')).toBe('interrupted');
  expect(engine.db.select().from(callerResults).all()).toEqual([]);
  expect(byStatus(engine.db, 'running')).toEqual([1]);
});

test('a stage claimed but never inserted (cut in between) launches its author once, without a session', async () => {
  const db = open();
  seedEpic(db, 1); // stage ship, no execution row
  const engine = await start(1);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ stage: 'ship', context: { previousSummaries: [] } });
  expect(runner.tasks[0]!.resumeSession).toBeUndefined();
  expect(executionsOf(engine.db)).toHaveLength(1);
});

test('a result imported whose next stage never launched launches it on restart', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'fix', round: 1, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic' });
  seedExecution(db, 'r1', 1, { stage: 'review', status: 'finished' });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'changes_requested', result: JSON.stringify({ summary: 's', blockers: [{ title: 'fix it' }] }) }).run();
  await start(1);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ stage: 'fix', context: { blockers: [{ title: 'fix it' }] } });
});

test('a restart in the middle of the pass resumes the fix as a pass with the same observations', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'fix', round: 1, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', observationsPassAt: 1, reviewedSha: SHA });
  seedExecution(db, 'r1', 1, { stage: 'review', status: 'finished' });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'completed', result: JSON.stringify({ summary: 's', observations: [{ title: 'rename it' }] }) }).run();
  seedExecution(db, 'f1', 1, { stage: 'fix', status: 'interrupted', startedAt: 1 });
  await start(1);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ stage: 'fix', resumeSession: 's-f1', context: { observations: [{ title: 'rename it' }], round: 1, verifyStateFirst: true } });
  expect(runner.tasks[0]!.context.blockers).toBeUndefined();
});

test('a review imported whose pass never launched launches the pass on restart', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'fix', round: 1, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', observationsPassAt: 1, reviewedSha: SHA });
  seedExecution(db, 'r1', 1, { stage: 'review', status: 'finished' });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'completed', result: JSON.stringify({ summary: 's', observations: [{ title: 'rename it' }] }) }).run();
  await start(1);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ stage: 'fix', context: { observations: [{ title: 'rename it' }] } });
});

test('needs_human, cancelled, merged and ready_for_test epics are not reactivated and the queue keeps its order', async () => {
  const db = open();
  const finished = { needs_human: 1, cancelled: 2, merged: 3, ready_for_test: 4 } as const;
  for (const [status, issue] of Object.entries(finished)) {
    seedEpic(db, issue, { status: status as keyof typeof finished });
    seedExecution(db, `e${issue}`, issue, { status: 'interrupted' });
  }
  db.insert(epics).values([{ repo: 'AshuLab/a', issue: 9 }, { repo: 'AshuLab/b', issue: 5 }, { repo: 'AshuLab/a', issue: 6 }]).run();
  runner.alive.add('e1'); // even its live agent is stopped, never relaunched

  const engine = await start(5);
  await clock.advance(5 * MIN);
  expect(runner.stopped).toEqual(['e1']);
  expect(runner.tasks.map((t) => t.epic)).toEqual([9, 5, 6]); // only the queue, in order
  expect(byStatus(engine.db, 'needs_human')).toEqual([1]);
  expect(byStatus(engine.db, 'cancelled')).toEqual([2]);
  expect(byStatus(engine.db, 'merged')).toEqual([3]);
  expect(byStatus(engine.db, 'ready_for_test')).toEqual([4]);
});

test('labels that differ from SQLite on restart are corrected to SQLite', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'review', prNumber: 50 });
  seedExecution(db, 'e0', 1, { stage: 'review', status: 'finished' });
  seedEpic(db, 2, { status: 'needs_human' });
  seedEpic(db, 3, { status: 'ready_for_test' });
  github.issues = {
    'AshuLab/a#1': { state: 'open', labels: ['solve:epic:ready', 'solve:epic:ready-for-test', 'unrelated'] },
    'AshuLab/a#2': { state: 'open', labels: ['solve:epic:running'] },
    'AshuLab/a#3': { state: 'open', labels: [] },
  };
  await start(0);
  expect(labelsOf(1)).toEqual(['unrelated', 'solve:epic:running']);
  expect(labelsOf(2)).toEqual(['solve:epic:needs-human']);
  expect(labelsOf(3)).toEqual(['solve:epic:ready-for-test']);
});

// --- repo removed from the config ---

const githubRepoCalls = () => {
  const touched: string[] = [];
  for (const method of ['listReadyEpics', 'getIssue', 'getPullRequest', 'findPullRequest', 'setLabels', 'listLabels', 'createLabel'] as const) {
    const original = github[method].bind(github) as (repo: string, ...rest: unknown[]) => Promise<unknown>;
    (github as unknown as Record<string, unknown>)[method] = (repo: string, ...rest: unknown[]) => (touched.push(`${method} ${repo}`), original(repo, ...rest));
  }
  return touched;
};

test('a repo missing from the config stops its pending epics with the reason and where they were, touching nothing of it', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'review', round: 2, prNumber: 50 }); // running
  seedExecution(db, 'e1', 1, { stage: 'review' });
  runner.alive.add('e1');
  seedEpic(db, 2, { status: 'queued', stage: null, config: null, startedAt: null });
  seedEpic(db, 3, { status: 'needs_human', needsHumanReason: 'needs a decision' });
  seedEpic(db, 4, { status: 'ready_for_test' });
  seedEpic(db, 5, { repo: 'AshuLab/b', status: 'queued', stage: null, config: null, startedAt: null });
  seedExecution(db, 'f1', 1, { stage: 'ship', status: 'failed', error: 'x' }); // a past failure that must stay as it is
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: ['solve:epic:running'] }, 'AshuLab/a#3': { state: 'open', labels: ['solve:epic:needs-human'] } };
  github.ready = { 'AshuLab/a': ready(9), 'AshuLab/b': ready(5) };
  const touched = githubRepoCalls();
  const before = executionsOf(db).length;

  const engine = await start(3, [repos[1]!]);
  await clock.advance(5 * MIN);

  expect(rows(engine.db).map((e) => [e.issue, e.status, e.removedFrom])).toEqual([
    [1, 'repo_removed', 'running'],
    [2, 'repo_removed', 'queued'],
    [3, 'repo_removed', 'needs_human'],
    [4, 'ready_for_test', null],
    [5, 'running', null],
  ]);
  const stopped = rows(engine.db).find((e) => e.issue === 1)!;
  expect(stopped).toMatchObject({ removedReason: expect.stringContaining('configuration'), stage: 'review', round: 2, prNumber: 50 });
  expect(rows(engine.db).find((e) => e.issue === 3)!.needsHumanReason).toBe('needs a decision');
  expect(eventTypes(engine.db).filter((t) => t === 'repo_removed')).toHaveLength(3);
  // Sessions and history stay; the live orphan is stopped, no new execution and no retry for the removed repo.
  expect(runner.stopped).toEqual(['e1']);
  expect(statusOf(engine.db, 'e1')).toBe('interrupted');
  expect(executionsOf(engine.db).filter((e) => e.epicId === 1)).toHaveLength(2);
  expect(executionsOf(engine.db).find((e) => e.executionId === 'e1')!.sessionId).toBe('s-e1');
  expect(executionsOf(engine.db).length).toBe(before + 1); // only AshuLab/b#5
  expect(runner.tasks.map((t) => `${t.repo}#${t.epic}`)).toEqual(['AshuLab/b#5']);
  expect(touched.filter((c) => c.endsWith('AshuLab/a'))).toEqual([]);
  expect(labelsOf(1)).toEqual(['solve:epic:running']);
  expect(labelsOf(3)).toEqual(['solve:epic:needs-human']);
});

test('a repo configured again resumes its epics where they were, except the ones that needed a person', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA });
  seedExecution(db, 'e1', 1, { stage: 'review' });
  seedEpic(db, 2, { status: 'queued', stage: null, config: null, startedAt: null });
  seedEpic(db, 3, { status: 'needs_human', needsHumanReason: 'needs a decision' });
  seedEpic(db, 4, { status: 'queued', stage: null, config: null, startedAt: null });
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: ['solve:epic:running'] }, 'AshuLab/a#3': { state: 'open', labels: ['solve:epic:needs-human'] } };
  runner.behavior = () => ({ exit: 'hang' });

  await (await start(2, [repos[1]!])).idle(); // the repo is gone
  expect(byStatus(db, 'repo_removed')).toEqual([1, 2, 3, 4]);
  expect(runner.tasks).toEqual([]);

  const engine = await start(2); // and back
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'needs_human')).toEqual([3]);
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]); // 1 resumed, 2 reserved first in queue order
  expect(byStatus(engine.db, 'queued')).toEqual([4]);
  expect(runner.tasks[0]).toMatchObject({ epic: 1, stage: 'review', resumeSession: 's-e1', context: { verifyStateFirst: true, round: 2 } });
  expect(runner.tasks.map((t) => t.epic)).toEqual([1, 2]);
  expect(rows(engine.db).every((e) => e.removedFrom === null && e.removedReason === null)).toBe(true);
  expect(eventTypes(engine.db).filter((t) => t === 'repo_restored')).toHaveLength(4);
  expect(labelsOf(3)).toEqual(['solve:epic:needs-human']);
});

test('purges expired logs and sessions when the engine starts and every 24 hours after', async () => {
  const db = open();
  const old = db.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'merged', finishedAt: -30 * 24 * 60 * MIN }).returning().get();
  db.insert(executions).values({ executionId: 'x-old', epicId: old.id, stage: 'ship', sessionId: 's-old', resultPath: 'r', startedAt: 0 }).run();
  const logs = join(dir, 'orchestrator', 'logs', 'executions', 'x-old');
  mkdirSync(logs, { recursive: true });
  const engine = createEngine({ db, github, clock, repos, pollIntervalMs: 5 * MIN, maxConcurrentEpics: 0, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, runner, workspaces, root: dir });
  await engine.start();
  expect(existsSync(logs)).toBe(false);
  mkdirSync(logs, { recursive: true });
  await clock.advance(24 * 60 * MIN);
  expect(existsSync(logs)).toBe(false);
  engine.stop();
});

// --- Forge authentication errors ---

test('an auth_failed stops only the running epics of that profile and their runs; other profiles go on and nothing is relaunched', async () => {
  const other = { author: { ...agents.author, profile: 'c' }, reviewer: { ...agents.reviewer, profile: 'd' } };
  const config = [{ name: 'AshuLab/a', agents }, { name: 'AshuLab/b', agents: other }];
  github.ready = { 'AshuLab/a': ready(1, 2), 'AshuLab/b': ready(3) };
  let release!: () => void;
  const bothRunning = new Promise<void>((resolve) => (release = resolve));
  runner.behavior = (task) => (task.epic === 1 ? { sessionId: 's-1', exit: 'auth_failed', when: bothRunning } : { exit: 'hang' });
  const engine = await start(3, config);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));
  release();
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1, 2]));

  const [first, second, third] = rows(engine.db);
  expect(first).toMatchObject({ issue: 1, status: 'needs_human', needsHumanKind: 'auth', needsHumanReason: 'authentication error for profile a', finishedAt: 5 * MIN, labelPending: false });
  expect(second).toMatchObject({ issue: 2, status: 'needs_human', needsHumanReason: 'authentication error for profile a' });
  expect(third).toMatchObject({ issue: 3, status: 'running' });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  expect(labelsOf(2)).toEqual(['solve:epic:needs-human']);
  expect(labelsOf(3, 'AshuLab/b')).toEqual(['solve:epic:running']);
  // The run of epic 2 was stopped, the one of epic 3 was not.
  const taskOf = (epic: number) => runner.tasks.find((t) => t.epic === epic)!;
  expect(runner.stopped).toEqual([taskOf(2).executionId]);
  expect(executionsOf(engine.db).map((e) => [e.epicId, e.status])).toEqual([[1, 'failed'], [2, 'interrupted'], [3, 'running']]);
  // Never retried, nor relaunched under another profile.
  await clock.advance(10 * MIN);
  expect(runner.tasks.map((t) => [t.epic, t.profile])).toEqual([[1, 'a'], [2, 'a'], [3, 'c']]);
});

test('an auth_failed of the reviewer profile stops the epic in review', async () => {
  const engine = await reviewing(() => ({ exit: 'auth_failed' }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'authentication error for profile b' });
  expect(runner.tasks.map((t) => t.profile)).toEqual(['a', 'b']);
});

test('an AuthError of the orchestrator profile suspends every GitHub operation, keeps queue and state, and the next cycle that works resumes them', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const error = new AuthError('a');
  // Epic 1 ends technically with a result written while the profile fails: label and PR check must wait.
  pull(50);
  runner.behavior = (task) => {
    github.authError = error;
    return { sessionId: 's', write: completed(task) };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(engine.error).toBe(error);
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'finished' });
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, status: 'running', stage: 'ship', prNumber: null });
  expect(ids(engine)).toEqual(['AshuLab/a#2']);

  // From now on only the poll's probe reaches the port, one call per cycle, and nothing else changes.
  const attempts = github.attempts;
  for (let i = 1; i <= 3; i++) {
    await clock.advance(5 * MIN);
    await engine.idle();
    expect(github.attempts).toBe(attempts + i);
    expect(engine.error).toBe(error);
  }
  expect(ids(engine)).toEqual(['AshuLab/a#2']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
  expect(runner.tasks).toHaveLength(1);

  github.authError = null;
  runner.behavior = () => ({ exit: 'hang' });
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(engine.error).toBeNull();
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, status: 'running', stage: 'review', prNumber: 50 });
  expect(runner.tasks.map((t) => [t.epic, t.stage, t.profile])).toEqual([[1, 'ship', 'a'], [1, 'review', 'b']]);
});

test('a label change that cannot reach GitHub because the orchestrator profile fails waits and is applied once it works', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => {
    github.authError = new AuthError('a');
    return { exit: 'timed_out' };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', labelPending: true });
  expect(labelsOf(1)).toEqual(['solve:epic:running']);

  const attempts = github.attempts;
  await clock.advance(5 * MIN);
  expect(github.attempts).toBe(attempts + 1);
  expect(labelsOf(1)).toEqual(['solve:epic:running']);

  github.authError = null;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', labelPending: false });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
});

test('pollNow polls at once and the interval counts from then; a poll that is already running is not doubled', async () => {
  const engine = await start();
  await clock.advance(2 * MIN);
  const calls = github.calls;
  await Promise.all([engine.pollNow(), engine.pollNow()]);
  expect(github.calls).toBeGreaterThan(calls); // it polled now, not in 3 minutes
  const after = github.calls;
  await clock.advance(5 * MIN - 1);
  expect(github.calls).toBe(after); // the timer was re-armed from the manual poll
  await clock.advance(1);
  expect(github.calls).toBeGreaterThan(after);
});

test('paused: new epics are queued but not reserved, running ones go on, and resuming starts them at once', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2), 'AshuLab/b': [] };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([1]);
  await engine.setPaused(true);
  expect(engine.paused).toBe(true);
  github.ready = { 'AshuLab/a': ready(1, 2, 3), 'AshuLab/b': [] };
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([1]); // the one that was running still is
  expect(byStatus(engine.db, 'queued')).toEqual([2, 3]); // queued, not started, even with GitHub polled
  await engine.setPaused(false);
  expect(engine.paused).toBe(false);
});

// --- slices: a cache of GitHub (ADR 0008) ---

const slice = (number: number, extra: Partial<EpicSlice> = {}): EpicSlice => ({ number, title: `Slice ${number}`, state: 'ready', blockedBy: [], assignee: null, prNumber: null, prState: null, prMergedAt: null, closedAt: null, ...extra });
const cached = (db: Db) => db.select().from(epicSlices).all().map((r) => `${r.epicId}:${r.number}:${r.state}@${r.readAt}`);

// Epic 1 running (its author is cut, so it stays so), epic 2 queued behind it.
async function runningWithSlices() {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  github.slices = { 'AshuLab/a#1': { slices: [slice(10, { state: 'closed', closedAt: 1000 }), slice(11, { state: 'waiting', blockedBy: [12] })] }, 'AshuLab/a#2': { slices: [slice(20)] } };
  runner.behavior = () => ({ exit: 'stopped' });
  const engine = await start(1);
  await clock.advance(5 * MIN); // registers and reserves epic 1, reading its slices as it starts
  return engine;
}

test('an epic that starts has its slices cached at once, before the next poll', async () => {
  const engine = await runningWithSlices();
  expect(github.sliceReads).toEqual(['AshuLab/a#1']); // epic 2 is still queued: no read
  expect(cached(engine.db)).toEqual([`1:10:closed@${5 * MIN}`, `1:11:waiting@${5 * MIN}`]);
});

test('the poll caches the slices of live epics, replacing them, and a finished epic keeps its last list', async () => {
  const engine = await runningWithSlices();
  await clock.advance(5 * MIN);
  expect(github.sliceReads).toEqual(['AshuLab/a#1', 'AshuLab/a#1']);
  expect(cached(engine.db)).toEqual([`1:10:closed@${10 * MIN}`, `1:11:waiting@${10 * MIN}`]);

  github.slices['AshuLab/a#1'] = { slices: [slice(11, { state: 'in_progress' })] };
  await clock.advance(5 * MIN);
  expect(cached(engine.db)).toEqual([`1:11:in_progress@${15 * MIN}`]);

  engine.db.update(epics).set({ status: 'ready_for_test' }).where(eq(epics.issue, 1)).run();
  github.slices['AshuLab/a#1'] = { slices: [slice(11, { state: 'closed', closedAt: 2000 })] };
  await clock.advance(5 * MIN);
  expect(cached(engine.db)).toEqual([`1:11:closed@${20 * MIN}`, `2:20:ready@${20 * MIN}`]); // parked is still live; epic 2 took the free slot and was read as it started

  engine.db.update(epics).set({ status: 'merged' }).where(eq(epics.issue, 1)).run();
  github.slices['AshuLab/a#1'] = { slices: [] };
  await clock.advance(5 * MIN);
  expect(cached(engine.db).filter((r) => r.startsWith('1:'))).toEqual([`1:11:closed@${20 * MIN}`]);
});

test('a finished epic with no cached slices, e.g. it ended before the cache existed, is read once', async () => {
  const engine = await runningWithSlices();
  engine.db.delete(epicSlices).run();
  engine.db.update(epics).set({ status: 'merged' }).where(eq(epics.issue, 1)).run();
  await clock.advance(5 * MIN);
  expect(cached(engine.db).filter((r) => r.startsWith('1:'))).toEqual([`1:10:closed@${10 * MIN}`, `1:11:waiting@${10 * MIN}`]);

  github.slices['AshuLab/a#1'] = { slices: [slice(99)] };
  await clock.advance(5 * MIN);
  expect(cached(engine.db).filter((r) => r.startsWith('1:'))).toEqual([`1:10:closed@${10 * MIN}`, `1:11:waiting@${10 * MIN}`]);
});

test('a failing slices read keeps the previous rows and the poll goes on', async () => {
  const engine = await runningWithSlices();
  await clock.advance(5 * MIN);
  const before = cached(engine.db);
  expect(before).toHaveLength(2);

  github.slicesUnavailable = new GitHubUnavailable();
  github.slices['AshuLab/a#1'] = { slices: [slice(99)] };
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  await clock.advance(5 * MIN);
  expect(cached(engine.db)).toEqual(before);
  expect(engine.error).toBeNull();
  expect(ids(engine)).toContain('AshuLab/a#3');

  github.slicesUnavailable = null;
  await clock.advance(5 * MIN);
  expect(cached(engine.db)).toEqual([`1:99:ready@${20 * MIN}`]);
});

test('the engine decides the same with the table empty: an epic goes through ship and review to ready for test', async () => {
  const engine = await reviewing((task) => ({
    write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'ok' } }),
  }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA });
  expect(cached(engine.db)).toEqual([]);
});

// --- the pull request block: a cache of GitHub ---

const block = (extra: Partial<PullRequestBlock> = {}): PullRequestBlock => ({ number: 50, url: 'https://github.com/AshuLab/a/pull/50', draft: false, mergeState: 'CLEAN', reviewDecision: null, checks: { passing: 3, failing: 0, pending: 0 }, ...extra });
const cachedPr = (db: Db, issue: number) => db.select({ pr: epics.pr }).from(epics).where(eq(epics.issue, issue)).get()?.pr;

test('the poll reads the pull request of an epic that has one and makes no query for one that has none', async () => {
  const engine = await runningWithSlices();
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toEqual([]);
  expect(cachedPr(engine.db, 1)).toBeNull();

  engine.db.update(epics).set({ prNumber: 50 }).where(eq(epics.issue, 1)).run();
  github.pullRequestBlocks['AshuLab/a#50'] = block();
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toEqual(['AshuLab/a#50']); // epic 2 is queued with no PR: no query
  expect(cachedPr(engine.db, 1)).toEqual(block());
  expect(cachedPr(engine.db, 2)).toBeNull();
});

test('a failing pull request read keeps the last block and the poll goes on', async () => {
  const engine = await runningWithSlices();
  engine.db.update(epics).set({ prNumber: 50 }).where(eq(epics.issue, 1)).run();
  github.pullRequestBlocks['AshuLab/a#50'] = block();
  await clock.advance(5 * MIN);

  github.pullRequestUnavailable = new GitHubUnavailable();
  github.pullRequestBlocks['AshuLab/a#50'] = block({ draft: true });
  await clock.advance(5 * MIN);
  expect(cachedPr(engine.db, 1)).toEqual(block());
  expect(engine.error).toBeNull();

  github.pullRequestUnavailable = null;
  await clock.advance(5 * MIN);
  expect(cachedPr(engine.db, 1)).toEqual(block({ draft: true }));
});

test('a finished epic with a pull request and no cached block is read once; one that has a block is never read', async () => {
  const engine = await runningWithSlices();
  engine.db.update(epics).set({ status: 'merged', prNumber: 50 }).where(eq(epics.issue, 1)).run();
  github.pullRequestBlocks['AshuLab/a#50'] = block();
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toEqual(['AshuLab/a#50']);
  expect(cachedPr(engine.db, 1)).toEqual(block());

  github.pullRequestBlocks['AshuLab/a#50'] = block({ draft: true });
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toEqual(['AshuLab/a#50']);
  expect(cachedPr(engine.db, 1)).toEqual(block());
});

// --- the review threads of the pull request: read with the block, a cache of GitHub ---

const thread = (id: string, extra: Partial<ReviewThread> = {}): ReviewThread => ({ id, path: 'src/a.ts', line: 3, resolved: false, outdated: false, author: 'someone', bot: false, firstLine: `Thread ${id}`, commentCount: 1, url: `https://github.com/AshuLab/a/pull/50#discussion_${id}`, ...extra });
const storedThreads = (db: Db, issue: number) =>
  db.select({ id: epicReviewThreads.id, firstLine: epicReviewThreads.firstLine, readAt: epicReviewThreads.readAt, truncated: epicReviewThreads.truncated })
    .from(epicReviewThreads).innerJoin(epics, eq(epics.id, epicReviewThreads.epicId)).where(eq(epics.issue, issue)).orderBy(epicReviewThreads.position).all()
    .map((r) => `${r.id}:${r.firstLine}@${r.readAt}${r.truncated ? ':truncated' : ''}`);

test('the poll stores the threads in GitHub order with the block, replaces them on each read and flags more than the limit', async () => {
  const engine = await runningWithSlices();
  engine.db.update(epics).set({ prNumber: 50 }).where(eq(epics.issue, 1)).run();
  github.pullRequestBlocks['AshuLab/a#50'] = block();
  github.reviewThreads['AshuLab/a#50'] = { threads: [thread('b'), thread('a', { line: null, outdated: true, author: null })] };
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toEqual(['AshuLab/a#50']); // one read for the block and the threads
  expect(storedThreads(engine.db, 1)).toEqual([`b:Thread b@${10 * MIN}`, `a:Thread a@${10 * MIN}`]);
  expect(engine.db.select().from(epicReviewThreads).where(eq(epicReviewThreads.id, 'a')).get()).toMatchObject({ line: null, outdated: true, author: null, bot: false, commentCount: 1 });
  expect(storedThreads(engine.db, 2)).toEqual([]);

  github.reviewThreads['AshuLab/a#50'] = { threads: [thread('c', { resolved: true })], truncated: true };
  await clock.advance(5 * MIN);
  expect(storedThreads(engine.db, 1)).toEqual([`c:Thread c@${15 * MIN}:truncated`]);

  github.reviewThreads['AshuLab/a#50'] = { threads: [] };
  await clock.advance(5 * MIN);
  expect(storedThreads(engine.db, 1)).toEqual([]);
});

test('a failing read keeps the previous threads; a pull request GitHub does not know leaves them as they were', async () => {
  const engine = await runningWithSlices();
  engine.db.update(epics).set({ prNumber: 50 }).where(eq(epics.issue, 1)).run();
  github.pullRequestBlocks['AshuLab/a#50'] = block();
  github.reviewThreads['AshuLab/a#50'] = { threads: [thread('a')] };
  await clock.advance(5 * MIN);
  const before = storedThreads(engine.db, 1);
  expect(before).toHaveLength(1);

  github.pullRequestUnavailable = new GitHubUnavailable();
  github.reviewThreads['AshuLab/a#50'] = { threads: [thread('b')] };
  await clock.advance(5 * MIN);
  expect(storedThreads(engine.db, 1)).toEqual(before);
  expect(engine.error).toBeNull();

  github.pullRequestUnavailable = null;
  delete github.pullRequestBlocks['AshuLab/a#50'];
  await clock.advance(5 * MIN);
  expect(storedThreads(engine.db, 1)).toEqual(before);
  expect(cachedPr(engine.db, 1)).toEqual(block());

  github.pullRequestBlocks['AshuLab/a#50'] = block();
  await clock.advance(5 * MIN);
  expect(storedThreads(engine.db, 1)).toEqual([`b:Thread b@${25 * MIN}`]);
});

test('a finished epic with a pull request and no cached block gets its threads from one read; one that has a block is not read again', async () => {
  const engine = await runningWithSlices();
  engine.db.update(epics).set({ status: 'merged', prNumber: 50 }).where(eq(epics.issue, 1)).run();
  github.pullRequestBlocks['AshuLab/a#50'] = block();
  github.reviewThreads['AshuLab/a#50'] = { threads: [thread('a')] };
  await clock.advance(5 * MIN);
  expect(storedThreads(engine.db, 1)).toEqual([`a:Thread a@${10 * MIN}`]);

  github.reviewThreads['AshuLab/a#50'] = { threads: [thread('b')] };
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toEqual(['AshuLab/a#50']);
  expect(storedThreads(engine.db, 1)).toEqual([`a:Thread a@${10 * MIN}`]);
});

// An epic that stopped in needs_human; the next ship hangs, so a restart is seen while it runs.
async function stoppedEpic() {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'the CI is red' }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
  runner.behavior = () => ({ exit: 'hang' });
  return engine;
}
const flush = () => new Promise<void>((resolve) => setImmediate(resolve));
const refusal = (promise: Promise<void>) => promise.then(() => null, (e: ResumeRefused) => e.reason);

test('resumeEpic puts ready on a needs_human epic, checks, and answers only once it runs again from ship', async () => {
  const engine = await stoppedEpic();
  const settled = vi.fn();
  const resumed = engine.resumeEpic('AshuLab/a', 1).then(settled);
  await flush();
  expect(settled).not.toHaveBeenCalled(); // the poll started, the answer waits for its tick
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', needsHumanReason: null });
  await clock.advance(1000);
  await resumed;
  expect(settled).toHaveBeenCalled();
  expect(runner.tasks.filter((t) => t.stage === 'ship')).toHaveLength(2);
  expect(labelsOf(1)).toEqual(['solve:epic:running']); // ready came off with the restart, put there by the engine first
});

test('resumeEpic on an epic the engine does not know is refused as unknown epic', async () => {
  const engine = await start(1);
  expect(await refusal(engine.resumeEpic('AshuLab/a', 9))).toBe('unknown epic');
  expect(github.issues).toEqual({});
});

test.each(['queued', 'running', 'ready_for_test', 'merged', 'cancelled'] as const)('resumeEpic on an epic that is %s is refused as not stopped and touches nothing', async (status) => {
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(0);
  await clock.advance(5 * MIN);
  engine.db.update(epics).set({ status }).run();
  const before = github.issue('AshuLab/a', 1).labels.slice();
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1))).toBe('not stopped');
  expect(labelsOf(1)).toEqual(before);
});

test('resumeEpic with GitHub failing is refused as github unavailable and the epic stays stopped', async () => {
  const engine = await stoppedEpic();
  github.setLabelsUnavailable = new GitHubUnavailable();
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1))).toBe('github unavailable');
  github.setLabelsUnavailable = null;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'the CI is red' });
  expect(labelsOf(1)).toEqual(['solve:epic:needs-human']);
  github.authError = new AuthError('orchestrator');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1))).toBe('github unavailable');
});

test('resumeEpic on an epic that has not restarted thirty seconds after the label answers did not restart and leaves the label on', async () => {
  const engine = await stoppedEpic();
  github.unavailable = new GitHubUnavailable(); // the label goes on, the check cannot read
  const resumed = refusal(engine.resumeEpic('AshuLab/a', 1));
  await flush();
  await clock.advance(29_000);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
  let answered = false;
  void resumed.then(() => (answered = true));
  await flush();
  expect(answered).toBe(false);
  await clock.advance(1000);
  expect(await resumed).toBe('did not restart');
  expect(labelsOf(1)).toContain('solve:epic:ready');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });

  // the next check takes it
  github.unavailable = null;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
});

test('resumeEpic while a check is already running does not start a second one and answers when that one restarts the epic', async () => {
  const engine = await stoppedEpic();
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => (release = resolve));
  const listing = github.listReadyEpics.bind(github);
  let listed = 0;
  github.listReadyEpics = async (repo) => {
    listed++;
    await gate;
    return listing(repo);
  };
  void engine.pollNow(); // the timer's poll, held on its first read
  await flush();
  github.issue('AshuLab/a', 1).labels = []; // as if the label had not been there yet
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  release();
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(listed).toBe(2); // one per repo of the single poll that ran
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
});
