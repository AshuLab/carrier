import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { loadProviders } from '../config/providers.ts';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { defaultSkills, resolveReviewSkills, resolveSkills, savedSkills, solveSkills } from '../config/skills.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { eq } from 'drizzle-orm';
import { epics } from '../storage/schema.ts';
import type { QuotaSnapshot } from '../usage/types.ts';
import { createEngine, type EngineSettings } from './engine.ts';
import { ReloadRefused } from './reload-refused.ts';
import type { ResumeRefused } from './resume-refused.ts';
import { reserve } from './reserve.ts';
import { FakeAgentRunner, FakeWorkspaces, type Behavior } from '../execution/fake.ts';
import type { AgentFailure, AgentTask } from '../execution/agent-runner.ts';
import { epicOf } from '../control/epic.ts';
import { eventsOf as eventsReplyOf, lastEventOf } from '../control/events.ts';
import { buildSnapshot } from '../status/snapshot.ts';
import { epicEvents, executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { failureStreak } from './retry.ts';
import { callerResults } from '../storage/caller-results.ts';
import { latestBlockers } from './blockers.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { FakeClock, FakeGitHub, FakeQuota } from './fake.ts';
import { AuthError, GitHubRejected, GitHubUnavailable, type EpicSlice, type PullRequestBlock, type ReviewThread } from './github.ts';
import { epicReviewThreads } from '../storage/epic-review-threads.ts';
import { epicSlices } from '../storage/epic-slices.ts';
import { enginePlacesOf } from '../config/places.ts';
import { defaultLabels } from './github.ts';
import { FakeSkills } from '../harnesses/fake-skills.ts';

const MIN = 60_000;
const agents = {
  author: { profile: 'a', option: 'o', harness: 'claude' as const, model: 'm' },
  reviewer: { profile: 'b', option: 'o', harness: 'codex' as const, model: 'm' },
};
const repos: EffectiveRepoConfig[] = ['AshuLab/a', 'AshuLab/b'].map((name) => ({ name, agents }));

let dir: string;
let dbs: Db[];
let github: FakeGitHub;
let clock: FakeClock;
let runner: FakeAgentRunner;
let fakeQuota: FakeQuota;
let workspaces: FakeWorkspaces;
let skills: FakeSkills;
let settings: EngineSettings; // what the engine reads: a test changes it the way a reload does
let watched: EffectiveRepoConfig[]; // the repos the engine reads, changed the same way
let declaredProfile: (name: string) => boolean; // whether the configuration declares a profile, changed the same way
beforeEach(() => {
  runner = new FakeAgentRunner();
  fakeQuota = new FakeQuota();
  workspaces = new FakeWorkspaces();
  skills = new FakeSkills();
  dir = mkdtempSync(join(tmpdir(), 'carrier-'));
  dbs = [];
  github = new FakeGitHub();
  github.readyLabel = () => settings.labels.ready; // an entry of `ready` is listed while its issue carries the ready label the engine runs with
  workspaces.reviewerCommit = (repo, pr) => github.pulls[`${repo}#${pr}`]?.headSha ?? SHA; // a checkout is at the PR's head as GitHub has it when it is made
  clock = new FakeClock();
  declaredProfile = () => true;
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
  settings = { pollIntervalMs: 5 * MIN, labels: defaultLabels, maxConcurrentEpics, maxExecutionHours, maxExecutionRetries, maxReviews, maxLeadRounds: 3, autoResume: false, autoResumeMaxHours: 12 };
  watched = config;
  const engine = createEngine({ db, github, clock, repos: () => watched, settings: () => settings, profileDeclared: (name) => declaredProfile(name), runner, workspaces, quota: fakeQuota.read, places: enginePlacesOf(dir), skills });
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
  github.issue('AshuLab/a', 1).labels = ['solve:epic', 'carrier:status:running'];
  await clock.advance(5 * MIN);
  expect(rows(engine.db)).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ title: 'Renamed again', labels: ['solve:epic', 'carrier:status:running'] });
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

test('every poll refreshes the slice progress by repo and issue; a failed listing skips the repo and keeps the last values', async () => {
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

  github.openEpicsUnavailable = new GitHubUnavailable('network', 'down');
  github.openEpics['AshuLab/a'] = [{ issue: 1, slices: { done: 3, total: 3 } }];
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 5, title: '' }] };
  await clock.advance(5 * MIN);
  expect(engine.slices('AshuLab/a', 1)).toEqual({ done: 2, total: 3 }); // the stale value stays
  expect(engine.error).toBeNull();
  expect(engine.lastCheck('AshuLab/a')).toMatchObject({ ok: false });
  expect(ids(engine)).toEqual(['AshuLab/a#1']); // the repo is skipped for the cycle: nothing new is queued from it

  github.openEpicsUnavailable = null;
  await clock.advance(5 * MIN);
  expect(engine.slices('AshuLab/a', 1)).toEqual({ done: 3, total: 3 });
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/a#5']);
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
  github.unavailable = new GitHubUnavailable('server_error', 'HTTP 503', 12 * MIN);
  const calls = github.calls;
  await clock.advance(5 * MIN);
  expect(engine.error).toBeNull(); // every repo was skipped with its reason: the poll itself did not fail
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 10 * MIN, ok: false, error: github.unavailable.message });
  expect(ids(engine)).toEqual(['AshuLab/a#1']);
  expect(engine.queue()[0]?.status).toBe('queued');

  await clock.advance(12 * MIN - 1);
  expect(github.calls).toBe(calls + 2); // each cycle reads both repos, and both fail
  github.unavailable = new GitHubUnavailable('network', 'down'); // no retryAfter: falls back to the interval
  await clock.advance(1);
  expect(github.calls).toBe(calls + 4);

  await clock.advance(5 * MIN);
  expect(github.calls).toBe(calls + 6);

  github.unavailable = null;
  await clock.advance(5 * MIN);
  expect(engine.error).toBeNull();
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/b#2']);
});

const unavailable = (kind: 'server_error' | 'network' | 'timeout' | 'rate_limited', retryAfterMs?: number) => new GitHubUnavailable(kind, kind === 'server_error' ? 'HTTP 502' : 'down', retryAfterMs);
const failingRepo = (repo: string, failure: GitHubUnavailable) => {
  const listed = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (name, label) => {
    if (name === repo) throw failure;
    return listed(name, label);
  };
};

test.each(['timeout', 'server_error', 'network'] as const)('a repo whose read fails with %s is skipped with its reason; the other repo is read, queued and launched', async (kind) => {
  github.ready = { 'AshuLab/a': ready(1), 'AshuLab/b': ready(2) };
  const failure = unavailable(kind);
  failingRepo('AshuLab/b', failure);
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.repo)).toEqual(['AshuLab/a']));
  expect(rows(engine.db).map((e) => e.repo)).toEqual(['AshuLab/a']); // nothing of the skipped repo was queued
  expect(engine.error).toBeNull();
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 5 * MIN, ok: false, error: failure.message });
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });
});

test('a skipped repo is left out of the reserve for that cycle and read again at the next one', async () => {
  const db = open();
  seedEpic(db, 1, { repo: 'AshuLab/b', status: 'queued', stage: null, startedAt: null, config: null });
  github.ready = { 'AshuLab/a': ready(2), 'AshuLab/b': ready(1) };
  failingRepo('AshuLab/b', unavailable('network'));
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.repo)).toEqual(['AshuLab/a'])); // b's epic is older, and still waits
  expect(engine.queue().filter((e) => e.status === 'queued').map((e) => `${e.repo}#${e.issue}`)).toEqual(['AshuLab/b#1']);

  github.listOpenEpics = FakeGitHub.prototype.listOpenEpics.bind(github);
  const calls = github.calls;
  await clock.advance(5 * MIN);
  expect(github.calls).toBe(calls + 2); // both repos read again
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 10 * MIN, ok: true, error: null });
});

test('the longest wait GitHub asked for among the repos that failed is the wait before the next cycle', async () => {
  failingRepo('AshuLab/a', unavailable('server_error', 7 * MIN));
  const listed = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    if (repo === 'AshuLab/b') throw unavailable('server_error', 12 * MIN);
    return listed(repo, label);
  };
  const engine = await start();
  await clock.advance(5 * MIN);
  expect(engine.nextPollAt).toBe(5 * MIN + 12 * MIN);
});

// A rate limit is the account's: whichever read gets it, the poll ends, the repos after it are not read and Carrier waits what GitHub asked for.
test.each([
  ['the listing', () => failingRepo('AshuLab/a', unavailable('rate_limited', 9 * MIN))],
  ['the progress read', () => { github.openEpicsUnavailable = unavailable('rate_limited', 9 * MIN); }],
  ['the slices read', () => { github.slicesUnavailable = unavailable('rate_limited', 9 * MIN); }],
  ['the pull request read', () => { github.pullRequestUnavailable = unavailable('rate_limited', 9 * MIN); }],
])('a rate limit in %s ends the poll and makes the engine wait what GitHub asked for', async (_name, limit) => {
  seedEpic(open(), 1, { status: 'ready_for_test', prNumber: 50 });
  github.ready = { 'AshuLab/b': ready(2) };
  const engine = await start();
  limit();
  await clock.advance(5 * MIN);
  expect(engine.error).toBeInstanceOf(GitHubUnavailable);
  expect((engine.error as GitHubUnavailable).kind).toBe('rate_limited');
  expect(engine.nextPollAt).toBe(5 * MIN + 9 * MIN);
  expect(engine.queue().map((e) => e.repo)).toEqual([]); // nothing queued: the second repo was not read
  expect(engine.lastCheck('AshuLab/b')).toMatchObject({ ok: false });
});

test('each repo keeps its last check: when, whether it worked and why not, from a failure to its recovery', async () => {
  const engine = await start();
  expect(engine.lastCheck('AshuLab/a')).toBeUndefined();

  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 5 * MIN, ok: true, error: null });

  // b fails: a was read in that cycle, b was not.
  github.listOpenEpics = async (repo, label) => {
    if (repo === 'AshuLab/b') throw new GitHubUnavailable('server_error', 'HTTP 502');
    return [];
  };
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 10 * MIN, ok: true, error: null });
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 10 * MIN, ok: false, error: 'GitHub unavailable (server_error: HTTP 502)' });

  github.listOpenEpics = FakeGitHub.prototype.listOpenEpics.bind(github);
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
  const opts = { now: 7, repos, choiceMs: 60_000 };

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
  expect(labelsOf(4)).toEqual(['bug', 'carrier:status:running']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: false });
});

test('with another ready label only the issues that carry it are queued, and the default one queues nothing', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  github.issue('AshuLab/a', 1).labels = ['carrier:go', 'bug'];
  github.issue('AshuLab/a', 2).labels = ['solve:epic:ready'];
  const engine = await start();
  settings.labels = { ...defaultLabels, ready: 'carrier:go' };
  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#1']);
});

test('with another ready label, reserving takes that label off and puts running on, and a lost one cancels the epic', async () => {
  github.ready = { 'AshuLab/a': ready(4, 5) };
  github.issue('AshuLab/a', 4).labels = ['carrier:go', 'bug'];
  github.issue('AshuLab/a', 5).labels = ['carrier:go'];
  const list = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    const listed = await list(repo, label);
    github.issue('AshuLab/a', 5).labels = ['solve:epic:ready']; // the custom label goes after the listing, before the slot is reserved
    return listed;
  };
  const engine = await start(2);
  settings.labels = { ...defaultLabels, ready: 'carrier:go' };
  await clock.advance(5 * MIN);
  expect(labelsOf(4)).toEqual(['bug', 'carrier:status:running']);
  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason])).toEqual([[4, 'running', null], [5, 'cancelled', 'ready label removed']]);
});

test('with the status labels renamed, the repo gets the new names and the epic shows the running one', async () => {
  github.ready = { 'AshuLab/a': ready(4, 5) };
  github.issue('AshuLab/a', 4).labels = ['carrier:go'];
  github.issue('AshuLab/a', 5).labels = ['carrier:go'];
  await start(1);
  settings.labels = { ...defaultLabels, ready: 'carrier:go', running: 'carrier:busy', readyForTest: 'carrier:test', needsHuman: 'carrier:stuck' };
  await clock.advance(5 * MIN);
  expect(labelsOf(4)).toEqual(['carrier:busy']);
  expect(github.repoLabels['AshuLab/a']).toEqual(['carrier:busy', 'carrier:test', 'carrier:stuck']);
});

test('GitHubUnavailable on the label change keeps the epic reserved and the next cycle reconciles it once', async () => {
  github.ready = { 'AshuLab/a': ready(4) };
  github.setLabelsUnavailable = new GitHubUnavailable('network', 'down');
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: true });
  expect(labelsOf(4)).toEqual(['solve:epic:ready']);
  expect(engine.error).toBe(github.setLabelsUnavailable);

  github.setLabelsUnavailable = null;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: false });
  expect(labelsOf(4)).toEqual(['carrier:status:running']);
  await clock.advance(5 * MIN);
  expect(labelsOf(4)).toEqual(['carrier:status:running']);
});

test('a closed issue is cancelled, a lost ready too, and the slot goes to the next epic', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  github.issue('AshuLab/a', 1).state = 'closed';
  const list = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    const listed = await list(repo, label);
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
    throw new GitHubUnavailable('network', 'down');
  };
  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/a#2']);
  expect(rows(engine.db)[0]).toMatchObject({ startedAt: null, config: null });
});

test('epics that enter the queue in the same millisecond never tie, and keep the order they were listed in', async () => {
  github.ready = { 'AshuLab/a': ready(5, 3), 'AshuLab/b': ready(4) };
  const engine = await start();
  await clock.advance(5 * MIN);
  expect(engine.queue().map((e) => [e.issue, e.queuedAt])).toEqual([[5, 5 * MIN], [3, 5 * MIN + 1], [4, 5 * MIN + 2]]);
});

test('the reserve takes the epic that entered the queue first, then the lowest id', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'queued', queuedAt: 7, stage: null, startedAt: null, config: null });
  seedEpic(db, 2, { status: 'queued', queuedAt: 3, stage: null, startedAt: null, config: null });
  seedEpic(db, 3, { status: 'queued', queuedAt: 3, stage: null, startedAt: null, config: null });
  const picked = [reserve(db, { maxConcurrent: 3, now: 10, repos })?.issue, reserve(db, { maxConcurrent: 3, now: 10, repos })?.issue, reserve(db, { maxConcurrent: 3, now: 10, repos })?.issue];
  expect(picked).toEqual([2, 3, 1]);
});

test('an epic resumed while others wait goes to the end of the line, and the queue the app reads has the same order', async () => {
  const engine = await start();
  seedEpic(engine.db, 9, { status: 'needs_human', needsHumanKind: 'retries_exhausted', needsHumanReason: 'x' }); // id 1: the lowest
  github.ready = { 'AshuLab/a': ready(1, 2) };
  await clock.advance(5 * MIN);
  github.ready = { 'AshuLab/a': ready(1, 2, 9) }; // the person's resume put `ready` back
  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/a#2', 'AshuLab/a#9']);
  const snapshot = buildSnapshot(engine.db, { now: clock.now(), maxConcurrentEpics: 1, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, slices: engine.slices, version: 'x', pollIntervalMs: 1, labels: defaultLabels });
  expect(snapshot.queue.map((q) => q.issue)).toEqual([1, 2, 9]);

  settings.maxConcurrentEpics = 1; // scarce slots: the epic that waited longest starts
  runner.behavior = () => ({ exit: 'hang' });
  await clock.advance(5 * MIN);
  expect(rows(engine.db).filter((e) => e.status === 'running').map((e) => e.issue)).toEqual([1]);
});

test('an epic resumed with a slot free starts at once', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 9, { status: 'needs_human', needsHumanKind: 'retries_exhausted', needsHumanReason: 'x' });
  github.ready = { 'AshuLab/a': ready(9) };
  runner.behavior = () => ({ exit: 'hang' });
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
});

test.each([
  ['ready removed', 'ready_removed', 'ready label removed'],
  ['issue closed', 'issue_closed', 'closed before it started'],
] as const)('an epic cancelled before it started (%s) goes back to the queue when ready comes back, with nothing of the cancel left', async (_, kind, reason) => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const list = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    const listed = await list(repo, label);
    if (kind === 'ready_removed') github.issue('AshuLab/a', 2).labels = [];
    else github.issue('AshuLab/a', 2).state = 'closed'; // the issue closes after the listing, before the slot is reserved
    return listed;
  };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(2);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[1]).toMatchObject({ status: 'cancelled', cancelKind: kind, cancelReason: reason });
  expect(rows(engine.db)[1]?.cleanedAt).not.toBeNull();

  github.listOpenEpics = list;
  github.issue('AshuLab/a', 2).labels = [defaultLabels.ready];
  github.issue('AshuLab/a', 2).state = 'open';
  settings.maxConcurrentEpics = 1; // the first epic holds the only slot: the requeued one waits
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[1]).toMatchObject({ status: 'queued', queuedAt: 10 * MIN, cancelKind: null, cancelReason: null, cleanedAt: null, finishedAt: null, resumeAt: null });
  expect(eventsOf(engine.db).filter((e) => e.type === 'requeued')).toMatchObject([{ epicId: 2, at: 10 * MIN, data: { kind, reason } }]);
});

test.each([
  ['its pull request was closed', { cancelKind: 'pr_closed' as const }, false],
  ['its issue no longer exists', { cancelKind: 'issue_gone' as const }, false],
  ['it was cancelled before kinds were kept', { cancelKind: null }, false],
  ['it already had an execution', { cancelKind: 'ready_removed' as const }, true],
])('an epic stays cancelled when ready comes back if %s', async (_, extra, ran) => {
  const db = open();
  seedEpic(db, 1, { status: 'cancelled', cancelReason: 'why', finishedAt: MIN, cleanedAt: MIN, stage: null, ...extra });
  if (ran) seedExecution(db, 'x1', 1, { status: 'finished' });
  db.$client.close();
  dbs.pop();
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelReason: 'why', finishedAt: MIN, cleanedAt: MIN });
  expect(eventsOf(engine.db)).toEqual([]);
});

test('the open epics are listed by the epic label the config names', async () => {
  github.openEpics = { 'AshuLab/a': [{ issue: 1, slices: null }] };
  await start();
  settings.labels = { ...defaultLabels, epic: 'carrier:epic' };
  await clock.advance(5 * MIN);
  expect(github.openEpicsAsked.length).toBeGreaterThan(0);
  expect(new Set(github.openEpicsAsked)).toEqual(new Set(['carrier:epic']));
});

test('labels are compared without case, as GitHub does: a ready label spelled another way still starts the epic and comes off, and an owned label that exists in another case is not created', async () => {
  github.repoLabels = { 'AshuLab/a': ['Carrier:Status:Running'] };
  github.ready = { 'AshuLab/a': ready(6) };
  github.issue('AshuLab/a', 6).labels = ['carrier:go'];
  const engine = await start(1);
  settings.labels = { ...defaultLabels, ready: 'Carrier:Go' };
  await clock.advance(5 * MIN);
  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason])).toEqual([[6, 'running', null]]);
  expect(labelsOf(6)).toEqual(['carrier:status:running']);
  expect(github.created).not.toContain('AshuLab/a:carrier:status:running');
});

test('labels: a stage that changes while the labels of the one before are being written keeps its own to write', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's', write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1);
  settings.labels = { ...defaultLabels, stages: { ship: 'carrier:building', review: 'carrier:reviewing', fix: 'carrier:fixing' } };
  const set = github.setLabels.bind(github);
  let moved = false;
  github.setLabels = async (repo, issue, change) => {
    await set(repo, issue, change);
    if (!moved && change.add.includes('carrier:reviewing')) {
      moved = true;
      engine.db.update(epics).set({ stage: 'fix', labelPending: true }).where(eq(epics.issue, issue)).run(); // the stage moved on while this write was going
    }
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(moved).toBe(true);
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'fix', labelPending: true }); // the write of `review` does not clear what `fix` still has to write
});

test('labels: start asks for none; the first epic taken in a repo creates that repo\'s missing owned labels, never ready, and the second asks nothing more', async () => {
  github.repoLabels = { 'AshuLab/a': ['carrier:status:running', 'bug'] };
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 2, title: '' }] };
  const calls = vi.spyOn(github, 'listLabels');
  const engine = await start(1);
  expect(calls).not.toHaveBeenCalled();
  expect(github.created).toEqual([]);

  await clock.advance(5 * MIN); // takes the first epic
  expect(github.created).toEqual(['AshuLab/a:carrier:status:ready-for-test', 'AshuLab/a:carrier:status:needs-human']);
  expect(github.styles['carrier:status:needs-human']).toEqual({ color: 'd93f0b', description: expect.stringContaining('person') }); // created with a colour and a description
  expect(github.repoLabels['AshuLab/a']).toEqual(['carrier:status:running', 'bug', 'carrier:status:ready-for-test', 'carrier:status:needs-human']);
  expect(github.repoLabels['AshuLab/b']).toBeUndefined(); // no epic there: never asked
  expect(calls).toHaveBeenCalledTimes(1);

  // The first epic ends; the second one is taken on the same repo.
  github.ready = { 'AshuLab/a': [{ issue: 2, title: '' }] };
  github.issue('AshuLab/a', 1).state = 'closed';
  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([2]);
  expect(github.created).toHaveLength(2);
  expect(calls).toHaveBeenCalledTimes(1);
});

test('labels: when creating them fails with GitHubUnavailable the epic keeps labelPending and is not launched; the next poll with GitHub back creates them and launches', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  const createLabel = github.createLabel.bind(github);
  github.createLabel = async () => {
    throw new GitHubUnavailable('network', 'down');
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', labelPending: true });
  expect(runner.tasks).toHaveLength(0);
  expect(github.repoLabels['AshuLab/a'] ?? []).toEqual([]);

  github.createLabel = createLabel;
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  expect(github.repoLabels['AshuLab/a']).toEqual(['carrier:status:running', 'carrier:status:ready-for-test', 'carrier:status:needs-human']);
  expect(rows(engine.db)[0]).toMatchObject({ labelPending: false });
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
  const config = [{ name: 'AshuLab/a', agents: { ...agents, author: { profile: 'p', option: 'o', harness: 'codex' as const, model: 'x' } } }];
  const engine = await start(2, config, 2);
  await clock.advance(5 * MIN);

  expect(runner.tasks).toHaveLength(2);
  const [task, other] = runner.tasks as [AgentTask, AgentTask];
  expect(task).toMatchObject({
    repo: 'AshuLab/a', epic: 1, stage: 'ship', profile: 'p', harness: 'codex', model: 'x',
    workspace: '/work/AshuLab/a/1/author', timeoutMs: 2 * 3_600_000, context: { previousSummaries: [] },
  });
  expect(task.resultPath).toContain(join(dir, 'engine', 'state', 'results'));
  expect(new Set([task.executionId, other.executionId, task.resultPath, other.resultPath]).size).toBe(4);
  expect(executionsOf(engine.db).map((e) => [e.epicId, e.stage, e.status])).toEqual([[1, 'ship', 'running'], [2, 'ship', 'running']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
});

test('an epic reserved before options existed, whose saved config has no option, runs with the harness, model and provider it saved', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const legacy = { profile: 'p', harness: 'codex', model: 'x', provider: 'ollama' };
  const engine = await start(1, [{ name: 'AshuLab/a', agents: { author: legacy, reviewer: legacy } } as unknown as EffectiveRepoConfig]);
  await clock.advance(5 * MIN);
  expect(runner.tasks[0]).toMatchObject({ stage: 'ship', harness: 'codex', model: 'x', provider: 'ollama' });
  expect(executionsOf(engine.db)[0]).toMatchObject({ harness: 'codex', model: 'x', provider: 'ollama' });
});

test('every execution row records the option and the config folder it ran with, null when the option had none', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const withFolder = { ...agents.author, option: 'claude-ashu', configDir: '/cfg/ashu' };
  const withoutFolder = { ...agents.reviewer, option: 'codex-main' };
  pull(50, { headRef: 'feat/demo/epic' });
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) } : { exit: 'stopped' };
  const engine = await start(1, [{ name: 'AshuLab/a', agents: { author: withFolder, reviewer: withoutFolder } }]);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks[0]).toMatchObject({ option: 'claude-ashu', configDir: '/cfg/ashu' });
  expect(executionsOf(engine.db).map((e) => [e.stage, e.option, e.configDir])).toEqual([
    ['ship', 'claude-ashu', '/cfg/ashu'],
    ['review', 'codex-main', null],
  ]);
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
  const folder = join(dir, 'engine', 'logs', 'executions', runner.tasks[0]!.executionId);
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
    slices: engine.slices, version: '0', pollIntervalMs: 1, labels: defaultLabels, lastEvent: (id) => lastEventOf(engine.db, id),
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
});

test('with stage labels named, the issue shows the stage the epic is in and the next one replaces it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's', write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1);
  settings.labels = { ...defaultLabels, stages: { ship: 'carrier:building', review: 'carrier:reviewing', fix: 'carrier:fixing' } };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', labelPending: false });
  expect([...labelsOf(1)].sort()).toEqual(['carrier:reviewing', 'carrier:status:running']);
  expect(github.repoLabels['AshuLab/a']).toEqual(['carrier:status:running', 'carrier:status:ready-for-test', 'carrier:status:needs-human', 'carrier:building', 'carrier:reviewing', 'carrier:fixing']);
});

test('with a label named for a kind of stop, the issue shows it beside needs-human, and only that kind', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'a credential is missing' }) });
  const engine = await start(1);
  settings.labels = { ...defaultLabels, reasons: { agent_needs_human: 'carrier:asked', timeout: 'carrier:slow' } };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'agent_needs_human' });
  expect([...labelsOf(1)].sort()).toEqual(['carrier:asked', 'carrier:status:needs-human']);
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
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  // The second one started right away, with no new poll, and was not affected.
  expect(second).toMatchObject({ issue: 2, status: 'running', stage: 'review' });
  expect(labelsOf(2)).toEqual(['carrier:status:running']);
});

test('a needs_human result stops the epic with the caller reason and label', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'a credential is missing' }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'a credential is missing', finishedAt: 5 * MIN });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
    throw new GitHubUnavailable('network', 'down');
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
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review']); // the ship result is not imported again; the stopped review is the poll's recovery, resumed
  expect(engine.db.select().from(callerResults).all()).toHaveLength(1);
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
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
// What the engine records when it spends a retry or a recovery attempt on an epic.
const retriesOf = (db: Db) => eventsOf(db).filter((e) => e.type === 'execution_retried' || e.type === 'recovered');
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
  expect(github.created).toHaveLength(3); // the owned labels of the first label write, nothing from the retry
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
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
  expect(rows(engine.db)[0]?.needsHumanReason).toBe('ran out of ship retries (4 attempts): the agent process ended with an error (crashed: exit code 1)');
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });

  await clock.advance(5 * MIN);
  expect(runner.tasks.filter((t) => t.epic === 1)).toHaveLength(4);
});

// --- failures: the wait before the retry of an api_error ---

const apiError: AgentFailure = { kind: 'api_error', detail: 'HTTP 529: Overloaded', exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null };
const startedAts = (db: Db) => executionsOf(db).map((e) => e.startedAt);

test('an api_error is retried after 30 seconds, 2 minutes and 10 minutes with the injected clock, and not before, whatever the polls say', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: apiError });
  const engine = await start(1);
  await clock.advance(5 * MIN); // the poll takes the epic, and its first execution fails
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ retryAt: 5 * MIN + 30_000 }));
  expect(runner.tasks).toHaveLength(1);

  await clock.advance(30_000 - 1);
  await flush();
  expect(runner.tasks).toHaveLength(1);
  await clock.advance(1);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ retryAt: 5 * MIN + 30_000 + 2 * MIN }));

  await clock.advance(2 * MIN - 1);
  await flush();
  expect(runner.tasks).toHaveLength(2);
  await clock.advance(1);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));
  const third = 5 * MIN + 30_000 + 2 * MIN;
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ retryAt: third + 10 * MIN }));

  await clock.advance(10 * MIN - 1); // two polls fall inside the wait and start nothing
  await flush();
  expect(runner.tasks).toHaveLength(3);
  await clock.advance(1);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(4));
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'retries_exhausted', retryAt: null }));
  expect(startedAts(engine.db)).toEqual([5 * MIN, 5 * MIN + 30_000, third, third + 10 * MIN]);
});

test('a process that died is retried at once, and an api_error after a crash waits by its position in the streak', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', ...(runner.tasks.length >= 3 && { failure: apiError }) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3)); // two crashes, each retried in the same instant
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ retryAt: 5 * MIN + 10 * MIN })); // the api_error is the third failure of the streak
  expect(startedAts(engine.db)).toEqual([5 * MIN, 5 * MIN, 5 * MIN]);
});

test('an engine stopped while a retry waits stops at once, keeps the due time, and starts nothing afterwards', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: apiError });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ retryAt: 5 * MIN + 30_000 }));

  await engine.shutdown(); // resolves with the clock where it is: it waits for nothing
  expect(clock.now()).toBe(5 * MIN);
  await clock.advance(30 * MIN);
  expect(runner.tasks).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', retryAt: 5 * MIN + 30_000 });
});

test('a retry that came due while the engine was down starts at the first poll after it starts', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: apiError });
  const first = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(first.db)[0]).toMatchObject({ retryAt: 5 * MIN + 30_000 }));
  await first.shutdown();
  dbs.pop()!.$client.close();

  await clock.advance(2 * 3_600_000); // the engine stays down well past the due time
  runner.behavior = (task) => (task.resumeSession ? { exit: 'hang' } : { exit: 'failed', failure: apiError });
  const second = await start(1);
  expect(runner.tasks).toHaveLength(1); // starting alone does not launch it
  expect(rows(second.db)[0]).toMatchObject({ status: 'running', retryAt: 5 * MIN + 30_000 });
  await clock.advance(5 * MIN); // the first poll
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(runner.tasks[1]).toMatchObject({ stage: 'ship', resumeSession: 's' });
  expect(rows(second.db)[0]).toMatchObject({ status: 'running', retryAt: null });
});

// An epic that ran out of retries, resumed a minute later: the executions it had before the resume are another attempt's.
async function exhaustedThenResumed(config = repos) {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed' });
  const engine = await start(1, config);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'retries_exhausted' }));
  expect(runner.tasks).toHaveLength(4);
  await clock.advance(MIN);
  return engine;
}

test('a resumed epic that stopped in retries_exhausted has the full retries for its first technical failure', async () => {
  const engine = await exhaustedThenResumed();
  let fail!: () => void;
  const gate = new Promise<void>((resolve) => (fail = resolve)); // the epic is seen running again before its first failure
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', ...(runner.tasks.length === 5 && { when: gate }) });
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  fail();
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'retries_exhausted' }));

  expect(runner.tasks).toHaveLength(8); // four more tries, not the one that the old attempt's failures left
  expect(eventsOf(engine.db).filter((e) => e.type !== 'resumed').map((e) => e.data.attempt)).toEqual([2, 3, 4, 2, 3, 4]);
  expect(rows(engine.db)[0]?.needsHumanReason).toContain('(4 attempts)');
});

test('a resumed epic gets back the failover options that ran out in its previous attempt', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude', 'spare')(task, { exit: 'hang' });
  const engine = await startFailover(['spare']);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit' }));
  expect(runner.tasks.map((t) => t.option)).toEqual(['claude', 'spare']);

  await clock.advance(MIN);
  runner.behavior = (task) => outOf('claude')(task, { exit: 'hang' }); // `spare` is back
  const resumed = engine.resumeEpic('AshuLab/a', 1, { author: 'claude' });
  await flush();
  await clock.advance(1000);
  await resumed;
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.option)).toEqual(['claude', 'spare', 'claude', 'spare']));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', needsHumanKind: null });
});

const killedBy: AgentFailure = { kind: 'killed', detail: 'SIGKILL', exitCode: null, signal: 'SIGKILL', hostFreeMemMb: 1234, hostLoad: 2.5 };

test('a killed execution stores its failure, names the kind in the epic error, and the exhausted reason quotes it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: killedBy });
  const engine = await start(1, repos, 4, 0);
  await clock.advance(5 * MIN);
  await engine.idle();
  const text = 'the agent process ended with an error (killed: SIGKILL)';
  expect(executionsOf(engine.db)[0]).toMatchObject({
    status: 'failed', error: text, failureKind: 'killed', failureDetail: 'SIGKILL', exitCode: null, signal: 'SIGKILL', hostFreeMemMb: 1234, hostLoad: 2.5,
  });
  expect(rows(engine.db)[0]).toMatchObject({ lastError: text, status: 'needs_human', needsHumanKind: 'retries_exhausted' });
  expect(rows(engine.db)[0]?.needsHumanReason).toContain(text);
});

test('retries exhausted on a missing result says that no result file was written, with the kind', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's' });
  const engine = await start(1, repos, 4, 0);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'retries_exhausted', needsHumanReason: 'ran out of ship retries (1 attempts): the agent ended with an invalid result (invalid_result: no result file was written)' });
});

test('retries exhausted on a process the idle watchdog killed names limits.idleMinutes', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const idleKill = { kind: 'killed' as const, detail: 'no output for 2700 seconds', exitCode: null, signal: 'SIGTERM', hostFreeMemMb: 1, hostLoad: 1 };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: idleKill });
  const engine = await start(1, repos, 4, 0);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]?.needsHumanReason).toBe('ran out of ship retries (1 attempts): the agent process ended with an error (killed: no output for 2700 seconds) · limits.idleMinutes ended it: raise it or remove it');
});

const outOfCredits: AgentFailure = { kind: 'usage_limit', detail: "You've hit your session limit · resets 12:40pm", exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null };

test('a usage limit stops the epic at once with the option that ran out and its reset time, and spends no retry', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const config = [{ name: 'AshuLab/a', agents: { ...agents, author: { ...agents.author, option: 'claude-ashu' } } }];
  runner.behavior = (task) => (task.epic === 1 ? { sessionId: 's', exit: 'failed', failure: outOfCredits } : { exit: 'hang' });
  const engine = await start(1, config); // maxExecutionRetries 3
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.some((t) => t.epic === 2)).toBe(true));

  expect(runner.tasks.filter((t) => t.epic === 1)).toHaveLength(1);
  expect(eventsOf(engine.db)).toEqual([]);
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'failed', failureKind: 'usage_limit', failureDetail: outOfCredits.detail, error: null });
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, status: 'needs_human', needsHumanKind: 'usage_limit', finishedAt: 5 * MIN });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe(`the ship execution ran out of usage on option claude-ashu · carrier restart AshuLab/a#1 --author <option> · ${outOfCredits.detail}`);
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });
});

test('a usage limit does not count in the retry streak', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'failed', error: 'boom', failureKind: 'crashed' });
  seedExecution(db, 'e1', 1, { status: 'failed', failureKind: 'usage_limit', failureDetail: 'resets 12:40pm' });
  seedExecution(db, 'e2', 1, { status: 'failed', error: 'boom', failureKind: 'crashed' });
  expect(failureStreak(db, { id: 1, startedAt: 0 }).map((e) => e.executionId)).toEqual(['e2']);
});

test('an unexpected error while settling one epic stops only that epic with engine_error and a redacted reason, and the other keeps running', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  pull(50);
  runner.behavior = (task) => (task.epic === 1 ? { write: completed(task) } : { exit: 'hang' });
  const getPullRequest = github.getPullRequest.bind(github);
  github.getPullRequest = async () => {
    throw new Error('exploded with token ghp_abcdefghijklmnopqrstuvwxyz0123456789\nsecond line');
  };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error' }));

  const [stopped, other] = rows(engine.db);
  expect(stopped?.needsHumanReason).toMatch(/^exploded with token \S+ second line$/);
  expect(stopped?.needsHumanReason).not.toContain('ghp_abcdefghijklmnopqrstuvwxyz0123456789');
  expect(other).toMatchObject({ issue: 2, status: 'running' });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  github.getPullRequest = getPullRequest;
});

test('an error that leaves a launched execution running ends it as failed and does not leave the epic running', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let launches = 0;
  const run = runner.run.bind(runner);
  runner.run = (task) => {
    if (task.epic === 1 && ++launches === 2) throw new Error('could not spawn the retry');
    return run(task);
  };
  runner.behavior = (task) => (task.epic === 1 ? { exit: 'failed' } : { exit: 'hang' });
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error', needsHumanReason: 'could not spawn the retry' }));

  expect(executionsOf(engine.db).filter((e) => e.epicId === 1).map((e) => e.status)).toEqual(['failed', 'failed']);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });
});

// Two epics whose finished executions wait for the poll: GitHub was down when their results arrived.
async function startWithResultsPending() {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  pull(50);
  pull(51, {}, 2);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task, { number: 50 + task.epic - 1, headSha: SHA }) } : { exit: 'hang' });
  const engine = await start(2);
  const getPullRequest = github.getPullRequest.bind(github);
  github.getPullRequest = async () => {
    throw new GitHubUnavailable('network', 'down');
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['finished', 'finished']);
  return { engine, getPullRequest };
}

