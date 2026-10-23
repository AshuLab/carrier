import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { FakeAgentRunner, FakeWorkspaces, type Behavior } from '../execution/fake.ts';
import { createEngine } from '../orchestration/engine.ts';
import { FakeClock, FakeGitHub } from '../orchestration/fake.ts';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epicSlices } from '../storage/epic-slices.ts';
import { epics } from '../storage/schema.ts';
import { epicOf, MAX_ROUNDS } from './epic.ts';

const MIN = 60_000;
const CLIENT_LINE_LIMIT = 8 * 1024 * 1024; // macos/Sources/CarrierCore/ControlClient.swift maxLineBytes
const SHA = 'a'.repeat(40);
const agents = { author: { profile: 'a', harness: 'claude' as const, model: 'm' }, reviewer: { profile: 'b', harness: 'codex' as const, model: 'r' } };
const repos: EffectiveRepoConfig[] = [{ name: 'AshuLab/a', agents }];

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-'));
  db = openDatabase(join(dir, 'carrier.db'));
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const reply = () => epicOf(db, 'AshuLab/a', 1)!;
const titles = (round: { blockers: { title: string; mark: string }[] }) => round.blockers.map((b) => `${b.mark}:${b.title}`);

// --- the engine with its fakes: ship, then reviews that ask for the given blockers (or approve), a fix after each one ---

async function drive(script: (string[] | 'approved')[], { maxReviews = 5, flaky = false } = {}) {
  const github = new FakeGitHub();
  const clock = new FakeClock();
  const runner = new FakeAgentRunner();
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  github.pulls['AshuLab/a#50'] = { state: 'open', body: 'Closes #1', headSha: SHA, headRef: 'feat/epic' };
  const result = (task: AgentTask, extra: object): Behavior['write'] => ({ executionId: task.executionId, repo: task.repo, epic: task.epic, stage: task.stage, summary: 'done', ...extra });
  const pr = { number: 50, headSha: SHA };
  const failedOnce = new Set<string>();
  runner.behavior = (task) => {
    // a technical failure comes first, once per stage and round: it is retried inside the same round
    const key = `${task.stage}${task.context.round}`;
    if (flaky && task.stage !== 'ship' && failedOnce.has(key) === false) return failedOnce.add(key), { exit: 'failed' };
    if (task.stage === 'ship') return { write: result(task, { outcome: 'completed', pr, verification: { ci: 'absent', evidence: 'x' } }) };
    if (task.stage === 'fix') return { write: result(task, { outcome: 'completed', pr, verification: { ci: 'absent', evidence: 'x' } }) };
    const verdict = script[task.context.round! - 1];
    if (verdict === undefined) return { exit: 'stopped' };
    return { write: verdict === 'approved' ? result(task, { outcome: 'completed', pr, verification: { ci: 'passed', evidence: 'ok' } }) : result(task, { outcome: 'changes_requested', pr, blockers: verdict.map((title) => ({ title })) }) };
  };
  const engine = createEngine({
    db, github, clock, repos, pollIntervalMs: 5 * MIN, maxConcurrentEpics: 1, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews, runner, workspaces: new FakeWorkspaces(), root: dir,
  });
  await engine.start();
  await clock.advance(5 * MIN);
  await engine.idle();
  const again = async () => {
    github.issue('AshuLab/a', 1).labels.push('solve:epic:ready'); // a person puts it back
    await clock.advance(5 * MIN);
    await engine.idle();
  };
  return { again, runner };
}

test('approved in the first round: one round with no blockers, the reviewer, the timeline and the worktrees', async () => {
  await drive(['approved']);
  const epic = reply();
  expect(epic.rounds).toEqual([
    expect.objectContaining({ round: 1, reviewer: { harness: 'codex', model: 'r', provider: null }, verdict: 'approved', blockers: [], fixedSha: null, reviewedSha: SHA, commits: [] }),
  ]);
  expect(epic.stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'ready']);
  expect(epic.stages.at(-1)).toMatchObject({ stage: 'ready', endedAt: null });
  expect(epic.worktrees).toEqual([
    { kind: 'epic', lane: null, path: '/work/AshuLab/a/worktrees/feat/epic' },
    { kind: 'reviewer', lane: null, path: '/work/AshuLab/a/1/reviewer-50' },
  ]);
  expect(epic.slices).toEqual([]);
  expect(epic.pr).toBeNull();
});

