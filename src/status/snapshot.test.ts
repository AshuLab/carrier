import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics, epicStates } from '../storage/schema.ts';
import { renderPanel } from '../terminal/dashboard/plain.ts';
import { buildSnapshot, watchedOf } from './snapshot.ts';

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-snapshot-'));
  db = openDatabase(join(dir, 'carrier.db'));
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const add = (issue: number, status: (typeof epicStates)[number], extra: Partial<typeof epics.$inferInsert> = {}) =>
  db.insert(epics).values({ repo: 'acme/web', issue, status, ...extra }).returning().get();
let slices: Parameters<typeof buildSnapshot>[1]['slices'] = () => null;
const snapshot = (now = 100_000) => buildSnapshot(db, { now, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 40_000, repos: 2, nextCheckAt: 160_000, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 300_000 });

test('slots count the running epics, the queue lists the queued ones oldest first, and finished ones do not show', () => {
  add(5, 'queued');
  add(6, 'running');
  add(4, 'queued');
  for (const status of ['ready_for_test', 'merged', 'cancelled', 'repo_removed'] as const) add(10 + epicStates.indexOf(status), status);

  const s = snapshot();
  expect(s.slots).toEqual({ busy: 1, total: 3 });
  expect(s.queue).toEqual([{ repo: 'acme/web', issue: 5, title: null, queuedAt: 0 }, { repo: 'acme/web', issue: 4, title: null, queuedAt: 0 }]);
  expect(s.epics.map((e) => e.issue)).toEqual([6]);
});

test('an epic carries its stage, round, links, activity, error and the blockers of the last review that asked for changes', () => {
  const epic = add(12, 'running', {
    stage: 'fix', round: 2, prNumber: 50, startedAt: 1_000, stageStartedAt: 40_000, lastActivityAt: 90_000, lastError: 'the agent process ended with an error',
  });
  const base = { epicId: epic.id, stage: 'review' as const, resultPath: '/r', startedAt: 0 };
  const review = (executionId: string, outcome: string, result: object) => {
    db.insert(executions).values({ ...base, executionId }).run();
    db.insert(callerResults).values({ executionId, outcome, result: JSON.stringify(result) }).run();
  };
  review('r1', 'changes_requested', { blockers: [{ title: 'a' }, { title: 'b' }, { title: 'c' }] });
  review('r2', 'changes_requested', { blockers: [{ title: 'a' }, { title: 'b' }] });

  expect(snapshot().epics).toEqual([
    {
      repo: 'acme/web', issue: 12, status: 'running', stage: 'fix', round: 2, maxReviews: 5, blockers: 2, stageSince: 40_000, lastActivityAt: 90_000,
      issueUrl: 'https://github.com/acme/web/issues/12', prUrl: 'https://github.com/acme/web/pull/50',
      lastError: 'the agent process ended with an error', needsHumanReason: null, slices: null, executionId: 'r2',
      title: null, labels: [], queuedAt: 0, startedAt: 1_000, finishedAt: null, branch: null, workspace: null, needsHumanKind: null, blockerTitles: ['a', 'b'], agents: null,
    },
  ]);
});

test('what the engine does not keep yet is empty: no title, labels, branch, kind, watched repositories, sessions or rate limit', () => {
  add(1, 'queued', { queuedAt: 500 });
  add(2, 'running');
  const s = snapshot();
  expect(s.engine).toEqual({ version: '0.1.0', pollIntervalMs: 300_000, maxConcurrentEpics: 3, rateLimit: null });
  expect(s.watched).toEqual([]);
  expect(s.sessions).toEqual([]);
  expect(s.queue).toEqual([{ repo: 'acme/web', issue: 1, title: null, queuedAt: 500 }]);
});