test('an error settling the first of two pending results stops that epic with engine_error, the second is settled and launched, and the poll finishes', async () => {
  const { engine, getPullRequest } = await startWithResultsPending();
  github.getPullRequest = async (repo, number) => {
    if (number === 50) throw new Error('could not read the pull request');
    return getPullRequest(repo, number);
  };
  await clock.advance(5 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error', needsHumanReason: 'could not read the pull request' });
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running', stage: 'review', round: 1 });
  expect(runner.tasks.filter((t) => t.epic === 2).map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(engine.nextPollAt).toBe(15 * MIN);
});

test('an error retrying the first of two epics with a retry pending stops that epic with engine_error, the second is retried, and the poll finishes', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const launched = new Set<number>();
  runner.behavior = (task) => (launched.has(task.epic) ? { exit: 'hang' } : (launched.add(task.epic), { exit: 'failed' })); // each epic's first run fails, its retry hangs
  const engine = await start(2);
  const findPullRequest = github.findPullRequest.bind(github);
  github.findPullRequest = async () => {
    throw new GitHubUnavailable('network', 'down');
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks).toHaveLength(2); // nothing was retried: GitHub was down

  github.findPullRequest = async (repo, issue) => {
    if (issue === 1) throw new Error('could not look for the pull request');
    return findPullRequest(repo, issue);
  };
  await clock.advance(5 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error', needsHumanReason: 'could not look for the pull request' });
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(2);
  expect(engine.nextPollAt).toBe(15 * MIN);
});

test('an error about the whole engine while settling stops the poll with its message and parks no epic', async () => {
  const { engine } = await startWithResultsPending();
  const fail = Object.assign(new Error('attempt to write a readonly database'), { code: 'SQLITE_READONLY' });
  github.getPullRequest = async () => {
    throw fail;
  };
  const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
  try {
    await clock.advance(5 * MIN);
    expect(logged.mock.calls.flat().join(' ')).toContain('attempt to write a readonly database');
  } finally {
    logged.mockRestore();
  }
  expect(rows(engine.db).map((e) => e.status)).toEqual(['running', 'running']);
});

test('a configuration that cannot be read stops the poll with a message that names it, parks no epic, and the next check is armed', async () => {
  const { engine } = await startWithResultsPending();
  const unreadable = new Error('could not read the configuration: config.yaml is unreadable');
  watched = { [Symbol.iterator]: () => { throw unreadable; }, map: () => { throw unreadable; } } as unknown as EffectiveRepoConfig[];
  const logged = vi.spyOn(console, 'error').mockImplementation(() => {});
  try {
    await engine.pollNow();
    expect(logged.mock.calls.flat().join(' ')).toContain('could not read the configuration');
  } finally {
    logged.mockRestore();
  }
  expect(rows(engine.db).map((e) => e.status)).toEqual(['running', 'running']);
  expect(engine.nextPollAt).toBe(clock.now() + settings.pollIntervalMs);
});

// Failover: three options, the author on `claude` and the reviewer on `codex`; `spare` is the one only the list can name.
type Steps = { provider: string; model?: string; effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max' }[];
const failoverRepos = (roles?: { author?: Steps; reviewer?: Steps }): EffectiveRepoConfig[] =>
  choosing({ claude: claudeOption, codex: codexOption, spare: { harness: 'agy', model: 'flash' } }).map((repo) => ({ ...repo, ...(roles && { failover: { roles } }) }));
// Reserves the epic, which starts at once on the defaults.
async function startFailover(order: string[], slots = 1) {
  const steps = order.map((provider) => ({ provider }));
  return startWith(failoverRepos({ author: steps, reviewer: steps }), slots);
}
async function startWith(config: EffectiveRepoConfig[], slots = 1) {
  const engine = await start(slots, config);
  await clock.advance(5 * MIN);
  return engine;
}
const outOf = (...options: string[]) => (task: AgentTask, otherwise: Behavior): Behavior =>
  task.option !== undefined && options.includes(task.option) ? { sessionId: `s-${task.option}`, exit: 'failed', failure: outOfCredits } : otherwise;

test('with failover on, an author that runs out moves to the next option in order, rebuilt in the same worktree, spending no retry, and the epic goes on', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => outOf('claude')(task, task.stage === 'ship' ? { sessionId: 's-spare', write: completed(task) } : { exit: 'hang' });
  const engine = await startFailover(['spare']);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'claude'], ['ship', 'spare'], ['review', 'codex']]);
  expect(runner.tasks[1]).toMatchObject({ harness: 'agy', workspace: runner.tasks[0]!.workspace, context: { verifyStateFirst: true, pr: { number: 50, headSha: SHA } } });
  expect(runner.tasks[1]!.resumeSession).toBeUndefined();
  expect(eventsOf(engine.db)).toMatchObject([{ epicId: 1, at: 5 * MIN, type: 'option_switched', data: { role: 'author', from: 'claude', fromModel: 'opus', to: 'spare', toModel: 'flash', stage: 'ship' } }]);
  expect(executionsOf(engine.db).map((e) => [e.option, e.status])).toEqual([['claude', 'failed'], ['spare', 'finished'], ['codex', 'running']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', authorOption: 'spare', reviewerOption: 'codex', lastError: null });
  expect(rows(engine.db)[0]!.config!.agents.author).toMatchObject({ option: 'spare', harness: 'agy', model: 'flash', profile: 'a' });
});

test("a role's effort goes with it when it moves to the next step", async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => outOf('claude')(task, task.stage === 'ship' ? { sessionId: 's-spare', write: completed(task) } : { exit: 'hang' });
  const config = failoverRepos({ author: [{ provider: 'spare' }] }).map((repo) => ({ ...repo, agents: { ...repo.agents, author: { ...repo.agents.author, effort: 'high' as const } } }));
  await startWith(config);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));
  expect(runner.tasks[1]).toMatchObject({ option: 'spare', effort: 'high' });
});

test('a failover step with its own effort runs on it, and one without keeps the effort the role was running with', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.option === 'codex' ? { sessionId: 's-3', write: completed(task) } : outOf(task.option === 'claude' ? 'claude' : 'spare')(task, { exit: 'hang' }));
  const config = failoverRepos({ author: [{ provider: 'spare', effort: 'low' }, { provider: 'codex' }] }).map((repo) => ({ ...repo, agents: { ...repo.agents, author: { ...repo.agents.author, effort: 'high' as const } } }));
  await startWith(config);
  await vi.waitFor(() => expect(runner.tasks.length).toBeGreaterThanOrEqual(3));
  expect(runner.tasks[1]).toMatchObject({ option: 'spare', effort: 'low' });
  expect(runner.tasks[2]).toMatchObject({ option: 'codex', effort: 'low' });
});

test('only the role that ran out moves: a reviewer that runs out leaves the author option as it is', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => outOf('codex')(task, task.stage === 'ship' ? { sessionId: 's-1', write: completed(task) } : { exit: 'hang' });
  const engine = await startFailover(['spare']);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'claude'], ['review', 'codex'], ['review', 'spare']]);
  expect(eventsOf(engine.db)).toMatchObject([{ type: 'option_switched', data: { role: 'reviewer', from: 'codex', to: 'spare', stage: 'review' } }]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', authorOption: 'claude', reviewerOption: 'spare' });
});

test('a step names its own model, and the same provider on another model is a step of its own', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.model === 'opus' ? outOf('claude')(task, { exit: 'hang' }) : task.stage === 'ship' ? { sessionId: 's-1', write: completed(task) } : { exit: 'hang' });
  const author = [{ provider: 'claude', model: 'haiku' }, { provider: 'spare', model: 'pro' }];
  const engine = await startWith(failoverRepos({ author }));
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => [t.stage, t.option, t.model])).toEqual([['ship', 'claude', 'opus'], ['ship', 'claude', 'haiku'], ['review', 'codex', 'gpt']]);
  expect(eventsOf(engine.db)).toMatchObject([{ type: 'option_switched', data: { role: 'author', from: 'claude', fromModel: 'opus', to: 'claude', toModel: 'haiku' } }]);
});

test('a step that ran out is not tried again, and when none is left the epic stops naming each step', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude', 'spare')(task, { exit: 'hang' });
  const engine = await startWith(failoverRepos({ author: [{ provider: 'claude', model: 'haiku' }, { provider: 'spare', model: 'pro' }] }));
  await vi.waitFor(() => expect(rows(engine.db)[0]!.status).toBe('needs_human'));

  expect(runner.tasks.map((t) => [t.option, t.model])).toEqual([['claude', 'opus'], ['claude', 'haiku'], ['spare', 'pro']]);
  expect(rows(engine.db)[0]?.needsHumanReason).toContain('no step left in failover, ran out: claude opus, claude haiku, spare pro');
});

test('failover skips the options that already ran out in this epic, and the one that ran out last is not tried again', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude', 'spare')(task, { exit: 'hang' });
  const engine = await startFailover(['spare', 'claude', 'codex']);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => t.option)).toEqual(['claude', 'spare', 'codex']);
  expect(eventsOf(engine.db).map((e) => [e.data.from, e.data.to])).toEqual([['claude', 'spare'], ['spare', 'codex']]);
});

test('failover across harnesses without a model on the provider uses that harness default model rather than leaking the previous model', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => outOf('claude')(task, task.stage === 'ship' ? { sessionId: 's-codex', write: completed(task) } : { exit: 'hang' });
  const repos = choosing({ claude: claudeOption, codexBare: { harness: 'codex' as const } }).map((repo) => ({
    ...repo,
    failover: { roles: { author: [{ provider: 'codexBare' }] } },
  }));
  const engine = await startWith(repos);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));
  expect(runner.tasks[1]).toMatchObject({ harness: 'codex', model: 'gpt-5.3-codex', option: 'codexBare' });
});

test('failover on service_down failure suppresses execution error and does not burn retry streak', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const serviceDownFailure: AgentFailure = { kind: 'api_error', detail: 'ECONNREFUSED 127.0.0.1:1234', exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null };
  runner.behavior = (task) =>
    task.option === 'claude'
      ? { sessionId: 's-claude', exit: 'failed', failure: serviceDownFailure }
      : task.stage === 'ship'
        ? { sessionId: 's-spare', write: completed(task) }
        : { exit: 'hang' };
  const engine = await startFailover(['spare']);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'claude'], ['ship', 'spare'], ['review', 'codex']]);
  const execs = executionsOf(engine.db);
  expect(execs[0]).toMatchObject({ option: 'claude', status: 'failed', error: null, failureKind: 'api_error' });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', lastError: null });
});

test('failover on rate_limit failure switches provider', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const rateLimitFailure: AgentFailure = { kind: 'api_error', detail: 'HTTP 429: Rate limit exceeded', exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null };
  runner.behavior = (task) =>
    task.option === 'claude'
      ? { sessionId: 's-claude', exit: 'failed', failure: rateLimitFailure }
      : task.stage === 'ship'
        ? { sessionId: 's-spare', write: completed(task) }
        : { exit: 'hang' };
  const engine = await startFailover(['spare']);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'claude'], ['ship', 'spare'], ['review', 'codex']]);
  expect(executionsOf(engine.db)[0]).toMatchObject({ option: 'claude', status: 'failed', error: null, failureKind: 'api_error' });
});

test('when no option in the list is left the epic stops with usage_limit and names every option that ran out, and never uses one outside the list', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => (task.epic === 1 ? outOf('claude', 'spare')(task, { exit: 'hang' }) : { exit: 'hang' });
  const engine = await startFailover(['spare'], 2);
  await vi.waitFor(() => expect(rows(engine.db)[0]!.status).toBe('needs_human'));
  await vi.waitFor(() => expect(runner.tasks.some((t) => t.epic === 2)).toBe(true));

  expect(runner.tasks.filter((t) => t.epic === 1).map((t) => t.option)).toEqual(['claude', 'spare']); // codex is the reviewer's default, not in the list
  expect(rows(engine.db)[0]).toMatchObject({ issue: 1, status: 'needs_human', needsHumanKind: 'usage_limit', finishedAt: 5 * MIN });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe(`the ship execution ran out of usage on option spare · carrier restart AshuLab/a#1 --author <option> · ${outOfCredits.detail}; no step left in failover, ran out: claude opus, spare flash`);
  expect(eventsOf(engine.db)).toMatchObject([{ type: 'option_switched', data: { from: 'claude', to: 'spare' } }]);
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(rows(engine.db)[1]).toMatchObject({ issue: 2, status: 'running' });
});

test('a stop that comes from a provider\'s 5xx says that the provider answered with a server error, and not that the epic ran out of usage', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const down: AgentFailure = { kind: 'api_error', detail: 'HTTP 503: Service unavailable', exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: down });
  const engine = await startFailover(['spare']);
  await vi.waitFor(() => expect(rows(engine.db)[0]!.status).toBe('needs_human'));

  expect(rows(engine.db)[0]).toMatchObject({ needsHumanKind: 'usage_limit' });
  const reason = rows(engine.db)[0]!.needsHumanReason!;
  expect(reason).toBe('the provider answered the ship execution on option spare with a server error, not a usage limit · wait and resume the epic, or carrier restart AshuLab/a#1 --author <option> · HTTP 503: Service unavailable; no step left in failover, ran out: claude opus, spare flash');
  expect(reason).not.toContain('ran out of usage');
});

test.each([['an empty list', { author: [], reviewer: [] }], ['absent', undefined]])('with failover %s, a usage limit stops the epic on the first option as before', async (_, failover) => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude')(task, { exit: 'hang' });
  const engine = await startWith(failoverRepos(failover));
  await vi.waitFor(() => expect(rows(engine.db)[0]!.status).toBe('needs_human'));

  expect(runner.tasks.map((t) => t.option)).toEqual(['claude']);
  expect(eventsOf(engine.db)).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit' });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe(`the ship execution ran out of usage on option claude · carrier restart AshuLab/a#1 --author <option> · ${outOfCredits.detail}`);
});

// Auto-resume: the epic keeps the time its window comes back, read from the quota of the account of each option that ran out.
const HOUR = 60 * MIN;
const claudeAccount = { harness: 'claude' as const, model: 'opus', configDir: '/cfg/claude' };
const spareAccount = { harness: 'codex' as const, model: 'gpt', configDir: '/cfg/spare' };
const quotaRepos = (failover?: boolean): EffectiveRepoConfig[] => [{
  name: 'AshuLab/a',
  providers: { claude: claudeAccount, spare: spareAccount } as any,
  ...(failover && { failover: { roles: { author: [{ provider: 'spare' }], reviewer: [] } } }),
  agents: { author: { profile: 'a', option: 'claude', ...claudeAccount }, reviewer: { profile: 'b', option: 'spare', ...spareAccount } },
}];
const full = (provider: 'claude' | 'codex', resetsAt: number): QuotaSnapshot => ({ provider, status: 'ok', checkedAt: 0, windows: [{ id: 'w', label: 'w', usedPercent: 100, resetsAt }] });
// The author runs out on `claude` (and on `spare` with failover) and the epic stops; `on` is auto-resume.
async function stopOnQuota(over: { autoResume?: boolean; failover?: boolean; autoResumeMaxHours?: number } = {}) {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude', 'spare')(task, { exit: 'hang' });
  const engine = await start(1, quotaRepos(over.failover));
  settings = { ...settings, autoResume: over.autoResume ?? true, ...(over.autoResumeMaxHours && { autoResumeMaxHours: over.autoResumeMaxHours }) }; // a reload before the stop
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit' }));
  return engine;
}

test('with auto-resume on and a time within the maximum the epic keeps resumeAt, writes auto_resume_scheduled, and the reason says when', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 3 * HOUR);
  const engine = await stopOnQuota();

  expect(fakeQuota.asked).toEqual([{ provider: 'claude', configDir: '/cfg/claude' }]);
  expect(rows(engine.db)[0]).toMatchObject({ resumeAt: 5 * MIN + 3 * HOUR });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe(`the ship execution ran out of usage on option claude · carrier restart AshuLab/a#1 --author <option> · resumes by itself at 1970-01-01T03:05:00.000Z · ${outOfCredits.detail}`);
  expect(eventsOf(engine.db)).toMatchObject([{ epicId: 1, at: 5 * MIN, type: 'auto_resume_scheduled', data: { resumeAt: 5 * MIN + 3 * HOUR } }]);
  expect(buildSnapshot(engine.db, { now: clock.now(), maxConcurrentEpics: 1, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, slices: engine.slices, version: 'x', pollIntervalMs: 1, labels: defaultLabels }).epics[0]).toMatchObject({ status: 'needs_human', resumeAt: 5 * MIN + 3 * HOUR });
});

test('with failover the time is the earliest over the options the epic ran out of', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 5 * HOUR);
  fakeQuota.snapshots['/cfg/spare'] = full('codex', 5 * MIN + 2 * HOUR);
  const engine = await stopOnQuota({ failover: true });

  expect(fakeQuota.asked.map((t) => t.configDir).sort()).toEqual(['/cfg/claude', '/cfg/spare']);
  expect(rows(engine.db)[0]).toMatchObject({ resumeAt: 5 * MIN + 2 * HOUR });
});

test('with auto-resume off the quota is not asked, resumeAt is not set and the reason is the usual one', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 3 * HOUR);
  const engine = await stopOnQuota({ autoResume: false });

  expect(fakeQuota.asked).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ resumeAt: null });
  expect(rows(engine.db)[0]?.needsHumanReason).toBe(`the ship execution ran out of usage on option claude · carrier restart AshuLab/a#1 --author <option> · ${outOfCredits.detail}`);
  expect(eventTypes(engine.db)).toEqual([]);
});

test.each([
  ['the probe says no window is full', () => {}],
  ['the probe is rate limited', () => { fakeQuota.snapshots['/cfg/claude'] = { provider: 'claude', status: 'rate_limited', checkedAt: 0, windows: [], message: 'x' }; }],
  ['the probe throws', () => { fakeQuota.failing = true; }],
])('with no known time (%s) resumeAt is not set and the reason says why', async (_, setUp) => {
  fakeQuota.snapshots['/cfg/claude'] = { provider: 'claude', status: 'ok', checkedAt: 0, windows: [{ id: 'w', label: 'w', usedPercent: 40 }] };
  setUp();
  const engine = await stopOnQuota();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit', resumeAt: null });
  expect(rows(engine.db)[0]?.needsHumanReason).toContain('it will not resume by itself: the provider did not say when the window comes back');
  expect(eventTypes(engine.db)).toEqual([]);
});

test('a wait longer than autoResumeMaxHours is not scheduled and the reason says when the window comes back', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 13 * HOUR);
  const engine = await stopOnQuota();

  expect(rows(engine.db)[0]).toMatchObject({ resumeAt: null });
  expect(rows(engine.db)[0]?.needsHumanReason).toContain('the window comes back at 1970-01-01T13:05:00.000Z, more than 12 h away: it will not resume by itself');
  expect(eventTypes(engine.db)).toEqual([]);
});

test('the maximum is the live setting: a wait of 13 hours is within 24', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 13 * HOUR);
  const engine = await stopOnQuota({ autoResumeMaxHours: 24 });

  expect(rows(engine.db)[0]).toMatchObject({ resumeAt: 5 * MIN + 13 * HOUR });
});

test('a resume by a person clears resumeAt', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 3 * HOUR);
  const engine = await stopOnQuota();
  expect(rows(engine.db)[0]?.resumeAt).toBe(5 * MIN + 3 * HOUR);

  runner.behavior = () => ({ exit: 'hang' });
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', resumeAt: null });
});

test('any other change of the epic\'s status clears resumeAt: ended from outside', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 3 * HOUR);
  const engine = await stopOnQuota();

  github.issue('AshuLab/a', 1).state = 'closed';
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', resumeAt: null }));
});

// The wake-up: at the first poll after `resumeAt` the quota is read again, and the epic resumes only when its window is below 100%.
const back = (provider: 'claude' | 'codex' = 'claude'): QuotaSnapshot => ({ provider, status: 'ok', checkedAt: 0, windows: [{ id: 'w', label: 'w', usedPercent: 20, resetsAt: 9 * HOUR }] });
const WAKE = 5 * MIN + 3 * HOUR; // the epic stops at 5 minutes and its window says it is back 3 hours later
async function stoppedForQuota(over: Parameters<typeof stopOnQuota>[0] = {}) {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', WAKE);
  const engine = await stopOnQuota(over);
  runner.behavior = () => ({ exit: 'hang' });
  return engine;
}
const shipTasks = () => runner.tasks.filter((t) => t.stage === 'ship').length;

test('before resumeAt the probe is not asked again and the epic stays stopped', async () => {
  const engine = await stoppedForQuota();
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(2 * HOUR);

  expect(fakeQuota.asked).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: WAKE });
});

test('at the first poll after resumeAt the probe is asked again and a window below 100% resumes the epic from ship through the queue, with an auto_resumed event', async () => {
  const engine = await stoppedForQuota();
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(WAKE - clock.now() - 1);
  expect(fakeQuota.asked).toHaveLength(1); // not before the time
  await clock.advance(5 * MIN);

  expect(fakeQuota.asked).toHaveLength(2);
  expect(shipTasks()).toBe(2);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', resumeAt: null, autoResumes: 1, needsHumanKind: null });
  expect(eventsOf(engine.db).map((e) => [e.type, e.data])).toEqual([['auto_resume_scheduled', { resumeAt: WAKE }], ['auto_resumed', { stage: 'ship', option: 'claude', resumeAt: WAKE, count: 1 }]]);
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
});

test.each([
  ['the window is still at 100%', () => { fakeQuota.snapshots['/cfg/claude'] = full('claude', 9 * HOUR); }],
  ['the probe is rate limited', () => { fakeQuota.snapshots['/cfg/claude'] = { provider: 'claude', status: 'rate_limited', checkedAt: 0, windows: [], message: 'x' }; }],
  ['the probe fails', () => { fakeQuota.failing = true; }],
  ['the probe has no data for the account', () => { delete fakeQuota.snapshots['/cfg/claude']; }],
])('when %s the epic waits for the next poll and nothing is guessed, and resumes at the poll that finds it back', async (_, setUp) => {
  const engine = await stoppedForQuota();
  setUp();
  await clock.advance(3 * HOUR); // past resumeAt: the poll at its time asks
  const asked = fakeQuota.asked.length;

  expect(asked).toBeGreaterThan(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: WAKE, autoResumes: 0 });
  expect(shipTasks()).toBe(1);

  fakeQuota.failing = false;
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', autoResumes: 1 });
  expect(shipTasks()).toBe(2);
});

test('the wake-up takes a slot like any epic: with none free it waits queued and starts when one frees', async () => {
  const engine = await stoppedForQuota();
  settings.maxConcurrentEpics = 0;
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(3 * HOUR);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', autoResumes: 1 });
  expect(shipTasks()).toBe(1);

  settings.maxConcurrentEpics = 1;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
  expect(shipTasks()).toBe(2);
});

test.each(['review', 'fix'] as const)('an epic that stopped at %s wakes up at that stage with its round, pull request, worktree and session', async (stage) => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', stage, round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'usage_limit', needsHumanReason: 'out of usage', resumeAt: MIN, config: quotaRepos()[0] });
  seedExecution(db, 's1', 1, { status: 'finished', stage: 'ship' });
  seedExecution(db, 'x1', 1, { status: 'failed', stage, round: stage === 'review' ? 2 : null, option: 'claude', harness: 'claude', model: 'opus', configDir: '/cfg/claude', failureKind: 'usage_limit' });
  db.insert(callerResults).values({ executionId: 'x1', outcome: 'changes_requested', result: JSON.stringify({ summary: 's', blockers: [] }) }).run();
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
  fakeQuota.snapshots['/cfg/claude'] = back();
  db.$client.close();
  dbs.pop();
  const engine = await start(1, quotaRepos());
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);

  expect(runner.tasks.map((t) => t.stage)).toEqual([stage]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage, round: 2, prNumber: 50, workspace: '/w/epic', resumeAt: null, resumeStage: null, autoResumes: 1 });
  expect(eventsOf(engine.db).map((e) => [e.type, e.data])).toEqual([['auto_resumed', { stage, option: 'claude', resumeAt: MIN, count: 1 }]]);
});

test('an epic that stopped at review does not wake up when its pull request head changed', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'usage_limit', resumeAt: MIN, config: quotaRepos()[0] });
  seedExecution(db, 'x1', 1, { status: 'failed', stage: 'review', option: 'claude', harness: 'claude', model: 'opus', configDir: '/cfg/claude', failureKind: 'usage_limit' });
  pull(50, { headSha: 'b'.repeat(40) });
  fakeQuota.snapshots['/cfg/claude'] = back();
  db.$client.close();
  dbs.pop();
  const engine = await start(1, quotaRepos());
  settings = { ...settings, autoResume: true };
  await clock.advance(10 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: null, autoResumes: 0 });
  expect(fakeQuota.asked).toEqual([]);
});

test('the wake-up goes on the option that came back, not the last one the failover tried', async () => {
  fakeQuota.snapshots['/cfg/spare'] = full('codex', WAKE + HOUR);
  const engine = await stoppedForQuota({ failover: true });
  fakeQuota.snapshots['/cfg/claude'] = back(); // spare is still at 100%
  await clock.advance(3 * HOUR);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', authorOption: 'claude', autoResumes: 1 });
  expect(runner.tasks.at(-1)).toMatchObject({ stage: 'ship', option: 'claude' });
});

test('an epic wakes up at most three times in a row: the stop after the third stays in needs-human', async () => {
  // Each stop reads the window full for an hour, each wake-up finds it back.
  fakeQuota.read = async (target) => {
    fakeQuota.asked.push(target);
    return fakeQuota.asked.length % 2 === 1 ? full('claude', clock.now() + HOUR) : back();
  };
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude')(task, { exit: 'hang' });
  const engine = await start(1, quotaRepos());
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);
  await clock.advance(6 * HOUR);

  expect(shipTasks()).toBe(4);
  expect(fakeQuota.asked).toHaveLength(6); // the fourth stop does not ask
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit', resumeAt: null, autoResumes: 3 });
  expect(rows(engine.db)[0]?.needsHumanReason).toContain('it already resumed by itself 3 times in a row: it will not again');
  expect(eventTypes(engine.db).filter((t) => t === 'auto_resumed')).toHaveLength(3);
});

test('the count starts again when an execution of the epic ends with anything but usage_limit', async () => {
  const engine = await stoppedForQuota();
  engine.db.update(epics).set({ autoResumes: 2 }).run();
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's', write: completed(task) } : { exit: 'hang' });
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(3 * HOUR);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', autoResumes: 0 });
});

test.each([['review'], ['fix'], [undefined]] as const)('the count starts again when a person resumes the epic at another stage (from %s)', async (from) => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review', { autoResumes: 2 });
  await resumeFrom(engine, from);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', autoResumes: 0 });
});

test('with the engine paused nothing resumes, and it resumes once the engine is not paused', async () => {
  const engine = await stoppedForQuota();
  fakeQuota.snapshots['/cfg/claude'] = back();
  await engine.setPaused(true);
  await clock.advance(4 * HOUR);

  expect(fakeQuota.asked).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: WAKE });

  await engine.setPaused(false);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', autoResumes: 1 });
});

test('with limits.autoResume off by a reload nothing resumes', async () => {
  const engine = await stoppedForQuota();
  fakeQuota.snapshots['/cfg/claude'] = back();
  settings = { ...settings, autoResume: false };
  await clock.advance(4 * HOUR);

  expect(fakeQuota.asked).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: WAKE });
});

test('resumeAt survives a restart of the engine: the epic resumes once the time passes', async () => {
  const first = await stoppedForQuota();
  await settle(); // the stop's own label write ends before the database closes
  first.stop();
  dbs.pop()!.$client.close();
  fakeQuota.snapshots['/cfg/claude'] = back();
  const second = await start(1, quotaRepos());
  settings = { ...settings, autoResume: true };
  expect(rows(second.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: WAKE });
  await clock.advance(3 * HOUR);

  expect(rows(second.db)[0]).toMatchObject({ status: 'running', stage: 'ship', autoResumes: 1 });
  expect(shipTasks()).toBe(2);
});

test('a resume by a person before the time clears resumeAt and the wake-up does not run a second time', async () => {
  const engine = await stoppedForQuota();
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', resumeAt: null });

  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(3 * HOUR);
  expect(shipTasks()).toBe(2);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', autoResumes: 0 });
  expect(eventTypes(engine.db)).not.toContain('auto_resumed');
});

test('a later epic starts on its own role, whatever ran out in an earlier one', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => (task.epic === 1 ? outOf('claude')(task, { exit: 'hang' }) : { exit: 'hang' });
  const engine = await startFailover(['spare'], 2);
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1));

  expect(runner.tasks.filter((t) => t.epic === 1).map((t) => t.option)).toEqual(['claude', 'spare']);
  expect(runner.tasks.filter((t) => t.epic === 2).map((t) => t.option)).toEqual(['claude']);
});

test('a failed end the runner gave no failure for is stored as unknown, with no dangling colon', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: undefined });
  const engine = await start(1, repos, 4, 0);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'failed', error: 'the agent process ended with an error (unknown)', failureKind: 'unknown', failureDetail: '' });
});

test('an execution that ends ok, and one that Carrier stops, leave every failure column null', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(statuses(engine.db)).toContain('finished');
  expect(statuses(engine.db)).toContain('interrupted');
  for (const row of executionsOf(engine.db)) expect(row).toMatchObject({ failureKind: null, failureDetail: null, exitCode: null, signal: null, hostFreeMemMb: null, hostLoad: null });
});

const usage = { inputTokens: 10, cachedInputTokens: 20, cacheWriteTokens: 3, outputTokens: 4, reasoningTokens: 5, costUsd: 0.5, byModel: { m: { inputTokens: 10, cachedInputTokens: 20, cacheWriteTokens: 3, outputTokens: 4, reasoningTokens: 5, costUsd: 0.5 } } };

test.each([
  ['ok', 'finished', {}],
  ['failed', 'failed', { failure: outOfCredits }],
  ['timed_out', 'timed_out', {}],
  ['stopped', 'interrupted', {}],
] as const)('the usage a run reports is stored on the execution that ends %s', async (exit, status, extra) => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => ({ sessionId: 's', exit, ...(exit === 'ok' && { write: completed(task) }), ...extra, usage });
  const engine = await start(1, repos, 4, 0);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(executionsOf(engine.db)[0]?.status).toBe(status));
  expect(executionsOf(engine.db)[0]?.usage).toEqual(usage);
});

test('an execution whose run reports no usage keeps usage null', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => ({ sessionId: 's', write: completed(task) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(executionsOf(engine.db)[0]?.status).toBe('finished'));
  expect(executionsOf(engine.db)[0]?.usage).toBeNull();
});

const noProcess = { exitCode: null, signal: null, hostFreeMemMb: null, hostLoad: null };

const endKinds = [
  ['auth_failed', 'failed', 'auth', 'profile a', 'authentication error for profile a'],
  ['session_unavailable', 'failed', 'session_lost', 'the agent session is not available', 'the agent session is not available'],
  ['timed_out', 'timed_out', 'timeout', 'exceeded 4 h', null],
] as const;

test.each(endKinds)('%s records its kind and a detail on the execution, with the error it already had', async (exit, status, kind, detail, error) => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => (task.resumeSession ? { exit: 'hang' } : { sessionId: 's', exit });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  // The first authentication signal is retried (and the retry hangs), so the engine does not go idle: the retry's start is what is waited for.
  if (exit === 'auth_failed') await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  else await engine.idle();
  expect(executionsOf(engine.db)[0]).toMatchObject({ status, failureKind: kind, failureDetail: detail, error, ...noProcess });
});

test('a timed-out execution does not count in the retry streak', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'timed_out', failureKind: 'timeout', failureDetail: 'exceeded 4 h' });
  expect(failureStreak(db, { id: 1, startedAt: 0 })).toEqual([]);
});

test('a lost session is rebuilt because of its kind, whatever the error text says', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'failed', error: 'some other words', failureKind: 'session_lost', failureDetail: 'gone' });
  pull(50);
  await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  expect(runner.tasks[0]!.resumeSession).toBeUndefined();
  expect(eventTypes(db)).toEqual(['session_rebuilt']);
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
  const down = new GitHubUnavailable('network', 'down');
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
  const base = { epicId: 1, stage: 'ship' as const, resultPath: '/r', startedAt: 5 * MIN };
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'timeout', needsHumanReason: 'the ship execution exceeded the time limit of 4 h (limits.maxExecutionHours) · session and worktree are kept: raise the limit or set it to "unlimited", then resume the epic' });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
  const config = [{ name: 'AshuLab/a', agents: { ...agents, reviewer: { profile: 'rev', option: 'o', harness: 'codex' as const, model: 'r' } } }];
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

test('the reviewer is told the commit its checkout was made at, and a result that carries another head is invalid and retried', async () => {
  const checkout = 'c'.repeat(40);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headSha: checkout });
  let attempt = 0;
  runner.behavior = (task) =>
    task.stage === 'ship' ? { write: completed(task, { number: 50, headSha: checkout }) } : { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: ++attempt === 1 ? SHA : checkout }, verification: { ci: 'passed', evidence: 'ok' } }) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  const reviews = runner.tasks.filter((t) => t.stage === 'review');
  expect(reviews).toHaveLength(2);
  for (const task of reviews) expect(task.context.pr).toEqual({ number: 50, headSha: checkout });
  const [first, second] = executionsOf(engine.db).filter((e) => e.stage === 'review');
  expect(first).toMatchObject({ status: 'invalid_result', failureKind: 'invalid_result', headSha: checkout });
  expect(first!.error).toContain(`not ${checkout}`);
  expect(second).toMatchObject({ headSha: checkout, status: 'finished' });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: checkout });
});

test('a concluding review on the current head leaves the epic ready for test with the reviewed SHA and verification', async () => {
  const engine = await reviewing((task) => ({
    write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'pnpm test ok, repo without CI' } }),
  }));
  expect(rows(engine.db)[0]).toMatchObject({
    status: 'ready_for_test', reviewedSha: SHA, verification: { ci: 'absent', evidence: 'pnpm test ok, repo without CI' },
    finishedAt: 5 * MIN, labelPending: false, needsHumanReason: null,
  });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
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

const HEAD3 = 'd'.repeat(40);
const HEAD4 = 'e'.repeat(40);
// A reviewer whose run is made at the head it was given and, for each head in `pushes`, lands a commit while it works: the head GitHub has at its end is the next one.
const reviewedWhile = (pushes: string[], outcome: (task: AgentTask) => object = () => ({ outcome: 'completed', verification: { ci: 'passed', evidence: 'ok' } })) => (task: AgentTask) => {
  const next = pushes.shift();
  if (next) pull(50, { headSha: next });
  return { write: result(task, { ...outcome(task), pr: { number: 50, headSha: task.context.pr!.headSha } }) };
};

test('a head that moved during the review is reviewed again on the new head, counting no round, and the epic is ready on the head that was reviewed', async () => {
  const engine = await reviewing(reviewedWhile([HEAD2]));
  expect(runner.tasks.map((t) => [t.stage, t.context.round, t.context.pr?.headSha])).toEqual([['ship', undefined, undefined], ['review', 1, SHA], ['review', 1, HEAD2]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, prHeadSha: HEAD2, reviewedSha: HEAD2, headRepeats: 0, labelPending: false });
  expect(eventsOf(engine.db)).toMatchObject([{ epicId: 1, type: 'review_repeated', data: { round: 1, from: SHA, to: HEAD2, repeats: 1 } }]);
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
  // the superseded execution says so in its own events, which the app reads
  const [superseded] = executionsOf(engine.db).filter((e) => e.stage === 'review');
  expect(engine.db.select().from(executionEvents).where(eq(executionEvents.executionId, superseded!.executionId)).all()).toMatchObject([{ kind: 'note', payload: { text: expect.stringContaining(`from ${SHA} to ${HEAD2}`) } }]);
});

test('a third moved head in a row stops the epic in pr_invalid, never ready, with the count saved and each repeat an event', async () => {
  const engine = await reviewing(reviewedWhile([HEAD2, HEAD3, HEAD4]));
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'pr_invalid', round: 1, headRepeats: 2, reviewedSha: null });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('changed during the review 3 times in a row');
  expect(eventsOf(engine.db).filter((e) => e.type === 'review_repeated').map((e) => e.data)).toMatchObject([{ from: SHA, to: HEAD2, repeats: 1 }, { from: HEAD2, to: HEAD3, repeats: 2 }]);
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
});

test('the review that hits the cap of repeats is superseded too: a resume at review never reads its verdict or its blockers', async () => {
  const engine = await reviewing(reviewedWhile([HEAD2, HEAD3, HEAD4], () => ({ outcome: 'changes_requested', blockers: [{ title: 'about a head that is gone' }] })));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'pr_invalid', headRepeats: 2 });
  expect(engine.db.select().from(callerResults).all().map((r) => r.outcome)).toEqual(['completed', 'superseded', 'superseded', 'superseded']); // the ship result, then the three reviews
  expect(latestBlockers(engine.db, rows(engine.db)[0]!)).toEqual([]);
  expect((await epicOf(engine.db, 'AshuLab/a', 1))?.rounds).toEqual([]); // no round of its own either
});

test('the count of repeats starts again when a review completes on its own head', async () => {
  // two repeats, then a review that completes on its own head with changes
  const pushes = [HEAD2, HEAD3];
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { sessionId: 's-ship', write: completed(task) };
    if (task.stage === 'fix') {
      pull(50, { headSha: HEAD4 });
      return fixDone(task, HEAD4);
    }
    return task.context.round === 2 ? { exit: 'stopped' } : reviewedWhile(pushes, () => ({ outcome: 'changes_requested', blockers: [{ title: 'x' }] }))(task);
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'review', 'fix', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ round: 2, stage: 'review', headRepeats: 0 });
});

test('a restart of the epic clears the count of repeats', async () => {
  const engine = await reviewing(reviewedWhile([HEAD2, HEAD3, HEAD4]));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', headRepeats: 2 });
  runner.behavior = () => ({ exit: 'hang' });
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', headRepeats: 0 });
});

test('the result of a review of a superseded head is kept but its blockers and summary never reach the next round', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let reviews = 0;
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { sessionId: 's-ship', write: completed(task) };
    if (task.stage === 'fix') return fixDone(task);
    reviews++;
    const asking = (extra: object) => ({ write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: task.context.pr!.headSha }, ...extra }) });
    if (reviews === 1) return asking({ blockers: [{ title: 'answered in round 1' }], summary: 'round 1 summary' });
    if (reviews === 2) {
      pull(50, { headSha: HEAD2 }); // a push lands during the round 2 review, which asks for changes on the head it saw
      return asking({ blockers: [{ title: 'about a head that is gone' }], summary: 'stale summary' });
    }
    return { exit: 'stopped' };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => [t.stage, t.context.round])).toEqual([['ship', undefined], ['review', 1], ['fix', 1], ['review', 2], ['review', 2]]);
  const [, , , superseded, again] = runner.tasks as AgentTask[];
  expect(superseded!.context.blockers).toEqual([{ title: 'answered in round 1' }]);
  expect(again!.context).toMatchObject({ round: 2, pr: { number: 50, headSha: HEAD2 }, blockers: [{ title: 'answered in round 1' }], previousSummaries: ['round 1 summary', 'done'] });
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review').map((e) => e.status)).toEqual(['finished', 'finished', 'interrupted']);
  expect(engine.db.select().from(callerResults).all().map((r) => r.outcome)).toEqual(['completed', 'changes_requested', 'completed', 'superseded']);
});