test('fixed in two rounds: the second review approves and marks what the first asked as fixed', async () => {
  const { runner } = await drive([['Token expiry is not checked', 'Missing test'], 'approved']);
  const reviews = runner.tasks.filter((t) => t.stage === 'review');
  expect(reviews[0]!.context.blockers).toBeUndefined(); // round one has nothing earlier
  expect(reviews[1]!.context.blockers?.map((b) => b.title)).toEqual(['Token expiry is not checked', 'Missing test']);
  const { rounds, stages } = reply();
  expect(rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'approved']]);
  expect(titles(rounds[0]!)).toEqual(['new:Token expiry is not checked', 'new:Missing test']);
  expect(rounds[0]!.blockers.every((b) => b.approximate === false && b.id === null)).toBe(true);
  expect(titles(rounds[1]!)).toEqual(['fixed:Token expiry is not checked', 'fixed:Missing test']);
  expect(rounds[1]!.blockers.every((b) => b.approximate)).toBe(true);
  expect(stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'fix', 'review', 'ready']);
});

test('the limit: the last round is limit_reached, and the marks cover persisting, fixed and new, and a title changed only by case or spaces', async () => {
  await drive([['Token expiry', 'Missing test', 'Log leak'], ['token   EXPIRY ', 'Missing test', 'Brand new']], { maxReviews: 2 });
  const { rounds, stages } = reply();
  expect(rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'limit_reached']]);
  expect(titles(rounds[1]!)).toEqual(['carried:token   EXPIRY ', 'carried:Missing test', 'new:Brand new', 'fixed:Log leak']);
  expect(stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'fix', 'review']);
  expect(stages.at(-1)!.endedAt).not.toBeNull(); // the epic stopped
});

test('with ids the marks are exact for a persisting, a fixed and a new blocker; without them they stay approximate', () => {
  const id = epicRow();
  const review = (round: number, blockers: object[], extra: object = {}) =>
    run(id, 'review', round * 10, round * 10 + 1, { outcome: 'changes_requested', ...pr(SHA), blockers, ...extra }, round);
  review(1, [{ id: 'a', title: 'Token expiry' }, { id: 'b', title: 'Missing test' }, { id: 'c', title: 'Log leak' }]);
  // the persisting one is reworded (ids settle it), b is fixed and said so, c just disappeared, d is new
  review(2, [{ id: 'a', title: 'The token never expires' }, { id: 'd', title: 'Brand new' }], { resolved: ['b'] });
  const marks = (round: number) => reply().rounds[round]!.blockers.map((b) => [b.id, b.mark, b.approximate]);
  expect(marks(0)).toEqual([['a', 'new', false], ['b', 'new', false], ['c', 'new', false]]);
  expect(marks(1)).toEqual([['a', 'carried', false], ['d', 'new', false], ['b', 'fixed', false], ['c', 'fixed', false]]);

  // a later round with no ids at all falls back to titles and says so
  review(3, [{ title: 'brand   NEW' }, { title: 'Another' }]);
  expect(marks(2)).toEqual([[null, 'carried', true], [null, 'new', true], ['a', 'fixed', true]]);
});

test('a round carries the observations its completed review listed, in order; a round without any, or from before the field, has none', () => {
  const id = epicRow();
  run(id, 'review', 10, 11, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ title: 'A blocker' }] }, 1);
  run(id, 'fix', 12, 13, { outcome: 'completed', ...pr(SHA) }, 1);
  run(id, 'review', 20, 21, { outcome: 'completed', ...pr(SHA), observations: [{ id: 'o1', title: 'Rename x', url: 'https://github.com/o/r/pull/50#c1' }, { title: 'No id, no url' }, { id: 'o3', title: 'Long link', url: `https://github.com/o/r/${'u'.repeat(600)}` }] }, 2);
  run(id, 'review', 30, 31, { outcome: 'completed', ...pr(SHA), observations: [] }, 3);
  run(id, 'review', 40, 41, { outcome: 'completed', ...pr(SHA) }, 4);
  expect(reply().rounds.map((r) => r.observations)).toEqual([
    [],
    [{ id: 'o1', title: 'Rename x', url: 'https://github.com/o/r/pull/50#c1' }, { id: null, title: 'No id, no url', url: null }, { id: 'o3', title: 'Long link', url: null }],
    [],
    [],
  ]);
});