test('watched lists every repo with the agents it resolves to and its last check, ok and unchecked before the first poll', () => {
  const agent = (harness: 'claude' | 'codex', model: string) => ({ profile: 'secret-profile', option: 'o', harness, model });
  const repos = ['acme/web', 'acme/api'].map((name) => ({ name, agents: { author: agent('claude', 'm-author'), reviewer: { ...agent('codex', 'm-review'), provider: 'ollama' as const } } }));
  const checks: Record<string, { at: number; ok: boolean; error: string | null }> = { 'acme/api': { at: 90_000, ok: false, error: 'GitHub unavailable (rate_limited: HTTP 403)' } };
  const watched = watchedOf(repos, (repo) => checks[repo]);
  const agents = { author: { harness: 'claude', model: 'm-author', provider: null }, reviewer: { harness: 'codex', model: 'm-review', provider: 'ollama' } };
  expect(watched).toEqual([
    { repo: 'acme/web', lastCheckedAt: null, ok: true, error: null, agents },
    { repo: 'acme/api', lastCheckedAt: 90_000, ok: false, error: 'GitHub unavailable (rate_limited: HTTP 403)', agents },
  ]);
  expect(buildSnapshot(db, { now: 1, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 2, nextCheckAt: null, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 1, watched }).watched).toBe(watched);
});

test('a running epic with a frozen config lists its running execution as a session, without the profile; blocker titles are capped', () => {
  const agent = { profile: 'secret-profile', option: 'o', harness: 'claude' as const, model: 'm-author' };
  const config = { name: 'acme/web', agents: { author: agent, reviewer: { profile: 'other', option: 'o', harness: 'codex' as const, model: 'm-review', provider: 'ollama' as const } } };
  const epic = add(7, 'running', { config, round: 2 });
  db.insert(executions).values({ executionId: 'e1', epicId: epic.id, stage: 'review', resultPath: '/r', startedAt: 10 }).run();
  db.insert(callerResults).values({ executionId: 'e1', outcome: 'changes_requested', result: JSON.stringify({ blockers: Array.from({ length: 12 }, () => ({ title: 'x'.repeat(300) })) }) }).run();
  db.insert(executions).values({ executionId: 'e2', epicId: epic.id, stage: 'fix', resultPath: '/r', startedAt: 20 }).run();

  const s = snapshot();
  expect(s.sessions).toEqual([{ executionId: 'e2', repo: 'acme/web', issue: 7, stage: 'fix', round: 2, harness: 'claude', model: 'm-author', startedAt: 20, last: null }]);
  expect(s.epics[0]?.agents).toEqual({ author: { harness: 'claude', model: 'm-author', provider: null }, reviewer: { harness: 'codex', model: 'm-review', provider: 'ollama' } });
  expect(s.epics[0]?.blockerTitles).toHaveLength(10);
  expect(s.epics[0]?.blockerTitles[0]).toHaveLength(200);
});

test('before the first stage the epic counts from its start, has no PR and no activity; a needs_human epic shows its reason', () => {
  add(1, 'running', { startedAt: 7_000 });
  add(2, 'needs_human', { stage: 'review', round: 5, prNumber: 9, stageStartedAt: 8_000, needsHumanReason: 'review limit' });

  const [first, second] = snapshot().epics;
  expect(first).toMatchObject({ stage: null, stageSince: 7_000, prUrl: null, lastActivityAt: null, blockers: 0 });
  expect(second).toMatchObject({ status: 'needs_human', needsHumanReason: 'review limit', round: 5 });
});

test('renders through renderPanel: the stage duration and the activity age come from the stored instants', () => {
  add(3, 'running', { stage: 'review', round: 1, stageStartedAt: 40_000, lastActivityAt: 95_000 });
  const lines = renderPanel(snapshot()).join('\n');
  expect(lines).toContain('in stage 1m');
  expect(lines).toContain('activity 5s ago');
  expect(lines).toContain('slots 1/3');
});