test('a review after one that completed gets no blockers, even when an earlier round asked for changes; a review after one that asked for changes still gets its blockers', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { sessionId: 's-ship', write: completed(task) };
    const head = task.context.pr?.headSha ?? SHA;
    if (task.stage === 'fix') {
      if (task.context.observations) pull(50, { headSha: HEAD2 }); // the pass commits
      return fixDone(task, task.context.observations ? HEAD2 : head);
    }
    // round 1 asks for changes, round 2 completes with observations (the pass), round 3 is the review after the pass
    if (task.context.round === 1) return { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: head }, blockers: [{ title: 'answered in round 1' }] }) };
    if (task.context.round === 2) return { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: head }, verification: reviewerVerification, observations: [{ title: 'a nitpick' }] }) };
    return { exit: 'stopped' };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks.map((t) => [t.stage, t.context.round])).toEqual([['ship', undefined], ['review', 1], ['fix', 1], ['review', 2], ['fix', 2], ['review', 3]]);
  expect(runner.tasks[3]!.context.blockers).toEqual([{ title: 'answered in round 1' }]);
  expect(runner.tasks[5]!.context.blockers).toEqual([]);
});

test('a needs_human review, an inconclusive one included, stops the epic with its reason', async () => {
  const engine = await reviewing((task) => ({ write: result(task, { outcome: 'needs_human', reason: 'inconclusive review: missing context' }) }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'inconclusive review: missing context', reviewedSha: null });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
});

test('ship, review and fix carry the persona of their role: the author\'s for ship and fix, the reviewer\'s for review', async () => {
  const personas = { author: { name: 'Ada', prompt: 'Be terse.' }, reviewer: { name: 'Rex' } };
  const config = repos.map((r) => ({ ...r, agents: { author: { ...agents.author, persona: personas.author }, reviewer: { ...agents.reviewer, persona: personas.reviewer } } }));
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }) }
    : { exit: 'stopped' };
  const engine = await start(1, config);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => [t.stage, t.persona])).toEqual([['ship', personas.author], ['review', personas.reviewer], ['fix', personas.author]]);
});

test.each([[true], [false]])('with sharedIdentity %s in the epic\'s config the task carries it in ship, review and fix', async (expected) => {
  const config = repos.map((r) => ({ ...r, sharedIdentity: expected }));
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) }
    : task.stage === 'review' ? { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }) }
    : { exit: 'stopped' };
  const engine = await start(1, config);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => [t.stage, t.sharedIdentity])).toEqual([['ship', expected], ['review', expected], ['fix', expected]]);
});

test('the skills of the repo are saved with the epic when it is reserved; a row saved without them reads Solve\'s defaults', async () => {
  const named = resolveSkills(solveSkills, { fix: 'my-fix' });
  github.ready = { 'AshuLab/a': ready(1), 'AshuLab/b': ready(2) };
  runner.behavior = () => ({ exit: 'stopped' });
  const engine = await start(2, [{ ...repos[0]!, skills: named }, repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();

  const [withSkills, without] = rows(engine.db).sort((x, y) => x.repo.localeCompare(y.repo));
  expect(withSkills!.config!.skills).toEqual(named);
  expect(savedSkills(withSkills!.config).fix).toEqual({ name: 'my-fix', named: true });
  expect(without!.config!.skills).toBeUndefined();
  expect(savedSkills(without!.config)).toEqual(defaultSkills);
});

test('the extra reviewers and the lead\'s skills are saved with the epic when it is reserved, a reload changes nothing for it, and an epic saved before reads one reviewer and no lead', async () => {
  const extra = { profile: 'c', option: 'o', harness: 'claude' as const, model: 'm', skills: resolveReviewSkills('review', solveSkills, undefined, { review: 'my-review' }) };
  const withExtras = (extraReviewers: (typeof extra)[], lead = resolveReviewSkills('lead', solveSkills, undefined, { review: 'my-lead' })): EffectiveRepoConfig => ({
    ...repos[0]!,
    agents: { ...agents, leadReviewer: { profile: 'd', option: 'o', harness: 'claude', model: 'm' }, extraReviewers },
    skills: { ...resolveSkills(solveSkills), lead },
  });
  github.ready = { 'AshuLab/a': ready(1), 'AshuLab/b': ready(2) };
  runner.behavior = () => ({ exit: 'stopped' });
  const engine = await start(2, [withExtras([extra]), repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();
  const saved = () => Object.fromEntries(rows(engine.db).map((row) => [row.repo, row.config!]));

  expect(saved()['AshuLab/a']!.agents.extraReviewers).toEqual([extra]);
  expect(saved()['AshuLab/a']!.skills!.lead).toEqual({ review: { name: 'my-lead', named: true }, publish: { name: 'code-post', named: false } });
  const before = structuredClone(saved()['AshuLab/a']);

  reload(engine, { repos: [withExtras([], resolveReviewSkills('lead', solveSkills, undefined, { review: 'other' })), repos[1]!] });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(saved()['AshuLab/a']).toEqual(before);

  expect(saved()['AshuLab/b']!.agents.extraReviewers).toBeUndefined();
  expect(savedSkills(saved()['AshuLab/b']!).lead).toBeUndefined();
});

test('the tasks carry the skills the epic was saved with: a reload while it runs changes nothing, a restart from ship takes the new ones', async () => {
  const before = resolveSkills(solveSkills, { ship: 'build', fix: 'my-fix' });
  const after = resolveSkills(solveSkills, { ship: 'build-two', review: { review: 'my-review', publish: null } });
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let engine: Awaited<ReturnType<typeof start>>;
  runner.behavior = (task) => {
    if (task.stage === 'ship' && runner.tasks.length === 1) {
      reload(engine, { repos: [{ ...repos[0]!, skills: after }, repos[1]!] }); // while the epic runs
      return { write: completed(task) };
    }
    return task.stage === 'review' ? { write: result(task, { outcome: 'needs_human', reason: 'unclear' }) } : { exit: 'stopped' };
  };
  engine = await start(1, [{ ...repos[0]!, skills: before }, repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks.map((t) => [t.stage, t.skills])).toEqual([['ship', before], ['review', before]]);

  github.issue('AshuLab/a', 1).labels.push('solve:epic:ready'); // restarted from ship
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks.at(-1)).toMatchObject({ stage: 'ship', skills: after });
});

test('the task of an epic saved without skills reads Solve\'s defaults', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'stopped' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]!.config!.skills).toBeUndefined();
  expect(runner.tasks[0]!.skills).toEqual(defaultSkills);
});

// --- skill_missing: a skill the person named that the role's harness does not find ---

const namedShip = resolveSkills(solveSkills, { ship: 'my-ship' });
const namedFix = resolveSkills(solveSkills, { fix: 'my-fix' });
const namedReview = resolveSkills(solveSkills, { review: { review: 'my-review', publish: 'my-post' } });
const skillStop = (engine: Awaited<ReturnType<typeof start>>) => rows(engine.db)[0]!;
// A resume that stops again at once: the command sees no restart.
const resumeStopping = async (engine: Awaited<ReturnType<typeof start>>, options: Parameters<typeof engine.resumeEpic>[2]) => {
  const resumed = refusal(engine.resumeEpic('AshuLab/a', 1, options));
  await flush();
  await clock.advance(60_000);
  expect(await resumed).toBe('did not restart');
};
// The requeue freezes the repo's configuration again, so the skills must be in the one the engine runs with.
const watching = (skillsOf: ReturnType<typeof resolveSkills>) => { watched = watched.map((repo) => ({ ...repo, skills: skillsOf })); };

test.each([
  ['codex', /^the skill my-ship \(skills\.ship\) is not installed for the author: codex looked where it finds skills, in the account folder .*~\/\.agents\/skills.*\/etc\/codex\/skills and its plugin cache/],
  ['agy', /^the skill my-ship \(skills\.ship\) is not installed for the author: agy looked where it finds skills, in the repo \(.*\), ~\/\.gemini and the plugins it lists/],
] as const)('the stop of a %s author names the places that harness reads', async (harness, reason) => {
  skills.answers['my-ship'] = 'absent';
  github.ready = { 'AshuLab/a': ready(1) };
  const author = { ...agents.author, harness };
  const engine = await start(1, [{ ...repos[0]!, agents: { ...agents, author }, skills: namedShip }, repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(skillStop(engine).needsHumanReason).toMatch(reason);
});

test('an epic whose named ship skill is absent stops with skill_missing before any execution, naming the skill, the role and where it looked', async () => {
  skills.answers['my-ship'] = 'absent';
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1, [{ ...repos[0]!, skills: namedShip }, repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks).toEqual([]);
  expect(executionsOf(engine.db)).toEqual([]);
  expect(retriesOf(engine.db)).toEqual([]);
  expect(skillStop(engine)).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
  expect(skillStop(engine).needsHumanReason).toMatch(/^the skill my-ship \(skills\.ship\) is not installed for the author: claude looked where it finds skills, in the account folder .*the repo \(/);
  expect(skills.asked[0]).toMatchObject({ harness: 'claude', name: 'my-ship' });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
});

test('the skill_missing stop has its own reason label when the person names one', async () => {
  skills.answers['my-ship'] = 'absent';
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1, [{ ...repos[0]!, skills: namedShip }, repos[1]!]);
  settings = { ...settings, labels: { ...defaultLabels, reasons: { skill_missing: 'carrier:reason:skill-missing' } } };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human', 'carrier:reason:skill-missing']);
});

test('the check covers every skill the role invokes: a named fix skill stops the epic before ship, and the reviewer checks review and publish', async () => {
  skills.answers['my-fix'] = 'absent';
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1, [{ ...repos[0]!, skills: namedFix }, repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(runner.tasks).toEqual([]);
  expect(skillStop(engine)).toMatchObject({ needsHumanKind: 'skill_missing' });
  expect(skillStop(engine).needsHumanReason).toContain('my-fix (skills.fix)');

});

test('the reviewer is asked on its own harness for the skills of review and publish, and an absent named publish skill stops the resume', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  watching(namedReview);
  skills.answers['my-post'] = 'absent';
  await resumeStopping(engine, { from: 'review' });

  expect(skills.asked.map((a) => [a.harness, a.name])).toEqual([['codex', 'my-review'], ['codex', 'my-post']]);
  expect(runner.tasks).toEqual([]);
  expect(skillStop(engine)).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
  expect(skillStop(engine).needsHumanReason).toContain('my-post (skills.review.publish) is not installed for the reviewer');
});

test('a resume from a stage stops with skill_missing when the named skill is absent, and goes on once the person installed it', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'fix');
  watching(namedFix);
  skills.answers['my-fix'] = 'absent';
  await resumeStopping(engine, { from: 'fix' });
  expect(runner.tasks).toEqual([]);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'fix')).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });

  skills.answers = {}; // installed
  await resumeFrom(engine, 'fix');
  expect(runner.tasks.map((t) => t.stage)).toEqual(['fix']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', needsHumanKind: null });
});

test('after the person installs the skill, resuming a first launch goes on', async () => {
  skills.answers['my-ship'] = 'absent';
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1, [{ ...repos[0]!, skills: namedShip }, repos[1]!]);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(skillStop(engine)).toMatchObject({ needsHumanKind: 'skill_missing' });

  skills.answers = {};
  runner.behavior = () => ({ exit: 'hang' });
  await resumeFrom(engine);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']);
  expect(skillStop(engine)).toMatchObject({ status: 'running', stage: 'ship' });
});

test('a failover onto an option whose harness lacks a named skill stops the epic with skill_missing, spending no run on it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => outOf('claude')(task, { exit: 'hang' });
  skills.has = async (harness) => (harness === 'agy' ? 'absent' : 'present');
  const engine = await startWith(failoverRepos({ author: [{ provider: 'spare' }] }).map((repo) => ({ ...repo, skills: namedShip })));
  await engine.idle();

  expect(runner.tasks.map((t) => t.option)).toEqual(['claude']);
  expect(skillStop(engine)).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
  expect(skillStop(engine).needsHumanReason).toContain('agy looked where it finds skills');
  expect(executionsOf(engine.db)).toHaveLength(1);
});

test('restarting on another option checks the skills for that option\'s harness', async () => {
  const engine = await stoppedOnCodex();
  watching(namedShip);
  skills.has = async (harness) => (harness === 'claude' ? 'absent' : 'present');
  await resumeStopping(engine, { author: 'claude' });

  expect(runner.tasks).toHaveLength(1); // only the first run, before the stop
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });

  skills.has = async () => 'present';
  await restartWith(engine, { author: 'claude' });
  expect(runner.tasks.map((t) => t.option)).toEqual(['codex', 'claude']);
});

test('a wake-up stops with skill_missing when the named skill is absent, and starts no run', async () => {
  const engine = await stoppedForQuota();
  reload(engine, { repos: quotaRepos().map((repo) => ({ ...repo, skills: namedShip })) });
  skills.answers['my-ship'] = 'absent';
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(WAKE - clock.now() + 5 * MIN);

  expect(shipTasks()).toBe(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing', autoResumes: 1 });
});

test.each([
  ['a named skill the check cannot tell', namedShip, 'cannot-tell'],
  ['a named skill that is present', namedShip, 'present'],
  ['Solve\'s default ship skill that is absent', resolveSkills(solveSkills), 'absent'],
  ['Solve\'s default ship skill the check cannot tell', resolveSkills(solveSkills), 'cannot-tell'],
] as const)('%s never stops the epic', async (_, config, answer) => {
  skills.has = async () => answer;
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1, [{ ...repos[0]!, skills: config }, repos[1]!]);
  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']);
  expect(skillStop(engine)).toMatchObject({ status: 'running', needsHumanKind: null });
});

test('only the skills the person named are asked about: a default is never looked for', async () => {
  skills.answers['code-resolve'] = 'absent';
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'hang' });
  await start(1, [{ ...repos[0]!, skills: namedShip }, repos[1]!]);
  await clock.advance(5 * MIN);
  expect(skills.asked.map((a) => a.name)).toEqual(['my-ship']);
});

test('an epic resumed after the config changed keeps the sharedIdentity it started with', async () => {
  const shared = repos.map((r) => ({ ...r, sharedIdentity: true }));
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => (task.resumeSession ? { write: completed(task) } : { sessionId: 's-1', exit: 'failed' });
  const first = await start(1, shared);
  await clock.advance(5 * MIN);
  await first.idle();
  first.stop();
  const second = await start(1, repos); // the config no longer says shared
  await clock.advance(5 * MIN);
  await second.idle();

  expect(runner.tasks.length).toBeGreaterThan(1);
  expect(runner.tasks.every((t) => t.stage === 'ship' && t.sharedIdentity === true)).toBe(true);
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

test('a fix whose saved workspace is not on disk stops the epic in needs_human with kind workspace and the path, before any agent and with no retry spent', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  const gone = '/home/me/.solve/worktrees/a/demo';
  workspaces.findWorktree = async () => gone;
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { write: completed(task) };
    workspaces.missing.add(gone); // deleted while the review ran
    return { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }) };
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'workspace', needsHumanReason: `could not prepare the workspace: the saved workspace ${gone} does not exist` });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(executionsOf(engine.db).map((e) => e.stage)).toEqual(['ship', 'review']);
  expect(retriesOf(engine.db)).toEqual([]);
  expect(rows(engine.db)[0]?.recoveries).toBe(0);
});

test('a resume at fix whose saved workspace is not on disk stops the epic with kind workspace and launches no agent', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'fix');
  workspaces.missing.add('/w/epic');
  const resumed = refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'fix' }));
  await flush();
  await clock.advance(60_000);
  expect(await resumed).toBe('did not restart'); // it stopped again at once, so the command saw no restart

  expect(runner.tasks).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'workspace', needsHumanReason: 'could not prepare the workspace: the saved workspace /w/epic does not exist' });
  expect(retriesOf(engine.db)).toEqual([]);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'fix')).toEqual([]);
  expect(rows(engine.db)[0]?.recoveries).toBe(0);
});

test('the poll recovering a fix whose saved workspace is not on disk stops the epic with kind workspace and launches no agent', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'fix', round: 1, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic' });
  seedExecution(engine.db, 'r1', 1, { stage: 'review', status: 'finished' });
  engine.db.insert(callerResults).values({ executionId: 'r1', outcome: 'changes_requested', result: JSON.stringify({ summary: 's', blockers: [{ title: 'fix it' }] }) }).run();
  workspaces.missing.add('/w/epic');

  await clock.advance(5 * MIN);
  expect(runner.tasks).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'workspace', needsHumanReason: 'could not prepare the workspace: the saved workspace /w/epic does not exist' });
  expect(retriesOf(engine.db)).toEqual([]);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'fix')).toEqual([]);
  expect(rows(engine.db)[0]?.recoveries).toBe(0);
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

test('a ship result whose epic worktree is not among the worktrees of git sends the epic to needs_human with the branch, at once', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  runner.behavior = (task) => ({ write: completed(task, { number: 50, headSha: SHA }) });
  let asked = 0;
  workspaces.findWorktree = async () => (asked++, null);
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db).map((e) => [e.status, e.needsHumanKind, e.needsHumanReason, e.workspace, e.prNumber])).toEqual([
    ['needs_human', 'workspace', 'could not find the worktree for branch feat/demo/epic in the clone of AshuLab/a', null, null],
  ]);
  expect(asked).toBe(1);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']);
});

test('an error of git worktree list after ship leaves the result to be settled again, and the epic goes on once git answers', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task, { number: 50, headSha: SHA }) } : { exit: 'hang' });
  let asked = 0;
  workspaces.findWorktree = async () => {
    if (++asked <= 3) throw new Error('git broke');
    return '/home/me/.solve/worktrees/a/demo';
  };
  const engine = await start(1);
  for (let i = 0; i < 5; i++) await clock.advance(5 * MIN);

  expect(asked).toBe(4);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', workspace: '/home/me/.solve/worktrees/a/demo', needsHumanKind: null });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
});

test('the fourth error of git worktree list after ship stops the epic with kind workspace, never engine_error', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50, { headRef: 'feat/demo/epic' });
  runner.behavior = (task) => ({ write: completed(task, { number: 50, headSha: SHA }) });
  let asked = 0;
  workspaces.findWorktree = async () => {
    asked++;
    throw new Error('git broke');
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' }); // the first three leave it to be settled again

  for (let i = 0; i < 5; i++) await clock.advance(5 * MIN);
  await engine.idle();

  expect(asked).toBe(4);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'workspace', needsHumanReason: 'could not list the worktrees of the clone of AshuLab/a after 4 attempts: git broke', prNumber: null });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']);
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
      done: new Promise((resolve) => (finish = (exit) => resolve(exit === 'failed' ? { exit, failure: { ...killedBy, kind: 'crashed', detail: 'exit code 1', exitCode: 1, signal: null } } : { exit }))),
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
  expect(readFileSync(join(dir, 'engine', 'logs', 'executions', runner.tasks[0]!.executionId, 'stdout.log'), 'utf8')).toBe('a\nb\n'); // every chunk is logged, only the write is limited

  finish('failed');
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2)); // the retry
  expect(row()).toMatchObject({ lastError: 'the agent process ended with an error (crashed: exit code 1)', stage: 'ship', stageStartedAt: 5 * MIN });
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
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'invalid_result', failureKind: 'invalid_result', ...noProcess });
  expect(executionsOf(engine.db)[0]!.failureDetail).toBe(executionsOf(engine.db)[0]!.error);
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
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
});

test('a pass that ends with the reviewed head sends the epic to ready for test with the reviewed head and the reviewer\'s verification', async () => {
  const engine = await passing((task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'the author says so' } }) }));
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'fix']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, verification: reviewerVerification, finishedAt: 5 * MIN, labelPending: false });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
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

test('a pass after which the head moved and the next review listed new observations: ready for test, two left, the pass was already taken', async () => {
  const engine = await passing(
    (task) => {
      pull(50, { headSha: HEAD2 });
      return fixDone(task, HEAD2);
    },
    { later: (task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: HEAD2 }, verification: reviewerVerification, observations: [{ title: 'again' }, { title: 'and again' }] }) }) },
  );
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', observationsPassAt: 5 * MIN, unansweredObservations: 2, unansweredReason: 'already_taken' });
});

test('observations left at the last round the cap allows: ready for test with their count and last_round, no pass taken', async () => {
  const engine = await passing(() => ({ exit: 'stopped' }), { maxReviews: 1 });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', observationsPassAt: null, unansweredObservations: 2, unansweredReason: 'last_round' });
});

test('an epic whose pass answered the observations has no unanswered ones', async () => {
  const engine = await passing((task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'the author says so' } }) }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', unansweredObservations: null, unansweredReason: null });
});

test('a review completed with an empty list of observations goes to ready for test as before', async () => {
  const engine = await passing(() => ({ exit: 'stopped' }), { listed: [] });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, observationsPassAt: null, unansweredObservations: null, unansweredReason: null });
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'workspace', needsHumanReason: 'could not prepare the workspace: checkout failed' });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']); // no review run was spent
  expect(executionsOf(engine.db).map((e) => e.stage)).toEqual(['ship']);
});

test('a ready label that did not reach GitHub is retried on the next poll', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) =>
    task.stage === 'ship' ? { write: completed(task) } : { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } }) };
  const engine = await start(1);
  const setLabels = github.setLabels.bind(github);
  github.setLabels = async (repo, issue, change) => {
    if (change.add.includes('carrier:status:ready-for-test')) throw new GitHubUnavailable('network', 'down');
    return setLabels(repo, issue, change);
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', labelPending: true });

  github.setLabels = setLabels;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ labelPending: false });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
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

test('a merged epic has its worktrees and branches cleaned up once, and a failed clean-up is tried again at the next poll', async () => {
  const engine = await reviewingHung();
  const branch = rows(engine.db)[0]!.branch;
  workspaces.failCleanUp = new Error('git worktree remove failed');
  pull(50, { state: 'merged' });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged', cleanedAt: null }); // the failure blocks nothing

  workspaces.failCleanUp = null;
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(workspaces.cleanedUp).toEqual([{ repo: 'AshuLab/a', epic: 1, branch }]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged', cleanedAt: 15 * MIN });

  await clock.advance(5 * MIN);
  await engine.idle();
  expect(workspaces.cleanedUp).toHaveLength(1);
});

test('a clean-up that kept a worktree or a branch still marks the epic as cleaned, so it does not repeat, and what was kept is an event of the epic', async () => {
  const engine = await reviewingHung();
  workspaces.kept = ['/w/epic', 'feat/f1/001-x'];
  pull(50, { state: 'merged' });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged', cleanedAt: 10 * MIN });
  expect(eventsOf(engine.db).filter((e) => e.type === 'cleanup_kept')).toMatchObject([{ epicId: 1, at: 10 * MIN, data: { kept: ['/w/epic', 'feat/f1/001-x'] } }]);
  // The same read as the events reply of the epic's last execution.
  const last = executionsOf(engine.db).at(-1)!;
  expect(eventsReplyOf(engine.db, last.executionId, 0, 100)?.events.filter((e) => e.kind === 'note' && e.text?.includes('kept'))).toMatchObject([{ at: 10 * MIN, text: expect.stringContaining('/w/epic, feat/f1/001-x') }]);

  await clock.advance(5 * MIN);
  await engine.idle();
  expect(workspaces.cleanedUp).toHaveLength(1);
  expect(eventsOf(engine.db).filter((e) => e.type === 'cleanup_kept')).toHaveLength(1);
  expect(eventsReplyOf(engine.db, last.executionId, 0, 100)?.events.filter((e) => e.text?.includes('clean-up'))).toHaveLength(1);
});

test('epics that ended before the clean-up existed are caught up, and live or parked ones are never touched', async () => {
  github.ready = {};
  const engine = await start(0);
  for (const [issue, status] of [[1, 'merged'], [2, 'cancelled'], [3, 'ready_for_test'], [4, 'needs_human'], [5, 'repo_removed']] as const)
    engine.db.insert(epics).values({ repo: 'AshuLab/a', issue, status, branch: `feat/f${issue}/epic` }).run();
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(workspaces.cleanedUp.map((c) => [c.epic, c.branch])).toEqual([[1, 'feat/f1/epic'], [2, 'feat/f2/epic']]);
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelKind: 'issue_closed', cancelReason: 'the epic issue was closed without merging' });
});

test('a final PR closed without merge cancels the epic with the reason and stops its executions', async () => {
  const engine = await reviewingHung();
  pull(50, { state: 'closed' });
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelKind: 'pr_closed', cancelReason: 'the final PR #50 was closed without merging', finishedAt: 10 * MIN });
  expect(runner.stopped).toHaveLength(1);
  expect(labelsOf(1)).toEqual([]);
});

// --- an epic that ended outside Carrier is found with what the same poll read, and GitHub is asked only for what that poll did not bring ---

/** Epics parked in ready-for-test with a final PR, each listed as open and with its pull request block, as the poll reads them. */
async function parkedWithPullRequests(count: number, { listed = true }: { listed?: boolean } = {}) {
  const db = open();
  for (let n = 1; n <= count; n++) {
    seedEpic(db, n, { status: 'ready_for_test', stage: null, prNumber: 50 + n });
    pull(50 + n, {}, n);
    github.pullRequestBlocks[`AshuLab/a#${50 + n}`] = { number: 50 + n, url: `https://github.com/AshuLab/a/pull/${50 + n}`, draft: false, mergeState: 'CLEAN', reviewDecision: null, checks: null };
    github.issue('AshuLab/a', n).labels = ['solve:epic', 'carrier:status:ready-for-test'];
  }
  if (listed) github.openEpics = { 'AshuLab/a': Array.from({ length: count }, (_, i) => ({ issue: i + 1, slices: null })) };
  const engine = await start(0, [repos[0]!]);
  return { engine, getPullRequest: vi.spyOn(github, 'getPullRequest'), getIssue: vi.spyOn(github, 'getIssue') };
}

test('a poll reads the pull request of each live epic once and does not ask GitHub again for what it read', async () => {
  const { getPullRequest, getIssue } = await parkedWithPullRequests(3);
  github.pullRequestReads.length = 0;
  await clock.advance(5 * MIN);
  expect(github.pullRequestReads).toHaveLength(3); // one read per epic, the graphql that carries the state
  expect([getPullRequest.mock.calls.length, getIssue.mock.calls.length]).toEqual([0, 0]); // what used to be two more calls per epic
});

test('a pull request state read for the epic\'s old final PR does not end the epic whose PR is another one by the time it is decided', async () => {
  const { engine, getPullRequest } = await parkedWithPullRequests(1);
  pull(51, { state: 'merged' }, 1); // the old final PR is merged...
  pull(77, {}, 1);
  const read = github.readPullRequest.bind(github);
  vi.spyOn(github, 'readPullRequest').mockImplementation(async (repo, number) => {
    const answer = await read(repo, number);
    engine.db.update(epics).set({ prNumber: 77 }).where(eq(epics.issue, 1)).run(); // ...and a restart imported another one while the poll was reading
    return answer;
  });
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', prNumber: 77 });
  expect(getPullRequest).toHaveBeenCalledWith('AshuLab/a', 77); // asked about the PR it has now
});

test('a final PR that the poll read as merged ends the epic with no other question', async () => {
  const { engine, getPullRequest } = await parkedWithPullRequests(2);
  pull(51, { state: 'merged' }, 1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db).map((r) => r.status)).toEqual(['merged', 'ready_for_test']);
  expect(getPullRequest).not.toHaveBeenCalled();
});

test('an epic that the poll did not list as open is asked about: closed ends it, and one that only lost its label stays', async () => {
  const { engine, getIssue } = await parkedWithPullRequests(2);
  github.openEpics = { 'AshuLab/a': [] }; // neither is listed: `solve:epic` came off one, the other was closed
  github.issue('AshuLab/a', 2).state = 'closed';
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db).map((r) => r.status)).toEqual(['ready_for_test', 'cancelled']);
  expect([...new Set(getIssue.mock.calls.map((c) => c[1]))].sort()).toEqual([1, 2]);
});

test('with the open list unavailable the repo is skipped for the cycle and no live epic is asked about', async () => {
  const { getIssue } = await parkedWithPullRequests(2);
  github.openEpicsUnavailable = new GitHubUnavailable('network', 'down');
  await clock.advance(5 * MIN);
  expect(getIssue).not.toHaveBeenCalled();
});

test('with the pull request read unavailable the final PR is asked about, as before', async () => {
  const { engine, getPullRequest } = await parkedWithPullRequests(1);
  github.pullRequestUnavailable = new GitHubUnavailable('network', 'down');
  pull(51, { state: 'merged' }, 1);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(getPullRequest).toHaveBeenCalledOnce();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'merged' });
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
  expect(rows(engine.db)[0]).toMatchObject({ status: 'cancelled', cancelKind: 'issue_closed', cancelReason: 'the epic issue was closed without merging', finishedAt: 10 * MIN });
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
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
      throw new GitHubUnavailable('network', 'down');
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

// A check can arrive while the start recovers (the control socket opens before the recovery): it must wait for that recovery, not run a second one.
async function startWhileRecovering() {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'interrupted' });
  let open1!: () => void;
  const gate = new Promise<void>((resolve) => (open1 = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (await gate, `/work/${repo}/${epic}/author`);
  runner.behavior = () => ({ exit: 'hang' });
  settings = { pollIntervalMs: 5 * MIN, labels: defaultLabels, maxConcurrentEpics: 1, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, maxLeadRounds: 3, autoResume: false, autoResumeMaxHours: 12 };
  watched = repos;
  const engine = createEngine({ db, github, clock, repos: () => watched, settings: () => settings, profileDeclared: () => true, runner, workspaces, quota: fakeQuota.read, places: enginePlacesOf(dir), skills: new FakeSkills() });
  const started = engine.start();
  const checked = engine.pollNow();
  await settle();
  open1();
  await Promise.all([started, checked]);
  await settle();
  return engine;
}

test('a check asked while the start recovers shares that recovery: one agent per interrupted epic', async () => {
  const engine = await startWhileRecovering();
  expect(runner.tasks).toHaveLength(1);
  engine.stop();
});

test('a check asked while the start recovers leaves one chain of polls, not two', async () => {
  const engine = await startWhileRecovering();
  const before = github.calls;
  await clock.advance(5 * MIN);
  expect(github.calls - before).toBe(repos.length); // one listing per repo for the interval
  await clock.advance(5 * MIN);
  expect(github.calls - before).toBe(2 * repos.length);
  engine.stop();
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

test('the recovery at start ignores the executions of an earlier attempt: its last one is not this stop', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'ship', startedAt: 10 * MIN }); // restarted: the stage was claimed and no execution inserted before the cut
  seedExecution(db, 'old', 1, { stage: 'ship', status: 'interrupted', startedAt: 5 * MIN });
  await start(1);
  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]!.resumeSession).toBeUndefined(); // not the old execution continued
  expect(runner.tasks[0]!.context?.verifyStateFirst).toBeFalsy();
  expect(executionsOf(db).find((e) => e.executionId === 'old')!.status).toBe('interrupted');
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
  db.insert(callerResults).values({ executionId: 'old', outcome: 'changes_requested', result: JSON.stringify({ summary: 'round 1 findings', blockers: [] }) }).run();
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

test('an epic whose last execution ended on a usage limit before it moved on is stopped at start, not left running with no agent', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'failed', option: 'claude', failureKind: 'usage_limit', failureDetail: 'resets 12:40pm' });
  const engine = await start(1);
  await vi.waitFor(() => expect(rows(engine.db)[0]!.status).toBe('needs_human'));
  expect(rows(engine.db)[0]).toMatchObject({ needsHumanKind: 'usage_limit', needsHumanReason: 'the ship execution ran out of usage on option claude · carrier restart AshuLab/a#1 --author <option> · resets 12:40pm' });
  expect(runner.tasks).toHaveLength(0);
});

test('an epic stopped after service_down failure with failover enabled recovers and failsover on start', async () => {
  const db = open();
  const repoWithFailover = failoverRepos({ author: [{ provider: 'spare' }] });
  seedEpic(db, 1, { config: repoWithFailover[0] });
  seedExecution(db, 'e0', 1, { status: 'failed', option: 'claude', failureKind: 'api_error', failureDetail: 'ECONNREFUSED' });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1, repoWithFailover);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  expect(runner.tasks[0]).toMatchObject({ stage: 'ship', option: 'spare' });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', authorOption: 'spare' });
});

test('a requeued epic that has not launched yet is not stopped again by the usage limit of its old history', async () => {
  const db = open();
  seedEpic(db, 1, { stage: null });
  seedExecution(db, 'e0', 1, { status: 'failed', option: 'claude', failureKind: 'usage_limit', failureDetail: 'resets 12:40pm' });
  const engine = await start(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', needsHumanKind: null });
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
    'AshuLab/a#1': { state: 'open', labels: ['solve:epic:ready', 'carrier:status:ready-for-test', 'unrelated'] },
    'AshuLab/a#2': { state: 'open', labels: ['carrier:status:running'] },
    'AshuLab/a#3': { state: 'open', labels: [] },
  };
  await start(0);
  expect(labelsOf(1)).toEqual(['unrelated', 'carrier:status:running']);
  expect(labelsOf(2)).toEqual(['carrier:status:needs-human']);
  expect(labelsOf(3)).toEqual(['carrier:status:ready-for-test']);
});

// --- repo removed from the config ---

const githubRepoCalls = () => {
  const touched: string[] = [];
  for (const method of ['listOpenEpics', 'getIssue', 'getPullRequest', 'findPullRequest', 'setLabels', 'listLabels', 'createLabel'] as const) {
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
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: ['carrier:status:running'] }, 'AshuLab/a#3': { state: 'open', labels: ['carrier:status:needs-human'] } };
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
  expect(labelsOf(3)).toEqual(['carrier:status:needs-human']);
});

test('a repo configured again resumes its epics where they were, except the ones that needed a person', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA });
  seedExecution(db, 'e1', 1, { stage: 'review' });
  seedEpic(db, 2, { status: 'queued', stage: null, config: null, startedAt: null });
  seedEpic(db, 3, { status: 'needs_human', needsHumanReason: 'needs a decision' });
  seedEpic(db, 4, { status: 'queued', stage: null, config: null, startedAt: null });
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: ['carrier:status:running'] }, 'AshuLab/a#3': { state: 'open', labels: ['carrier:status:needs-human'] } };
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
  expect(labelsOf(3)).toEqual(['carrier:status:needs-human']);
});

test('a reload while the reviewer\'s workspace is being prepared does not launch the reviewer twice', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  workspaces.prepareReviewer = async (repo, epic, pr) => ({ path: (await gate, `/work/${repo}/${epic}/reviewer-${pr}`), commit: SHA });
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ stage: 'review' })); // the author is done and the reviewer waits for its workspace
  const checks = github.calls;

  reload(engine, { pollIntervalMs: MIN });
  await vi.waitFor(() => expect(github.calls).toBeGreaterThan(checks)); // the check the reload asked for ran
  open();
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(1));
  await settle();

  expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(1);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review')).toHaveLength(1);
});

test('a repo removed while the author\'s workspace is prepared keeps its epic parked: no execution, no run, no label written after', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (await gate, `/work/${repo}/${epic}/author`);
  const engine = await start(1);
  void clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' })); // claimed, waiting for the workspace
  const touched = githubRepoCalls();

  reload(engine, { repos: [repos[1]!] });
  open();
  await settle();
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'repo_removed', removedFrom: 'running' });
  expect(runner.tasks).toEqual([]);
  expect(executionsOf(engine.db)).toEqual([]);
  expect(touched.filter((c) => c.endsWith('AshuLab/a'))).toEqual([]);
});

test('a repo removed while a finished run\'s result is being imported keeps its epic where it was, and adding it back imports the result', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  const found = github.getPullRequest.bind(github);
  let asked = 0;
  github.getPullRequest = async (repo, number) => (asked++, await gate, found(repo, number));
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'hang' });
  const engine = await start(1);
  void clock.advance(5 * MIN);
  await vi.waitFor(() => expect(asked).toBe(1)); // the ship run is done and GitHub is being asked about its PR

  reload(engine, { repos: [repos[1]!] });
  open();
  await settle();
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'repo_removed', removedFrom: 'running', stage: 'ship', prNumber: null });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']); // no reviewer for a parked epic

  reload(engine, { repos });
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review'])); // back: the result is imported once and the reviewer starts
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', prNumber: 50 });
});

test('purges expired logs and sessions when the engine starts and every 24 hours after', async () => {
  const db = open();
  const old = db.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'merged', finishedAt: -30 * 24 * 60 * MIN }).returning().get();
  db.insert(executions).values({ executionId: 'x-old', epicId: old.id, stage: 'ship', sessionId: 's-old', resultPath: 'r', startedAt: 0 }).run();
  const logs = join(dir, 'engine', 'logs', 'executions', 'x-old');
  mkdirSync(logs, { recursive: true });
  const engine = createEngine({ db, github, clock, profileDeclared: () => true, repos: () => repos, settings: () => ({ pollIntervalMs: 5 * MIN, labels: defaultLabels, maxConcurrentEpics: 0, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, maxLeadRounds: 3, autoResume: false, autoResumeMaxHours: 12 }), runner, workspaces, quota: fakeQuota.read, places: enginePlacesOf(dir), skills: new FakeSkills() });
  await engine.start();
  expect(existsSync(logs)).toBe(false);
  mkdirSync(logs, { recursive: true });
  await clock.advance(24 * 60 * MIN);
  expect(existsSync(logs)).toBe(false);
  engine.stop();
});

// --- Forge authentication errors ---