test('technical retries inside a round do not make a round', async () => {
  await drive([['Only blocker'], 'approved'], { flaky: true });
  const { rounds } = reply();
  expect(rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'approved']]);
  const retried = db.select().from(executions).all().filter((e) => e.status === 'failed');
  expect(retried.length).toBeGreaterThanOrEqual(3); // review 1, fix 1 and review 2 each failed once
  expect(rounds[0]!.fixMs).not.toBeNull(); // the fix that answered the round is the one that finished
});

test('an epic put back in the queue starts its rounds again, and the old ones stay readable', async () => {
  const { again, runner } = await drive([['One'], ['One']], { maxReviews: 2 });
  expect(reply().rounds.map((r) => r.verdict)).toEqual(['changes_requested', 'limit_reached']);

  const old = runner.behavior;
  runner.behavior = (task) => (task.stage === 'review' ? { write: { executionId: task.executionId, repo: task.repo, epic: task.epic, stage: 'review', summary: 'ok', outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } } } : old(task));
  await again();
  const epic = reply();
  expect(epic.rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'limit_reached'], [1, 'approved']]);
  expect(titles(epic.rounds[2]!)).toEqual([]); // nothing carried over from the old attempt
  expect(epic.stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'ready']); // the timeline is the current attempt's
});

test('an unknown epic is null', () => {
  expect(epicOf(db, 'AshuLab/a', 99)).toBeNull();
});

// --- rows written by hand, for exact times, a real repository and sizes ---

const config = { name: 'AshuLab/a', agents };
const epicRow = (extra: Partial<typeof epics.$inferInsert> = {}) =>
  db.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'ready_for_test', config, queuedAt: 500, startedAt: 1_000, finishedAt: 18_000, ...extra }).returning({ id: epics.id }).get().id;
let n = 0;
function run(epicId: number, stage: 'ship' | 'review' | 'fix', startedAt: number, finishedAt: number | null, result?: object, round: number | null = null) {
  const executionId = `e-${++n}`;
  db.insert(executions).values({ executionId, epicId, stage, status: 'finished', resultPath: '/r.json', startedAt, finishedAt, round, harness: 'codex', model: 'r', provider: null, workspace: `/reviews/${stage}` }).run();
  if (result) db.insert(callerResults).values({ executionId, outcome: (result as { outcome: string }).outcome, result: JSON.stringify(result) }).run();
}
const pr = (headSha: string) => ({ pr: { number: 50, headSha } });

const git = (cwd: string, ...args: string[]) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args], { cwd, encoding: 'utf8' }).trim();

test('durations, shas and the commits between them come from the executions and a real repository; a missing worktree gives none', () => {
  const repo = join(dir, 'worktree');
  execFileSync('git', ['init', '-q', '-b', 'feat/epic', repo]);
  const commit = (subject: string) => (git(repo, 'commit', '-q', '--allow-empty', '-m', subject), git(repo, 'rev-parse', 'HEAD'));
  const first = commit('feat: first');
  commit('fix(auth): check the expiry');
  const last = commit('test(auth): cover refresh');
  const id = epicRow({ workspace: repo });
  run(id, 'ship', 1_000, 5_000);
  run(id, 'review', 5_000, 9_000, { outcome: 'changes_requested', ...pr(first), blockers: [{ title: 'A', url: 'https://github.com/o/r/pull/50#c1' }] }, 1);
  run(id, 'fix', 9_000, 15_000, { outcome: 'completed', ...pr(last) }, 1);
  run(id, 'review', 15_000, 18_000, { outcome: 'completed', ...pr(last) }, 2);

  const epic = reply();
  expect(epic.stages).toEqual([
    { stage: 'queued', startedAt: 500, endedAt: 1_000 },
    { stage: 'ship', startedAt: 1_000, endedAt: 5_000 },
    { stage: 'review', startedAt: 5_000, endedAt: 9_000 },
    { stage: 'fix', startedAt: 9_000, endedAt: 15_000 },
    { stage: 'review', startedAt: 15_000, endedAt: 18_000 },
    { stage: 'ready', startedAt: 18_000, endedAt: null },
  ]);
  expect(epic.branch).toBe('feat/epic');
  expect(epic.rounds[0]).toMatchObject({ reviewMs: 4_000, fixMs: 6_000, reviewedSha: first, fixedSha: last });
  expect(epic.rounds[0]!.blockers[0]!.url).toBe('https://github.com/o/r/pull/50#c1');
  expect(epic.rounds[0]!.commits).toEqual([{ sha: last, subject: 'test(auth): cover refresh' }, { sha: expect.any(String), subject: 'fix(auth): check the expiry' }]);
  expect(epic.rounds[1]).toMatchObject({ reviewMs: 3_000, fixMs: null, fixedSha: null, commits: [] });

  db.update(epics).set({ workspace: join(dir, 'gone') }).run();
  const gone = reply();
  expect(gone.rounds[0]).toMatchObject({ reviewedSha: first, fixedSha: last, commits: [] });
  expect(gone.branch).toBeNull();
  expect(gone.worktrees[0]!.path).toBe(join(dir, 'gone'));
});

