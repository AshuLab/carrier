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
import { executions } from '../storage/executions.ts';
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
  await drive([['Token expiry is not checked', 'Missing test'], 'approved']);
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