test('a second auth_failed stops only the running epics of that profile and their runs; other profiles go on and nothing is relaunched', async () => {
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
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(labelsOf(2)).toEqual(['carrier:status:needs-human']);
  expect(labelsOf(3, 'AshuLab/b')).toEqual(['carrier:status:running']);
  // The run of epic 2 was stopped, the one of epic 3 was not.
  const taskOf = (epic: number) => runner.tasks.find((t) => t.epic === epic)!;
  expect(runner.stopped).toEqual([taskOf(2).executionId]);
  expect(executionsOf(engine.db).map((e) => [e.epicId, e.status])).toEqual([[1, 'failed'], [2, 'interrupted'], [3, 'running'], [1, 'failed']]);
  // The first signal was retried (and failed the same way); nothing is relaunched after the stop, nor under another profile.
  await clock.advance(10 * MIN);
  expect(runner.tasks.map((t) => [t.epic, t.profile])).toEqual([[1, 'a'], [2, 'a'], [3, 'c'], [1, 'a']]);
});

test('a second auth_failed of the reviewer profile stops the epic in review', async () => {
  const engine = await reviewing(() => ({ exit: 'auth_failed' }));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'authentication error for profile b' });
  expect(runner.tasks.map((t) => t.profile)).toEqual(['a', 'b', 'b']); // the first signal was retried
});

// ADR 0050: the first authentication signal of a profile is a technical failure that retries; the second stops the profile.
const authFailure = (detail: string): AgentFailure => ({ kind: 'auth', detail, exitCode: null, signal: null, hostFreeMemMb: null, hostLoad: null });
const notLoggedIn = 'Not logged in · Please run /login';
const runsOf = (epic: number) => runner.tasks.filter((t) => t.epic === epic);

test('a first authentication signal ends the execution as a technical failure retried at once with its message, and the other epics of the profile go on', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  runner.behavior = (task) => (task.epic === 1 && runsOf(1).length === 1 ? { sessionId: 's-1', exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { exit: 'hang' });
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runsOf(1)).toHaveLength(2)); // retried with no wait
  await vi.waitFor(() => expect(runsOf(2)).toHaveLength(1));
  expect(runsOf(1)[1]).toMatchObject({ stage: 'ship', resumeSession: 's-1' });
  expect(rows(engine.db)).toMatchObject([{ issue: 1, status: 'running', retryAt: null }, { issue: 2, status: 'running' }]);
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'failed', failureKind: 'auth', failureDetail: notLoggedIn, error: `authentication error for profile a: ${notLoggedIn}` });
  expect(runner.stopped).toEqual([]);
  expect(runsOf(2)).toHaveLength(1);
});

test('a second authentication signal in the retry of the same epic stops every epic of the profile with the message as the reason', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let release!: () => void;
  const bothStarted = new Promise<void>((resolve) => (release = resolve));
  runner.behavior = (task) => (task.epic === 1 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn), when: bothStarted } : { exit: 'hang' });
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runsOf(2)).toHaveLength(1));
  release();
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1, 2]));
  const reason = `authentication error for profile a: ${notLoggedIn}`;
  expect(rows(engine.db)).toMatchObject([{ needsHumanKind: 'auth', needsHumanReason: reason }, { needsHumanKind: 'auth', needsHumanReason: reason }]);
  expect(runsOf(1)).toHaveLength(2); // the second signal was not retried
  expect(runner.stopped).toEqual([runsOf(2)[0]!.executionId]);
});

test('a second authentication signal of the profile in another epic stops the epic that was retrying', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let release!: () => void;
  const firstRetrying = new Promise<void>((resolve) => (release = resolve));
  runner.behavior = (task) => {
    if (task.epic === 2) return { exit: 'auth_failed', failure: authFailure('401 again'), when: firstRetrying };
    return runsOf(1).length === 1 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { exit: 'hang' };
  };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runsOf(1)).toHaveLength(2));
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]); // the first signal stopped nothing
  release();
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1, 2]));
  expect(rows(engine.db).map((e) => e.needsHumanReason)).toEqual(['authentication error for profile a: 401 again', 'authentication error for profile a: 401 again']);
  expect(runner.stopped).toEqual([runsOf(1)[1]!.executionId]);
  expect(runsOf(2)).toHaveLength(1);
});

test('a signal that ends while the profile is being stopped does not bring its memory back: a restarted epic gets its first-signal retry', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let release!: () => void;
  const secondSignals = new Promise<void>((resolve) => (release = resolve));
  runner.behavior = (task) => {
    if (task.epic === 2) return { exit: 'auth_failed', failure: authFailure(notLoggedIn), when: secondSignals };
    if (runsOf(1).length === 1) return { exit: 'auth_failed', failure: authFailure(notLoggedIn) }; // the first signal of the profile
    return { exit: 'auth_failed', failure: authFailure(notLoggedIn), when: secondSignals };
  };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runsOf(1)).toHaveLength(2));
  release(); // the second signal of both epics arrives together
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1, 2]));
  await flush();
  runner.behavior = (task) => (runsOf(1).length === 3 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { exit: 'hang' });
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  await vi.waitFor(() => expect(runsOf(1)).toHaveLength(4)); // the single signal after the stop is retried, not a second one
  expect(byStatus(engine.db, 'running')).toEqual([1]);
});

test('an execution of the profile that ends with no authentication signal clears the memory, so a later single signal is a first one again', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let release!: () => void;
  const epicOneSettled = new Promise<void>((resolve) => (release = resolve));
  runner.behavior = (task) => {
    if (task.epic === 2) return runsOf(2).length === 1 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn), when: epicOneSettled } : { exit: 'hang' };
    if (runsOf(1).length === 1) return { exit: 'auth_failed', failure: authFailure(notLoggedIn) };
    return runsOf(1).length === 2 ? { exit: 'failed' } : { exit: 'hang' }; // the retry ends with no signal
  };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runsOf(1)).toHaveLength(3));
  release();
  await vi.waitFor(() => expect(runsOf(2)).toHaveLength(2)); // a first signal: retried
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]);
  expect(runner.stopped).toEqual([]);
});

test('after the profile stopped, a single signal of a person-restarted epic is a first one again', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'auth_failed', failure: authFailure(notLoggedIn) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1]));
  expect(runsOf(1)).toHaveLength(2);
  runner.behavior = (task) => (runsOf(1).length === 3 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { exit: 'hang' });
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  await vi.waitFor(() => expect(runsOf(1)).toHaveLength(4));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running' });
});

// The profile `x` in the roles that are not the author's, to see the rule across roles (ADR 0050, ADR 0048).
const asX = (agent: object) => ({ ...agent, profile: 'x' });
const reviewVerdict = (task: AgentTask, extra: object = ok): Behavior => ({ write: result(task, { ...extra, pr: { number: 50, headSha: task.context.pr!.headSha } }) });

test('the first signal of an extra reviewer is a failure of that execution retried like any other, and an execution of the profile in another role that ends with no signal clears the memory of a first one', async () => {
  const config = twoReviewers({ agents: { author: asX(agents.author), reviewer: agents.reviewer, extraReviewers: [asX(extraReviewer)] } as EffectiveRepoConfig['agents'] });
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const extraRuns = () => runner.tasks.filter((t) => t.reviewer === 'reviewer-2');
  runner.behavior = (task) => {
    if (task.stage === 'ship') return runsOf(1).filter((t) => t.stage === 'ship').length === 1 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { write: completed(task) }; // a first signal of x, then the author's end with none
    return task.reviewer === 'reviewer-2' && extraRuns().length === 1 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : reviewVerdict(task); // a first signal again, not a second
  };
  const engine = await start(1, [config]);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(extraRuns()).toHaveLength(2);
  expect(executionsOf(engine.db).find((e) => e.reviewer === 'reviewer-2')).toMatchObject({ status: 'failed', failureKind: 'auth', error: `authentication error for profile x: ${notLoggedIn}` });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test' });
  expect(runner.stopped).toEqual([]);
});

test('a second signal of a profile stops, with the kind auth, the running epics that use it in an extra reviewer or in the lead and their runs, and leaves the others alone', async () => {
  const configs = [
    { name: 'AshuLab/a', agents: { ...agents, extraReviewers: [asX(extraReviewer)] } },
    { name: 'AshuLab/b', agents: { ...agents, leadReviewer: asX({ option: 'o', harness: 'claude', model: 'm' }) } },
    { name: 'AshuLab/c', agents },
  ] as EffectiveRepoConfig[];
  github.ready = { 'AshuLab/a': ready(1), 'AshuLab/b': ready(2), 'AshuLab/c': ready(3) };
  pull(50);
  runner.behavior = (task) => {
    if (task.epic === 1 && task.stage === 'ship') return { write: completed(task) };
    if (task.reviewer === 'reviewer-2') return { exit: 'auth_failed', failure: authFailure(notLoggedIn) }; // the first signal retries, the second stops
    return { exit: 'hang' };
  };
  const engine = await start(3, configs);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db).map((e) => e.status)).toEqual(['needs_human', 'needs_human', 'running']));
  await vi.waitFor(() => expect(rows(engine.db).map((e) => e.labelPending)).toEqual([false, false, false]));
  await vi.waitFor(() => expect(runner.stopped).toHaveLength(2));

  const reason = `authentication error for profile x: ${notLoggedIn}`;
  expect(rows(engine.db)).toMatchObject([
    { status: 'needs_human', needsHumanKind: 'auth', needsHumanReason: reason, labelPending: false },
    { status: 'needs_human', needsHumanKind: 'auth', needsHumanReason: reason, labelPending: false },
    { status: 'running' },
  ]);
  expect(runsOf(1).map((t) => t.reviewer)).toEqual([undefined, 'reviewer', 'reviewer-2', 'reviewer-2']);
  const running = (epic: number) => runsOf(epic).filter((t) => t.reviewer !== 'reviewer-2').map((t) => t.executionId);
  expect(new Set(runner.stopped)).toEqual(new Set([...running(1).slice(1), ...running(2)])); // the epic that has the profile only in the lead stops its author, the third epic's run goes on
  expect(runsOf(3)).toHaveLength(1);
});

test('the stop of a profile that several slots of one epic use leaves the epic in needs-human once with one reason, and the memory of the signal goes only with all its runs', async () => {
  const config = twoReviewers({ agents: { author: agents.author, reviewer: asX(agents.reviewer), extraReviewers: [asX(extraReviewer)] } as EffectiveRepoConfig['agents'] });
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const { when, open } = lateOpen();
  let stopped = false;
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { write: completed(task) };
    if (stopped) return task.reviewer === 'reviewer' && runsOf(1).filter((t) => t.reviewer === 'reviewer').length === 3 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { exit: 'hang' };
    return { exit: 'auth_failed', failure: authFailure(notLoggedIn), when }; // both slots signal in the same turn: a first one and a second one
  };
  const engine = await start(1, [config]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2));
  open();
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1]));
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'auth', needsHumanReason: `authentication error for profile x: ${notLoggedIn}` });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(executionsOf(engine.db).filter((e) => e.status === 'running')).toEqual([]);

  // Forgotten with every run stopped: another epic of the profile gets the retry of a first signal.
  const other = { name: 'AshuLab/b', agents: { ...agents, author: asX(agents.author) } } as EffectiveRepoConfig;
  watched = [config, other];
  github.ready = { 'AshuLab/b': ready(2) };
  runner.behavior = (task) => (task.epic === 2 && runsOf(2).length === 1 ? { exit: 'auth_failed', failure: authFailure(notLoggedIn) } : { exit: 'hang' });
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runsOf(2)).toHaveLength(2));
  expect(rows(engine.db).map((e) => e.status)).toEqual(['needs_human', 'running']);
});

test('the reason an authentication stop keeps is redacted like the other reasons', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'auth_failed', failure: authFailure('rejected token ghp_abcDEF123456 for the account') });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1]));
  expect(rows(engine.db)[0]?.needsHumanReason).toBe('authentication error for profile a: rejected token [redacted] for the account');
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']);

  const attempts = github.attempts;
  await clock.advance(5 * MIN);
  expect(github.attempts).toBe(attempts + 1);
  expect(labelsOf(1)).toEqual(['carrier:status:running']);

  github.authError = null;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', labelPending: false });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
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
  expect(github.sliceReads).toEqual(['AshuLab/a#1', 'AshuLab/a#1']); // the start's read and the minute timer's, which fires as the poll does; epic 2 is still queued: no read
  expect(cached(engine.db)).toEqual([`1:10:closed@${5 * MIN}`, `1:11:waiting@${5 * MIN}`]);
});

test('the poll caches the slices of live epics, replacing them, and a finished epic keeps its last list', async () => {
  const engine = await runningWithSlices();
  github.sliceReads.length = 0;
  await clock.advance(5 * MIN);
  expect(github.sliceReads).toHaveLength(5 + 1); // the minute timer five times and the poll's own read, epic 2 never
  expect(new Set(github.sliceReads)).toEqual(new Set(['AshuLab/a#1']));
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

  github.slicesUnavailable = new GitHubUnavailable('network', 'down');
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

// --- slices: read again when the agent changes them, and every minute as a net ---

const claim = 'gh issue edit 10 --add-assignee @me';
// Epic 1 running with an agent that hangs, epic 2 queued; the clock is 10 s past the poll that started it, outside the window of its first read.
async function working() {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  github.slices = { 'AshuLab/a#1': { slices: [slice(10)] } };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await clock.advance(10_000);
  github.sliceReads.length = 0;
  const executionId = runner.tasks[0]!.executionId;
  const run = (callId: string, command: string, status: 'ok' | 'err' | null = 'ok') => {
    runner.emit(executionId, [{ kind: 'tool_start', callId, tool: 'Bash', arg: command }]);
    if (status) runner.emit(executionId, [{ kind: 'tool_end', callId, tool: 'Bash', status }]);
  };
  const states = () => cached(engine.db).map((r) => r.split('@')[0]);
  return { engine, run, states };
}
const settle = () => new Promise((resolve) => setTimeout(resolve, 0));

test('a command that changes the slices makes one read when it ends, and the stored rows change', async () => {
  const { run, states } = await working();
  github.slices['AshuLab/a#1'] = { slices: [slice(10, { state: 'in_progress' })] };
  run('c1', claim, null);
  await settle();
  expect(github.sliceReads).toEqual([]); // started: GitHub does not show it yet
  run('c1', claim);
  await settle();
  expect(github.sliceReads).toEqual(['AshuLab/a#1']);
  expect(states()).toEqual(['1:10:in_progress']);
});

test('a read slower than the window is followed by the next, never overlapped, and the newer rows stay', async () => {
  const { run, states } = await working();
  let open = () => {};
  github.slicesGate = new Promise<void>((resolve) => { open = resolve; });
  run('c1', claim); // reads the rows as they are now (ready) and waits for GitHub's answer
  await settle();
  github.slices['AshuLab/a#1'] = { slices: [slice(10, { state: 'in_progress' })] };
  await clock.advance(11_000); // outside the window of the first read, which has not answered yet
  run('c2', 'gh pr create');
  await settle();
  expect(github.sliceReads).toHaveLength(1); // the second waits for the first
  open();
  await settle();
  await settle();
  expect(github.sliceReads).toHaveLength(2);
  expect(states()).toEqual(['1:10:in_progress']);
});

test('a command that is not on the list makes no read, and one that ends in error makes it', async () => {
  const { run } = await working();
  run('c1', 'gh issue view 10');
  run('c2', 'git push -u origin x');
  await settle();
  expect(github.sliceReads).toEqual([]);
  run('c3', 'gh pr create --base x', 'err');
  await settle();
  expect(github.sliceReads).toEqual(['AshuLab/a#1']);
});

test('a burst of commands reads at most once every ten seconds and the last read sees the last change', async () => {
  const { run, states } = await working();
  run('c1', claim);
  await settle();
  expect(github.sliceReads).toHaveLength(1);
  github.slices['AshuLab/a#1'] = { slices: [slice(10, { state: 'in_progress' })] };
  run('c2', 'gh pr create');
  github.slices['AshuLab/a#1'] = { slices: [slice(10, { state: 'closed', closedAt: 1 })] };
  run('c3', 'gh pr merge 5');
  await settle();
  await clock.advance(9_999);
  expect(github.sliceReads).toHaveLength(1);
  await clock.advance(1);
  expect(github.sliceReads).toHaveLength(2); // one read for the two, at the end of the window
  expect(states()).toEqual(['1:10:closed']);
});

test('with no events the live epics are read every minute, and a finished one is not', async () => {
  const { engine } = await working();
  await clock.advance(50_000);
  expect(github.sliceReads).toEqual(['AshuLab/a#1']); // epic 2 is queued: not live
  await clock.advance(MIN);
  expect(github.sliceReads).toEqual(['AshuLab/a#1', 'AshuLab/a#1']);
  engine.db.update(epics).set({ status: 'merged' }).where(eq(epics.issue, 1)).run();
  await clock.advance(2 * MIN);
  expect(github.sliceReads).toHaveLength(2);
});

test('a failing read after a command keeps the last rows', async () => {
  const { run, states } = await working();
  const before = states();
  github.slicesUnavailable = new GitHubUnavailable('network', 'down');
  github.slices['AshuLab/a#1'] = { slices: [slice(99)] };
  run('c1', claim);
  await settle();
  expect(github.sliceReads).toEqual(['AshuLab/a#1']);
  expect(states()).toEqual(before);
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

  github.pullRequestUnavailable = new GitHubUnavailable('network', 'down');
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

  github.pullRequestUnavailable = new GitHubUnavailable('network', 'down');
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
  expect(labelsOf(1)).toEqual(['carrier:status:running']); // ready came off with the restart, put there by the engine first
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
  github.setLabelsUnavailable = new GitHubUnavailable('network', 'down');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1))).toBe('github unavailable');
  github.setLabelsUnavailable = null;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanReason: 'the CI is red' });
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  github.authError = new AuthError('orchestrator');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1))).toBe('github unavailable');
});

test('a resume asked while the start recovers waits for it up to thirty seconds, and a longer one is refused before the label goes on', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'interrupted' });
  seedEpic(db, 2, { status: 'needs_human' });
  let open1!: () => void;
  const gate = new Promise<void>((resolve) => (open1 = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (await gate, `/work/${repo}/${epic}/author`);
  runner.behavior = () => ({ exit: 'hang' });
  github.ready = { 'AshuLab/a': ready(2) };
  settings = { pollIntervalMs: 5 * MIN, labels: defaultLabels, maxConcurrentEpics: 2, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, maxLeadRounds: 3, autoResume: false, autoResumeMaxHours: 12 };
  watched = repos;
  const engine = createEngine({ db, github, clock, repos: () => watched, settings: () => settings, profileDeclared: () => true, runner, workspaces, quota: fakeQuota.read, places: enginePlacesOf(dir), skills: new FakeSkills() });
  const setLabels = vi.spyOn(github, 'setLabels');
  const started = engine.start();
  const refused = refusal(engine.resumeEpic('AshuLab/a', 2));
  await flush();
  await clock.advance(30_000); // the recovery is still going: the client would give up soon, so the resume says so now
  expect(await refused).toBe('did not restart');
  expect(setLabels).not.toHaveBeenCalledWith('AshuLab/a', 2, expect.anything()); // nothing was changed
  expect(rows(db).find((r) => r.issue === 2)).toMatchObject({ status: 'needs_human' });

  open1();
  await started;
  const resumed = engine.resumeEpic('AshuLab/a', 2); // the recovery is over: it has its own thirty seconds
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(db).find((r) => r.issue === 2)).toMatchObject({ status: 'running' });
  engine.stop();
});

test('resumeEpic on an epic that has not restarted thirty seconds after the label answers did not restart and leaves the label on', async () => {
  const engine = await stoppedEpic();
  github.unavailable = new GitHubUnavailable('network', 'down'); // the label goes on, the check cannot read
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

test('resumeEpic asks for one more check when the check that was running had listed before the label went on', async () => {
  const engine = await stoppedEpic();
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => (release = resolve));
  const listing = github.listOpenEpics.bind(github);
  let stale = true; // only the first poll reads before the label and answers after it
  github.listOpenEpics = async (repo, label) => {
    if (!stale) return listing(repo, label);
    const before = await listing(repo, label);
    await gate;
    return before;
  };
  github.issue('AshuLab/a', 1).labels = [];
  void engine.pollNow(); // the timer's poll, held after it read
  await flush();
  stale = false;
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  release();
  await flush();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' }); // the held poll never saw the label
  await clock.advance(1000); // the held poll has settled: the next tick asks for one more
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
});

test('resumeEpic while a check is already running does not start a second one and answers when that one restarts the epic', async () => {
  const engine = await stoppedEpic();
  let release: () => void = () => {};
  const gate = new Promise<void>((resolve) => (release = resolve));
  const listing = github.listOpenEpics.bind(github);
  let listed = 0;
  github.listOpenEpics = async (repo, label) => {
    listed++;
    await gate;
    return listing(repo, label);
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


// --- the choice of agent options ---

const claudeOption = { harness: 'claude' as const, model: 'opus', provider: 'ollama' as const };
const codexOption = { harness: 'codex' as const, model: 'gpt', configDir: '/cfg/codex' };
const choosing = (options: NonNullable<EffectiveRepoConfig['options']> = { claude: claudeOption, codex: codexOption }): EffectiveRepoConfig[] => [
  { name: 'AshuLab/a', options, providers: options as any, agents: { author: { profile: 'a', option: 'claude', ...claudeOption }, reviewer: { profile: 'b', option: 'codex', ...codexOption } } },
];
const choiceRefusal = (promise: Promise<void>) => promise.then(() => null, (e: ResumeRefused) => e.reason);

test('with two or more accounts a reserved epic starts its author at once, the account of each role recorded', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const engine = await start(1, choosing());
  await clock.advance(5 * MIN);

  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'claude']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', authorOption: 'claude', reviewerOption: 'codex' });
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
  expect(ids(engine)).toEqual(['AshuLab/a#2']);
  await clock.advance(MIN); // no timer of a choice firing later
  expect(runner.tasks).toHaveLength(1);
});

test('an epic sent back to the queue starts again at once on its roles', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'the CI is red' }) });
  const engine = await start(1, choosing());
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', authorOption: 'claude' });

  runner.behavior = () => ({ exit: 'hang' });
  github.issue('AshuLab/a', 1).labels = ['solve:epic:ready'];
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', authorOption: 'claude' });
});

// --- resumeEpic on the options chosen ---

// An epic with two options that stopped in needs_human with its author on codex, which wrote session s-1; the next ship hangs.
async function stoppedOnCodex() {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => ({ sessionId: 's-1', write: result(task, { outcome: 'needs_human', reason: 'the CI is red' }) });
  const [repo] = choosing();
  const engine = await start(1, [{ ...repo!, agents: { ...repo!.agents, author: { profile: 'a', option: 'codex', ...codexOption } } }]);
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', authorOption: 'codex', reviewerOption: 'codex' });
  runner.behavior = () => ({ exit: 'hang' });
  return engine;
}
async function restartWith(engine: Awaited<ReturnType<typeof stoppedOnCodex>>, chosen: { author?: string; reviewer?: string }) {
  const resumed = engine.resumeEpic('AshuLab/a', 1, chosen);
  await flush();
  await clock.advance(1000);
  await resumed;
}

test('resumeEpic without options keeps each role on its current option, asks nothing and continues the author session with --resume', async () => {
  const engine = await stoppedOnCodex();
  await restartWith(engine, {});
  expect(runner.tasks).toHaveLength(2);
  expect(runner.tasks[1]).toMatchObject({ stage: 'ship', option: 'codex', harness: 'codex', resumeSession: 's-1', workspace: runner.tasks[0]!.workspace });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', authorOption: 'codex', reviewerOption: 'codex' });
  expect(eventTypes(engine.db)).not.toContain('session_rebuilt');
});

test('resumeEpic with another author option launches it with no resumeSession, in the same worktree and with the pull request, and records the rebuild', async () => {
  const engine = await stoppedOnCodex();
  await restartWith(engine, { author: 'claude' });
  expect(runner.tasks).toHaveLength(2);
  expect(runner.tasks[1]).toMatchObject({ stage: 'ship', option: 'claude', harness: 'claude', provider: 'ollama', workspace: runner.tasks[0]!.workspace, context: { pr: { number: 50, headSha: SHA } } });
  expect(runner.tasks[1]!.resumeSession).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', authorOption: 'claude', reviewerOption: 'codex' });
  expect(rows(engine.db)[0]!.config!.agents.author).toMatchObject({ option: 'claude', harness: 'claude' });
  expect(executionsOf(engine.db).map((e) => e.option)).toEqual(['codex', 'claude']);
  expect(eventTypes(engine.db)).toEqual(['session_rebuilt', 'resumed']);
});

test('a GitHub error reading the pull request while restarting on another option leaves the epic unstarted, and the poll starts the epic on the chosen option once GitHub answers', async () => {
  const engine = await stoppedOnCodex();
  const find = github.findPullRequest.bind(github);
  let failures = 1;
  github.findPullRequest = async (...args) => {
    if (failures-- > 0) throw new GitHubUnavailable('network', 'down');
    return find(...args);
  };
  await restartWith(engine, { author: 'claude' });
  expect(runner.tasks).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: null, authorOption: 'claude' });

  await clock.advance(5 * MIN);
  expect(runner.tasks).toHaveLength(2);
  expect(runner.tasks[1]).toMatchObject({ stage: 'ship', option: 'claude', context: { pr: { number: 50, headSha: SHA } } });
  expect(runner.tasks[1]!.resumeSession).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', authorOption: 'claude' });
  expect(eventTypes(engine.db)).toEqual(['resumed', 'session_rebuilt']);
});

test('a resumeEpic that ends as did not restart forgets its choice: the epic restarted by a later check starts at once on its roles', async () => {
  const engine = await stoppedOnCodex();
  github.unavailable = new GitHubUnavailable('network', 'down'); // the label goes on, the check cannot read
  const resumed = refusal(engine.resumeEpic('AshuLab/a', 1, { author: 'claude' }));
  await flush();
  await clock.advance(30_000);
  expect(await resumed).toBe('did not restart');

  github.unavailable = null;
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', authorOption: 'codex' });
  expect(runner.tasks).toHaveLength(2);
});

test('resumeEpic with another reviewer option keeps the author on its session and stores the reviewer option', async () => {
  const engine = await stoppedOnCodex();
  await restartWith(engine, { reviewer: 'claude' });
  expect(runner.tasks[1]).toMatchObject({ option: 'codex', resumeSession: 's-1' });
  expect(rows(engine.db)[0]).toMatchObject({ authorOption: 'codex', reviewerOption: 'claude' });
  expect(rows(engine.db)[0]!.config!.agents.reviewer).toMatchObject({ option: 'claude', harness: 'claude' });
});

test('resumeEpic accepts an option declared after the epic was frozen: the requeue freezes it again from the configuration the engine runs with', async () => {
  const engine = await stoppedOnCodex();
  const [row] = rows(engine.db);
  const { claude: _added, ...frozen } = row!.config!.options!;
  engine.db.update(epics).set({ config: { ...row!.config!, options: frozen } }).where(eq(epics.id, row!.id)).run();
  await restartWith(engine, { author: 'claude' });
  expect(runner.tasks[1]).toMatchObject({ stage: 'ship', option: 'claude' });
});

test('resumeEpic with an option that is not declared is refused and changes nothing', async () => {
  const engine = await stoppedOnCodex();
  const before = rows(engine.db);
  const labels = labelsOf(1).slice();
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { author: 'nope' }))).toBe('unknown option');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { author: 'claude', reviewer: 'nope' }))).toBe('unknown option');
  expect(rows(engine.db)).toEqual(before);
  expect(labelsOf(1)).toEqual(labels);
});

// An epic with two extra reviewers and a lead, every role on codex.
const everyRole = (lead = true): EffectiveRepoConfig[] => {
  const on = (profile: string) => ({ profile, option: 'codex', ...codexOption });
  const dflt = { review: { name: 'code-review', named: false }, publish: null };
  const [base] = choosing();
  return [{ ...base!, agents: { author: on('a'), reviewer: on('b'), extraReviewers: [{ ...on('c'), skills: dflt }, { ...on('d'), skills: dflt }], ...(lead && { leadReviewer: on('e') }) } as unknown as EffectiveRepoConfig['agents'] }];
};

test('resumeEpic with an option for an extra reviewer and the lead runs that slot on it, records it in the event and keeps every other role of the epic', async () => {
  const engine = await start(1, everyRole());
  stoppedAt(engine.db, 'review', { config: everyRole()[0], authorOption: 'codex', reviewerOption: 'codex' });
  runner.behavior = () => ({ exit: 'stopped' }); // each reviewer is launched, so the whole round is seen
  const resumed = engine.resumeEpic('AshuLab/a', 1, { from: 'review', reviewer3: 'claude', lead: 'claude' });
  await flush();
  await clock.advance(1000);
  await resumed;

  const { agents } = rows(engine.db)[0]!.config!;
  expect([agents.author.option, agents.reviewer.option, ...agents.extraReviewers!.map((r) => r.option), agents.leadReviewer?.option]).toEqual(['codex', 'codex', 'codex', 'claude', 'claude']);
  expect(agents.extraReviewers!.map((r) => r.profile)).toEqual(['c', 'd']); // the profile of each role is its own
  expect(agents.leadReviewer).toMatchObject({ profile: 'e', harness: 'claude', model: 'opus' });
  await vi.waitFor(() => expect(runner.tasks.map((t) => [t.reviewer, t.option])).toEqual([['reviewer', 'codex'], ['reviewer-2', 'codex'], ['reviewer-3', 'claude']]));
  expect(eventsOf(engine.db).filter((e) => e.type === 'resumed').map((e) => e.data)).toEqual([{ from: 'review', by: 'command', options: { 'reviewer-3': 'claude', lead: 'claude' } }]);
});

test('resumeEpic that changes the author only still keeps the extra reviewers and the lead', async () => {
  const engine = await start(1, everyRole());
  stoppedAt(engine.db, 'fix', { config: everyRole()[0], authorOption: 'codex', reviewerOption: 'codex' });
  const resumed = engine.resumeEpic('AshuLab/a', 1, { author: 'claude' });
  await flush();
  await clock.advance(1000);
  await resumed;

  const { agents } = rows(engine.db)[0]!.config!;
  expect(agents.author).toMatchObject({ option: 'claude', harness: 'claude' });
  expect(agents.extraReviewers).toHaveLength(2);
  expect(agents.leadReviewer).toMatchObject({ profile: 'e', option: 'codex' });
});

test('resumeEpic refuses a slot the epic does not have and an option the repo does not declare, for each extra role, and changes nothing', async () => {
  const engine = await start(1, everyRole(false));
  stoppedAt(engine.db, 'review', { config: everyRole(false)[0] });
  const before = rows(engine.db);
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { reviewer4: 'claude' }))).toBe('no such role');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { lead: 'claude' }))).toBe('no such role');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { reviewer2: 'nope' }))).toBe('unknown option');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { reviewer2: 'claude', lead: 'nope' }))).toBe('unknown option'); // the name is checked first
  expect(rows(engine.db)).toEqual(before);
  expect(runner.tasks).toEqual([]);
});

// --- Reload ---

const reload = (engine: { reload: (swap: () => void) => void }, { repos: next, ...change }: Partial<EngineSettings> & { repos?: EffectiveRepoConfig[] }) =>
  engine.reload(() => {
    settings = { ...settings, ...change };
    if (next) watched = next;
  });

test('a reload re-arms the next poll from now with the new interval, and checks GitHub at once', async () => {
  const engine = await start();
  await clock.advance(2 * MIN);
  reload(engine, { pollIntervalMs: MIN });
  await vi.waitFor(() => expect(github.calls).toBe(2)); // both repos, now and not at 5 minutes
  await vi.waitFor(() => expect(engine.nextPollAt).toBe(3 * MIN));
  await clock.advance(MIN - 1);
  expect(github.calls).toBe(2);
  await clock.advance(1);
  expect(github.calls).toBe(4); // the new interval, not the 5 minutes the old timer had left
});

test('a reload asked while a poll runs does not double it: one more poll follows it, and the wait after is the new interval', async () => {
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  const listed = github.listOpenEpics.bind(github);
  let lists = 0;
  github.listOpenEpics = async (repo, label) => (lists++, await gate, listed(repo, label));
  const engine = await start();
  void clock.advance(5 * MIN); // the poll starts and waits on its first list
  await vi.waitFor(() => expect(lists).toBe(1));
  reload(engine, { pollIntervalMs: 2 * MIN });
  reload(engine, { pollIntervalMs: 2 * MIN });
  open();
  await vi.waitFor(() => expect(lists).toBe(4)); // two repos for the poll that was running, two for the one that follows it, once for two reloads
  await vi.waitFor(() => expect(engine.nextPollAt).toBe(7 * MIN)); // armed once, with the interval now in force
  await settle();
  expect(lists).toBe(4);
});

test('a repo a reload adds while a poll runs is read by the poll that follows it, not an interval later', async () => {
  github.ready = { 'AshuLab/b': ready(7) };
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  const listed = github.listOpenEpics.bind(github);
  let lists = 0;
  github.listOpenEpics = async (repo, label) => (lists++, await gate, listed(repo, label));
  const engine = await start(0, [repos[0]!]);
  void clock.advance(5 * MIN);
  await vi.waitFor(() => expect(lists).toBe(1)); // the poll lists the old repos
  reload(engine, { repos });
  open();
  await vi.waitFor(() => expect(ids(engine)).toEqual(['AshuLab/b#7']));
  expect(clock.now()).toBe(5 * MIN);
});

test('a reload that is refused leaves every setting as it was, rethrows the problem and checks nothing', async () => {
  const engine = await start(2);
  const before = settings;
  expect(() => engine.reload(() => { throw new ReloadRefused('Invalid config /c.json:\n  limits.maxReviews: Too small'); })).toThrow('limits.maxReviews');
  expect(settings).toBe(before);
  await clock.advance(5 * MIN - 1);
  expect(github.calls).toBe(0); // no check was asked for, and the timer is the one it was
});

test('a concurrency limit lowered below the epics running starts no new epic and stops none; raised, the next poll takes them', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]);

  reload(engine, { maxConcurrentEpics: 1 });
  await settle();
  expect(byStatus(engine.db, 'running')).toEqual([1, 2]);
  expect(runner.stopped).toEqual([]);

  engine.db.update(epics).set({ status: 'merged' }).where(eq(epics.issue, 1)).run();
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'running')).toEqual([2]); // one running, limit one: epic 3 waits

  reload(engine, { maxConcurrentEpics: 2 });
  await vi.waitFor(() => expect(byStatus(engine.db, 'running')).toEqual([2, 3]));
});

test('a run already launched keeps its timeout, and the next one launched has the new limit', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const engine = await start(1); // the fake runner's runs hang by default
  await clock.advance(5 * MIN);
  reload(engine, { maxExecutionHours: 9, maxConcurrentEpics: 2 });
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(runner.tasks.map((t) => [t.epic, t.timeoutMs])).toEqual([[1, 4 * 3_600_000], [2, 9 * 3_600_000]]);
  expect(engine.db.select().from(executions).all().map((e) => e.status)).toEqual(['running', 'running']); // epic 1's run was not touched
});

test('idleMinutes reaches the run as milliseconds; a reload applies it to the next run only, and absent it no run has one', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2, 3) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  reload(engine, { idleMinutes: 45, maxConcurrentEpics: 2 });
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  reload(engine, { idleMinutes: undefined, maxConcurrentEpics: 3 });
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));
  expect(runner.tasks.map((t) => [t.epic, t.idleMs])).toEqual([[1, undefined], [2, 45 * MIN], [3, undefined]]);
});

test('a process the watchdog killed is retried as a technical failure, resuming its session', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const idleKill = { kind: 'killed' as const, detail: 'no output for 2700 seconds', exitCode: null, signal: 'SIGTERM', hostFreeMemMb: 1, hostLoad: 1 };
  runner.behavior = (task) => (task.resumeSession ? { exit: 'hang' } : { sessionId: 's-1', exit: 'failed', failure: idleKill });
  const engine = await start(1);
  reload(engine, { idleMinutes: 45 });
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(runner.tasks[0]!.idleMs).toBe(45 * MIN);
  expect(runner.tasks[1]).toMatchObject({ resumeSession: 's-1', idleMs: 45 * MIN });
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'failed', failureKind: 'killed', failureDetail: 'no output for 2700 seconds' });
});

test('a timeout names the limit the run started with, not the one in force when it ended', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let end!: () => void;
  runner.behavior = () => ({ sessionId: 's-1', exit: 'timed_out', when: new Promise<void>((resolve) => (end = resolve)) });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  reload(engine, { maxExecutionHours: 9 });
  end();
  await engine.idle();
  expect(executionsOf(engine.db)[0]).toMatchObject({ status: 'timed_out', failureDetail: 'exceeded 4 h' });
});

test('the retry limit is the one in force when the failure is decided', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let fail!: () => void;
  runner.behavior = () => ({ sessionId: 's', exit: 'failed', failure: killedBy, when: new Promise<void>((resolve) => (fail = resolve)) });
  const engine = await start(1, repos, 4, 5);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  reload(engine, { maxExecutionRetries: 0 });
  fail();
  await engine.idle();
  expect(runner.tasks).toHaveLength(1); // no retry: the lowered limit was read at the failure
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'retries_exhausted' });
});

// --- Profiles that a reload removes ---

test('a profile removed while a running epic names it fails the next run naming it and stops the epic in needs_human; putting it back and restarting runs it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const declared = new Set(['a', 'b']); // what the credentials of the real runner look up: a missing profile is auth_failed
  let release!: () => void;
  const firstRunEnds = new Promise<void>((resolve) => (release = resolve));
  declaredProfile = (name) => declared.has(name);
  runner.behavior = (task) => (declared.has(task.profile) ? (runner.tasks.length === 1 ? { exit: 'failed', when: firstRunEnds } : { exit: 'hang' }) : { exit: 'auth_failed' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));

  declared.delete('a'); // the reload
  release();
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'auth', needsHumanReason: 'profile a was removed from the configuration: put it back, then restart the epic' }));
  expect(runner.tasks.map((t) => t.profile)).toEqual(['a', 'a']); // the retry was the run that failed, not another profile
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);

  declared.add('a');
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', needsHumanReason: null });
  expect(runner.tasks).toHaveLength(3);
});