test('it carries the process facts and the epics that ended ready for test, most recent first, at most five', () => {
  for (let i = 1; i <= 7; i += 1) add(i, 'ready_for_test', { finishedAt: i * 1000, prNumber: 100 + i });
  add(50, 'merged', { finishedAt: 99_000 });
  const s = snapshot();
  expect([s.startedAt, s.repos, s.nextCheckAt, s.problem]).toEqual([40_000, 2, 160_000, null]);
  expect(s.done.map((d) => [d.issue, d.prNumber, d.finishedAt])).toEqual([[7, 107, 7000], [6, 106, 6000], [5, 105, 5000], [4, 104, 4000], [3, 103, 3000]]);
});

test('finished lists the merged and cancelled epics inside the window, newest first, and nothing else', () => {
  const day = 86_400_000;
  const now = 20 * day;
  const edge = now - 15 * day;
  const edgeEpic = add(1, 'merged', { finishedAt: edge, prNumber: 101, title: 'Edge', labels: ['solve:epic'] });
  add(2, 'merged', { finishedAt: edge - 1 });
  add(3, 'cancelled', { finishedAt: now - day, cancelReason: 'final PR closed' });
  add(4, 'merged', { finishedAt: now - 2 * day });
  add(5, 'merged', { finishedAt: null });
  for (const status of epicStates.filter((s) => s !== 'merged' && s !== 'cancelled')) add(10 + epicStates.indexOf(status), status, { finishedAt: now - 1000 });
  db.insert(executions).values({ executionId: 'exec-edge', epicId: edgeEpic.id, stage: 'ship', resultPath: '/r', startedAt: 1000 }).run();
  const s = snapshot(now);
  expect(s.finished.map((f) => [f.issue, f.status])).toEqual([[3, 'cancelled'], [4, 'merged'], [1, 'merged']]);
  expect(s.finished[0]).toEqual({ repo: 'acme/web', issue: 3, title: null, labels: [], prNumber: null, finishedAt: now - day, status: 'cancelled', cancelReason: 'final PR closed', executionId: null });
  expect(s.finished[2]).toEqual({ repo: 'acme/web', issue: 1, title: 'Edge', labels: ['solve:epic'], prNumber: 101, finishedAt: edge, status: 'merged', cancelReason: null, executionId: 'exec-edge' });
  expect(s.done.map((d) => d.issue)).toEqual([epicStates.indexOf('ready_for_test') + 10]);
});

test('a longer window lets older finished epics in', () => {
  add(1, 'merged', { finishedAt: 0 });
  const build = (finishedWindowDays: number) => buildSnapshot(db, { now: 20 * 86_400_000, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 300_000 });
  expect(build(15).finished).toEqual([]);
  expect(build(20).finished.map((f) => f.issue)).toEqual([1]);
});

test('an epic and a ready-for-test epic carry the id of their latest execution, where the agent output is', () => {
  const running = add(1, 'running');
  const done = add(2, 'ready_for_test', { finishedAt: 5000 });
  const exec = (executionId: string, epicId: number, startedAt: number) => db.insert(executions).values({ executionId, epicId, stage: 'ship', resultPath: '/r', startedAt }).run();
  exec('old', running.id, 1000);
  exec('new', running.id, 2000);
  exec('done-1', done.id, 1000);
  const s = snapshot();
  expect(s.epics[0]?.executionId).toBe('new');
  expect(s.done[0]?.executionId).toBe('done-1');
  expect(buildSnapshot(db, { now: 1, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: true, slices, version: '0.1.0', pollIntervalMs: 300_000 }).paused).toBe(true);
});

test('an epic carries its slices once they are known and null before', () => {
  add(12, 'running');
  add(13, 'running');
  expect(snapshot().epics.map((e) => e.slices)).toEqual([null, null]);
  slices = (repo, issue) => (repo === 'acme/web' && issue === 12 ? { done: 3, total: 5 } : null);
  expect(snapshot().epics.map((e) => e.slices)).toEqual([{ done: 3, total: 5 }, null]);
});