test('a queued epic has only its queue time, and a running one has an open stage', () => {
  const id = epicRow({ status: 'queued', startedAt: null, finishedAt: null });
  expect(reply()).toMatchObject({ stages: [{ stage: 'queued', startedAt: 500, endedAt: null }], rounds: [], worktrees: [], branch: null });
  db.update(epics).set({ status: 'running', startedAt: 1_000, stage: 'ship' }).run();
  run(id, 'ship', 1_100, null);
  expect(reply().stages).toEqual([{ stage: 'queued', startedAt: 500, endedAt: 1_000 }, { stage: 'ship', startedAt: 1_000, endedAt: null }]);
});

test('a merged epic answers like any other: its history closed at the merge, no ready stage, nothing live', () => {
  const id = epicRow({ status: 'merged', finishedAt: 20_000 });
  run(id, 'ship', 1_000, 5_000);
  run(id, 'review', 5_000, 9_000, { outcome: 'completed', ...pr('a'.repeat(40)) }, 1);
  db.insert(epicSlices).values({ epicId: id, number: 10, title: 'S', state: 'closed', blockedBy: [], prNumber: 30, closedAt: 6_000, readAt: 1 }).run();
  expect(reply()).toMatchObject({
    stages: [
      { stage: 'queued', startedAt: 500, endedAt: 1_000 },
      { stage: 'ship', startedAt: 1_000, endedAt: 5_000 },
      { stage: 'review', startedAt: 5_000, endedAt: 20_000 },
    ],
    rounds: [{ round: 1, verdict: 'approved' }],
    slices: [{ number: 10, lane: null, activity: null }],
  });
});

test('the reply of an epic with far more rounds than the cap, with the largest blockers, stays under the client line limit', () => {
  const id = epicRow();
  const long = (c: string, size: number) => c.repeat(size);
  const blockers = Array.from({ length: 80 }, (_, i) => ({ title: `${i} ${long('t', 400)}`, url: `https://github.com/o/r/pull/50#${long('u', 800)}` }));
  run(id, 'ship', 1_000, 2_000);
  for (let round = 1; round <= MAX_ROUNDS + 10; round++) {
    run(id, 'review', round * 10_000, round * 10_000 + 1, { outcome: 'changes_requested', ...pr(SHA), blockers }, round);
    run(id, 'fix', round * 10_000 + 2, round * 10_000 + 3, { outcome: 'completed', ...pr('b'.repeat(40)) }, round);
  }
  const epic = reply();
  expect(epic.rounds).toHaveLength(MAX_ROUNDS);
  expect(epic.rounds.at(-1)!.round).toBe(MAX_ROUNDS + 10);
  expect(Math.max(...epic.rounds.map((r) => r.blockers.length))).toBeLessThanOrEqual(50);
  expect(Buffer.byteLength(JSON.stringify({ id: 1, ok: true, data: epic }))).toBeLessThan(CLIENT_LINE_LIMIT);
});