test('a profile removed by a reload stops the epic whose run fails for it and not the other epics of that profile, whose runs go on', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  const declared = new Set(['a', 'b']);
  declaredProfile = (name) => declared.has(name);
  let release!: () => void;
  const firstRunEnds = new Promise<void>((resolve) => (release = resolve));
  runner.behavior = (task) => {
    if (!declared.has(task.profile)) return { exit: 'auth_failed' };
    return task.epic === 1 && runner.tasks.filter((t) => t.epic === 1).length === 1 ? { exit: 'failed', when: firstRunEnds } : { exit: 'hang' };
  };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));

  declared.delete('a'); // the reload
  release();
  await vi.waitFor(() => expect(byStatus(engine.db, 'needs_human')).toEqual([1]));
  await settle();
  expect(rows(engine.db).find((e) => e.issue === 1)).toMatchObject({ needsHumanKind: 'auth', needsHumanReason: 'profile a was removed from the configuration: put it back, then restart the epic' });
  expect(byStatus(engine.db, 'running')).toEqual([2]); // its run has the token it started with
  expect(runner.stopped).toEqual([]);
});

// --- Repos, roles and accounts that a reload changes ---

test('a repo removed by a reload parks its epics and stops its run without touching GitHub for it; added back, they resume where they were', async () => {
  github.ready = { 'AshuLab/a': ready(1), 'AshuLab/b': ready(2) };
  const engine = await start(2);
  await clock.advance(5 * MIN);
  github.ready = { 'AshuLab/a': ready(1, 4), 'AshuLab/b': ready(2) };
  await clock.advance(5 * MIN); // the slots are full: a#4 waits
  expect(byStatus(engine.db, 'running').sort()).toEqual([1, 2]);
  expect(ids(engine)).toEqual(['AshuLab/a#4']);
  const stopRun = executionsOf(engine.db).find((e) => e.epicId === rows(engine.db).find((r) => r.repo === 'AshuLab/a' && r.issue === 1)!.id)!.executionId;
  const touched = githubRepoCalls();

  reload(engine, { repos: [repos[1]!] });
  await vi.waitFor(() => expect(touched).toContain('listOpenEpics AshuLab/b')); // the check the reload asked for
  await vi.waitFor(() => expect(statusOf(engine.db, stopRun)).toBe('interrupted'));
  await settle();

  expect(rows(engine.db).map((e) => [e.repo, e.issue, e.status, e.removedFrom])).toEqual([
    ['AshuLab/a', 1, 'repo_removed', 'running'],
    ['AshuLab/b', 2, 'running', null],
    ['AshuLab/a', 4, 'repo_removed', 'queued'],
  ]);
  expect(runner.stopped).toEqual([stopRun]); // only the run of the removed repo
  expect(touched.filter((c) => c.endsWith('AshuLab/a'))).toEqual([]);
  expect(runner.tasks).toHaveLength(2);

  reload(engine, { repos });
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));
  expect(byStatus(engine.db, 'running').sort()).toEqual([1, 2]); // a#1 resumed on its stage, a#4 queued again behind the limit
  expect(ids(engine)).toEqual(['AshuLab/a#4']);
  expect(runner.tasks[2]).toMatchObject({ repo: 'AshuLab/a', epic: 1, stage: 'ship', context: { verifyStateFirst: true } });
  expect(eventTypes(engine.db).filter((t) => t === 'repo_restored')).toHaveLength(2);
});

test('a repo added by a reload is polled by the check the reload asks for and gets no labels until an epic is first labelled there', async () => {
  github.ready = { 'AshuLab/b': ready(7) };
  const engine = await start(0, [repos[0]!]);
  reload(engine, { repos });
  await vi.waitFor(() => expect(ids(engine)).toEqual(['AshuLab/b#7']));
  expect(github.created).toEqual([]); // labels come with the first label write on the repo (engine-start-is-quick), not with the reload
});

test('an epic that starts after a reload gets the new roles, and the running one keeps the ones it stored', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1, [repos[0]!]);
  await clock.advance(5 * MIN);
  github.ready = { 'AshuLab/a': ready(1, 2) };
  reload(engine, { maxConcurrentEpics: 2, repos: [{ name: 'AshuLab/a', agents: { ...agents, author: { ...agents.author, model: 'new-model' } } }] });
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  expect(runner.tasks.map((t) => [t.epic, t.model])).toEqual([[1, 'm'], [2, 'new-model']]);
  expect(rows(engine.db).map((e) => e.config!.agents.author.model)).toEqual(['m', 'new-model']);
});

test('a restart checks the account names against the accounts of the reload, not the ones the engine started with', async () => {
  const engine = await stoppedOnCodex();
  const [repo] = choosing();
  reload(engine, { repos: [{ ...repo!, options: { codex: codexOption }, providers: { codex: codexOption } as any }] });
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { author: 'claude' }))).toBe('unknown option');
});

// --- A reload on a live engine: what the second review found ---

test('a repo a reload adds that GitHub answers 404 for fails its own check; the other is still read and the polling goes on', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const listed = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    if (repo === 'AshuLab/b') throw new GitHubRejected('GitHub answered HTTP 404: Not Found');
    return listed(repo, label);
  };
  const engine = await start(0, [repos[0]!]);
  reload(engine, { repos });
  await vi.waitFor(() => expect(ids(engine)).toEqual(['AshuLab/a#1']));
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 0, ok: false, error: 'GitHub answered HTTP 404: Not Found' });
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 0, ok: true, error: null });

  await clock.advance(5 * MIN); // the interval was armed again: it is not an engine that stopped looking
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });
  expect(engine.lastCheck('AshuLab/b')).toMatchObject({ at: 5 * MIN, ok: false });
});

test('a poll that fails in a way nobody planned is logged and the next one is still armed', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', prNumber: 50 });
  const engine = await start(0);
  let asked = 0;
  github.getPullRequest = async () => {
    asked++;
    throw new Error('boom');
  };
  await clock.advance(5 * MIN);
  expect(asked).toBe(1); // stopEnded failed in the middle of the cycle
  await clock.advance(5 * MIN);
  expect(asked).toBe(2);
  expect(engine.nextPollAt).toBe(15 * MIN);
});

test('a repo removed and added back before the stop of its run has ended continues the epic once the run has, and launches it once', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let stopEnds!: () => void;
  const slowStop = new Promise<void>((resolve) => (stopEnds = resolve));
  const run = runner.run.bind(runner);
  runner.run = (task) => {
    const started = run(task);
    const stop = started.stop;
    started.stop = async () => (await slowStop, stop()); // the process takes its time to die
    return started;
  };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(runner.tasks).toHaveLength(1);

  reload(engine, { repos: [repos[1]!] });
  reload(engine, { repos }); // back at once: the run has not ended
  await settle();
  expect(runner.tasks).toHaveLength(1); // nothing to continue from yet
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });

  stopEnds();
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));
  await settle();
  expect(runner.tasks).toHaveLength(2);
  expect(runner.tasks[1]).toMatchObject({ epic: 1, stage: 'ship', context: { verifyStateFirst: true } });
  expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['interrupted', 'running']);
});

test('a repo removed and added back while the reviewer\'s workspace is prepared launches the reviewer once', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  let prepared = 0;
  workspaces.prepareReviewer = async (repo, epic, pr) => (prepared++, await gate, { path: `/work/${repo}/${epic}/reviewer-${pr}`, commit: SHA });
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(prepared).toBe(1)); // the reviewer waits for its workspace

  reload(engine, { repos: [repos[1]!] });
  reload(engine, { repos });
  await vi.waitFor(() => expect(prepared).toBe(2)); // the restore launched the stage again, as it found it
  open();
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(1));
  await settle();

  expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(1);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review')).toHaveLength(1);
});

test('an epic a reload restores while a recovery is waiting is recovered by the check that follows, not lost', async () => {
  const db = open();
  seedEpic(db, 1, { repo: 'AshuLab/b', status: 'repo_removed', removedFrom: 'running', removedReason: 'x' });
  seedExecution(db, 'e1', 1, { status: 'interrupted' });
  seedEpic(db, 2);
  seedExecution(db, 'e2', 2, { status: 'interrupted' });
  const listActive = runner.listActive.bind(runner);
  runner.listActive = async () => {
    throw new GitHubUnavailable('network', 'down'); // the recovery of the start fails: the first check does it again
  };
  const engine = await start(2, [repos[0]!]);
  runner.listActive = listActive;
  let open2!: () => void;
  const gate = new Promise<void>((resolve) => (open2 = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (await gate, `/work/${repo}/${epic}/author`);
  runner.behavior = () => ({ exit: 'hang' });
  void clock.advance(5 * MIN); // the check recovers epic 2 and waits for its workspace

  await vi.waitFor(() => expect(runner.listActive).toBe(listActive));
  await settle();
  reload(engine, { repos }); // epic 1's repo comes back while that recovery is awaiting
  open2();
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.epic).sort()).toEqual([1, 2]));
});

test('an epic restored while the orchestrator profile fails is recovered by the first check that works, not before', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(runner.tasks).toHaveLength(1);
  reload(engine, { repos: [repos[1]!] });
  await settle();
  await settle();

  github.authError = new AuthError('a');
  reload(engine, { repos }); // back, while the profile fails
  await settle();
  await settle();
  expect(engine.error).not.toBeNull();
  expect(runner.tasks).toHaveLength(1); // a suspended engine launches nothing

  github.authError = null;
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2)); // the check that works takes the epic back
});

// --- A reload on a live engine: what the third review found ---

test('a repo GitHub refuses in the middle of the cycle fails its own check; the other repos still settle and start in that same cycle', async () => {
  const db = open();
  seedEpic(db, 1, { repo: 'AshuLab/b', status: 'needs_human', prNumber: 50 });
  github.ready = { 'AshuLab/a': ready(1) };
  const found = github.getPullRequest.bind(github);
  github.getPullRequest = async (repo, number) => {
    if (repo === 'AshuLab/b') throw new GitHubRejected('GitHub answered HTTP 404: Not Found');
    return found(repo, number);
  };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.repo)).toEqual(['AshuLab/a'])); // fillSlots ran after stopEnded failed for the other repo
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 5 * MIN, ok: false, error: 'GitHub answered HTTP 404: Not Found' });
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });
});

test('what is not GitHub refusing a repo still surfaces from the listing, and the next poll is armed all the same', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const listed = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    if (repo === 'AshuLab/b') throw new Error('database is locked');
    return listed(repo, label);
  };
  const engine = await start(0);
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/b')).toBeUndefined(); // not written off as that repo's failure
  expect(engine.nextPollAt).toBe(10 * MIN);
});

test('a begin that read its epic before the repo was removed and added back does not launch a second author', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  let held = 0;
  const label = github.setLabels.bind(github);
  github.setLabels = async (repo, issue, change) => {
    if (issue === 2 && held++ === 0) await gate; // the labels of the second epic, as the result of the first frees its slot
    return label(repo, issue, change);
  };
  let openWorkspace!: () => void;
  const workspaceGate = new Promise<void>((resolve) => (openWorkspace = resolve));
  let prepared = 0;
  workspaces.prepareAuthor = async (repo, epic) => (epic === 2 && prepared++ === 0 && (await workspaceGate), `/work/${repo}/${epic}/author`);
  runner.behavior = (task) => (task.epic === 1 ? { write: result(task, { outcome: 'needs_human', reason: 'stop' }) } : { exit: 'hang' });
  const engine = await start(1);
  void clock.advance(5 * MIN);
  await vi.waitFor(() => expect(held).toBe(1)); // epic 2 is reserved and its begin waits for the labels

  reload(engine, { repos: [repos[1]!] });
  reload(engine, { repos });
  open();
  await vi.waitFor(() => expect(prepared).toBeGreaterThanOrEqual(1));
  await settle();
  openWorkspace(); // a begin that went on after the restore would be the second author preparing a workspace for the same stage
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1));
  await settle();

  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1);
});

test('an epic whose pull request was merged while its repo was parked ends when the repo is back and is not launched first', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ stage: 'review' }));
  const reviewers = () => runner.tasks.filter((t) => t.stage === 'review').length;
  await vi.waitFor(() => expect(reviewers()).toBe(1));

  reload(engine, { repos: [repos[1]!] });
  await settle();
  await settle();
  const finalPr = rows(engine.db)[0]!.prNumber!;
  pull(finalPr, { state: 'merged' }); // merged by a person while Carrier did not watch the repo
  reload(engine, { repos });
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'merged' }));
  await settle();

  expect(reviewers()).toBe(1); // the one that was running before; none was started for an epic that was already over
});

test('an epic a reload parks and restores after its own turn of a recovery is not dropped from the restore', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e1', 1, { status: 'interrupted' });
  seedEpic(db, 2);
  seedExecution(db, 'e2', 2, { status: 'interrupted' });
  const listActive = runner.listActive.bind(runner);
  runner.listActive = async () => {
    throw new GitHubUnavailable('network', 'down'); // the recovery of the start fails: the first check does it again
  };
  const engine = await start(2, repos);
  runner.listActive = listActive;
  let open2!: () => void;
  const gate = new Promise<void>((resolve) => (open2 = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (epic === 2 ? (await gate, `/work/${repo}/${epic}/author`) : `/work/${repo}/${epic}/author`);
  runner.behavior = () => ({ exit: 'hang' });
  void clock.advance(5 * MIN); // the check recovers epic 1 (its agent starts), then waits for epic 2's workspace
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.epic)).toEqual([1]));

  reload(engine, { repos: [repos[1]!] }); // both epics are in AshuLab/a: parked, epic 1's agent stopped
  reload(engine, { repos }); // and back, while the recovery is still awaiting epic 2
  open2();
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.epic === 1).length).toBeGreaterThanOrEqual(2)); // epic 1 continued by the restore
  await settle();
  expect(rows(engine.db).map((e) => e.status)).toEqual(['running', 'running']);
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1); // and epic 2, which the recovery was waiting for, once
});

test('the review limit is the one in force when a review asks for changes', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let ends!: () => void;
  runner.behavior = (task) =>
    task.stage === 'ship'
      ? { write: completed(task) }
      : { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }), when: new Promise<void>((resolve) => (ends = resolve)) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']));
  reload(engine, { maxReviews: 1 }); // lowered while round 1 is under review
  ends();
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'review_limit', round: 1 });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']); // no fix turn for a round the new limit does not allow
});

test('a slice read that waited for its window is not made once the repo has left the configuration', async () => {
  const { engine, run } = await working();
  run('c1', claim);
  await settle();
  expect(github.sliceReads).toHaveLength(1);
  run('c2', 'gh pr create'); // inside the window: it waits for its end
  reload(engine, { repos: [repos[1]!] });
  await clock.advance(10_000);
  await settle();
  expect(github.sliceReads).toHaveLength(1);
});

test('a retry whose repo left the configuration while GitHub was asked writes no event and launches nothing', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let open!: () => void;
  const gate = new Promise<void>((resolve) => (open = resolve));
  const found = github.findPullRequest.bind(github);
  let asked = 0;
  github.findPullRequest = async (repo, issue) => (asked++, await gate, found(repo, issue));
  runner.behavior = () => ({ exit: 'failed' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(asked).toBe(1)); // the run failed and the retry asks GitHub what it left

  reload(engine, { repos: [repos[1]!] });
  open();
  await settle();
  await engine.idle();

  expect(eventTypes(engine.db)).not.toContain('execution_retried');
  expect(runner.tasks).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'repo_removed', removedFrom: 'running' });
});

test('an epic that ended on GitHub while its repo left the configuration stays parked', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', prNumber: 50 });
  pull(50, { state: 'merged' });
  const engine = await start(0);
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const found = github.getPullRequest.bind(github);
  let asked = 0;
  github.getPullRequest = async (repo, number) => (asked++, await gate, found(repo, number));
  void clock.advance(5 * MIN);
  await vi.waitFor(() => expect(asked).toBe(1)); // the poll asks whether its final PR was merged

  reload(engine, { repos: [repos[1]!] });
  release();
  await settle();
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'repo_removed', removedFrom: 'needs_human' });
});

// --- A reload on a live engine: what the fourth review found ---

test('an epic restored in a repo GitHub refuses fails that repo\'s check only: the other repos still start in that cycle, and the epic is recovered once the repo answers', async () => {
  const db = open();
  const [a] = failoverRepos({ author: [{ provider: 'spare' }] });
  const failover = [a!, { ...a!, name: 'AshuLab/b' }];
  seedEpic(db, 1, { repo: 'AshuLab/b', status: 'repo_removed', removedFrom: 'running', removedReason: 'x', config: failover[1] });
  seedExecution(db, 'e1', 1, { status: 'failed', option: 'claude', failureKind: 'api_error', failureDetail: 'ECONNREFUSED' });
  github.ready = { 'AshuLab/a': ready(2) };
  const found = github.findPullRequest.bind(github);
  let refusing = true;
  github.findPullRequest = async (repo, issue) => {
    if (refusing && repo === 'AshuLab/b') throw new GitHubRejected('GitHub answered HTTP 404: Not Found');
    return found(repo, issue);
  };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(2, [failover[0]!]);
  reload(engine, { repos: failover }); // epic 1 comes back; recovering it asks GitHub about its pull request
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.epic)).toEqual([2])); // fillSlots ran after the restore was refused
  expect(engine.lastCheck('AshuLab/b')).toMatchObject({ ok: false, error: 'GitHub answered HTTP 404: Not Found' });

  refusing = false;
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.epic)).toEqual([2, 1])); // the restore was kept for this cycle, not dropped
});

test('an epic a reload restores while another launch of its first stage is preparing its workspace does not get a second author', async () => {
  const db = open();
  seedEpic(db, 2, { repo: 'AshuLab/b', status: 'repo_removed', removedFrom: 'running', removedReason: 'x', stage: null, labelPending: true });
  github.ready = { 'AshuLab/a': ready(1) };
  let ends!: () => void;
  runner.behavior = (task) => (task.epic === 1 ? { write: result(task, { outcome: 'needs_human', reason: 'stop' }), when: new Promise<void>((resolve) => (ends = resolve)) } : { exit: 'hang' });
  const engine = await start(1, [repos[0]!]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));

  let release!: () => void;
  const listed = new Promise<void>((resolve) => (release = resolve));
  const list = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => (await listed, list(repo, label));
  let openWorkspace!: () => void;
  const workspaceGate = new Promise<void>((resolve) => (openWorkspace = resolve));
  let prepared = 0;
  workspaces.prepareAuthor = async (repo, epic) => (epic === 2 && (prepared++, await workspaceGate), `/work/${repo}/${epic}/author`);
  reload(engine, { repos }); // epic 2 is back, running with no stage; the check that restores it waits for the listing
  ends(); // epic 1 ends: its slot is freed and the labels pass launches epic 2
  await vi.waitFor(() => expect(prepared).toBe(1));

  release(); // now the restore finds epic 2 with its stage claimed and no execution yet
  await settle();
  await settle();
  openWorkspace();
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1));
  await settle();
  expect(prepared).toBe(1);
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1);
});

test('a poll that listed a repo before a reload removed it queues nothing for it', async () => {
  github.ready = { 'AshuLab/a': ready(1), 'AshuLab/b': ready(2) };
  let release!: () => void;
  const listed = new Promise<void>((resolve) => (release = resolve));
  const list = github.listOpenEpics.bind(github);
  github.listOpenEpics = async (repo, label) => {
    const epics = await list(repo, label);
    if (repo === 'AshuLab/b') await listed; // the list is read, the answer is not back yet
    return epics;
  };
  const engine = await start(0);
  void clock.advance(5 * MIN);
  await vi.waitFor(() => expect(github.calls).toBe(2));
  reload(engine, { repos: [repos[0]!] });
  release();
  await settle();
  await engine.idle();
  expect(ids(engine)).toEqual(['AshuLab/a#1']);
});

test('a reload whose parking of the removed repos fails still answers: its settings are in force', async () => {
  const engine = await start(0);
  let reads = 0;
  const flaky = { agents, get name() { if (reads++ === 0) throw new Error('database is locked'); return 'AshuLab/a'; } } as unknown as EffectiveRepoConfig;
  expect(() => reload(engine, { repos: [flaky], maxConcurrentEpics: 3 })).not.toThrow();
  expect(settings.maxConcurrentEpics).toBe(3);
  await settle();
});

// --- the poll recovers a running epic that lost its agent (ADR 0046) ---

const recovered = (db: Db) => db.select().from(epicEvents).all().filter((e) => e.type === 'recovered');

test('the poll continues a running epic whose last execution ended on a usage limit and was not failed over, from where it was, and leaves a recovered event', async () => {
  const config = failoverRepos({ author: [{ provider: 'spare' }] });
  const engine = await start(1, config);
  seedEpic(engine.db, 1, { config: config[0] }); // the epic was running when its handler lost the end: no agent, nothing scheduled
  seedExecution(engine.db, 'e0', 1, { status: 'failed', option: 'claude', failureKind: 'usage_limit', failureDetail: 'resets 12:40pm' });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });

  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'spare']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', authorOption: 'spare', recoveries: 1 });
  expect(recovered(engine.db).map((e) => e.data)).toEqual([{ stage: 'ship', attempt: 1 }]);
});

test('the poll launches the next stage of an epic whose result was imported and whose launch never happened', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'fix', round: 1, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic' });
  seedExecution(engine.db, 'r1', 1, { stage: 'review', status: 'finished' });
  engine.db.insert(callerResults).values({ executionId: 'r1', outcome: 'changes_requested', result: JSON.stringify({ summary: 's', blockers: [{ title: 'fix it' }] }) }).run();

  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['fix']);
  expect(recovered(engine.db)).toHaveLength(1);
});

test('the poll recovers nothing while the engine holds the epic\'s run', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);
  expect(runner.tasks).toHaveLength(1);
  expect(recovered(engine.db)).toEqual([]);
});

test('the poll recovers nothing for an epic whose launch is in flight, and starts no second agent', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let ends!: () => void;
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  runner.behavior = (task) => (task.epic === 1 ? { write: result(task, { outcome: 'needs_human', reason: 'x' }), when: new Promise<void>((resolve) => (ends = resolve)) } : { exit: 'hang' });
  workspaces.prepareAuthor = async (repo, epic) => (epic === 2 ? (await gate, `/work/${repo}/${epic}/author`) : `/work/${repo}/${epic}/author`);
  const engine = await start(1);
  await clock.advance(5 * MIN);
  ends(); // epic 1 stops, and the slot it frees starts epic 2, which waits for its workspace with its stage claimed
  await vi.waitFor(() => expect(rows(engine.db)[1]).toMatchObject({ status: 'running', stage: 'ship' }));

  await clock.advance(5 * MIN); // a poll meanwhile: epic 2 has a stage and no execution yet, and is not a cut one
  expect(recovered(engine.db)).toEqual([]);
  opens();
  await settle();
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1);
});

test('the poll recovers nothing for an epic whose retry is in flight, and starts no second agent', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  runner.behavior = (task) => (runner.tasks.length === 1 ? { exit: 'failed' } : { exit: 'hang' });
  const find = github.findPullRequest.bind(github);
  github.findPullRequest = async (...args) => (await gate, find(...args)); // the retry reads GitHub before it launches
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['failed']));

  await clock.advance(5 * MIN);
  expect(recovered(engine.db)).toEqual([]);
  opens();
  await settle();
  expect(runner.tasks).toHaveLength(2);
});

test('an epic a reload parked and restored while the poll recovered another is left to its restore, not recovered twice', async () => {
  const engine = await start(2);
  seedEpic(engine.db, 1);
  seedEpic(engine.db, 2, { repo: 'AshuLab/b', config: repos[1] });
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (epic === 1 ? (await gate, `/work/${repo}/${epic}/author`) : `/work/${repo}/${epic}/author`);
  void clock.advance(5 * MIN); // the poll recovers epic 1 and waits for its workspace
  await vi.waitFor(() => expect(github.calls).toBeGreaterThan(0));
  await settle();

  reload(engine, { repos: [repos[0]!] }); // epic 2's repo leaves...
  reload(engine, { repos }); // ...and comes back, while the poll still has to reach epic 2
  opens();
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1));
  await settle();
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1); // the restore's, once
  expect(recovered(engine.db).map((e) => e.epicId)).toEqual([1]);
});

test('the count of recoveries is saved with the epic: after three in a row, also across an engine restart, the next poll stops it in engine_error', async () => {
  const first = await start(1);
  seedEpic(first.db, 1, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA, recoveries: 3 });
  seedExecution(first.db, 'e0', 1, { stage: 'ship', status: 'interrupted' }); // of a stage the epic left: nothing a recovery moves, so it stays stuck
  first.stop();
  dbs.pop()!.$client.close();

  const second = await start(1); // the same database: the count survives the restart
  expect(rows(second.db)[0]).toMatchObject({ status: 'running', recoveries: 3 });
  await clock.advance(5 * MIN);
  expect(rows(second.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error', needsHumanReason: 'the poll recovered this epic 3 times in a row and it is still stuck at review' });
  expect(recovered(second.db)).toEqual([]);
});

test('the poll launches a stage a resume left claimed with no execution, once, though an execution of the previous attempt finished', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'ship', startedAt: 10 * MIN }); // resumed: the launch claimed the stage and was cut (engine stopping, epic parked) before its execution
  seedExecution(engine.db, 'old', 1, { stage: 'ship', status: 'finished', startedAt: 5 * MIN });
  engine.db.insert(callerResults).values({ executionId: 'old', outcome: 'needs_human', result: JSON.stringify({ summary: 's', reason: 'x' }) }).run();
  runner.behavior = () => ({ exit: 'hang' });

  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']);
  expect(recovered(engine.db).map((e) => e.data)).toEqual([{ stage: 'ship', attempt: 1 }]);
});

test('an epic whose last execution timed out while it was parked is stopped for a person by the poll', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA });
  seedExecution(engine.db, 'e0', 1, { stage: 'review', status: 'timed_out', failureKind: 'timeout', failureDetail: 'exceeded 2 h' });

  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'timeout', needsHumanReason: 'the review execution exceeded the time limit of 2 h (limits.maxExecutionHours) · session and worktree are kept: raise the limit or set it to "unlimited", then resume the epic' });
  expect(runner.tasks).toEqual([]);
});

test('the poll does nothing for an interrupted execution of a stage the epic has moved on from', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA });
  seedExecution(engine.db, 'e0', 1, { stage: 'ship', status: 'interrupted' });
  runner.behavior = () => ({ exit: 'hang' });

  await clock.advance(5 * MIN);
  expect(runner.tasks).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review' });
});

test('the poll recovers nothing for an epic that stopped being running while it waited for the one before', async () => {
  const engine = await start(2);
  seedEpic(engine.db, 1);
  seedEpic(engine.db, 2);
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (epic === 1 ? (await gate, `/work/${repo}/${epic}/author`) : `/work/${repo}/${epic}/author`);
  runner.behavior = () => ({ exit: 'hang' });
  void clock.advance(5 * MIN); // the poll recovers epic 1 and waits for its workspace
  await vi.waitFor(() => expect(github.calls).toBeGreaterThan(0));
  await settle();

  engine.db.update(epics).set({ status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x' }).where(eq(epics.issue, 2)).run();
  opens();
  await settle();
  expect(runner.tasks.map((t) => t.epic)).toEqual([1]);
  expect(recovered(engine.db).map((e) => e.epicId)).toEqual([1]);
});

test('the count starts again when an execution of the epic ends', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { recoveries: 2 });
  seedExecution(engine.db, 'e0', 1, { status: 'interrupted' });
  let ends!: () => void;
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task), when: new Promise<void>((resolve) => (ends = resolve)) } : { exit: 'hang' });
  pull(50);

  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ recoveries: 3 });
  ends();
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']));
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', recoveries: 0 });
});

test('an unexpected error in a recovery stops that epic in engine_error and the poll goes on with the others', async () => {
  const config = failoverRepos({ author: [{ provider: 'spare' }] });
  const engine = await start(2, config);
  seedEpic(engine.db, 1, { config: config[0] });
  seedExecution(engine.db, 'e1', 1, { status: 'failed', option: 'claude', failureKind: 'usage_limit', failureDetail: 'resets' });
  seedEpic(engine.db, 2, { config: config[0] });
  seedExecution(engine.db, 'e2', 2, { status: 'interrupted' });
  github.findPullRequest = async (_repo, issue) => {
    if (issue === 1) throw new TypeError('boom');
    return null;
  };
  runner.behavior = () => ({ exit: 'hang' });

  await clock.advance(5 * MIN);
  expect(rows(engine.db).map((e) => [e.status, e.needsHumanKind, e.needsHumanReason])).toEqual([['needs_human', 'engine_error', 'boom'], ['running', null, null]]);
  expect(runner.tasks.map((t) => t.epic)).toEqual([2]);
});

// --- recoverEpic: the same recovery, asked for one epic (ADR 0044) ---

test('recoverEpic continues a running epic that lost its agent from its real state, leaves a recovered event that says a command asked, and answers once it was continued', async () => {
  const config = failoverRepos({ author: [{ provider: 'spare' }] });
  const engine = await start(1, config);
  seedEpic(engine.db, 1, { config: config[0] });
  seedExecution(engine.db, 'e0', 1, { status: 'failed', option: 'claude', failureKind: 'usage_limit', failureDetail: 'resets 12:40pm' });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });

  await engine.recoverEpic('AshuLab/a', 1);
  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['ship', 'spare']]); // already started when it answers
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', authorOption: 'spare', recoveries: 0 }); // the poll's budget is not spent by a person
  expect(recovered(engine.db).map((e) => e.data)).toEqual([{ stage: 'ship', by: 'command' }]);
  await clock.advance(5 * MIN); // the poll finds an agent alive: no second one
  expect(runner.tasks).toHaveLength(1);
});

test('recoverEpic refuses an epic the engine does not know, and one that is not running, and touches nothing', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x' });
  seedExecution(engine.db, 'e0', 1, { status: 'interrupted' });
  expect(await refusal(engine.recoverEpic('AshuLab/a', 9))).toBe('unknown epic');
  expect(await refusal(engine.recoverEpic('AshuLab/other', 1))).toBe('unknown epic');
  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('not running');
  expect(runner.tasks).toEqual([]);
  expect(recovered(engine.db)).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
});

test('recoverEpic refuses an epic whose execution is alive, and starts no second agent', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(runner.tasks).toHaveLength(1);
  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('agent alive');
  expect(runner.tasks).toHaveLength(1);
  expect(recovered(engine.db)).toEqual([]);
});

test('recoverEpic refuses an epic whose launch is in flight, and starts no second agent', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  let ends!: () => void;
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  runner.behavior = (task) => (task.epic === 1 ? { write: result(task, { outcome: 'needs_human', reason: 'x' }), when: new Promise<void>((resolve) => (ends = resolve)) } : { exit: 'hang' });
  workspaces.prepareAuthor = async (repo, epic) => (epic === 2 ? (await gate, `/work/${repo}/${epic}/author`) : `/work/${repo}/${epic}/author`);
  const engine = await start(1);
  await clock.advance(5 * MIN);
  ends(); // epic 1 stops, and the slot it frees starts epic 2, which waits for its workspace with its stage claimed
  await vi.waitFor(() => expect(rows(engine.db)[1]).toMatchObject({ status: 'running', stage: 'ship' }));

  expect(await refusal(engine.recoverEpic('AshuLab/a', 2))).toBe('agent alive');
  opens();
  await settle();
  expect(runner.tasks.filter((t) => t.epic === 2)).toHaveLength(1);
  expect(recovered(engine.db)).toEqual([]);
});

test('recoverEpic refuses an epic whose retry is in flight, and starts no second agent', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  runner.behavior = () => (runner.tasks.length === 1 ? { exit: 'failed' } : { exit: 'hang' });
  const find = github.findPullRequest.bind(github);
  github.findPullRequest = async (...args) => (await gate, find(...args)); // the retry reads GitHub before it launches
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(executionsOf(engine.db).map((e) => e.status)).toEqual(['failed']));

  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('agent alive');
  opens();
  await settle();
  expect(runner.tasks).toHaveLength(2);
  expect(recovered(engine.db)).toEqual([]);
});

test('recoverEpic refuses an epic that has no stage yet, and a second one while the first is in flight', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: null });
  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('not started');

  seedEpic(engine.db, 2);
  seedExecution(engine.db, 'e0', 2, { status: 'interrupted' });
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  const find = github.findPullRequest.bind(github);
  github.findPullRequest = async (...args) => (await gate, find(...args));
  runner.behavior = () => ({ exit: 'hang' });
  const first = engine.recoverEpic('AshuLab/a', 2);
  await flush();
  expect(await refusal(engine.recoverEpic('AshuLab/a', 2))).toBe('agent alive');
  opens();
  await first;
  expect(runner.tasks).toHaveLength(1);
});

test('an unexpected error while recovering one epic stops it in engine_error, as the poll does, and the request fails', async () => {
  const config = failoverRepos({ author: [{ provider: 'spare' }] });
  const engine = await start(1, config);
  seedEpic(engine.db, 1, { config: config[0] });
  seedExecution(engine.db, 'e0', 1, { status: 'failed', option: 'claude', failureKind: 'usage_limit', failureDetail: 'resets' });
  github.findPullRequest = async () => {
    throw new TypeError('boom');
  };
  await expect(engine.recoverEpic('AshuLab/a', 1)).rejects.toThrow('boom');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error', needsHumanReason: 'boom' });
});

// --- An issue that is gone, and a repo that does not answer ---

const goneReason = 'the epic issue no longer exists';

test('an epic whose issue answers 404 while its repo answers is cancelled at the start, the engine starts and the other epics of the repo go on', async () => {
  const db = open();
  seedEpic(db, 1, { labelPending: true });
  seedEpic(db, 2);
  github.missingIssues.add('AshuLab/a#1');
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(2);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.epic)).toEqual([2])); // epic 2 was launched, epic 1 got no agent

  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason, e.labelPending])).toEqual([[1, 'cancelled', goneReason, false], [2, 'running', null, false]]);
  expect(rows(engine.db)[0]?.cancelKind).toBe('issue_gone');
  expect(eventTypes(engine.db)).toContain('epic_cancelled');
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null }); // the repo is not refused
});

test('the poll cancels an epic whose issue turned 404, 410 too, in any state it waits in, and goes on with the others of its repo', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x' });
  seedEpic(db, 2, { status: 'ready_for_test' });
  seedEpic(db, 3, { status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x' });
  github.ready = { 'AshuLab/a': ready(4) };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  github.missingIssues.add('AshuLab/a#1');
  github.missingIssues.add('AshuLab/a#2');
  await clock.advance(5 * MIN);

  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason])).toEqual([[1, 'cancelled', goneReason], [2, 'cancelled', goneReason], [3, 'needs_human', null], [4, 'running', null]]);
  expect(rows(engine.db).map((e) => e.cancelKind)).toEqual(['issue_gone', 'issue_gone', null, null]);
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });
});

test('a queued epic whose issue is 404 when its slot comes is cancelled and does not block the queue of its repo', async () => {
  github.ready = { 'AshuLab/a': ready(1, 2) };
  github.missingIssues.add('AshuLab/a#1');
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);

  expect(rows(engine.db).map((e) => [e.issue, e.status, e.cancelReason])).toEqual([[1, 'cancelled', goneReason], [2, 'running', null]]);
  expect(engine.lastCheck('AshuLab/a')).toMatchObject({ ok: true });
});

test('a repo that answers 404 is its own refusal at the start and at the poll: no epic of it is cancelled, the others are untouched, and it is tried again', async () => {
  const db = open();
  seedEpic(db, 1, { repo: 'AshuLab/b', config: repos[1], labelPending: true });
  seedEpic(db, 2, { repo: 'AshuLab/b', config: repos[1], status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x' });
  seedEpic(db, 3);
  github.ready = { 'AshuLab/a': ready(4) };
  github.missingRepos.add('AshuLab/b');
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(3);
  await clock.advance(5 * MIN);

  expect(rows(engine.db).map((e) => [e.repo.slice(-1), e.issue, e.status])).toEqual([['b', 1, 'running'], ['b', 2, 'needs_human'], ['a', 3, 'running'], ['a', 4, 'running']]);
  expect(rows(engine.db).every((e) => e.cancelReason === null)).toBe(true);
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 5 * MIN, ok: false, error: 'GitHub answered HTTP 404: Not Found' });
  expect(engine.lastCheck('AshuLab/a')).toEqual({ at: 5 * MIN, ok: true, error: null });

  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/b')).toMatchObject({ at: 10 * MIN, ok: false }); // tried again at the next check

  github.missingRepos.clear();
  await clock.advance(5 * MIN);
  expect(engine.lastCheck('AshuLab/b')).toEqual({ at: 15 * MIN, ok: true, error: null });
  expect(byStatus(engine.db, 'cancelled')).toEqual([]);
});

test('a missing issue in a repo that does not answer is the repo\'s refusal at the poll too: the epic stays', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x' });
  const engine = await start(0);
  github.missingRepos.add('AshuLab/a'); // GitHub answers 404 for the repo and so for its issues
  await clock.advance(5 * MIN);
  expect(byStatus(engine.db, 'cancelled')).toEqual([]);
  expect(engine.lastCheck('AshuLab/a')).toMatchObject({ ok: false });
});

// --- resume from a stage: review or fix keeps the round, the pull request, the worktree, the blockers and the session ---

// An epic stopped in needs_human at `stage` on round 2 with its pull request, worktree, one author session and the reviewer's blockers; `ready` can be put on it.
function stoppedAt(db: Db, stage: 'review' | 'fix', extra: Partial<typeof epics.$inferInsert> = {}) {
  seedEpic(db, 1, { status: 'needs_human', stage, round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'review_limit', needsHumanReason: 'review limit', observationsPassAt: 7, ...extra });
  seedExecution(db, 's1', 1, { status: 'finished', stage: 'ship', option: 'o' }); // the option the epic's author has
  seedExecution(db, 'r1', 1, { status: 'finished', stage: 'review', round: 1 });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'changes_requested', result: JSON.stringify({ summary: 's', blockers: [{ title: 'fix it' }] }) }).run();
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
}
const resumeFrom = async (engine: Awaited<ReturnType<typeof start>>, from?: 'ship' | 'review' | 'fix', extraRounds?: number) => {
  const resumed = engine.resumeEpic('AshuLab/a', 1, { from, extraRounds });
  await flush();
  await clock.advance(1000);
  await resumed;
};

test.each(['review', 'fix'] as const)('resuming at %s starts that stage with the round, pull request, worktree, blockers and session of the epic kept, takes a slot and leaves a resumed event', async (stage) => {
  const engine = await start(1);
  stoppedAt(engine.db, stage);
  await resumeFrom(engine, stage);

  expect(runner.tasks.map((t) => t.stage)).toEqual([stage]);
  expect(runner.tasks[0]).toMatchObject({ context: { round: 2, pr: { number: 50, headSha: SHA } }, ...(stage === 'fix' && { workspace: '/w/epic', resumeSession: 's-s1', context: { round: 2, pr: { number: 50, headSha: SHA }, blockers: [{ title: 'fix it' }] } }) });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage, round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', observationsPassAt: 7, needsHumanKind: null, resumeStage: null });
  expect(eventsOf(engine.db).filter((e) => e.type === 'resumed').map((e) => e.data)).toEqual([{ from: stage, by: 'command' }]);
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
});

test('a resume at a stage goes through the queue: with no free slot the epic waits queued with its stage saved, and starts there once a slot is free', async () => {
  const engine = await start(0);
  stoppedAt(engine.db, 'review');
  await resumeFrom(engine, 'review');
  expect(runner.tasks).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', stage: null, round: 2, prNumber: 50, resumeStage: 'review' });

  settings.maxConcurrentEpics = 1;
  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, resumeStage: null });
});

test('the stage asked is saved with the epic: an engine restarted while the epic waits for a slot starts it at that stage', async () => {
  const first = await start(0);
  stoppedAt(first.db, 'fix');
  await resumeFrom(first, 'fix');
  expect(rows(first.db)[0]).toMatchObject({ status: 'queued', resumeStage: 'fix' });
  first.stop();

  const second = await start(1);
  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => [t.stage, t.workspace, t.resumeSession])).toEqual([['fix', '/w/epic', 's-s1']]);
  expect(rows(second.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 2 });
});

test('an epic resumed at a stage whose claim was cut before its execution starts that stage again and never ship', async () => {
  const first = await start(1);
  seedEpic(first.db, 1, { stage: 'fix', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', startedAt: 1000 });
  seedExecution(first.db, 's1', 1, { status: 'finished', stage: 'ship', startedAt: 0 }); // an earlier attempt's
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
  first.stop();
  const second = await start(1);
  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['fix']);
  expect(rows(second.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 2 });
});

test.each([
  ['the pull request is closed', { state: 'closed' as const }, 'pull request not open'],
  ['the pull request is merged', { state: 'merged' as const }, 'pull request not open'],
])('resuming at a stage is refused when %s, and nothing changes', async (_name, change, reason) => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  pull(50, change);
  const before = github.issue('AshuLab/a', 1).labels.slice();
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'review' }))).toBe(reason);
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'fix' }))).toBe(reason);
  expect(labelsOf(1)).toEqual(before);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeStage: null, round: 2 });
  expect(runner.tasks).toEqual([]);
});

const MOVED = 'b'.repeat(40);

test('resuming at review after the head moved adopts the new head: it is stored, the review starts on it and the event says from which to which', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  pull(50, { headSha: MOVED });
  await resumeFrom(engine, 'review');

  expect(runner.tasks.map((t) => t.stage)).toEqual(['review']);
  expect(runner.tasks[0]).toMatchObject({ context: { round: 2, pr: { number: 50, headSha: MOVED } } });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, prNumber: 50, prHeadSha: MOVED, resumeStage: null });
  expect(eventsOf(engine.db).filter((e) => e.type === 'resumed').map((e) => e.data)).toEqual([{ from: 'review', by: 'command', headAdopted: { from: SHA, to: MOVED } }]);
});

test('resuming at review keeps the stored head when GitHub fails to put the label', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  pull(50, { headSha: MOVED });
  github.setLabelsUnavailable = new GitHubUnavailable('network', 'down');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'review' }))).toBe('github unavailable');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', prHeadSha: SHA, resumeStage: null });
});

test('resuming at review with the head unmoved has no head adopted in its event', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  await resumeFrom(engine, 'review');
  expect(eventsOf(engine.db).filter((e) => e.type === 'resumed').map((e) => e.data)).toEqual([{ from: 'review', by: 'command' }]);
});

test('resuming at fix is refused when the head moved, because the blockers belong to the stored head', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'fix');
  pull(50, { headSha: MOVED });
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'fix' }))).toBe('pull request head changed');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', prHeadSha: SHA, resumeStage: null });
  expect(runner.tasks).toEqual([]);
});

test('resuming at a stage is refused for an epic with no pull request or whose pull request GitHub does not know, and when GitHub is down', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review', { prNumber: null, prHeadSha: null });
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'review' }))).toBe('no pull request');
  engine.db.update(epics).set({ prNumber: 99, prHeadSha: SHA }).run();
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'review' }))).toBe('pull request not open');
  engine.db.update(epics).set({ prNumber: 50 }).run();
  github.unavailable = new GitHubUnavailable('network', 'down');
  expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from: 'review' }))).toBe('github unavailable');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeStage: null });
});

test.each([undefined, 'ship' as const])('resuming with from %s behaves as before: it starts from ship with the rounds reset and the pull request read again', async (from) => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  await resumeFrom(engine, from);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', round: null, prNumber: null, resumeStage: null });
});

test('a resume without from clears a stage an earlier resume asked and did not see start', async () => {
  const engine = await start(0);
  stoppedAt(engine.db, 'review');
  engine.db.update(epics).set({ resumeStage: 'review' }).run();
  const resumed = engine.resumeEpic('AshuLab/a', 1);
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', round: null, resumeStage: null });
});

// --- extra rounds: a resume of a review_limit stop grants rounds counted from the current one ---

test.each([
  ['the default is maxReviews', undefined, 7],
  ['extraRounds names the number', 2, 4],
])('resuming a review_limit stop at round 2 keeps the grant in roundLimit: %s', async (_name, extraRounds, limit) => {
  const engine = await start(0, repos, 4, 3, 5);
  stoppedAt(engine.db, 'review');
  await resumeFrom(engine, 'review', extraRounds);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', round: 2, roundLimit: limit, resumeStage: 'review' });
});

test('a resumed review_limit stop runs the rounds it was granted and stops again with review_limit, its snapshot showing its own cap', async () => {
  const engine = await start(1, repos, 4, 3, 2);
  seedEpic(engine.db, 1, { status: 'needs_human', stage: 'fix', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'review_limit', needsHumanReason: 'review limit' }); // round 2 of maxReviews 2
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let go!: () => void;
  const gate = new Promise<void>((resolve) => (go = resolve)); // the resume answers once the epic started: its first stage waits for that
  runner.behavior = (task) =>
    task.stage === 'review' ? { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: `round ${task.context.round}` }] }) }
    : { write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'ok' } }), when: gate };
  await resumeFrom(engine, 'fix');
  go();
  await engine.idle();
  expect(runner.tasks.map((t) => [t.stage, t.context.round])).toEqual([['fix', 2], ['review', 3], ['fix', 3], ['review', 4]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'review_limit', round: 4, roundLimit: 4 });
  expect(rows(engine.db)[0]!.needsHumanReason).toBe('review limit: round 4 of 4 still has requested changes');
  expect(buildSnapshot(engine.db, { now: clock.now(), maxConcurrentEpics: 1, maxReviews: 2, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, slices: engine.slices, version: 'x', pollIntervalMs: 1, labels: defaultLabels }).epics[0]).toMatchObject({ round: 4, maxReviews: 4 });
});

test('the cap of an epic is its roundLimit when set, whatever maxReviews is', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  let ends!: () => void;
  runner.behavior = (task) =>
    task.stage === 'ship' ? { write: completed(task) }
    : task.stage === 'fix' ? { exit: 'stopped' }
    : { write: result(task, { outcome: 'changes_requested', pr: { number: 50, headSha: SHA }, blockers: [{ title: 'x' }] }), when: new Promise<void>((resolve) => (ends = resolve)) };
  const engine = await start(1, repos, 4, 3, 1); // maxReviews 1: round 1 is the limit for an epic with no grant
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review']));
  engine.db.update(epics).set({ roundLimit: 2 }).run();
  ends();
  await engine.idle();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 1 });
});

test('a resume that grants nothing leaves the cap as it was, and one from ship takes the grant away with the rounds', async () => {
  const engine = await start(0);
  stoppedAt(engine.db, 'review', { needsHumanKind: 'agent_needs_human', roundLimit: 9 });
  await resumeFrom(engine, 'review');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', roundLimit: 9 });
  engine.db.update(epics).set({ status: 'needs_human', resumeStage: null }).run();
  await resumeFrom(engine, 'ship');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', round: null, roundLimit: null });
});

test('extraRounds without a stage to keep is refused and nothing changes', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  for (const from of [undefined, 'ship' as const]) expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from, extraRounds: 3 }))).toBe('extra rounds need a stage');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', roundLimit: null, resumeStage: null });
  expect(runner.tasks).toEqual([]);
});

test('the ready label of a stopped epic whose own label is still pending is seen by the poll: the reconciliation does not take it off first', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review', { labelPending: true }); // it stopped, and its needs-human mirror is not on the issue yet
  await resumeFrom(engine, 'review');
  expect(runner.tasks.map((t) => t.stage)).toEqual(['review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2 });
});

// --- findings of the review of this epic ---

// The epic stopped at `fix` after the failover moved the author from `claude` to `spare` and both ran out, with the session of each option stored.
function stoppedAtFixAfterFailover(db: Db) {
  const quota = quotaRepos(true)[0]!;
  seedEpic(db, 1, { status: 'needs_human', stage: 'fix', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'usage_limit', needsHumanReason: 'out of usage', resumeAt: MIN, config: { ...quota, agents: { ...quota.agents, author: { profile: 'a', option: 'spare', ...spareAccount } } }, authorOption: 'spare' });
  seedExecution(db, 's1', 1, { status: 'finished', stage: 'ship', option: 'claude', harness: 'claude', model: 'opus' });
  seedExecution(db, 'r1', 1, { status: 'finished', stage: 'review', round: 1 });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'changes_requested', result: JSON.stringify({ summary: 'why', blockers: [{ title: 'fix it' }] }) }).run();
  seedExecution(db, 'x1', 1, { status: 'failed', stage: 'fix', option: 'claude', harness: 'claude', model: 'opus', configDir: '/cfg/claude', failureKind: 'usage_limit' });
  seedExecution(db, 'x2', 1, { status: 'failed', stage: 'fix', option: 'spare', harness: 'codex', model: 'gpt', configDir: '/cfg/spare', failureKind: 'usage_limit' });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
}
async function restartedWithAutoResume(config: EffectiveRepoConfig[]) {
  dbs.pop()!.$client.close();
  const engine = await start(1, config);
  settings = { ...settings, autoResume: true };
  return engine;
}

test('a wake-up at fix on the option that came back after a failover starts a rebuilt session, never the session another option wrote', async () => {
  stoppedAtFixAfterFailover(open());
  fakeQuota.snapshots['/cfg/claude'] = back();
  fakeQuota.snapshots['/cfg/spare'] = full('codex', 9 * HOUR);
  await restartedWithAutoResume(quotaRepos(true));
  await clock.advance(5 * MIN);

  expect(runner.tasks).toHaveLength(1);
  expect(runner.tasks[0]).toMatchObject({ stage: 'fix', option: 'claude', context: { round: 2, pr: { number: 50, headSha: SHA }, previousSummaries: ['why'] } });
  expect(runner.tasks[0]!.resumeSession).toBeUndefined();
});

test('a resume at fix that switches the author to another option starts a rebuilt session, never the session the first option wrote', async () => {
  const engine = await start(1, quotaRepos());
  seedEpic(engine.db, 1, { status: 'needs_human', stage: 'fix', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x', config: quotaRepos()[0] });
  seedExecution(engine.db, 's1', 1, { status: 'finished', stage: 'ship', option: 'claude', harness: 'claude', model: 'opus' });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
  github.ready = { 'AshuLab/a': ready(1) };
  const resumed = engine.resumeEpic('AshuLab/a', 1, { author: 'spare', from: 'fix' });
  await flush();
  await clock.advance(1000);
  await resumed;
  expect(runner.tasks.map((t) => [t.option, t.resumeSession])).toEqual([['spare', undefined]]);
  expect(eventsOf(engine.db).filter((e) => e.type === 'session_rebuilt').map((e) => e.data)).toMatchObject([{ stage: 'fix', from: 'claude', to: 'spare' }]);
});

test('a fix on another author option that failed before it had a session is retried as a rebuilt session, never with the first option\'s', async () => {
  const engine = await start(1, quotaRepos());
  seedEpic(engine.db, 1, { status: 'needs_human', stage: 'fix', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'agent_needs_human', needsHumanReason: 'x', config: quotaRepos()[0] });
  seedExecution(engine.db, 's1', 1, { status: 'finished', stage: 'ship', option: 'claude', harness: 'claude', model: 'opus' });
  seedExecution(engine.db, 'r1', 1, { status: 'finished', stage: 'review', round: 1 });
  engine.db.insert(callerResults).values({ executionId: 'r1', outcome: 'changes_requested', result: JSON.stringify({ summary: 'why', blockers: [{ title: 'fix it' }] }) }).run();
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = () => (runner.tasks.length === 1 ? { exit: 'failed' } : { exit: 'hang' }); // the first run on the other option ends before it writes a session id
  const resumed = engine.resumeEpic('AshuLab/a', 1, { author: 'spare', from: 'fix' });
  await flush();
  await clock.advance(1000);
  await resumed;
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2)); // the first run and its retry

  expect(runner.tasks.map((t) => [t.stage, t.option, t.resumeSession])).toEqual([['fix', 'spare', undefined], ['fix', 'spare', undefined]]);
  expect(runner.tasks[1]!.context.previousSummaries).toEqual(['why']);
});

test('a wake-up on the option the epic already holds goes on that option, not on the repo default the queue resets it to', async () => {
  // claude (the default) ran out, the failover moved the epic to spare, spare ran out too, and spare is the one that comes back first.
  fakeQuota.snapshots['/cfg/spare'] = full('codex', WAKE + HOUR);
  const engine = await stoppedForQuota({ failover: true });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', authorOption: 'spare' });
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 9 * HOUR);
  fakeQuota.snapshots['/cfg/spare'] = back('codex');
  await clock.advance(3 * HOUR);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', authorOption: 'spare', autoResumes: 1 });
  expect(runner.tasks.at(-1)).toMatchObject({ stage: 'ship', option: 'spare' });
});

test('a wake-up refused because its pull request changed stops waiting: resumeAt is cleared so no later poll picks it again, and the panel does not promise a resume', async () => {
  const db = open();
  seedEpic(db, 1, { status: 'needs_human', stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'usage_limit', needsHumanReason: `the review execution ran out of usage on option claude · carrier restart AshuLab/a#1 --reviewer <option> · resumes by itself at 1970-01-01T00:01:00.000Z · out`, resumeAt: MIN, config: quotaRepos()[0] });
  seedExecution(db, 'x1', 1, { status: 'failed', stage: 'review', option: 'claude', harness: 'claude', model: 'opus', configDir: '/cfg/claude', failureKind: 'usage_limit' });
  pull(50, { headSha: 'b'.repeat(40) });
  fakeQuota.snapshots['/cfg/claude'] = back();
  const engine = await restartedWithAutoResume(quotaRepos());
  await clock.advance(5 * MIN); // the wake-up looks once, and refuses
  const reasonThen = rows(engine.db)[0]!.needsHumanReason;
  await clock.advance(30 * MIN); // nothing is due any more: the epic is not picked again by the wake-up
  expect(rows(engine.db)[0]!.needsHumanReason).toBe(reasonThen);
  expect(fakeQuota.asked).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeAt: null, autoResumes: 0 });
  expect(rows(engine.db)[0]!.needsHumanReason).toBe('the review execution ran out of usage on option claude · carrier restart AshuLab/a#1 --reviewer <option> · it will not resume by itself: pull request head changed · out');
  expect(buildSnapshot(engine.db, { now: clock.now(), maxConcurrentEpics: 1, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, slices: engine.slices, version: 'x', pollIntervalMs: 1, labels: defaultLabels }).epics[0]!.resumeAt).toBeUndefined();
});

test('a person resuming while the wake-up probes does not have the stage and options they asked overwritten by the wake-up', async () => {
  const engine = await start(1, quotaRepos());
  settings = { ...settings, autoResume: true };
  seedEpic(engine.db, 1, { status: 'needs_human', stage: 'review', round: 2, prNumber: 50, prHeadSha: SHA, workspace: '/w/epic', needsHumanKind: 'usage_limit', needsHumanReason: 'out of usage', resumeAt: MIN, config: quotaRepos()[0] });
  seedExecution(engine.db, 's1', 1, { status: 'finished', stage: 'ship', option: 'claude', harness: 'claude', model: 'opus' });
  seedExecution(engine.db, 'x1', 1, { status: 'failed', stage: 'review', option: 'claude', harness: 'claude', model: 'opus', configDir: '/cfg/claude', failureKind: 'usage_limit' });
  pull(50);
  fakeQuota.snapshots['/cfg/claude'] = back();
  runner.behavior = () => ({ exit: 'hang' });
  // The person's label write is held: the epic is in the middle of their resume when the poll wakes it up.
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  const set = github.setLabels.bind(github);
  let held = false;
  github.setLabels = async (...args) => {
    if (!held) {
      held = true;
      await gate;
    }
    return set(...args);
  };
  const resumed = engine.resumeEpic('AshuLab/a', 1, { reviewer: 'spare', from: 'fix' });
  await flush();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeStage: 'fix' });
  await clock.advance(5 * MIN); // the poll: its wake-up probes and finds the window back
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', resumeStage: 'fix', autoResumes: 0 });
  expect(eventTypes(engine.db)).not.toContain('auto_resumed');
  github.ready = { 'AshuLab/a': ready(1) }; // the label the person put is on the issue now
  opens();
  await flush();
  await clock.advance(1000);
  await resumed;

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', autoResumes: 0, resumeAt: null });
  expect(runner.tasks.map((t) => [t.stage, t.option])).toEqual([['fix', 'claude']]); // the author keeps its option; the reviewer asked for is saved with the epic
  expect(rows(engine.db)[0]!.config!.agents.reviewer.option).toBe('spare');
  expect(eventTypes(engine.db)).not.toContain('auto_resumed');
});

test('the poll does not count a recovery for an epic in a repo GitHub refused this cycle, and goes on with it once the repo answers', async () => {
  github.missingRepos.add('AshuLab/a');
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'failed', failureKind: 'unknown', error: 'the agent process ended with an error (unknown)' });
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  for (let i = 0; i < 4; i++) await clock.advance(5 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', recoveries: 0 });
  expect(recovered(engine.db)).toEqual([]);
  github.missingRepos.clear();
  await clock.advance(5 * MIN);
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']); // the retry the refused repo held back
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running' });
});

test('the poll leaves no recovered event for an epic its recovery parked', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA });
  seedExecution(engine.db, 'e0', 1, { stage: 'review', status: 'timed_out' });
  await clock.advance(5 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'timeout', recoveries: 0 });
  expect(recovered(engine.db)).toEqual([]);
});

test('the poll counts no recovery for an epic its recovery did not move, and never stops it in engine_error for that', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA });
  seedExecution(engine.db, 'e0', 1, { stage: 'ship', status: 'interrupted' }); // the cut execution is of a stage the epic has left: nothing to continue
  runner.behavior = () => ({ exit: 'hang' });
  for (let i = 0; i < 5; i++) await clock.advance(5 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', recoveries: 0 });
  expect(recovered(engine.db)).toEqual([]);
  expect(runner.tasks).toEqual([]);
});

test('recoverEpic refuses an epic with nothing a recovery continues, and records no recovered event', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1);
  seedExecution(engine.db, 'e0', 1, { status: 'failed', failureKind: 'unknown' }); // a retry owns it, not a recovery
  seedEpic(engine.db, 2, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA });
  seedExecution(engine.db, 'e1', 2, { stage: 'ship', status: 'interrupted' }); // of a stage the epic has left
  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('nothing to recover');
  expect(await refusal(engine.recoverEpic('AshuLab/a', 2))).toBe('nothing to recover');
  expect(runner.tasks).toEqual([]);
  expect(recovered(engine.db)).toEqual([]);
  expect(rows(engine.db).map((e) => e.status)).toEqual(['running', 'running']);
});

test('recoverEpic asked while the start recovers is refused: the start launches that epic, and a second agent would act on its workspace', async () => {
  const db = open();
  seedEpic(db, 1);
  seedExecution(db, 'e0', 1, { status: 'running' }); // the previous process's agent, gone
  let opens!: () => void;
  const gate = new Promise<void>((resolve) => (opens = resolve));
  workspaces.prepareAuthor = async (repo, epic) => (await gate, `/work/${repo}/${epic}/author`);
  runner.behavior = () => ({ exit: 'hang' });
  settings = { pollIntervalMs: 5 * MIN, labels: defaultLabels, maxConcurrentEpics: 1, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, maxLeadRounds: 3, autoResume: false, autoResumeMaxHours: 12 };
  watched = repos;
  const engine = createEngine({ db, github, clock, repos: () => watched, settings: () => settings, profileDeclared: () => true, runner, workspaces, quota: fakeQuota.read, places: enginePlacesOf(dir), skills: new FakeSkills() });
  const started = engine.start();
  await settle(); // the start marked the execution interrupted and is preparing the workspace of the launch
  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('engine unavailable');
  opens();
  await started;
  await settle();

  expect(runner.tasks).toHaveLength(1);
  expect(recovered(db)).toEqual([]);
  // once the start has recovered, a request is answered as any other
  expect(await refusal(engine.recoverEpic('AshuLab/a', 1))).toBe('agent alive');
  engine.stop();
});

test('a plain resume leaves a resumed event from ship, like one that names a stage', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review');
  await resumeFrom(engine, undefined);
  expect(eventsOf(engine.db).filter((e) => e.type === 'resumed').map((e) => e.data)).toEqual([{ from: 'ship', by: 'command' }]);
});

test('extraRounds is refused when the epic did not stop on the review limit, and nothing changes', async () => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review', { needsHumanKind: 'agent_needs_human' });
  for (const from of ['review', 'fix'] as const) expect(await refusal(engine.resumeEpic('AshuLab/a', 1, { from, extraRounds: 3 }))).toBe('extra rounds need a review limit');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', roundLimit: null, resumeStage: null });
  expect(runner.tasks).toEqual([]);
});

// --- labels written right ---

const withReady = (...labels: string[]) => ['solve:epic', defaultLabels.ready, ...labels];

test('a failed removal of ready while the epic ran cannot restart the stopped epic at the next poll, and the removal is retried', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'asked', labelPending: true, stage: null });
  github.ready = { 'AshuLab/a': ready(1) };
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: withReady() } }; // the removal while it ran failed: ready is still there
  const set = github.setLabels.bind(github);
  let failures = 1;
  github.setLabels = async (repo, issue, change) => {
    if (failures-- > 0) throw new GitHubUnavailable('network', 'down'); // the first removal fails again
    return set(repo, issue, change);
  };

  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', labelPending: true });
  expect(labelsOf(1)).toContain(defaultLabels.ready);

  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', labelPending: false });
  expect(labelsOf(1)).toEqual(['solve:epic', 'carrier:status:needs-human']);
  expect(runner.tasks).toEqual([]);

  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' });
  expect(runner.tasks).toEqual([]);
});

test.each(['ready_for_test', 'needs_human', 'merged', 'cancelled'] as const)('ready comes off the issue of an epic in %s', async (status) => {
  const db = open();
  seedEpic(db, 1, { status, labelPending: true, stage: null, ...(status === 'needs_human' && { needsHumanKind: 'agent_needs_human' as const }) });
  github.issues = { 'AshuLab/a#1': { state: status === 'merged' || status === 'cancelled' ? 'closed' : 'open', labels: withReady() } };
  await start(1);
  await clock.advance(5 * MIN);
  expect(labelsOf(1)).not.toContain(defaultLabels.ready);
  expect(rows(db)[0]).toMatchObject({ status, labelPending: false });
});

test('the ready a resume puts on a stopped epic whose labels are still pending is read by the poll, and the epic starts', async () => {
  const engine = await start(1);
  seedEpic(engine.db, 1, { status: 'needs_human', needsHumanKind: 'agent_needs_human', needsHumanReason: 'asked', labelPending: true, stage: null });
  github.ready = { 'AshuLab/a': ready(1) };
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: ['solve:epic'] } };
  runner.behavior = () => ({ exit: 'hang' });
  await resumeFrom(engine, undefined);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship' });
  expect(labelsOf(1)).toEqual(['solve:epic', 'carrier:status:running']); // started, and the ready it started on came off
});

test('the ready a wake-up puts on a stopped epic is read by the poll before the reconciliation takes it off, and the epic starts', async () => {
  const engine = await stoppedForQuota();
  fakeQuota.snapshots['/cfg/claude'] = back();
  engine.db.update(epics).set({ labelPending: true }).run(); // a label write of the stop is still pending when the epic wakes
  github.issue('AshuLab/a', 1).labels = ['solve:epic', 'carrier:status:needs-human'];
  await clock.advance(WAKE - clock.now() + 5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'ship', autoResumes: 1 });
  expect(labelsOf(1)).toEqual(['solve:epic', 'carrier:status:running']);
});

test('with every stage and reason label configured a status change removes only the owned labels the issue has', async () => {
  const stages = { ship: 'carrier:building', review: 'carrier:reviewing', fix: 'carrier:fixing' };
  const reasons = { agent_needs_human: 'carrier:asked', timeout: 'carrier:slow', retries_exhausted: 'carrier:retries', review_limit: 'carrier:limit' };
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's', write: completed(task) } : { exit: 'stopped' });
  const engine = await start(1);
  settings.labels = { ...defaultLabels, stages, reasons };
  const set = github.setLabels.bind(github);
  const removals: { label: string; present: boolean }[] = [];
  github.setLabels = async (repo, issue, change) => {
    const present = github.issue(repo, issue).labels;
    for (const label of change.remove) removals.push({ label, present: present.includes(label) });
    return set(repo, issue, change);
  };
  await clock.advance(5 * MIN);
  await engine.idle();
  expect(removals.length).toBeGreaterThan(0);
  expect(removals.filter((r) => !r.present)).toEqual([]); // no removal for a label the issue lacks
  expect(removals.length).toBeLessThan(Object.keys(stages).length + Object.keys(reasons).length + 4); // and not one for each label that could be there
});

test('an issue that carries an old default name keeps it when its status changes: Carrier adds the new label and never removes the old one', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  github.issues = { 'AshuLab/a#1': { state: 'open', labels: ['solve:epic', 'solve:epic:ready', 'solve:epic:running'] } };
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running' });
  expect([...labelsOf(1)].sort()).toEqual(['carrier:status:running', 'solve:epic', 'solve:epic:running']);
});

test('the open listing of a repo is read once per repo and cycle, and the ready epics come from it', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  runner.behavior = () => ({ exit: 'hang' });
  const listing = vi.spyOn(github, 'listOpenEpics');
  await start(1);
  await clock.advance(5 * MIN);
  expect(listing.mock.calls.map(([repo]) => repo)).toEqual(['AshuLab/a', 'AshuLab/b']);
  await clock.advance(5 * MIN);
  expect(listing).toHaveBeenCalledTimes(4);
});

test('no label is written for a repo that left the config, whatever the status of the epic', async () => {
  const db = open();
  for (const [issue, status] of [[1, 'running'], [2, 'ready_for_test'], [3, 'merged'], [4, 'cancelled'], [5, 'needs_human']] as const) {
    seedEpic(db, issue, { status, labelPending: true, ...(status === 'needs_human' && { needsHumanKind: 'agent_needs_human' as const }) });
  }
  runner.alive.add('e1');
  seedExecution(db, 'e1', 1);
  const touched = githubRepoCalls();
  await start(1, [repos[1]!]);
  await clock.advance(5 * MIN);
  expect(touched.filter((call) => call.endsWith('AshuLab/a') && /setLabels|createLabel|listLabels/.test(call))).toEqual([]);
  expect(rows(db).every((e) => e.labelPending)).toBe(true);
});

// --- the slots of a review: what is of the epic reads as of the slot (ADR 0048) ---

// An epic with the mandatory reviewer and one extra: the extra reviewers are kept by the saved configuration, which the config of the slice that reads them fills.
const extraReviewer = { profile: 'c', option: 'o', harness: 'codex' as const, model: 'm' };
const twoReviewers = (over: Partial<EffectiveRepoConfig> = {}): EffectiveRepoConfig => ({ ...repos[0]!, agents: { ...agents, extraReviewers: [extraReviewer] } as EffectiveRepoConfig['agents'], ...over });
const inReview = (db: Db, extra: Partial<typeof epics.$inferInsert> = {}, config = twoReviewers()) => {
  seedEpic(db, 1, { stage: 'review', round: 1, prNumber: 50, prHeadSha: SHA, config, ...extra });
  pull(50);
};
const reviewRow = (db: Db, executionId: string, reviewer: 'reviewer' | 'reviewer-2', extra: Partial<typeof executions.$inferInsert> = {}) =>
  seedExecution(db, executionId, 1, { stage: 'review', reviewer, round: 1, headSha: SHA, ...extra });
const apiFailure = { status: 'failed' as const, error: 'boom', failureKind: 'api_error' as const };
const retriedSlots = () => runner.tasks.map((t) => t.reviewer);

test('a review execution is stored with its slot, the task carries it, and ship and fix carry none', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'hang' });
  const engine = await start(1);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(2));

  expect(runner.tasks.map((t) => [t.stage, t.reviewer])).toEqual([['ship', undefined], ['review', 'reviewer']]);
  expect(executionsOf(engine.db).map((e) => [e.stage, e.reviewer])).toEqual([['ship', null], ['review', 'reviewer']]);
});

test('two slots whose failures are seeded retry each on its own wait, the epic shows the earliest due time, and a restart of the engine finds each', async () => {
  const db = open();
  inReview(db, { retryAt: 5 * MIN + 20_000 });
  reviewRow(db, 'r1', 'reviewer', { ...apiFailure, startedAt: 5 * MIN - 10_000, finishedAt: 5 * MIN - 10_000 }); // due 20 s after the first poll
  reviewRow(db, 'r2', 'reviewer-2', { ...apiFailure, startedAt: 5 * MIN - 5_000, finishedAt: 5 * MIN }); // due 30 s after it
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1); // the engine starts on a database that has the failures: nothing in memory knows them
  await clock.advance(5 * MIN);
  expect(runner.tasks).toHaveLength(0);

  await clock.advance(20_000 - 1);
  await flush();
  expect(runner.tasks).toHaveLength(0);
  await clock.advance(1);
  await vi.waitFor(() => expect(retriedSlots()).toEqual(['reviewer']));
  expect(rows(engine.db)[0]).toMatchObject({ retryAt: 5 * MIN + 30_000 }); // what is left waiting is the other slot's

  await clock.advance(10_000);
  await vi.waitFor(() => expect(retriedSlots()).toEqual(['reviewer', 'reviewer-2']));
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', retryAt: null });
  expect(runner.tasks.map((t) => t.resumeSession)).toEqual(['s-r1', 's-r2']);
  expect(executionsOf(engine.db).map((e) => [e.executionId === 'r1' || e.executionId === 'r2' ? e.executionId : 'retry', e.reviewer])).toEqual([['r1', 'reviewer'], ['r2', 'reviewer-2'], ['retry', 'reviewer'], ['retry', 'reviewer-2']]);
});

test('the failover of a slot reads the options that ran out in its own executions: another slot running out on an option does not take it from this one', async () => {
  const claude = { harness: 'claude' as const, model: 'opus' };
  const codex = { harness: 'codex' as const, model: 'gpt' };
  const config = twoReviewers({
    providers: { claude, codex } as any,
    failover: { roles: { reviewer: [{ provider: 'claude' }] } },
    agents: { author: { profile: 'a', option: 'claude', ...claude }, reviewer: { profile: 'b', option: 'codex', ...codex }, extraReviewers: [{ ...extraReviewer, option: 'claude', ...claude }] } as EffectiveRepoConfig['agents'],
  });
  const db = open();
  inReview(db, {}, config);
  reviewRow(db, 'r2', 'reviewer-2', { status: 'failed', failureKind: 'usage_limit', option: 'claude', model: 'opus', startedAt: 1 }); // the extra reviewer ran out on claude
  reviewRow(db, 'r1', 'reviewer', { status: 'failed', failureKind: 'usage_limit', option: 'codex', model: 'gpt', startedAt: 2 });
  runner.behavior = () => ({ exit: 'hang' });
  await start(1);

  // Read by the epic, claude had run out and no step would be left; read by the slot, claude is the next step of the mandatory reviewer.
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(1));
  expect(runner.tasks[0]).toMatchObject({ stage: 'review', reviewer: 'reviewer', option: 'claude' });
});

test('the quota probe and the wake-up read the slot: the options another slot ran out of are not asked, and the epic wakes on the option that came back', async () => {
  const lazy = { harness: 'codex' as const, model: 'gpt', configDir: '/cfg/spare' };
  const eager = { harness: 'claude' as const, model: 'opus', configDir: '/cfg/claude' };
  const config = twoReviewers({
    providers: { claude: eager, spare: lazy } as any,
    agents: { author: { profile: 'a', option: 'claude', ...eager }, reviewer: { profile: 'b', option: 'spare', ...lazy }, extraReviewers: [{ ...extraReviewer, option: 'claude', ...eager }] } as EffectiveRepoConfig['agents'],
  });
  const db = open();
  inReview(db, { status: 'needs_human', needsHumanKind: 'usage_limit', needsHumanReason: 'ran out', resumeAt: MIN, config });
  reviewRow(db, 'r1', 'reviewer', { status: 'failed', failureKind: 'usage_limit', option: 'spare', model: 'gpt', configDir: '/cfg/spare', harness: 'codex', startedAt: 1 });
  reviewRow(db, 'r2', 'reviewer-2', { status: 'failed', failureKind: 'usage_limit', option: 'claude', model: 'opus', configDir: '/cfg/claude', harness: 'claude', startedAt: 2 }); // the epic's newest
  fakeQuota.snapshots['/cfg/spare'] = back('codex');
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 9 * HOUR);
  runner.behavior = () => ({ exit: 'hang' });
  await start(1, [config]);
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);

  expect(fakeQuota.asked).toEqual([{ provider: 'codex', configDir: '/cfg/spare' }]);
  expect(eventsOf(db).filter((e) => e.type === 'auto_resumed').map((e) => e.data)).toMatchObject([{ stage: 'review', option: 'spare' }]);
  await vi.waitFor(() => expect(runner.tasks.find((task) => task.reviewer === 'reviewer')).toMatchObject({ stage: 'review', option: 'spare' })); // the extra reviewer is kept, it runs again as well
});

test('a restart recovers each review slot from its own last execution: the slot whose agent was lost runs again, the one with a result is left alone', async () => {
  const db = open();
  inReview(db);
  reviewRow(db, 'r1', 'reviewer', { status: 'finished', startedAt: 1 });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'completed', result: JSON.stringify({ summary: 's' }) }).run();
  reviewRow(db, 'r2', 'reviewer-2', { status: 'running', startedAt: 2 }); // its agent died with the engine
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);

  expect(runner.tasks.map((t) => [t.reviewer, t.resumeSession])).toEqual([['reviewer-2', 's-r2']]);
  expect(statusOf(engine.db, 'r2')).toBe('interrupted');
  expect(statusOf(engine.db, 'r1')).toBe('finished');
  expect(executionsOf(engine.db).map((e) => e.reviewer)).toEqual(['reviewer', 'reviewer-2', 'reviewer-2']);
});

test('a slot that already settled with no verdict on the round\'s head is not recovered again: the poll counts no recovery for it', async () => {
  const db = open();
  inReview(db);
  reviewRow(db, 'r1', 'reviewer', { status: 'finished', startedAt: 1 });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'completed', result: JSON.stringify({ summary: 's' }) }).run();
  reviewRow(db, 'r2', 'reviewer-2', { status: 'failed', error: null, failureKind: 'usage_limit', failureDetail: 'resets 12:40pm', startedAt: 2, finishedAt: 2 });
  db.insert(epicEvents).values({ epicId: 1, at: 3, type: 'reviewer_no_verdict', data: { round: 1, headSha: SHA, none: { slot: 'reviewer-2', kind: 'usage_limit', why: 'out of quota' } } }).run();
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  const before = executionsOf(engine.db).length;
  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);
  await clock.advance(5 * MIN);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', recoveries: 0 });
  expect(executionsOf(engine.db)).toHaveLength(before);
  expect(noVerdictOf(engine.db).map((n) => n.slot)).toEqual(['reviewer-2']);
});

test('an epic with one reviewer relaunches the review whose result stands in the round, as it did before the slots', async () => {
  const db = open();
  inReview(db, {}, repos[0]!);
  reviewRow(db, 'r1', 'reviewer', { status: 'finished', startedAt: 1 });
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'completed', result: JSON.stringify({ summary: 's' }) }).run();
  runner.behavior = () => ({ exit: 'hang' });
  await start(1);

  expect(runner.tasks.map((t) => [t.stage, t.reviewer])).toEqual([['review', 'reviewer']]);
});

test('a restart recovers both slots when both lost their agent, each in its own session', async () => {
  const db = open();
  inReview(db);
  reviewRow(db, 'r1', 'reviewer', { status: 'running', startedAt: 1 });
  reviewRow(db, 'r2', 'reviewer-2', { status: 'running', startedAt: 2 });
  runner.behavior = () => ({ exit: 'hang' });
  await start(1);

  expect(runner.tasks.map((t) => [t.reviewer, t.resumeSession])).toEqual([['reviewer', 's-r1'], ['reviewer-2', 's-r2']]);
});