test('a slice in progress shows the lane and the latest call of the agent building it, each slice its own agent; every other slice has none', () => {
  const id = epicRow({ status: 'running', finishedAt: null });
  const slice = (number: number, state: 'in_progress' | 'waiting') => db.insert(epicSlices).values({ epicId: id, number, title: `S${number}`, state, blockedBy: [], prNumber: null, closedAt: null, readAt: 1 }).run();
  [10, 11, 12, 13].forEach((number) => slice(number, 'in_progress'));
  slice(14, 'waiting');
  const hints = () => reply().slices.map(({ number, lane, activity }) => [number, lane, activity]);
  const noHints = [[10, null, null], [11, null, null], [12, null, null], [13, null, null], [14, null, null]];

  // no running author execution: nothing, even with events stored for an earlier one
  db.insert(executions).values({ executionId: 'old', epicId: id, stage: 'ship', status: 'finished', resultPath: '/r.json', startedAt: 1, finishedAt: 2, harness: 'claude', model: 'm', provider: null, workspace: '/w' }).run();
  const add = (executionId: string, kind: 'task' | 'tool_start', agentId: string, fields: Partial<typeof executionEvents.$inferInsert> = {}) =>
    db.insert(executionEvents).values({ executionId, at: 1, kind, agentId, ...fields }).run();
  add('old', 'task', 'a-old', { payload: { slice: 10 } });
  add('old', 'tool_start', 'a-old', { tool: 'Bash', arg: 'ls' });
  expect(hints()).toEqual(noHints);

  db.insert(executions).values({ executionId: 'live', epicId: id, stage: 'ship', status: 'running', resultPath: '/r.json', startedAt: 3, harness: 'claude', model: 'm', provider: null, workspace: '/w' }).run();
  const task = (agentId: string, slice: number, ended = false) => add('live', 'task', agentId, { payload: { text: `Build slice #${slice}`, slice }, ...(ended && { status: 'ok' as const }) });
  task('a-10', 10);
  task('a-11', 11);
  task('a-12', 12);
  task('a-12', 12, true); // its task ended
  task('a-14', 14); // not in progress
  add('live', 'tool_start', 'a-10', { tool: 'Edit', arg: '/w/repo--lane-2/src/a.ts' }); // the lane from a path
  add('live', 'tool_start', 'a-11', { tool: 'Read', arg: '/w/repo/src/b.ts' });
  add('live', 'tool_start', 'a-12', { tool: 'Bash', arg: 'pnpm test' });
  add('live', 'tool_start', 'a-14', { tool: 'Bash', arg: 'pnpm lint' });
  add('live', 'tool_start', 'a-10', { tool: 'Bash', arg: `pnpm test\n${'x'.repeat(100)}` }); // the latest of a-10: long, on two lines
  add('live', 'tool_start', 'a-11', { tool: 'Grep', arg: 'todo', payload: { lane: 3 } }); // the lane from the payload
  add('live', 'tool_start', 'a-99', { tool: 'Bash', arg: 'unrelated' });
  expect(hints()).toEqual([
    [10, 2, `Bash pnpm test ${'x'.repeat(100)}`.slice(0, 80)],
    [11, 3, 'Grep todo'],
    [12, null, null],
    [13, null, null], // no agent names it
    [14, null, null],
  ]);

  // an agent that has not made a call yet: no activity, and the lane stays null
  task('a-13', 13);
  expect(reply().slices.find((s) => s.number === 13)).toMatchObject({ lane: null, activity: null });
});

test('the read of events is bounded to the running execution: other executions and events beyond the cap do not count', () => {
  const id = epicRow({ status: 'running', finishedAt: null });
  db.insert(epicSlices).values({ epicId: id, number: 10, title: 'S', state: 'in_progress', blockedBy: [], prNumber: null, closedAt: null, readAt: 1 }).run();
  db.insert(executions).values({ executionId: 'live', epicId: id, stage: 'ship', status: 'running', resultPath: '/r.json', startedAt: 3, harness: 'claude', model: 'm', provider: null, workspace: '/w' }).run();
  db.insert(executionEvents).values({ executionId: 'live', at: 1, kind: 'task', agentId: 'a', payload: { slice: 10 } }).run();
  db.insert(executionEvents).values({ executionId: 'live', at: 1, kind: 'tool_start', agentId: 'a', tool: 'Bash', arg: 'first' }).run();
  const rows = Array.from({ length: 600 }, () => ({ executionId: 'live', at: 2, kind: 'tool_start' as const, agentId: 'b', tool: 'Bash', arg: 'other agent' }));
  db.insert(executionEvents).values(rows).run();
  // the agent's only call fell out of the newest 500: no activity, and no scan to find it
  expect(reply().slices[0]).toMatchObject({ lane: null, activity: null });
});