test('a slot that ends well does not reset the recoveries, the automatic resumes and the last error while another slot is recovering from a failure', async () => {
  const db = open();
  inReview(db, { recoveries: 2, autoResumes: 1, lastError: 'boom' });
  reviewRow(db, 'r2', 'reviewer-2', { ...apiFailure, failureDetail: 'HTTP 529', startedAt: 1, finishedAt: 1 });
  reviewRow(db, 'r1', 'reviewer', { status: 'running', startedAt: 2 });
  runner.behavior = (task) => ({ write: completed(task) });
  const engine = await start(1);
  await engine.idle();

  expect(executionsOf(engine.db).find((e) => e.executionId === 'r1')).toMatchObject({ status: 'interrupted' });
  const retried = executionsOf(engine.db).find((e) => e.reviewer === 'reviewer' && e.executionId !== 'r1')!;
  expect(retried.status).toBe('finished');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', recoveries: 2, autoResumes: 1, lastError: 'boom' }); // the round waits for the other slot's verdict
});

test('with no other slot failing, an execution that ends well resets them, as it does for one reviewer', async () => {
  const db = open();
  inReview(db, { recoveries: 2, autoResumes: 1, lastError: 'boom' });
  reviewRow(db, 'r1', 'reviewer', { status: 'running', startedAt: 2 });
  runner.behavior = (task) => ({ write: completed(task) });
  const engine = await start(1);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', recoveries: 0, autoResumes: 0, lastError: null });
});

// --- a review round of several reviewers: every slot on the same head, decided by their verdicts (ADR 0048) ---

const ok = { outcome: 'completed', verification: { ci: 'passed', evidence: 'ok' } };
const asks = (title: string, id?: string) => ({ outcome: 'changes_requested', blockers: [{ ...(id && { id }), title }] });
// A review answers on the head it was given with the verdict `by` has for its slot; a slot without one hangs.
const verdictBy = (by: Record<string, object | (() => object)>, when?: Promise<unknown>) => (task: AgentTask): Behavior => {
  const verdict = by[task.reviewer!];
  return verdict ? { when, write: result(task, { ...(typeof verdict === 'function' ? verdict() : verdict), pr: { number: 50, headSha: task.context.pr!.headSha } }) } : { exit: 'stopped' };
};
const reviewsOf = () => runner.tasks.filter((t) => t.stage === 'review').map((t) => [t.context.round, t.reviewer, t.context.pr!.headSha]);
const lateOpen = () => {
  let open!: () => void;
  const when = new Promise<void>((resolve) => (open = resolve));
  return { when, open };
};
// ship -> a round of every slot of `config` answered by `review` -> a fix answered by `fix`.
// `late` holds the reviewers' answers until every slot of the first round is launched, then lets them end together.
async function roundOf(review: (task: AgentTask) => Behavior, { fix = (() => ({ exit: 'stopped' })) as (task: AgentTask) => Behavior, maxReviews = 5, config = twoReviewers(), late = undefined as ReturnType<typeof lateOpen> | undefined } = {}) {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) } : task.stage === 'review' ? review(task) : fix(task));
  const engine = await start(1, [config], 4, 3, maxReviews);
  await clock.advance(5 * MIN);
  if (late) {
    await vi.waitFor(() => expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(roundSlotsOf(config)));
    late.open();
  }
  await engine.idle();
  return engine;
}
const roundSlotsOf = (config: EffectiveRepoConfig) => 1 + (config.agents.extraReviewers?.length ?? 0);
const fourReviewers = () => twoReviewers({ agents: { ...agents, extraReviewers: [extraReviewer, { ...extraReviewer, profile: 'd' }, { ...extraReviewer, profile: 'e' }] } as EffectiveRepoConfig['agents'] });

test('the author\'s ship launches every reviewer of the epic at once, each with its slot, its agent and its own checkout of the same commit', async () => {
  const engine = await roundOf(() => ({ exit: 'stopped' }));

  const reviews = runner.tasks.filter((t) => t.stage === 'review');
  expect(reviews.map((t) => [t.reviewer, t.profile, t.workspace])).toEqual([['reviewer', 'b', '/work/AshuLab/a/1/reviewer-50'], ['reviewer-2', 'c', '/work/AshuLab/a/1/reviewer-2-50']]);
  expect(new Set(reviews.map((t) => t.context.pr!.headSha))).toEqual(new Set([SHA]));
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review').map((e) => [e.reviewer, e.round, e.headSha, e.status])).toEqual([['reviewer', 1, SHA, 'interrupted'], ['reviewer-2', 1, SHA, 'interrupted']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 1 });
});

test('an epic with no extra reviewer launches one review, as it always did', async () => {
  const engine = await roundOf(() => ({ exit: 'stopped' }), { config: repos[0]! });
  expect(runner.tasks.filter((t) => t.stage === 'review').map((t) => t.reviewer)).toEqual(['reviewer']);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review')).toHaveLength(1);
});

test('each reviewer is launched with the skills of its own entry and with the shared identity of its own profile, not the epic\'s', async () => {
  const own = { review: { name: 'mine', named: true }, publish: null };
  await roundOf(() => ({ exit: 'stopped' }), { config: twoReviewers({ sharedIdentity: false, agents: { ...agents, extraReviewers: [{ ...extraReviewer, skills: own, sharedIdentity: true }] } as EffectiveRepoConfig['agents'] }) });

  const [first, second] = runner.tasks.filter((t) => t.stage === 'review');
  expect(first).toMatchObject({ reviewer: 'reviewer', sharedIdentity: false });
  expect(second).toMatchObject({ reviewer: 'reviewer-2', sharedIdentity: true, skills: { review: own } });
  expect(first!.skills!.review).not.toEqual(own);
  expect(first!.context.severalReviewers).toBe(true);
  expect(second!.context.severalReviewers).toBe(true);
});

test('a round is settled when every slot has a verdict: with all reviewers completed the epic is ready for test on the head they judged, with the first verification', async () => {
  const engine = await roundOf(verdictBy({ reviewer: ok, 'reviewer-2': { ...ok, verification: { ci: 'absent', evidence: 'second' } } }));

  expect(reviewsOf()).toEqual([[1, 'reviewer', SHA], [1, 'reviewer-2', SHA]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, reviewedSha: SHA, verification: ok.verification, finishedAt: 5 * MIN, labelPending: false });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
});

test('the round waits for the slot that has no verdict yet: the epic stays in review and the author is not launched', async () => {
  const engine = await roundOf(verdictBy({ reviewer: asks('x') }));
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 1 });
});

test('two reviewers that end together settle the round once: one fix, one next round', async () => {
  const { when, open } = lateOpen();
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : task.stage === 'review' ? verdictBy({ reviewer: asks('a', 'B1'), 'reviewer-2': asks('b', 'B1') }, when)(task) : { exit: 'stopped' });
  const engine = await start(1, [twoReviewers()]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2));
  open(); // both runs end in the same turn: both import their result before either settles the round
  await engine.idle();

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'fix']);
  expect(engine.db.select().from(callerResults).all().map((r) => r.outcome)).toEqual(['completed', 'changes_requested', 'changes_requested']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 1 });
});

test('when one reviewer asks for changes the author\'s fix gets its blockers, tagged with the reviewer, and the next round runs every reviewer on the new head, each given only its own blockers', async () => {
  const engine = await roundOf(
    (task) => (task.context.round === 1 ? verdictBy({ reviewer: ok, 'reviewer-2': asks('use the helper', 'B1') })(task) : { exit: 'stopped' }),
    { fix: (task) => (pull(50, { headSha: HEAD2 }), fixDone(task, HEAD2)) },
  );

  const fix = runner.tasks.find((t) => t.stage === 'fix')!;
  expect(fix.context.blockers).toEqual([{ id: 'B1', title: 'use the helper', reviewer: 'reviewer-2' }]);
  expect(fix.context.observations).toBeUndefined();
  expect(reviewsOf()).toEqual([[1, 'reviewer', SHA], [1, 'reviewer-2', SHA], [2, 'reviewer', HEAD2], [2, 'reviewer-2', HEAD2]]);
  const [, , round2, round2Extra] = runner.tasks.filter((t) => t.stage === 'review');
  expect(round2!.context.blockers).toEqual([]);
  expect(round2Extra!.context.blockers).toEqual([{ id: 'B1', title: 'use the helper' }]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, prHeadSha: HEAD2 });
});

test('two reviewers that ask for changes with the same id both reach the author, each under its reviewer', async () => {
  await roundOf(verdictBy({ reviewer: asks('first', 'B1'), 'reviewer-2': asks('second', 'B1') }));

  const fix = runner.tasks.find((t) => t.stage === 'fix')!;
  expect(fix.context.blockers).toEqual([{ id: 'B1', title: 'first', reviewer: 'reviewer' }, { id: 'B1', title: 'second', reviewer: 'reviewer-2' }]);
});

test('an epic with one reviewer shows the author the reviewer\'s own ids, with no prefix', async () => {
  await roundOf(verdictBy({ reviewer: asks('only', 'B1') }), { config: repos[0]! });
  expect(runner.tasks.find((t) => t.stage === 'fix')!.context.blockers).toEqual([{ id: 'B1', title: 'only' }]);
});

test('the open blockers of a reviewer that completed in the round after its own are not asked of the author again, those of another still are', async () => {
  await roundOf(
    (task) => (task.context.round === 1 ? verdictBy({ reviewer: asks('r1', 'B1'), 'reviewer-2': asks('r2', 'B1') })(task) : verdictBy({ reviewer: ok, 'reviewer-2': asks('r2 again', 'B1') })(task)),
    { fix: (task) => (pull(50, { headSha: HEAD2 }), fixDone(task, HEAD2)) },
  );
  const [firstFix, secondFix] = runner.tasks.filter((t) => t.stage === 'fix');
  expect(firstFix!.context.blockers!.map((b) => b.reviewer)).toEqual(['reviewer', 'reviewer-2']);
  expect(secondFix!.context.blockers).toEqual([{ id: 'B1', title: 'r2 again', reviewer: 'reviewer-2' }]);
});

test('a round of two reviewers that both ask for changes at the cap stops the epic with review_limit with no fix', async () => {
  const engine = await roundOf(verdictBy({ reviewer: asks('a'), 'reviewer-2': asks('b') }), { maxReviews: 1 });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'review_limit', round: 1 });
});

test('a round counts once toward the cap however many reviewers it has: maxReviews 2 allows two rounds of two reviewers', async () => {
  const engine = await roundOf(verdictBy({ reviewer: asks('a'), 'reviewer-2': asks('b') }), { maxReviews: 2, fix: (task) => fixDone(task) });
  expect(reviewsOf().map(([round]) => round)).toEqual([1, 1, 2, 2]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'review_limit', round: 2 });
});

test('when every verdict completed with observations the author gets those of all in the one pass, each with its reviewer, and the head that does not change is the agreed head', async () => {
  const engine = await roundOf(
    verdictBy({ reviewer: { ...ok, observations: [{ id: 'o1', title: 'rename' }] }, 'reviewer-2': { ...ok, observations: [{ id: 'o1', title: 'typo' }] } }),
    { fix: (task) => ({ write: result(task, { outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'absent', evidence: 'author' } }) }) },
  );

  const pass = runner.tasks.find((t) => t.stage === 'fix')!;
  expect(pass.context.observations).toEqual([{ id: 'o1', title: 'rename', reviewer: 'reviewer' }, { id: 'o1', title: 'typo', reviewer: 'reviewer-2' }]);
  expect(pass.context.blockers).toBeUndefined();
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, verification: ok.verification, observationsPassAt: 5 * MIN, unansweredObservations: null });
});

test('a pass that changes the head starts the next round of every reviewer, and the observations left at the last round count those of all reviewers', async () => {
  const engine = await roundOf(
    (task) => verdictBy({ reviewer: { ...ok, observations: [{ title: 'one' }] }, 'reviewer-2': { ...ok, observations: [{ title: 'two' }, { title: 'three' }] } })(task),
    { fix: (task) => (pull(50, { headSha: HEAD2 }), fixDone(task, HEAD2)) },
  );

  expect(reviewsOf()).toEqual([[1, 'reviewer', SHA], [1, 'reviewer-2', SHA], [2, 'reviewer', HEAD2], [2, 'reviewer-2', HEAD2]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 2, reviewedSha: HEAD2, observationsPassAt: 5 * MIN, unansweredObservations: 3, unansweredReason: 'already_taken' });
});

test('observations of two reviewers left at the last round the cap allows are counted together, with no pass', async () => {
  const engine = await roundOf(verdictBy({ reviewer: { ...ok, observations: [{ title: 'one' }] }, 'reviewer-2': { ...ok, observations: [{ title: 'two' }] } }), { maxReviews: 1 });
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', unansweredObservations: 2, unansweredReason: 'last_round', observationsPassAt: null });
});

test('the first result that finds the head moved stops the other runs of the round and launches it again on the new head, counting no round', async () => {
  const late = lateOpen();
  let moved = false;
  const engine = await roundOf((task) => {
    if (task.context.pr!.headSha === SHA && task.reviewer === 'reviewer') {
      if (!moved) pull(50, { headSha: HEAD2 });
      moved = true;
      return verdictBy({ reviewer: ok }, late.when)(task);
    }
    return task.context.pr!.headSha === SHA ? { exit: 'hang' } : verdictBy({ reviewer: ok, 'reviewer-2': ok })(task);
  }, { late });

  expect(reviewsOf()).toEqual([[1, 'reviewer', SHA], [1, 'reviewer-2', SHA], [1, 'reviewer', HEAD2], [1, 'reviewer-2', HEAD2]]);
  const stale = executionsOf(engine.db).find((e) => e.reviewer === 'reviewer-2' && e.headSha === SHA)!;
  expect(runner.stopped).toContain(stale.executionId);
  expect(stale.status).not.toBe('running');
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, prHeadSha: HEAD2, reviewedSha: HEAD2, headRepeats: 0 });
  expect(eventsOf(engine.db).filter((e) => e.type === 'review_repeated').map((e) => e.data)).toMatchObject([{ round: 1, from: SHA, to: HEAD2, repeats: 1 }]);
});

test('a retry that waited for GitHub while another slot repeated the round on a new head does not run the old head again beside the new round', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const late = lateOpen();
  const gate = lateOpen();
  const find = github.findPullRequest.bind(github);
  github.findPullRequest = async (...args) => (await gate.when, find(...args)); // the retry of reviewer-2 reads GitHub before it launches
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { write: completed(task) };
    if (task.context.pr!.headSha !== SHA) return { exit: 'stopped' };
    return task.reviewer === 'reviewer' ? verdictBy({ reviewer: ok }, late.when)(task) : { exit: 'failed' };
  };
  const engine = await start(1, [twoReviewers()]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(executionsOf(engine.db).filter((e) => e.reviewer === 'reviewer-2').map((e) => e.status)).toEqual(['failed']));

  pull(50, { headSha: HEAD2 }); // the head moves while reviewer-2 waits for GitHub
  late.open();
  await vi.waitFor(() => expect(reviewsOf()).toHaveLength(4));
  gate.open();
  await engine.idle();

  expect(reviewsOf()).toEqual([[1, 'reviewer', SHA], [1, 'reviewer-2', SHA], [1, 'reviewer', HEAD2], [1, 'reviewer-2', HEAD2]]);
  expect(executionsOf(engine.db).filter((e) => e.reviewer === 'reviewer-2').map((e) => [e.headSha, e.status])).toEqual([[SHA, 'failed'], [HEAD2, 'interrupted']]); // the old head's failure is not retried: the repeat made the slot again
});

test('a slot whose checkout was being prepared while another slot repeated the round on a new head is not launched on the old one', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const late = lateOpen();
  const gate = lateOpen();
  const prepare = workspaces.prepareReviewer.bind(workspaces);
  let held = false;
  workspaces.prepareReviewer = async (repo, epic, pr, options) => {
    if (options?.slot === 'reviewer-2' && !held) {
      held = true;
      await gate.when; // the checkout of reviewer-2 on the old head is slow
    }
    return prepare(repo, epic, pr, options);
  };
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : task.context.pr!.headSha === SHA && task.reviewer === 'reviewer' ? verdictBy({ reviewer: ok }, late.when)(task) : { exit: 'stopped' });
  const engine = await start(1, [twoReviewers()]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(reviewsOf()).toHaveLength(1));

  pull(50, { headSha: HEAD2 }); // reviewer finds the head moved while reviewer-2 is still being prepared
  late.open();
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ prHeadSha: HEAD2, headRepeats: 1 }));
  gate.open();
  await engine.idle();

  expect(reviewsOf()).toEqual([[1, 'reviewer', SHA], [1, 'reviewer', HEAD2], [1, 'reviewer-2', HEAD2]]);
});

test('four reviewers that find the same moved head are one repeat, and two repeats in a row count rounds: the third moved head stops the epic in pr_invalid', async () => {
  const heads = [HEAD2, HEAD3, HEAD4];
  const settled = lateOpen();
  const engine = await roundOf((task) => {
    // each reviewer of a round pushes to the next head the first time its round is seen, so all four judge a head that is gone
    const head = task.context.pr!.headSha;
    if (head === SHA || head === HEAD2 || head === HEAD3) {
      const next = heads[[SHA, HEAD2, HEAD3].indexOf(head)]!;
      pull(50, { headSha: next });
      return verdictBy(Object.fromEntries(['reviewer', 'reviewer-2', 'reviewer-3', 'reviewer-4'].map((slot) => [slot, ok])), settled.when)(task);
    }
    return { exit: 'hang' };
  }, { config: fourReviewers(), late: settled });

  const repeats = eventsOf(engine.db).filter((e) => e.type === 'review_repeated').map((e) => e.data);
  expect(repeats).toMatchObject([{ from: SHA, to: HEAD2, repeats: 1 }, { from: HEAD2, to: HEAD3, repeats: 2 }]); // four reviewers each, three rounds: two repeats and a stop
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'pr_invalid', round: 1, headRepeats: 2, reviewedSha: null });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('changed during the review 3 times in a row');
});

test('the count of repeats goes back to zero only when a round is decided on its own head, not when one of its reviewers completes', async () => {
  let pushed = false;
  const engine = await roundOf((task) => {
    if (task.context.pr!.headSha === SHA && task.reviewer === 'reviewer' && !pushed) {
      pushed = true;
      pull(50, { headSha: HEAD2 });
    }
    return verdictBy({ reviewer: ok, 'reviewer-2': ok })(task);
  });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: HEAD2, headRepeats: 0 });
  expect(eventsOf(engine.db).filter((e) => e.type === 'review_repeated')).toHaveLength(1);
});

test('a restart of the engine in the middle of a round finds from the rows which slots have a result, which lost their agent and which were never launched', async () => {
  const db = open();
  inReview(db, {}, twoReviewers({ agents: { ...agents, extraReviewers: [extraReviewer, { ...extraReviewer, profile: 'd' }, { ...extraReviewer, profile: 'e' }] } as EffectiveRepoConfig['agents'] }));
  reviewRow(db, 'r1', 'reviewer', { status: 'finished', startedAt: 1 }); // has its verdict
  db.insert(callerResults).values({ executionId: 'r1', outcome: 'completed', result: JSON.stringify({ outcome: 'completed', summary: 's', pr: { number: 50, headSha: SHA }, verification: ok.verification }) }).run();
  seedExecution(db, 'r2', 1, { stage: 'review', reviewer: 'reviewer-2', round: 1, headSha: SHA, status: 'running', startedAt: 2 }); // lost its agent with the engine
  // reviewer-3 and reviewer-4 were never launched
  runner.behavior = () => ({ exit: 'hang' });
  const engine = await start(1);
  await vi.waitFor(() => expect(runner.tasks).toHaveLength(3));

  expect(runner.tasks.map((t) => [t.reviewer, t.resumeSession])).toEqual([['reviewer-2', 's-r2'], ['reviewer-3', undefined], ['reviewer-4', undefined]]);
  expect(runner.tasks.map((t) => t.context.pr!.headSha)).toEqual([SHA, SHA, SHA]);
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review').map((e) => [e.reviewer, e.status])).toEqual([['reviewer', 'finished'], ['reviewer-2', 'interrupted'], ['reviewer-2', 'running'], ['reviewer-3', 'running'], ['reviewer-4', 'running']]);
});

// --- a reviewer with no verdict does not stop a round of several; with none the epic stops in reviewers_failed (ADR 0048) ---

const gives = (verdict: object) => (task: AgentTask): Behavior => ({ write: result(task, { ...verdict, pr: { number: 50, headSha: task.context.pr!.headSha } }) });
const cannotConclude = (task: AgentTask): Behavior => gives({ outcome: 'needs_human', reason: 'cannot verify' })(task);
const ranOut = (task: AgentTask): Behavior => ({ sessionId: `s-${task.reviewer}`, exit: 'failed', failure: outOfCredits });
const crashes = (): Behavior => ({ exit: 'failed' });
// Each slot answers as `by` says; a slot not named hangs.
const bySlot = (by: Record<string, (task: AgentTask) => Behavior>) => (task: AgentTask): Behavior => by[task.reviewer!]?.(task) ?? { exit: 'hang' };
const mine = { review: { name: 'mine', named: true }, publish: null };
const withExtras = (extras: object[]) => twoReviewers({ agents: { ...agents, extraReviewers: extras } as EffectiveRepoConfig['agents'] });
const absentSkill = () => { skills.answers = { mine: 'absent' }; };
// The retries of a technical failure are out once the waits between them have passed.
const outlast = async (engine: { idle(): Promise<void> }) => {
  for (let i = 0; i < 3; i++) await clock.advance(10 * MIN);
  await engine.idle();
};
const noVerdictOf = (db: Db) => eventsOf(db).filter((e) => e.type === 'reviewer_no_verdict').map((e) => (e.data as { none: { slot: string; kind: string; why: string } }).none);

// The four ways a reviewer settles with no verdict: what it does, the stop an epic with one reviewer has for it, and what the extra reviewer needs to have it.
const noVerdictCases = [
  { name: 'it answers needs_human', kind: 'agent_needs_human', behavior: cannotConclude, setUp: () => {}, slow: false, extra: {} },
  { name: 'it fails technically and its retries are out', kind: 'retries_exhausted', behavior: crashes, setUp: () => {}, slow: true, extra: {} },
  { name: 'it runs out of quota with no failover step left', kind: 'usage_limit', behavior: ranOut, setUp: () => {}, slow: false, extra: {} },
  { name: 'a skill the person named is absent', kind: 'skill_missing', behavior: () => ({ exit: 'hang' }) as Behavior, setUp: absentSkill, slow: false, extra: { skills: mine } },
] as const;

test.each(noVerdictCases)('with several reviewers, $name: the round goes on without it and the other reviewer\'s verdict decides', async ({ behavior, setUp, slow, extra }) => {
  setUp();
  const engine = await roundOf(bySlot({ reviewer: gives(ok), 'reviewer-2': behavior }), { config: withExtras([{ ...extraReviewer, ...extra }]) });
  if (slow) await outlast(engine);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', needsHumanKind: null, round: 1, reviewedSha: SHA, verification: ok.verification, lastError: null });
  expect(noVerdictOf(engine.db).map((n) => n.slot)).toEqual(['reviewer-2']);
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
});

test.each(noVerdictCases)('with one reviewer, $name: the epic stops with $kind, as it did', async ({ kind, behavior, setUp, slow }) => {
  setUp();
  const own = { ...repos[0]!, agents, ...(kind === 'skill_missing' && { skills: resolveSkills(solveSkills, { review: { review: 'mine' } }) }) } as EffectiveRepoConfig;
  const engine = await roundOf(bySlot({ reviewer: behavior }), { config: own });
  if (slow) await outlast(engine);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: kind });
  expect(noVerdictOf(engine.db)).toEqual([]);
});

test('a named skill that is absent for the mandatory reviewer stops the epic with skill_missing before any reviewer of the round is launched', async () => {
  skills.answers = { mine: 'absent' };
  const engine = await roundOf(() => ({ exit: 'hang' }), { config: twoReviewers({ skills: resolveSkills(solveSkills, { review: { review: 'mine' } }) }) });

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('the skill mine (skills.review.review) is not installed for the reviewer');
  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship']); // no run was spent on any slot
  expect(executionsOf(engine.db).filter((e) => e.stage === 'review')).toEqual([]);
  expect(noVerdictOf(engine.db)).toEqual([]);
});

test.each([
  ['a default skill that is absent', { review: { name: 'mine', named: false }, publish: null }, 'absent'],
  ['a named skill the check cannot tell', mine, 'cannot-tell'],
] as const)('%s never takes an extra reviewer out of the round', async (_, own, answer) => {
  skills.answers = { mine: answer };
  const engine = await roundOf(verdictBy({ reviewer: ok, 'reviewer-2': ok }), { config: withExtras([{ ...extraReviewer, skills: own }]) });

  expect(runner.tasks.filter((t) => t.stage === 'review').map((t) => t.reviewer)).toEqual(['reviewer', 'reviewer-2']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test' });
  expect(noVerdictOf(engine.db)).toEqual([]);
});

test('a slot that settled without an execution is stored: a restart of the engine reaches the same decision, spends no run on it and does not look for the skill again', async () => {
  absentSkill();
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : { exit: 'hang' });
  const first = await start(1, [withExtras([{ ...extraReviewer, skills: mine }])]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(noVerdictOf(first.db)).toHaveLength(1));
  expect(rows(first.db)[0]).toMatchObject({ status: 'running', stage: 'review' }); // the mandatory reviewer's verdict is still to come
  expect(noVerdictOf(first.db)[0]).toMatchObject({ slot: 'reviewer-2', kind: 'skill_missing' });
  expect(noVerdictOf(first.db)[0]!.why).toContain('the skill mine (skills.review.review)');
  first.stop();
  dbs.pop()!.$client.close();

  skills.asked = [];
  runner.tasks = [];
  runner.behavior = bySlot({ reviewer: gives(ok) });
  const second = await start(1, [withExtras([{ ...extraReviewer, skills: mine }])]);
  await second.idle();

  expect(runner.tasks.map((t) => t.reviewer)).toEqual(['reviewer']); // the slot with no verdict is not launched, nor looked at
  expect(skills.asked.filter((a) => a.name === 'mine')).toEqual([]);
  expect(executionsOf(second.db).filter((e) => e.reviewer === 'reviewer-2')).toEqual([]);
  expect(noVerdictOf(second.db)).toHaveLength(1); // stored once
  expect(rows(second.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA });
});

test('one verdict out of two is enough: the round counts it, and a sole verdict that asks for changes sends the author its blockers only', async () => {
  const engine = await roundOf(bySlot({ reviewer: gives(asks('use the helper', 'B1')), 'reviewer-2': cannotConclude }));

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'fix']);
  expect(runner.tasks.find((t) => t.stage === 'fix')!.context.blockers).toEqual([{ id: 'B1', title: 'use the helper', reviewer: 'reviewer' }]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'fix', round: 1 });
});

test('one verdict out of four is enough, whichever way the other three gave none', async () => {
  absentSkill();
  const config = withExtras([extraReviewer, { ...extraReviewer, profile: 'd' }, { ...extraReviewer, profile: 'e', skills: mine }]);
  const engine = await roundOf(bySlot({ reviewer: gives(ok), 'reviewer-2': cannotConclude, 'reviewer-3': ranOut }), { config });

  expect(noVerdictOf(engine.db).map((n) => [n.slot, n.kind])).toEqual(expect.arrayContaining([['reviewer-2', 'agent_needs_human'], ['reviewer-3', 'usage_limit'], ['reviewer-4', 'skill_missing']]));
  expect(noVerdictOf(engine.db)).toHaveLength(3);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA });
});

test('with no verdict at all the epic stops in needs-human with reviewers_failed, its reason naming each reviewer and why, and it does not wake by itself', async () => {
  absentSkill();
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + HOUR);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : bySlot({ reviewer: cannotConclude, 'reviewer-3': ranOut })(task)); // reviewer-2 has no run: its skill is absent
  const engine = await start(1, [withExtras([{ ...extraReviewer, skills: mine }, { ...extraReviewer, profile: 'd' }])]);
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);
  await engine.idle();

  const row = rows(engine.db)[0]!;
  expect(row).toMatchObject({ status: 'needs_human', needsHumanKind: 'reviewers_failed', resumeAt: null });
  expect(row.needsHumanReason).toContain('no reviewer gave a verdict in round 1');
  expect(row.needsHumanReason).toContain('reviewer: cannot verify');
  expect(row.needsHumanReason).toContain('reviewer-2: the skill mine (skills.review.review) is not installed for the reviewer-2');
  expect(row.needsHumanReason).toContain('reviewer-3: ran out of usage on option o');
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
  expect(fakeQuota.asked).toEqual([]);
  await clock.advance(24 * HOUR);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'reviewers_failed', autoResumes: 0 });
  expect(eventTypes(engine.db)).not.toContain('auto_resume_scheduled');
});

// --- a decided round of several is recorded as an event of the epic: how many gave a verdict of how many were configured, and why each other gave none ---

const roundsDecidedOf = (db: Db) => eventsOf(db).filter((e) => e.type === 'round_decided').map((e) => e.data);

test('a round of several that is decided records how many reviewers gave a verdict out of how many were configured, and why the other gave none', async () => {
  const engine = await roundOf(bySlot({ reviewer: gives(ok), 'reviewer-2': cannotConclude }));

  expect(roundsDecidedOf(engine.db)).toEqual([{ round: 1, headSha: SHA, decision: 'completed', given: 1, of: 2, none: [{ slot: 'reviewer-2', kind: 'agent_needs_human', why: 'cannot verify' }] }]);
});

test('a round where every reviewer gave a verdict records them all and no reason', async () => {
  const engine = await roundOf(verdictBy({ reviewer: ok, 'reviewer-2': asks('use the helper') }));

  expect(roundsDecidedOf(engine.db)).toEqual([{ round: 1, headSha: SHA, decision: 'changes_requested', given: 2, of: 2, none: [] }]);
});

test('each round of an epic records its own, and a round with no verdict at all records none given out of the configured', async () => {
  const engine = await roundOf(
    (task) => (task.context.round === 1 ? bySlot({ reviewer: gives(asks('x')), 'reviewer-2': cannotConclude })(task) : cannotConclude(task)),
    { fix: (task) => (pull(50, { headSha: HEAD2 }), fixDone(task, HEAD2)) },
  );

  expect(roundsDecidedOf(engine.db).map((d) => [(d as { round: number }).round, (d as { decision: string }).decision, (d as { given: number }).given, (d as { of: number }).of])).toEqual([[1, 'changes_requested', 1, 2], [2, 'failed', 0, 2]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'reviewers_failed' });
});

test('a round repeated on a moved head is not decided: only the round decided on the new head is recorded', async () => {
  const late = lateOpen();
  let moved = false;
  const engine = await roundOf((task) => {
    if (task.context.pr!.headSha === SHA && task.reviewer === 'reviewer') {
      if (!moved) pull(50, { headSha: HEAD2 });
      moved = true;
      return verdictBy({ reviewer: ok }, late.when)(task);
    }
    return task.context.pr!.headSha === SHA ? { exit: 'hang' } : verdictBy({ reviewer: ok, 'reviewer-2': ok })(task);
  }, { late });

  expect(roundsDecidedOf(engine.db)).toEqual([{ round: 1, headSha: HEAD2, decision: 'completed', given: 2, of: 2, none: [] }]);
});

test('an epic with one reviewer records no round event: nothing new for it', async () => {
  const engine = await roundOf(verdictBy({ reviewer: ok }), { config: repos[0]! });

  expect(roundsDecidedOf(engine.db)).toEqual([]);
});

// --- a reviewer whose blockers are still open and who gives no verdict is not agreement (ADR 0048) ---

const toHead2 = (task: AgentTask) => (pull(50, { headSha: HEAD2 }), fixDone(task, HEAD2));
// Round 1 is `first`, any later round `later`: each a map of the verdict of its slot.
const inRounds = (first: Record<string, (task: AgentTask) => Behavior>, later: Record<string, (task: AgentTask) => Behavior>) => (task: AgentTask) => bySlot(task.context.round === 1 ? first : later)(task);

test('a reviewer that asked for changes and gives no verdict in a later round keeps its blockers open: with every verdict that came completed the epic stops in reviewers_failed naming it, and no fix runs', async () => {
  const engine = await roundOf(inRounds({ reviewer: gives(ok), 'reviewer-2': gives(asks('use the helper', 'B1')) }, { reviewer: gives(ok), 'reviewer-2': cannotConclude }), { fix: toHead2 });

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'fix', 'review', 'review']);
  const row = rows(engine.db)[0]!;
  expect(row).toMatchObject({ status: 'needs_human', needsHumanKind: 'reviewers_failed', round: 2 });
  expect(row.needsHumanReason).toContain('reviewer-2 asked for changes before, its blockers are still open, and it gave no verdict (cannot verify)');
  expect(row.needsHumanReason).not.toContain('reviewer:');
  expect(labelsOf(1)).toEqual(['carrier:status:needs-human']);
});

test('the reviewer with open blockers that goes silent also stops the round when the others\' verdicts carry observations, which are not passed to the author', async () => {
  const engine = await roundOf(inRounds({ reviewer: gives(ok), 'reviewer-2': gives(asks('use the helper', 'B1')) }, { reviewer: gives({ ...ok, observations: [{ title: 'rename' }] }), 'reviewer-2': cannotConclude }), { fix: toHead2 });

  expect(runner.tasks.filter((t) => t.stage === 'fix')).toHaveLength(1);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'reviewers_failed' });
});

test('a reviewer with no verdict whose blockers are not open (it completed or never asked) does not stop the round', async () => {
  const engine = await roundOf(inRounds({ reviewer: gives(asks('first')), 'reviewer-2': gives(ok) }, { reviewer: gives(ok), 'reviewer-2': cannotConclude }), { fix: toHead2 });

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: HEAD2 });
});

test('when another reviewer asks for changes the fix goes ahead, and its list includes the blockers still open of the reviewer that gave none', async () => {
  const engine = await roundOf(
    inRounds({ reviewer: gives(ok), 'reviewer-2': gives(asks('use the helper', 'B1')) }, { reviewer: gives(asks('rename it', 'N1')), 'reviewer-2': cannotConclude }),
    { fix: toHead2, maxReviews: 5 },
  );

  const [, secondFix] = runner.tasks.filter((t) => t.stage === 'fix');
  expect(secondFix!.context.blockers).toEqual([{ id: 'N1', title: 'rename it', reviewer: 'reviewer' }, { id: 'B1', title: 'use the helper', reviewer: 'reviewer-2' }]);
  expect(rows(engine.db)[0]).not.toMatchObject({ needsHumanKind: 'reviewers_failed' });
});

test('two reviewers whose blockers have no id: the author sees each under its reviewer, each reviewer is given its own by title, and one that no longer lists it has it resolved', async () => {
  await roundOf(
    inRounds({ reviewer: gives(asks('first finding')), 'reviewer-2': gives(asks('second finding')) }, { reviewer: gives(asks('first finding')), 'reviewer-2': gives(ok) }),
    { fix: toHead2 },
  );

  const [firstFix, secondFix] = runner.tasks.filter((t) => t.stage === 'fix');
  expect(firstFix!.context.blockers).toEqual([{ title: 'first finding', reviewer: 'reviewer' }, { title: 'second finding', reviewer: 'reviewer-2' }]);
  const round2 = runner.tasks.filter((t) => t.stage === 'review' && t.context.round === 2);
  expect(round2.map((t) => [t.reviewer, t.context.blockers])).toEqual([['reviewer', [{ title: 'first finding' }]], ['reviewer-2', [{ title: 'second finding' }]]]);
  expect(secondFix!.context.blockers).toEqual([{ title: 'first finding', reviewer: 'reviewer' }]);
  expect(buildPrompt(firstFix!)).toContain('- reviewer: first finding\n- reviewer-2: second finding');
});

test('every reviewer reads the summaries of the rounds before in its next round, the author\'s on a contradiction included', async () => {
  await roundOf(
    inRounds({ reviewer: gives({ ...asks('a'), summary: 'reviewer round 1' }), 'reviewer-2': gives({ ...asks('b'), summary: 'reviewer-2 round 1' }) }, { reviewer: gives(ok), 'reviewer-2': gives(ok) }),
    { fix: (task) => (pull(50, { headSha: HEAD2 }), { write: result(task, { outcome: 'completed', summary: 'did not follow reviewer-2:B1, it contradicts reviewer:B1', pr: { number: 50, headSha: HEAD2 }, verification: { ci: 'absent', evidence: 'ok' } }) }) },
  );

  for (const task of runner.tasks.filter((t) => t.stage === 'review' && t.context.round === 2)) {
    expect(task.context.previousSummaries.slice(0, 3)).toEqual(['reviewer round 1', 'reviewer-2 round 1', 'did not follow reviewer-2:B1, it contradicts reviewer:B1']);
  }
});

// Two reviewers on two accounts: the mandatory one on `spare`, the extra one on `claude`.
const claudeEagerAccount = { harness: 'claude' as const, model: 'opus', configDir: '/cfg/claude' };
const spareLazyAccount = { harness: 'codex' as const, model: 'gpt', configDir: '/cfg/spare' };
const onTwoAccounts = (over: Partial<EffectiveRepoConfig> = {}, extra: object = {}) => twoReviewers({
  providers: { claude: claudeEagerAccount, spare: spareLazyAccount } as any,
  agents: { author: { profile: 'a', option: 'claude', ...claudeEagerAccount }, reviewer: { profile: 'b', option: 'spare', ...spareLazyAccount }, extraReviewers: [{ ...extraReviewer, option: 'claude', ...claudeEagerAccount, ...extra }] } as EffectiveRepoConfig['agents'],
  ...over,
});

test('with no verdict and every failure a quota one the epic stops with usage_limit, not reviewers_failed, wakes when the last window comes back, and auto-resume resumes it', async () => {
  fakeQuota.snapshots['/cfg/spare'] = full('codex', 5 * MIN + 2 * HOUR);
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 5 * MIN + 3 * HOUR);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : ranOut(task));
  const engine = await start(1, [onTwoAccounts()]);
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human' }));

  const WAKE_LAST = 5 * MIN + 3 * HOUR; // the window of the last of them to come back
  expect(rows(engine.db)[0]).toMatchObject({ needsHumanKind: 'usage_limit', resumeAt: WAKE_LAST });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('no reviewer gave a verdict, every one ran out of usage');
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('--reviewer <option>');
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('--reviewer-2 <option>');
  expect(fakeQuota.asked.map((t) => t.configDir).sort()).toEqual(['/cfg/claude', '/cfg/spare']);
  expect(eventsOf(engine.db).filter((e) => e.type === 'auto_resume_scheduled').map((e) => e.data)).toEqual([{ resumeAt: WAKE_LAST }]);

  // Both windows are back at the poll after the last one: the epic reviews again, every slot.
  fakeQuota.snapshots['/cfg/spare'] = back('codex');
  fakeQuota.snapshots['/cfg/claude'] = back();
  runner.behavior = () => ({ exit: 'hang' });
  await clock.advance(3 * HOUR);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', autoResumes: 1, resumeAt: null }));
  expect(eventTypes(engine.db)).toContain('auto_resumed');
});

test('a quota failure with another failure is no quota stop: the epic stops with reviewers_failed', async () => {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : bySlot({ reviewer: ranOut, 'reviewer-2': cannotConclude })(task));
  const engine = await start(1, [onTwoAccounts()]);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'reviewers_failed' });
});

test('each extra reviewer keeps its own failover and retry state: a usage limit moves only that slot, on its own steps or the reviewer role\'s, and what one slot spends does not count against the other', async () => {
  const codex = { harness: 'codex' as const, model: 'gpt', configDir: '/cfg/codex' };
  const spare = { harness: 'agy' as const, model: 'flash' };
  const config = twoReviewers({
    providers: { claude: claudeEagerAccount, codex, spare } as any,
    failover: { roles: { reviewer: [{ provider: 'claude' }] } },
    agents: { author: { profile: 'a', option: 'claude', ...claudeEagerAccount }, reviewer: { profile: 'b', option: 'codex', ...codex }, extraReviewers: [{ ...extraReviewer, option: 'claude', ...claudeEagerAccount, failover: [{ provider: 'spare' }] }] } as EffectiveRepoConfig['agents'],
  });
  let extraRuns = 0;
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => {
    if (task.stage === 'ship') return { write: completed(task) };
    if (task.reviewer === 'reviewer') return task.option === 'codex' ? ranOut(task) : { exit: 'hang' }; // runs out at once, moves on to claude
    if (task.option === 'claude') return ++extraRuns === 1 ? crashes() : ranOut(task); // crashes, is retried on its own, then runs out and moves to its own step
    return { exit: 'hang' };
  };
  const engine = await start(1, [config]);
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(runner.tasks.filter((t) => t.reviewer === 'reviewer-2').map((t) => t.option)).toEqual(['claude', 'claude', 'spare']));
  expect(eventsOf(engine.db).filter((e) => e.type === 'option_switched').map((e) => e.data)).toMatchObject([{ role: 'reviewer', from: 'codex', to: 'claude' }, { role: 'reviewer-2', from: 'claude', to: 'spare' }]);
  expect(runner.tasks.filter((t) => t.reviewer === 'reviewer').map((t) => t.option)).toEqual(['codex', 'claude']); // never delayed or moved by the other's
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review' });
});

// --- the lead reviewer: it reviews once after the reviewers agree, on the head they agreed on, and completes the epic ---

const leadAgent = { profile: 'e', option: 'o', harness: 'claude' as const, model: 'm' };
const leadSkills = { review: { name: 'my-lead', named: true }, publish: null };
const withLead = (config: EffectiveRepoConfig = repos[0]!, lead: Partial<typeof leadAgent> & { sharedIdentity?: true } = leadAgent): EffectiveRepoConfig => ({
  ...config,
  skills: { ...resolveSkills(solveSkills), lead: leadSkills },
  agents: { ...config.agents, leadReviewer: { ...leadAgent, ...lead } } as EffectiveRepoConfig['agents'],
});
const leadTasks = () => runner.tasks.filter((t) => t.stage === 'lead');
// The lead answers on the head it was given with `verdict`.
const leadSays = (verdict: object) => (task: AgentTask): Behavior => ({ write: result(task, { ...verdict, pr: { number: 50, headSha: task.context.pr!.headSha } }) });
// ship -> the reviewers answer with `review` -> (a fix with `fix`) -> the lead answers with `lead`.
async function leadFlow(review: (task: AgentTask) => Behavior, lead: (task: AgentTask) => Behavior, { config = withLead(twoReviewers()), fix = (() => ({ exit: 'stopped' })) as (task: AgentTask) => Behavior, labels = undefined as EngineSettings['labels'] | undefined } = {}) {
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : task.stage === 'review' ? review(task) : task.stage === 'lead' ? lead(task) : fix(task));
  const engine = await start(1, [config]);
  if (labels) settings.labels = labels;
  await clock.advance(5 * MIN);
  await engine.idle();
  return engine;
}
const bothAgree = verdictBy({ reviewer: { ...ok, summary: 'tickets covered' }, 'reviewer-2': { ...ok, summary: 'migration reversible' } });
const hang = () => ({ exit: 'stopped' as const }); // the run ends interrupted: the epic stays where it is

test('without a lead the agreed round goes to ready for test as before, with no lead round and no approved head', async () => {
  const engine = await leadFlow(bothAgree, hang, { config: twoReviewers() });

  expect(leadTasks()).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', stage: 'review', reviewedSha: SHA, leadRound: null, approvedSha: null });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
});

test('with a lead the agreed round sends the epic to the stage lead and launches one execution of the slot lead, in its own checkout, on the agreed head, with leadRound 1', async () => {
  const engine = await leadFlow(bothAgree, hang);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'lead', round: 1, leadRound: 1, reviewedSha: SHA, approvedSha: null, verification: ok.verification, finishedAt: null });
  expect(leadTasks()).toHaveLength(1);
  expect(leadTasks()[0]).toMatchObject({ stage: 'lead', reviewer: 'lead', profile: 'e', workspace: '/work/AshuLab/a/1/lead-50', context: { round: 1, pr: { number: 50, headSha: SHA } } });
  expect(executionsOf(engine.db).filter((e) => e.stage === 'lead').map((e) => [e.reviewer, e.round, e.headSha, e.status])).toEqual([['lead', 1, SHA, 'interrupted']]);
  expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2); // no reviewer runs again
});

test('an epic with one reviewer and a lead goes to the lead too, and its checkout is the lead\'s own, not the reviewer\'s', async () => {
  const engine = await leadFlow(verdictBy({ reviewer: ok }), hang, { config: withLead() });

  expect(rows(engine.db)[0]).toMatchObject({ stage: 'lead', leadRound: 1, reviewedSha: SHA });
  expect(leadTasks().map((t) => t.workspace)).toEqual(['/work/AshuLab/a/1/lead-50']);
  expect(runner.tasks.find((t) => t.stage === 'review')!.workspace).toBe('/work/AshuLab/a/1/reviewer-50');
});

test('the observations pass that ends with the head the reviewers agreed on sends the epic to the lead, on that head', async () => {
  const engine = await leadFlow(
    verdictBy({ reviewer: { ...ok, observations: [{ title: 'rename it' }] }, 'reviewer-2': ok }),
    hang,
    { fix: (task) => fixDone(task, SHA) },
  );

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'fix', 'lead']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'lead', leadRound: 1, reviewedSha: SHA, observationsPassAt: 5 * MIN });
  expect(leadTasks()[0]!.context.pr!.headSha).toBe(SHA);
});

test('the lead runs the skill resolved for it, with the shared-identity flag of its own profile, and is given the summaries of the reviewers that agreed', async () => {
  await leadFlow(bothAgree, hang, { config: withLead(twoReviewers(), { sharedIdentity: true }) });

  const [lead] = leadTasks();
  expect(lead!.skills!.lead).toEqual(leadSkills);
  expect(lead!.sharedIdentity).toBe(true); // the lead's profile is the author's, whatever the epic's own flag says
  expect(lead!.context.reviewerSummaries).toEqual([{ reviewer: 'reviewer', summary: 'tickets covered' }, { reviewer: 'reviewer-2', summary: 'migration reversible' }]);
  expect(lead!.context.previousSummaries).toEqual([]);
  const prompt = buildPrompt(lead!);
  expect(prompt).toContain('You are the lead reviewer');
  expect(prompt).toContain('Invoke /my-lead');
  expect(prompt).toContain('- reviewer-2: migration reversible');
});

test('a lead with a profile of its own is launched without the shared identity, even when the epic\'s author and reviewer share one', async () => {
  await leadFlow(bothAgree, hang, { config: { ...withLead(twoReviewers()), sharedIdentity: true } });
  expect(leadTasks()[0]!.sharedIdentity).toBe(false);
});

test('when the lead completes the epic is ready for test with the head it approved recorded, the head the reviewers agreed on kept, and its approval in an event', async () => {
  const approval = { submitted: true, url: 'https://github.com/AshuLab/a/pull/50#pullrequestreview-1' };
  const engine = await leadFlow(bothAgree, leadSays({ ...ok, approval }));

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', reviewedSha: SHA, approvedSha: SHA, leadRound: 1, finishedAt: 5 * MIN, labelPending: false, needsHumanReason: null });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
  expect(eventsOf(engine.db).filter((e) => e.type === 'lead_completed').map((e) => e.data)).toEqual([{ headSha: SHA, approval }]);
});

test.each([
  ['a lead that did not submit one', { approval: { submitted: false } }, false],
  ['a lead whose result carries none', {}, undefined],
])('%s does not block the flow: the epic is ready for test all the same', async (_name, extra, submitted) => {
  const engine = await leadFlow(bothAgree, leadSays({ ...ok, ...extra }));

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', approvedSha: SHA });
  expect(eventsOf(engine.db).filter((e) => e.type === 'lead_completed').map((e) => (e.data.approval as { submitted: boolean } | undefined)?.submitted)).toEqual([submitted]);
});

test('an approval on a result that is not a completed lead result is an invalid result, retried like any other, and records nothing', async () => {
  let runs = 0;
  const engine = await leadFlow(bothAgree, (task) => (++runs === 1 ? { write: result(task, { ...ok, stage: 'review', approval: { submitted: true }, pr: { number: 50, headSha: SHA } }) } : leadSays({ ...ok, approval: { submitted: true } })(task)));

  expect(executionsOf(engine.db).filter((e) => e.stage === 'lead').map((e) => [e.status, e.failureKind])).toEqual([['invalid_result', 'invalid_result'], ['finished', null]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', approvedSha: SHA });
  expect(eventsOf(engine.db).filter((e) => e.type === 'lead_completed')).toHaveLength(1);
});

test('a head that moves while the lead reviews sets its verdict aside and launches the lead again on the new head, not counted: the head the reviewers agreed on stays', async () => {
  const pushes = [HEAD2];
  const engine = await leadFlow(bothAgree, (task) => {
    const next = pushes.shift();
    if (next) pull(50, { headSha: next });
    return leadSays(ok)(task);
  });

  expect(leadTasks().map((t) => [t.context.round, t.context.pr!.headSha, t.workspace])).toEqual([[1, SHA, '/work/AshuLab/a/1/lead-50'], [1, HEAD2, '/work/AshuLab/a/1/lead-50']]);
  expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2); // the reviewers do not run again
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, leadRound: 1, prHeadSha: HEAD2, reviewedSha: SHA, approvedSha: HEAD2, headRepeats: 0 });
  expect(eventsOf(engine.db).filter((e) => e.type === 'review_repeated').map((e) => e.data)).toMatchObject([{ stage: 'lead', round: 1, from: SHA, to: HEAD2, repeats: 1 }]);
  expect(engine.db.select().from(callerResults).all().filter((r) => r.outcome === 'superseded')).toHaveLength(1);
  expect(eventsOf(engine.db).filter((e) => e.type === 'lead_completed').map((e) => e.data.headSha)).toEqual([HEAD2]); // the verdict set aside records no approval
});

test('a third head that moves in a row while the lead reviews stops the epic in pr_invalid, with the two repeats counted by the lead\'s reviews and nothing approved', async () => {
  const pushes = [HEAD2, HEAD3, HEAD4];
  const engine = await leadFlow(bothAgree, (task) => {
    const next = pushes.shift();
    if (next) pull(50, { headSha: next });
    return leadSays(ok)(task);
  });

  expect(leadTasks()).toHaveLength(3);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'pr_invalid', headRepeats: 2, reviewedSha: SHA, approvedSha: null });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('changed during the review 3 times in a row');
  expect(eventsOf(engine.db).filter((e) => e.type === 'lead_completed')).toEqual([]);
});

test('the lead\'s stage label is applied while the epic is in the stage lead, replaces the review\'s, and goes with the stage; the label is created like the others', async () => {
  const labels = { ...defaultLabels, stages: { review: 'carrier:reviewing', lead: 'carrier:stage:lead-reviewing' } };
  const engine = await leadFlow(bothAgree, hang, { labels });

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'lead', labelPending: false });
  expect([...labelsOf(1)].sort()).toEqual(['carrier:stage:lead-reviewing', 'carrier:status:running']);
  expect(github.repoLabels['AshuLab/a']).toContain('carrier:stage:lead-reviewing');
});

test('the lead\'s stage label goes when the lead completes: the epic shows only ready for test', async () => {
  const labels = { ...defaultLabels, stages: { review: 'carrier:reviewing', lead: 'carrier:stage:lead-reviewing' } };
  const engine = await leadFlow(bothAgree, leadSays(ok), { labels });

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', labelPending: false });
  expect(labelsOf(1)).toEqual(['carrier:status:ready-for-test']);
});

test('without a stage label for the lead the epic in the stage lead shows only running', async () => {
  const engine = await leadFlow(bothAgree, hang, { labels: { ...defaultLabels, stages: { review: 'carrier:reviewing' } } });

  expect(rows(engine.db)[0]).toMatchObject({ stage: 'lead' });
  expect(labelsOf(1)).toEqual(['carrier:status:running']);
});

// --- the lead asks for changes: the author fixes with the lead's blockers and only the lead reviews again, up to limits.maxLeadRounds ---

const leadAsks = (title: string, extra: object = {}) => leadSays({ outcome: 'changes_requested', blockers: [{ id: 'L1', title }], ...extra });
// The author's fix commits: the pull request has `head` and the fix says so.
const fixTo = (head: string) => (task: AgentTask): Behavior => {
  pull(50, { headSha: head });
  return { write: completed(task, { number: 50, headSha: head }) };
};
// The lead asks `asks` times, then completes; each fix commits the next head of `heads`.
const leadAfter = (asks: number, heads = [HEAD2, HEAD3, HEAD4]) => {
  let given = 0;
  return {
    lead: (task: AgentTask) => (++given <= asks ? leadAsks(`blocker ${given}`)(task) : leadSays(ok)(task)),
    fix: (task: AgentTask) => fixTo(heads.shift()!)(task),
  };
};

test('a lead that asks for changes below its limit sends the epic to the author fix with the lead\'s blockers only, and the lead reviews again on the head after the fix: the reviewers do not run again and the round stays', async () => {
  const { lead, fix } = leadAfter(1);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { sessionId: 's-ship', write: completed(task) } : task.stage === 'review' ? bothAgree(task) : task.stage === 'lead' ? lead(task) : fix(task));
  const engine = await start(1, [withLead(twoReviewers())], 4, 3, 1); // maxReviews 1: a lead exchange that counted as a round would hit it
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'lead', 'fix', 'lead']);
  const [fixTask] = runner.tasks.filter((t) => t.stage === 'fix');
  expect(fixTask).toMatchObject({ resumeSession: 's-ship', context: { round: 1, pr: { number: 50, headSha: SHA }, blockers: [{ id: 'L1', title: 'blocker 1' }] } });
  expect(fixTask!.context.observations).toBeUndefined();
  expect(buildPrompt(fixTask!)).toContain('- blocker 1');
  expect(leadTasks().map((t) => [t.context.round, t.context.pr!.headSha, t.workspace])).toEqual([[1, SHA, '/work/AshuLab/a/1/lead-50'], [1, HEAD2, '/work/AshuLab/a/1/lead-50']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, leadRound: 2, prHeadSha: HEAD2, reviewedSha: SHA, approvedSha: HEAD2 });
});

test('between the lead\'s request and its next review the epic is in the stage fix with the lead round kept, then back in the stage lead with one more', async () => {
  const { lead, fix } = leadAfter(1);
  let during: object | undefined;
  const engine = await leadFlow(bothAgree, lead, {
    fix: (task) => {
      during = rows(dbs.at(-1)!)[0];
      return fix(task);
    },
  });

  expect(during).toMatchObject({ status: 'running', stage: 'fix', round: 1, leadRound: 1, reviewedSha: SHA });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', stage: 'lead', leadRound: 2 });
});

test('a lead that asks for changes in each of its rounds stops the epic in lead_limit at maxLeadRounds, naming the lead and the limit, and launches no fix after the last', async () => {
  const { fix } = leadAfter(0);
  const engine = await leadFlow(bothAgree, (task) => leadAsks(`blocker ${leadTasks().length}`)(task), { fix });

  expect(runner.tasks.map((t) => t.stage)).toEqual(['ship', 'review', 'review', 'lead', 'fix', 'lead', 'fix', 'lead']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'lead_limit', stage: 'lead', leadRound: 3, round: 1, approvedSha: null });
  const reason = rows(engine.db)[0]!.needsHumanReason!;
  expect(reason).toContain('lead reviewer');
  expect(reason).toContain('3 rounds');
  expect(reason).toContain('limits.maxLeadRounds');
  expect(reason).toContain('blocker 3');
});

test('maxLeadRounds is read when the lead\'s answer is decided: raising it lets the epic go on, lowering it stops the epic at once', async () => {
  const raise = leadAfter(3, [HEAD2, HEAD3, HEAD4]);
  let raised = false;
  const engine = await leadFlow(bothAgree, (task) => {
    if (!raised && leadTasks().length === 3) {
      raised = true;
      settings.maxLeadRounds = 4; // the reload happens while the third review runs
    }
    return raise.lead(task);
  }, { fix: raise.fix });
  expect(leadTasks()).toHaveLength(4);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', leadRound: 4 });
});

test('a lowered maxLeadRounds stops the epic at the next decision', async () => {
  const lower = leadAfter(5);
  const engine = await leadFlow(bothAgree, (task) => {
    if (leadTasks().length === 2) settings.maxLeadRounds = 2;
    return lower.lead(task);
  }, { fix: lower.fix });
  expect(leadTasks()).toHaveLength(2);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'lead_limit', leadRound: 2 });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('2 rounds');
});

test('the lead\'s exchange does not count toward maxReviews: with maxReviews 1 the epic still ends up ready for test after the lead\'s fixes, and no round is added', async () => {
  const { lead, fix } = leadAfter(2);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : task.stage === 'review' ? bothAgree(task) : task.stage === 'lead' ? lead(task) : fix(task));
  const engine = await start(1, [withLead(twoReviewers())], 4, 3, 1);
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, leadRound: 3 });
  expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2);
  expect(eventsOf(engine.db).filter((e) => e.type === 'round_decided')).toHaveLength(1);
});

test('the lead\'s observations are kept with its result and are not sent to the author, and are not counted as left unanswered', async () => {
  const observations = [{ id: 'O1', title: 'a name could be clearer' }];
  const { fix } = leadAfter(1);
  let given = 0;
  const engine = await leadFlow(bothAgree, (task) => (++given === 1 ? leadAsks('blocker 1')(task) : leadSays({ ...ok, observations })(task)), { fix });

  const fixTask = runner.tasks.find((t) => t.stage === 'fix')!;
  expect(fixTask.context.blockers).toEqual([{ id: 'L1', title: 'blocker 1' }]);
  expect(fixTask.context.observations).toBeUndefined();
  expect(buildPrompt(fixTask)).not.toContain('a name could be clearer');
  const stored = engine.db.select().from(callerResults).all().filter((r) => leadTasks().some((t) => t.executionId === r.executionId));
  expect(stored.map((r) => (JSON.parse(r.result) as { observations: unknown }).observations)).toEqual([undefined, observations]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', unansweredObservations: null, unansweredReason: null });
  expect(eventsOf(engine.db).filter((e) => e.type === 'lead_completed').map((e) => e.data.observations)).toEqual([observations]); // shown with the event the lead's completion leaves
});

test('the reviewers\' own observations pass is still the observations pass: a lead after it that asks for changes gets only its blockers, never the reviewers\' observations', async () => {
  const observations = [{ id: 'O1', title: 'from a reviewer' }];
  let given = 0;
  const heads = [HEAD2, HEAD3];
  const engine = await leadFlow(
    verdictBy({ reviewer: { ...ok, observations }, 'reviewer-2': ok }),
    (task) => (++given === 1 ? leadAsks('blocker 1')(task) : leadSays(ok)(task)),
    { fix: (task) => fixTo(heads.shift()!)(task) },
  );

  const fixes = runner.tasks.filter((t) => t.stage === 'fix');
  expect(fixes.map((t) => [t.context.observations?.map((o) => o.title), t.context.blockers?.map((b) => b.title)])).toEqual([[['from a reviewer'], undefined], [undefined, ['blocker 1']]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', leadRound: 2 });
});

// A resume after the lead stopped the epic in lead_limit: the exchange starts over.
const lead3 = () => {
  const { fix } = leadAfter(0);
  return leadFlow(bothAgree, (task) => leadAsks(`blocker ${leadTasks().length}`)(task), { fix });
};
// The person puts `ready` back and resumes from `from`; what ran before is forgotten.
const resumeLead = async (engine: Awaited<ReturnType<typeof start>>, from: 'review' | 'fix') => {
  runner.tasks.length = 0;
  await clock.advance(MIN); // the person comes back later: the new attempt starts after the executions of the old one
  github.ready = { 'AshuLab/a': ready(1) };
  await resumeFrom(engine, from);
};

test('a resume at fix of an epic that stopped in lead_limit clears the lead round and the approved head, gives the fix the lead\'s latest blockers, and the fix goes back to the reviewers\' round, not to the lead', async () => {
  const engine = await lead3();
  expect(rows(engine.db)[0]).toMatchObject({ needsHumanKind: 'lead_limit', leadRound: 3 });
  const fixes: AgentTask[] = [];
  runner.behavior = (task) => (task.stage === 'fix' ? (fixes.push(task), fixTo(HEAD4)(task)) : { exit: 'stopped' });
  await resumeLead(engine, 'fix');
  await engine.idle();

  expect(fixes).toHaveLength(1);
  expect(fixes[0]!.context.blockers).toEqual([{ id: 'L1', title: 'blocker 3' }]);
  expect(fixes[0]!.context.observations).toBeUndefined();
  expect(runner.tasks.map((t) => t.stage)).toEqual(['fix', 'review', 'review']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'review', round: 2, leadRound: null, approvedSha: null });
});

test('after such a resume the lead gets its maxLeadRounds again once the reviewers agree', async () => {
  const engine = await lead3();
  const late = lateOpen(); // the reviewers answer once the resume is done
  runner.behavior = (task) => (task.stage === 'fix' ? fixTo(HEAD4)(task) : task.stage === 'review' ? verdictBy({ reviewer: ok, 'reviewer-2': ok }, late.when)(task) : leadAsks(`again ${leadTasks().length}`)(task));
  await resumeLead(engine, 'fix');
  late.open();
  await engine.idle();

  expect(runner.tasks.map((t) => t.stage)).toEqual(['fix', 'review', 'review', 'lead', 'fix', 'lead', 'fix', 'lead']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'lead_limit', leadRound: 3 });
});

test('a resume at review of an epic that stopped in lead_limit starts the reviewers\' round again on the head the pull request has, and the lead\'s exchange over once they agree', async () => {
  const engine = await lead3();
  runner.behavior = (task) => (task.stage === 'review' ? bothAgree(task) : { exit: 'stopped' });
  await resumeLead(engine, 'review');
  await engine.idle();

  expect(runner.tasks.map((t) => [t.stage, t.reviewer])).toEqual([['review', 'reviewer'], ['review', 'reviewer-2'], ['lead', 'lead']]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'lead', leadRound: 1, approvedSha: null });
});

test('a technical failure of the lead is retried as the lead, in its own slot and checkout, and then completes the epic', async () => {
  let runs = 0;
  const engine = await leadFlow(bothAgree, (task) => (++runs === 1 ? { exit: 'failed' } : leadSays(ok)(task)));

  expect(leadTasks().map((t) => [t.reviewer, t.workspace, t.context.verifyStateFirst ?? false])).toEqual([['lead', '/work/AshuLab/a/1/lead-50', false], ['lead', '/work/AshuLab/a/1/lead-50', true]]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', approvedSha: SHA });
});

test('a skill the person named for the lead that is absent stops the epic with skill_missing before a run is spent, and the lead\'s skills are the ones asked for', async () => {
  skills.answers['my-lead'] = 'absent';
  const engine = await leadFlow(bothAgree, hang);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('skills.lead.review');
  expect(leadTasks()).toEqual([]);
});

test('a restart that finds the epic in the stage lead with no lead execution launches the lead, never ship', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'lead', round: 1, prNumber: 50, prHeadSha: SHA, reviewedSha: SHA, leadRound: 1, config: withLead(twoReviewers()) });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
  await start(1);

  expect(runner.tasks.map((t) => [t.stage, t.reviewer])).toEqual([['lead', 'lead']]);
  expect(rows(db)[0]).toMatchObject({ stage: 'lead' });
});

test('a restart that finds the lead running when the engine died resumes its session in its own slot', async () => {
  const db = open();
  seedEpic(db, 1, { stage: 'lead', round: 1, prNumber: 50, prHeadSha: SHA, reviewedSha: SHA, leadRound: 1, config: withLead(twoReviewers()) });
  seedExecution(db, 'l1', 1, { stage: 'lead', reviewer: 'lead', round: 1, headSha: SHA, status: 'running', startedAt: 1 });
  pull(50);
  runner.behavior = () => ({ exit: 'hang' });
  await start(1);

  expect(runner.tasks.map((t) => [t.stage, t.reviewer, t.resumeSession])).toEqual([['lead', 'lead', 's-l1']]);
  expect(statusOf(db, 'l1')).toBe('interrupted');
});

test.each([
  ['a restart from ship', undefined],
  ['a resume at the reviewers\' round', 'review' as const],
  ['a resume at the author\'s fix', 'fix' as const],
])('%s of an epic that stopped at the lead clears its lead round and its approved head', async (_name, from) => {
  const engine = await start(1);
  stoppedAt(engine.db, 'review', { stage: 'lead' as never, leadRound: 1, approvedSha: SHA, needsHumanKind: 'lead_limit', config: withLead(twoReviewers()) });
  await resumeFrom(engine, from);

  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', leadRound: null, approvedSha: null });
});

test('the slot given back before an epic starts keeps no lead round: a requeue that keeps the work clears it while the epic waits', async () => {
  const engine = await start(0);
  stoppedAt(engine.db, 'review', { stage: 'lead' as never, leadRound: 1, approvedSha: SHA, needsHumanKind: 'lead_limit', config: withLead(twoReviewers()) });
  await resumeFrom(engine, 'review');

  expect(rows(engine.db)[0]).toMatchObject({ status: 'queued', leadRound: null, approvedSha: null, resumeStage: 'review' });
});

// --- the lead's failures: it names the lead when it stops the epic, quota has its own failover and wake-up, and its skills are checked at every launch ---

// The lead on `claude` (the fake quota knows its account) with `spare` to move to; the roles of the failover are the test's.
const leadOnClaude = (roles?: { reviewer?: { provider: string }[]; leadReviewer?: { provider: string }[] }): EffectiveRepoConfig => ({
  ...withLead(twoReviewers(), { option: 'claude', ...claudeAccount, profile: 'e' }),
  providers: { claude: claudeAccount, spare: spareAccount } as any,
  ...(roles && { failover: { roles } }),
});
const runsOut = (...options: string[]) => (task: AgentTask) => outOf(...options)(task, { exit: 'stopped' });

test('a lead that cannot conclude stops the epic with agent_needs_human, its reason names the lead and keeps what it said', async () => {
  const engine = await leadFlow(bothAgree, (task) => ({ write: result(task, { outcome: 'needs_human', reason: 'the migration cannot be verified' }) }));

  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'agent_needs_human' });
  expect(rows(engine.db)[0]!.needsHumanReason).toBe('the lead reviewer cannot conclude: the migration cannot be verified');
});

test('a lead that fails technically is retried with the waits of any execution, counted for the lead alone, and with the retries out the epic stops with retries_exhausted naming the lead', async () => {
  const engine = await leadFlow(bothAgree, () => ({ exit: 'failed' }));
  await clock.advance(HOUR);
  await engine.idle();

  const lead = executionsOf(engine.db).filter((e) => e.stage === 'lead');
  expect(lead.map((e) => [e.reviewer, e.status])).toEqual(Array(settings.maxExecutionRetries + 1).fill(['lead', 'failed']));
  expect(runner.tasks.filter((t) => t.stage === 'review')).toHaveLength(2); // the reviewers' own streaks are untouched
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'retries_exhausted' });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain(`ran out of lead retries (${settings.maxExecutionRetries + 1} attempts)`);
});

test('a usage limit of the lead moves it through failover.roles.leadReviewer, and with no step left the epic stops with usage_limit naming the lead and the way to restart it', async () => {
  const engine = await leadFlow(bothAgree, runsOut('claude', 'spare'), { config: leadOnClaude({ leadReviewer: [{ provider: 'spare' }] }) });

  expect(leadTasks().map((t) => t.option)).toEqual(['claude', 'spare']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit', stage: 'lead', leadRound: 1 });
  const reason = rows(engine.db)[0]!.needsHumanReason!;
  expect(reason).toContain('the lead execution ran out of usage on option spare');
  expect(reason).toContain('--lead <option>');
  expect(reason).toContain('no step left in failover');
  expect(eventsOf(engine.db).filter((e) => e.type === 'option_switched').map((e) => e.data)).toMatchObject([{ role: 'lead', from: 'claude', to: 'spare', stage: 'lead' }]);
});

test('with no steps of its own the lead takes failover.roles.reviewer', async () => {
  const engine = await leadFlow(bothAgree, (task) => outOf('claude')(task, leadSays(ok)(task)), { config: leadOnClaude({ reviewer: [{ provider: 'spare' }] }) });

  expect(leadTasks().map((t) => t.option)).toEqual(['claude', 'spare']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test' });
});

test('a lead with an empty list of its own does not take the reviewer\'s steps', async () => {
  const engine = await leadFlow(bothAgree, runsOut('claude'), { config: leadOnClaude({ reviewer: [{ provider: 'spare' }], leadReviewer: [] }) });

  expect(leadTasks().map((t) => t.option)).toEqual(['claude']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit' });
});

// The lead runs out on `claude`; the fake quota says its window is back at WAKE.
async function leadStoppedForQuota(config = leadOnClaude()) {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', WAKE);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : task.stage === 'review' ? bothAgree(task) : runsOut('claude')(task));
  const engine = await start(1, [config]);
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit' }));
  runner.behavior = (task) => (task.stage === 'lead' ? leadSays(ok)(task) : { exit: 'stopped' });
  return engine;
}

test('a quota stop of the lead schedules the wake-up from the lead\'s own account, and the epic wakes up at the stage lead with its lead round kept and no review round repeated', async () => {
  const engine = await leadStoppedForQuota();
  expect(rows(engine.db)[0]).toMatchObject({ stage: 'lead', leadRound: 1, resumeAt: WAKE, reviewedSha: SHA });
  expect(fakeQuota.asked).toEqual([{ provider: 'claude', configDir: '/cfg/claude' }]);
  const before = runner.tasks.length;

  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(WAKE - clock.now() + 5 * MIN);
  await engine.idle();

  expect(runner.tasks.slice(before).map((t) => [t.stage, t.reviewer, t.option, t.context.round])).toEqual([['lead', 'lead', 'claude', 1]]);
  expect(eventsOf(engine.db).filter((e) => e.type === 'auto_resumed').map((e) => e.data)).toMatchObject([{ stage: 'lead', option: 'claude', resumeAt: WAKE, count: 1 }]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, leadRound: 1, resumeStage: null, resumeAt: null, approvedSha: SHA });
});

test('an author fix of the lead\'s exchange that ran out of usage wakes up in the stage fix with the lead round kept, and when it ends the lead reviews again with one more round, not the reviewers', async () => {
  fakeQuota.snapshots['/cfg/claude'] = full('claude', WAKE);
  github.ready = { 'AshuLab/a': ready(1) };
  pull(50);
  const base = leadOnClaude();
  const config = { ...base, agents: { ...base.agents, author: { profile: 'a', option: 'claude', ...claudeAccount } } } as EffectiveRepoConfig;
  runner.behavior = (task) => (task.stage === 'ship' ? { write: completed(task) } : task.stage === 'review' ? bothAgree(task) : task.stage === 'lead' ? leadAsks('blocker')(task) : runsOut('claude')(task));
  const engine = await start(1, [config]);
  settings = { ...settings, autoResume: true };
  await clock.advance(5 * MIN);
  await vi.waitFor(() => expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'usage_limit', stage: 'fix', leadRound: 1 }));
  const before = runner.tasks.length;
  runner.behavior = (task) => (task.stage === 'lead' ? leadSays(ok)(task) : fixTo(HEAD2)(task));

  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(WAKE - clock.now() + 5 * MIN);
  await engine.idle();

  expect(runner.tasks.slice(before).map((t) => t.stage)).toEqual(['fix', 'lead']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'ready_for_test', round: 1, leadRound: 2, approvedSha: HEAD2 });
});

test('the wake-up of the lead waits while its window is at 100% and does not touch the reviewers\' account', async () => {
  const engine = await leadStoppedForQuota();
  const before = runner.tasks.length;
  fakeQuota.snapshots['/cfg/claude'] = full('claude', 9 * HOUR);
  await clock.advance(WAKE - clock.now() + 5 * MIN);

  expect(runner.tasks).toHaveLength(before);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', stage: 'lead', resumeAt: WAKE, autoResumes: 0 });
});

test('a person\'s resume at review after the lead\'s quota stop starts the lead\'s exchange over: only the wake-up sets the stage lead', async () => {
  const engine = await leadStoppedForQuota();
  runner.tasks.length = 0;
  await clock.advance(MIN);
  await resumeFrom(engine, 'review');

  expect(rows(engine.db)[0]).toMatchObject({ stage: 'review', leadRound: null, resumeStage: null });
  expect(runner.tasks.map((t) => t.stage)).toContain('review');
});

test('a default skill of the lead that is absent, and an answer that cannot tell, never stop the epic', async () => {
  skills.has = async () => 'absent';
  const dflt = { ...withLead(twoReviewers()), skills: { ...resolveSkills(solveSkills), lead: { review: { name: 'code-review', named: false }, publish: null } } };
  const engine = await leadFlow(bothAgree, hang, { config: dflt });
  expect(rows(engine.db)[0]).toMatchObject({ status: 'running', stage: 'lead' });
  expect(leadTasks()).toHaveLength(1);

  skills.has = async () => 'cannot-tell';
  const unsure = await leadFlow(bothAgree, hang);
  expect(rows(unsure.db).at(-1)).toMatchObject({ status: 'running', stage: 'lead' });
});

test('a skill the person named for the lead that is absent stops the epic with the skill, the role lead and where it looked, spending no run and no retry', async () => {
  skills.answers['my-lead'] = 'absent';
  const engine = await leadFlow(bothAgree, hang);

  const reason = rows(engine.db)[0]!.needsHumanReason!;
  expect(reason).toContain('the skill my-lead (skills.lead.review) is not installed for the lead');
  expect(reason).toContain('claude looked where it finds skills');
  expect(executionsOf(engine.db).filter((e) => e.stage === 'lead')).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ needsHumanKind: 'skill_missing', recoveries: 0 });
});

test('a failover of the lead onto an option whose harness lacks the named skill stops the epic with skill_missing and spends no run on it', async () => {
  skills.has = async (harness) => (harness === 'codex' ? 'absent' : 'present');
  const engine = await leadFlow(bothAgree, runsOut('claude'), { config: leadOnClaude({ leadReviewer: [{ provider: 'spare' }] }) });

  expect(leadTasks().map((t) => t.option)).toEqual(['claude']);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
  expect(rows(engine.db)[0]!.needsHumanReason).toContain('is not installed for the lead: codex looked');
});

test('a wake-up of the lead stops with skill_missing when its named skill is absent now, and starts no run', async () => {
  const engine = await leadStoppedForQuota();
  const before = runner.tasks.length;
  skills.answers['my-lead'] = 'absent';
  fakeQuota.snapshots['/cfg/claude'] = back();
  await clock.advance(WAKE - clock.now() + 5 * MIN);
  await engine.idle();

  expect(runner.tasks).toHaveLength(before);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
});

test('a restart that changes the lead\'s option checks the skills for that option\'s harness', async () => {
  const named = { ...everyRole()[0]!, skills: { ...resolveSkills(solveSkills), lead: leadSkills } };
  const engine = await start(1, [named]);
  stoppedAt(engine.db, 'review', { config: named, authorOption: 'codex', reviewerOption: 'codex' });
  runner.behavior = (task) => (task.stage === 'review' ? verdictBy({ reviewer: ok, 'reviewer-2': ok, 'reviewer-3': ok })(task) : { exit: 'stopped' });
  skills.has = async (harness) => (harness === 'claude' ? 'absent' : 'present'); // the lead moves to claude, where its skill is not found
  void engine.resumeEpic('AshuLab/a', 1, { from: 'review', lead: 'claude' }).catch(() => {}); // it stops at the lead, so the resume never sees the epic stay running
  await flush();
  await clock.advance(5 * MIN);
  await engine.idle();

  expect(runner.tasks.filter((t) => t.stage === 'lead')).toEqual([]);
  expect(rows(engine.db)[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'skill_missing' });
});
