import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { FakeAgentRunner, FakeWorkspaces, type Behavior } from '../execution/fake.ts';
import { createEngine } from '../orchestration/engine.ts';
import { FakeClock, FakeGitHub, FakeQuota } from '../orchestration/fake.ts';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { epicEvents, executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epicSlices } from '../storage/epic-slices.ts';
import { epics } from '../storage/schema.ts';
import { eq } from 'drizzle-orm';
import { epicOf, git as engineGit, limited, MAX_ROUNDS } from './epic.ts';
import { enginePlacesOf } from '../config/places.ts';
import { defaultLabels } from '../orchestration/github.ts';
import { FakeSkills } from '../harnesses/fake-skills.ts';

// the binary `withGit` hands over, replaced for the test that checks it is the one started
const handed = vi.hoisted(() => ({ binary: undefined as string | undefined }));
vi.mock('../execution/git-binary.ts', async (original) => {
  const real = await original<typeof import('../execution/git-binary.ts')>();
  return { ...real, withGit: <T>(start: (binary: string) => Promise<T>) => real.withGit((binary) => start(handed.binary ?? binary)) };
});

const MIN = 60_000;
const CLIENT_LINE_LIMIT = 8 * 1024 * 1024; // macos/Sources/CarrierCore/ControlClient.swift maxLineBytes
const SHA = 'a'.repeat(40);
const agents = { author: { profile: 'a', option: 'o', harness: 'claude' as const, model: 'm' }, reviewer: { profile: 'b', option: 'o', harness: 'codex' as const, model: 'r' } };
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

const reply = async () => (await epicOf(db, 'AshuLab/a', 1))!;
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
    profileDeclared: () => true,
    db, github, clock, repos: () => repos, settings: () => ({ pollIntervalMs: 5 * MIN, labels: defaultLabels, maxConcurrentEpics: 1, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews, maxLeadRounds: 3, autoResume: false, autoResumeMaxHours: 12 }), runner, workspaces: new FakeWorkspaces(), quota: new FakeQuota().read, places: enginePlacesOf(dir), skills: new FakeSkills(),
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
  const epic = await reply();
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
  const { rounds, stages } = await reply();
  expect(rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'approved']]);
  expect(titles(rounds[0]!)).toEqual(['new:Token expiry is not checked', 'new:Missing test']);
  expect(rounds[0]!.blockers.every((b) => b.approximate === false && b.id === null)).toBe(true);
  expect(titles(rounds[1]!)).toEqual(['fixed:Token expiry is not checked', 'fixed:Missing test']);
  expect(rounds[1]!.blockers.every((b) => b.approximate)).toBe(true);
  expect(stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'fix', 'review', 'ready']);
});

test('the limit: the last round is limit_reached, and the marks cover persisting, fixed and new, and a title changed only by case or spaces', async () => {
  await drive([['Token expiry', 'Missing test', 'Log leak'], ['token   EXPIRY ', 'Missing test', 'Brand new']], { maxReviews: 2 });
  const { rounds, stages } = await reply();
  expect(rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'limit_reached']]);
  expect(titles(rounds[1]!)).toEqual(['carried:token   EXPIRY ', 'carried:Missing test', 'new:Brand new', 'fixed:Log leak']);
  expect(stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'fix', 'review']);
  expect(stages.at(-1)!.endedAt).not.toBeNull(); // the epic stopped
});

test('with ids the marks are exact for a persisting, a fixed and a new blocker; without them they stay approximate', async () => {
  const id = epicRow();
  const review = (round: number, blockers: object[], extra: object = {}) =>
    run(id, 'review', round * 10, round * 10 + 1, { outcome: 'changes_requested', ...pr(SHA), blockers, ...extra }, round);
  review(1, [{ id: 'a', title: 'Token expiry' }, { id: 'b', title: 'Missing test' }, { id: 'c', title: 'Log leak' }]);
  // the persisting one is reworded (ids settle it), b is fixed and said so, c just disappeared, d is new
  review(2, [{ id: 'a', title: 'The token never expires' }, { id: 'd', title: 'Brand new' }], { resolved: ['b'] });
  const marks = async (round: number) => (await reply()).rounds[round]!.blockers.map((b) => [b.id, b.mark, b.approximate]);
  expect(await marks(0)).toEqual([['a', 'new', false], ['b', 'new', false], ['c', 'new', false]]);
  expect(await marks(1)).toEqual([['a', 'carried', false], ['d', 'new', false], ['b', 'fixed', false], ['c', 'fixed', false]]);

  // a later round with no ids at all falls back to titles and says so
  review(3, [{ title: 'brand   NEW' }, { title: 'Another' }]);
  expect(await marks(2)).toEqual([[null, 'carried', true], [null, 'new', true], ['a', 'fixed', true]]);
});

test('a round carries the observations its completed review listed, in order; a round without any, or from before the field, has none', async () => {
  const id = epicRow();
  run(id, 'review', 10, 11, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ title: 'A blocker' }] }, 1);
  run(id, 'fix', 12, 13, { outcome: 'completed', ...pr(SHA) }, 1);
  run(id, 'review', 20, 21, { outcome: 'completed', ...pr(SHA), observations: [{ id: 'o1', title: 'Rename x', url: 'https://github.com/o/r/pull/50#c1' }, { title: 'No id, no url' }, { id: 'o3', title: 'Long link', url: `https://github.com/o/r/${'u'.repeat(600)}` }] }, 2);
  run(id, 'review', 30, 31, { outcome: 'completed', ...pr(SHA), observations: [] }, 3);
  run(id, 'review', 40, 41, { outcome: 'completed', ...pr(SHA) }, 4);
  expect((await reply()).rounds.map((r) => r.observations)).toEqual([
    [],
    [{ id: 'o1', title: 'Rename x', url: 'https://github.com/o/r/pull/50#c1' }, { id: null, title: 'No id, no url', url: null }, { id: 'o3', title: 'Long link', url: null }],
    [],
    [],
  ]);
});

test('a review of a head that moved is no round: the repeat on the new head is the round', async () => {
  const id = epicRow();
  run(id, 'review', 10, 11, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ title: 'About a head that is gone' }] }, 1);
  db.update(callerResults).set({ outcome: 'superseded' }).run();
  run(id, 'review', 20, 21, { outcome: 'completed', ...pr('b'.repeat(40)) }, 1);
  expect((await reply()).rounds.map((r) => [r.round, r.verdict, r.reviewedSha])).toEqual([[1, 'approved', 'b'.repeat(40)]]);
});

// --- a round of several reviewers is one round, with the mandatory reviewer's verdict as the app reads it and the others' beside it ---

const extraAgent = { profile: 'c', option: 'o', harness: 'agy' as const, model: 'flash' };
const manyConfig = { name: 'AshuLab/a', agents: { ...agents, extraReviewers: [extraAgent, { ...extraAgent, harness: 'claude' as const, model: 'sonnet' }] } } as unknown as EffectiveRepoConfig;
let m = 0;
/** A review of a round by a slot, on the head it was given; the agent comes from the saved configuration, as it does for a row that recorded none. */
function slotReview(epicId: number, slot: string, round: number, headSha: string, result: object | null, startedAt = round * 100 + m) {
  const executionId = `m-${++m}`;
  db.insert(executions).values({ executionId, epicId, stage: 'review', reviewer: slot as 'reviewer', status: 'finished', resultPath: '/r.json', startedAt, finishedAt: startedAt + 5, round, headSha, workspace: `/reviews/${slot}` }).run();
  if (result) db.insert(callerResults).values({ executionId, outcome: (result as { outcome: string }).outcome, result: JSON.stringify(result) }).run();
  return executionId;
}

test('a round of several reviewers is one round: the mandatory reviewer\'s verdict, blockers and observations as the app reads them, and the others\' in an optional list with their slot and agent', async () => {
  const id = epicRow({ config: manyConfig });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA), observations: [{ title: 'Rename x' }] });
  slotReview(id, 'reviewer-2', 1, SHA, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ id: 'B1', title: 'Use the helper' }] });
  slotReview(id, 'reviewer-3', 1, SHA, { outcome: 'completed', ...pr(SHA) });

  const { rounds } = await reply();
  expect(rounds).toHaveLength(1);
  expect(rounds[0]).toMatchObject({ round: 1, verdict: 'approved', blockers: [], observations: [{ id: null, title: 'Rename x', url: null }], reviewedSha: SHA });
  expect(rounds[0]!.reviewer).toEqual({ harness: 'codex', model: 'r', provider: null }); // the mandatory reviewer's agent from its saved role
  expect(rounds[0]!.otherReviewers).toEqual([
    { slot: 'reviewer-2', agent: { harness: 'agy', model: 'flash', provider: null }, verdict: 'changes_requested', blockers: [{ id: 'B1', title: 'Use the helper', url: null, mark: 'new', approximate: false }], observations: [] },
    { slot: 'reviewer-3', agent: { harness: 'claude', model: 'sonnet', provider: null }, verdict: 'approved', blockers: [], observations: [] },
  ]);
});

test('an epic with one reviewer has no list of other reviewers', async () => {
  const id = epicRow();
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  expect((await reply()).rounds[0]).not.toHaveProperty('otherReviewers');
});

test('each reviewer\'s blockers are marked against its own earlier ones: the same id of two reviewers never collides', async () => {
  const id = epicRow({ config: manyConfig });
  const B = 'b'.repeat(40);
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ id: 'B1', title: 'first' }] });
  slotReview(id, 'reviewer-2', 1, SHA, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ id: 'B1', title: 'second' }] });
  run(id, 'fix', 300, 301, { outcome: 'completed', ...pr(B) }, 1);
  slotReview(id, 'reviewer', 2, B, { outcome: 'completed', ...pr(B), resolved: ['B1'] });
  slotReview(id, 'reviewer-2', 2, B, { outcome: 'changes_requested', ...pr(B), blockers: [{ id: 'B1', title: 'second, still' }] });

  const { rounds } = await reply();
  expect(rounds.map((r) => r.round)).toEqual([1, 2]);
  expect(rounds[1]!.blockers.map((b) => [b.id, b.mark])).toEqual([['B1', 'fixed']]);
  expect(rounds[1]!.otherReviewers![0]!.blockers.map((b) => [b.id, b.title, b.mark])).toEqual([['B1', 'second, still', 'carried']]);
  expect(rounds[0]!.fixedSha).toBe(B);
});

test('a reviewer that gave no verdict is not in the round; when it is the mandatory one, the first reviewer with a verdict stands for the round', async () => {
  const id = epicRow({ config: manyConfig });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'needs_human', ...pr(SHA), reason: 'cannot verify' });
  slotReview(id, 'reviewer-2', 1, SHA, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ title: 'Only one' }] });
  slotReview(id, 'reviewer-3', 1, SHA, { outcome: 'needs_human', ...pr(SHA), reason: 'cannot verify' });

  const { rounds } = await reply();
  expect(rounds).toHaveLength(1);
  expect(rounds[0]).toMatchObject({ verdict: 'changes_requested', reviewer: { harness: 'agy', model: 'flash' }, blockers: [{ title: 'Only one' }] });
  expect(rounds[0]).not.toHaveProperty('otherReviewers');
});

test('a round repeated on a new head shows once, for the head it was decided on, whichever reviewer found the head moved', async () => {
  const id = epicRow({ config: manyConfig });
  const B = 'b'.repeat(40);
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) }); // gave its verdict on a head that then moved: not of any round
  const found = slotReview(id, 'reviewer-2', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  db.update(callerResults).set({ outcome: 'superseded' }).where(eq(callerResults.executionId, found)).run();
  slotReview(id, 'reviewer', 1, B, { outcome: 'changes_requested', ...pr(B), blockers: [{ title: 'On the new head' }] });
  slotReview(id, 'reviewer-2', 1, B, { outcome: 'completed', ...pr(B) });

  const { rounds } = await reply();
  expect(rounds.map((r) => [r.round, r.reviewedSha, r.verdict, r.otherReviewers!.map((o) => o.slot)])).toEqual([[1, B, 'changes_requested', ['reviewer-2']]]);
});

test('the reply of an epic with several reviewers says how many gave a verdict out of how many are configured, and why each other gave none', async () => {
  const id = epicRow({ config: manyConfig, startedAt: 50 });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  slotReview(id, 'reviewer-2', 1, SHA, { outcome: 'needs_human', ...pr(SHA), reason: 'cannot verify' });
  slotReview(id, 'reviewer-3', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  db.insert(epicEvents).values({ epicId: id, at: 400, type: 'reviewer_no_verdict', data: { round: 1, headSha: SHA, none: { slot: 'reviewer-2', kind: 'agent_needs_human', why: 'x'.repeat(300) } } }).run();

  expect((await reply()).reviewers).toEqual({ given: 2, of: 3, none: [{ slot: 'reviewer-2', why: 'x'.repeat(200) }] });
});

test('the reply of an epic with one reviewer, or whose round is still waiting, has no count of reviewers', async () => {
  const single = epicRow({ startedAt: 50 });
  slotReview(single, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  expect(await reply()).not.toHaveProperty('reviewers');

  const waiting = epicRow({ issue: 2, config: manyConfig, startedAt: 50 });
  slotReview(waiting, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) }); // the other two have not settled
  expect(await epicOf(db, 'AshuLab/a', 2)).not.toHaveProperty('reviewers');
});

test('the review stage lists the slots that ran in it when there were several', async () => {
  const id = epicRow({ config: manyConfig, startedAt: 1 });
  run(id, 'ship', 10, 20, { outcome: 'completed', ...pr(SHA) });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) }, 30);
  slotReview(id, 'reviewer-2', 1, SHA, { outcome: 'completed', ...pr(SHA) }, 31);
  expect((await reply()).stages.map((s) => [s.stage, s.reviewers])).toEqual([['queued', undefined], ['ship', undefined], ['review', ['reviewer', 'reviewer-2']], ['ready', undefined]]);

  const single = epicRow({ issue: 2, startedAt: 1 });
  slotReview(single, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) }, 30);
  expect((await epicOf(db, 'AshuLab/a', 2))!.stages.every((s) => s.reviewers === undefined)).toBe(true);
});

test('technical retries inside a round do not make a round', async () => {
  await drive([['Only blocker'], 'approved'], { flaky: true });
  const { rounds } = await reply();
  expect(rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'approved']]);
  const retried = db.select().from(executions).all().filter((e) => e.status === 'failed');
  expect(retried.length).toBeGreaterThanOrEqual(3); // review 1, fix 1 and review 2 each failed once
  expect(rounds[0]!.fixMs).not.toBeNull(); // the fix that answered the round is the one that finished
});

test('an epic put back in the queue starts its rounds again, and the old ones stay readable', async () => {
  const { again, runner } = await drive([['One'], ['One']], { maxReviews: 2 });
  expect((await reply()).rounds.map((r) => r.verdict)).toEqual(['changes_requested', 'limit_reached']);

  const old = runner.behavior;
  runner.behavior = (task) => (task.stage === 'review' ? { write: { executionId: task.executionId, repo: task.repo, epic: task.epic, stage: 'review', summary: 'ok', outcome: 'completed', pr: { number: 50, headSha: SHA }, verification: { ci: 'passed', evidence: 'ok' } } } : old(task));
  await again();
  const epic = await reply();
  expect(epic.rounds.map((r) => [r.round, r.verdict])).toEqual([[1, 'changes_requested'], [2, 'limit_reached'], [1, 'approved']]);
  expect(titles(epic.rounds[2]!)).toEqual([]); // nothing carried over from the old attempt
  expect(epic.stages.map((s) => s.stage)).toEqual(['queued', 'ship', 'review', 'ready']); // the timeline is the current attempt's
});

test('an unknown epic is null', async () => {
  expect(await epicOf(db, 'AshuLab/a', 99)).toBeNull();
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

test('durations, shas and the commits between them come from the executions and a real repository; a missing worktree gives none', async () => {
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

  const epic = await reply();
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
  const gone = await reply();
  expect(gone.rounds[0]).toMatchObject({ reviewedSha: first, fixedSha: last, commits: [] });
  expect(gone.branch).toBeNull();
  expect(gone.worktrees[0]!.path).toBe(join(dir, 'gone'));
});

test('the reply carries the unanswered observations only when the epic has them, and an epic saved without them has none', async () => {
  epicRow({ status: 'ready_for_test', finishedAt: 20_000 });
  expect(await reply()).not.toHaveProperty('unansweredObservations');
  db.update(epics).set({ unansweredObservations: 2, unansweredReason: 'last_round' }).run();
  expect((await reply()).unansweredObservations).toEqual({ count: 2, reason: 'last_round' });
});

test('a queued epic has only its queue time, and a running one has an open stage', async () => {
  const id = epicRow({ status: 'queued', startedAt: null, finishedAt: null });
  expect(await reply()).toMatchObject({ stages: [{ stage: 'queued', startedAt: 500, endedAt: null }], rounds: [], worktrees: [], branch: null });
  db.update(epics).set({ status: 'running', startedAt: 1_000, stage: 'ship' }).run();
  run(id, 'ship', 1_100, null);
  expect((await reply()).stages).toEqual([{ stage: 'queued', startedAt: 500, endedAt: 1_000 }, { stage: 'ship', startedAt: 1_000, endedAt: null }]);
});

test('a merged epic answers like any other: its history closed at the merge, no ready stage, nothing live', async () => {
  const id = epicRow({ status: 'merged', finishedAt: 20_000 });
  run(id, 'ship', 1_000, 5_000);
  run(id, 'review', 5_000, 9_000, { outcome: 'completed', ...pr('a'.repeat(40)) }, 1);
  db.insert(epicSlices).values({ epicId: id, number: 10, title: 'S', state: 'closed', blockedBy: [], prNumber: 30, closedAt: 6_000, readAt: 1 }).run();
  expect(await reply()).toMatchObject({
    stages: [
      { stage: 'queued', startedAt: 500, endedAt: 1_000 },
      { stage: 'ship', startedAt: 1_000, endedAt: 5_000 },
      { stage: 'review', startedAt: 5_000, endedAt: 20_000 },
    ],
    rounds: [{ round: 1, verdict: 'approved' }],
    slices: [{ number: 10, lane: null, activity: null }],
  });
});

test('the reply of an epic with far more rounds than the cap, with the largest blockers, stays under the client line limit', async () => {
  const id = epicRow();
  const long = (c: string, size: number) => c.repeat(size);
  const blockers = Array.from({ length: 80 }, (_, i) => ({ title: `${i} ${long('t', 400)}`, url: `https://github.com/o/r/pull/50#${long('u', 800)}` }));
  run(id, 'ship', 1_000, 2_000);
  for (let round = 1; round <= MAX_ROUNDS + 10; round++) {
    run(id, 'review', round * 10_000, round * 10_000 + 1, { outcome: 'changes_requested', ...pr(SHA), blockers }, round);
    run(id, 'fix', round * 10_000 + 2, round * 10_000 + 3, { outcome: 'completed', ...pr('b'.repeat(40)) }, round);
  }
  const epic = await reply();
  expect(epic.rounds).toHaveLength(MAX_ROUNDS);
  expect(epic.rounds.at(-1)!.round).toBe(MAX_ROUNDS + 10);
  expect(Math.max(...epic.rounds.map((r) => r.blockers.length))).toBeLessThanOrEqual(50);
  expect(Buffer.byteLength(JSON.stringify({ id: 1, ok: true, data: epic }))).toBeLessThan(CLIENT_LINE_LIMIT);
});

test('a slice in progress shows the lane and the latest call of the agent building it, each slice its own agent; every other slice has none', async () => {
  const id = epicRow({ status: 'running', finishedAt: null });
  const slice = (number: number, state: 'in_progress' | 'waiting') => db.insert(epicSlices).values({ epicId: id, number, title: `S${number}`, state, blockedBy: [], prNumber: null, closedAt: null, readAt: 1 }).run();
  [10, 11, 12, 13].forEach((number) => slice(number, 'in_progress'));
  slice(14, 'waiting');
  const hints = async () => (await reply()).slices.map(({ number, lane, activity }) => [number, lane, activity]);
  const noHints = [[10, null, null], [11, null, null], [12, null, null], [13, null, null], [14, null, null]];

  // no running author execution: nothing, even with events stored for an earlier one
  db.insert(executions).values({ executionId: 'old', epicId: id, stage: 'ship', status: 'finished', resultPath: '/r.json', startedAt: 1, finishedAt: 2, harness: 'claude', model: 'm', provider: null, workspace: '/w' }).run();
  const add = (executionId: string, kind: 'task' | 'tool_start', agentId: string, fields: Partial<typeof executionEvents.$inferInsert> = {}) =>
    db.insert(executionEvents).values({ executionId, at: 1, kind, agentId, ...fields }).run();
  add('old', 'task', 'a-old', { payload: { slice: 10 } });
  add('old', 'tool_start', 'a-old', { tool: 'Bash', arg: 'ls' });
  expect(await hints()).toEqual(noHints);

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
  expect(await hints()).toEqual([
    [10, 2, `Bash pnpm test ${'x'.repeat(100)}`.slice(0, 80)],
    [11, 3, 'Grep todo'],
    [12, null, null],
    [13, null, null], // no agent names it
    [14, null, null],
  ]);

  // an agent that has not made a call yet: no activity, and the lane stays null
  task('a-13', 13);
  expect((await reply()).slices.find((s) => s.number === 13)).toMatchObject({ lane: null, activity: null });
});

test('the read of events is bounded to the running execution: other executions and events beyond the cap do not count', async () => {
  const id = epicRow({ status: 'running', finishedAt: null });
  db.insert(epicSlices).values({ epicId: id, number: 10, title: 'S', state: 'in_progress', blockedBy: [], prNumber: null, closedAt: null, readAt: 1 }).run();
  db.insert(executions).values({ executionId: 'live', epicId: id, stage: 'ship', status: 'running', resultPath: '/r.json', startedAt: 3, harness: 'claude', model: 'm', provider: null, workspace: '/w' }).run();
  db.insert(executionEvents).values({ executionId: 'live', at: 1, kind: 'task', agentId: 'a', payload: { slice: 10 } }).run();
  db.insert(executionEvents).values({ executionId: 'live', at: 1, kind: 'tool_start', agentId: 'a', tool: 'Bash', arg: 'first' }).run();
  const rows = Array.from({ length: 600 }, () => ({ executionId: 'live', at: 2, kind: 'tool_start' as const, agentId: 'b', tool: 'Bash', arg: 'other agent' }));
  db.insert(executionEvents).values(rows).run();
  // the agent's only call fell out of the newest 500: no activity, and no scan to find it
  expect((await reply()).slices[0]).toMatchObject({ lane: null, activity: null });
});

test('the live hints read the events of a run by their kind, not by walking all of them', async () => {
  const id = epicRow({ status: 'running', finishedAt: null });
  db.insert(epicSlices).values({ epicId: id, number: 10, title: 'S', state: 'in_progress', blockedBy: [], prNumber: null, closedAt: null, readAt: 1 }).run();
  db.insert(executions).values({ executionId: 'live', epicId: id, stage: 'ship', status: 'running', resultPath: '/r.json', startedAt: 3, harness: 'claude', model: 'm', provider: null, workspace: '/w' }).run();
  db.insert(executionEvents).values(Array.from({ length: 300 }, (_, n) => ({ executionId: 'live', at: n, kind: n % 100 === 0 ? ('task' as const) : ('say' as const), agentId: 'a', payload: { slice: 10 } }))).run();
  const statements: string[] = [];
  const traced = drizzle(new Database(join(dir, 'carrier.db'), { readonly: true, verbose: (sql) => statements.push(String(sql)) }));
  await epicOf(traced, 'AshuLab/a', 1);
  const reads = statements.filter((sql) => /^\s*select\b/i.test(sql) && /\bfrom "(executions|execution_events)"/.test(sql));
  expect(reads.length).toBeGreaterThan(0);
  // the kind is in the index, so a run that says a lot and calls a task now and then is not read through to find the tasks
  const plans = reads.flatMap((sql) => (traced.$client.prepare(`explain query plan ${sql}`).all() as { detail: string }[]).map((row) => row.detail));
  traced.$client.close();
  expect(plans.filter((detail) => /\bSCAN (executions|execution_events)\b/.test(detail))).toEqual([]);
  expect(plans.some((detail) => /USING (COVERING )?INDEX execution_events_kind/.test(detail))).toBe(true);
});

test('limited runs at most four jobs at once and finishes all of them, a rejected one included', async () => {
  let running = 0;
  let peak = 0;
  const gates: (() => void)[] = [];
  const job = (fail: boolean) =>
    limited(async () => {
      peak = Math.max(peak, ++running);
      await new Promise<void>((open) => gates.push(open));
      running--;
      if (fail) throw new Error('boom');
      return 'done';
    });
  const results = Array.from({ length: 10 }, (_, i) => job(i % 3 === 2).then((r) => r, (e: Error) => e.message));
  await new Promise((resolve) => setImmediate(resolve));
  expect(gates).toHaveLength(4); // the others wait their turn
  while (gates.length > 0) {
    gates.splice(0).forEach((open) => open());
    await new Promise((resolve) => setImmediate(resolve));
  }
  expect(peak).toBe(4);
  expect(await Promise.all(results)).toEqual(['done', 'done', 'boom', 'done', 'done', 'boom', 'done', 'done', 'boom', 'done']);
  expect(running).toBe(0);
});

test('limited never lets a job slip in beside the four when one finishes and another is waiting', async () => {
  let running = 0;
  let peak = 0;
  const gates: (() => void)[] = [];
  const job = () =>
    limited(async () => {
      peak = Math.max(peak, ++running);
      await new Promise<void>((open) => gates.push(open));
      running--;
    });
  const all = Array.from({ length: 8 }, job);
  await new Promise((resolve) => setImmediate(resolve));
  // a job starts at every possible moment after one finished, the way a handler would in the same turn
  for (let delay = 0; delay < 6; delay++) {
    gates.shift()!();
    for (let turn = 0; turn < delay; turn++) await Promise.resolve();
    all.push(job());
    await new Promise((resolve) => setImmediate(resolve));
  }
  while (gates.length > 0) {
    gates.splice(0).forEach((open) => open());
    await new Promise((resolve) => setImmediate(resolve));
  }
  await Promise.all(all);
  expect(peak).toBe(4);
});

test('git sees its input closed: a command that reads it ends instead of waiting for the timeout', async () => {
  expect(await engineGit(dir, ['hash-object', '--stdin'])).toBe('e69de29bb2d1d6434b8b29ae775ad8c2e48c5391\n'); // the empty blob
});

test('git starts the binary the machine hands over', async () => {
  handed.binary = join(dir, 'no-such-git');
  try {
    expect(await engineGit(dir, ['--version'])).toBeNull(); // not there: git failed, logged
  } finally {
    handed.binary = undefined;
  }
  expect(await engineGit(dir, ['--version'])).toMatch(/^git version /);
});

// --- the lead reviewer: its stage is a string of the replies, its review is no round, and the heads it kept are fields of the epic ---

const leadConfig = { name: 'AshuLab/a', agents: { ...agents, leadReviewer: { profile: 'e', option: 'o', harness: 'claude' as const, model: 'opus-lead' } } } as unknown as EffectiveRepoConfig;
function leadRun(epicId: number, headSha: string, startedAt: number, result: object | null) {
  const executionId = `lead-${startedAt}`;
  db.insert(executions).values({ executionId, epicId, stage: 'lead', reviewer: 'lead', status: 'finished', resultPath: '/r.json', startedAt, finishedAt: startedAt + 5, round: 1, headSha, workspace: '/reviews/lead' }).run();
  if (result) db.insert(callerResults).values({ executionId, outcome: (result as { outcome: string }).outcome, result: JSON.stringify(result) }).run();
}

test('the lead\'s review is no round, its stage is `lead` in the timeline, and the epic carries the heads, the approval and the lead\'s agent', async () => {
  const id = epicRow({ config: leadConfig, startedAt: 50, reviewedSha: SHA, approvedSha: 'b'.repeat(40), status: 'ready_for_test', finishedAt: 5_000 });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  leadRun(id, 'b'.repeat(40), 1_000, { outcome: 'completed', ...pr('b'.repeat(40)), approval: { submitted: true } });
  db.insert(epicEvents).values({ epicId: id, at: 1_100, type: 'lead_completed', data: { headSha: 'b'.repeat(40), approval: { submitted: true } } }).run();

  const r = await reply();
  expect(r.rounds.map((round) => [round.round, round.reviewedSha])).toEqual([[1, SHA]]); // the lead's review adds none
  expect(r.stages.map((s) => s.stage)).toEqual(['queued', 'review', 'lead', 'ready']);
  expect(r).toMatchObject({ reviewedSha: SHA, approvedSha: 'b'.repeat(40), leadApproval: true, lead: { harness: 'claude', model: 'opus-lead', provider: null } });
});

test('an epic with no lead carries none of the lead\'s fields, and one still in the stage lead has no approval yet', async () => {
  const plain = epicRow();
  expect(await reply()).not.toHaveProperty('lead');
  expect(await reply()).not.toHaveProperty('approvedSha');
  db.update(epics).set({ config: leadConfig, stage: 'lead', reviewedSha: SHA }).where(eq(epics.id, plain)).run();
  const r = await reply();
  expect(r).toMatchObject({ reviewedSha: SHA, lead: { model: 'opus-lead' } });
  expect(r).not.toHaveProperty('approvedSha');
  expect(r).not.toHaveProperty('leadApproval');
});

test('a fix of the lead\'s exchange belongs to no round: the round the reviewers agreed on keeps no fix time, head or commits from it', async () => {
  const B = 'b'.repeat(40);
  const id = epicRow({ config: leadConfig, startedAt: 50 });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA) });
  leadRun(id, SHA, 1_000, { outcome: 'changes_requested', ...pr(SHA), blockers: [{ title: 'The lead found this' }] });
  run(id, 'fix', 1_100, 1_200, { outcome: 'completed', ...pr(B) });
  leadRun(id, B, 1_300, { outcome: 'completed', ...pr(B) });

  const { rounds } = await reply();
  expect(rounds).toHaveLength(1);
  expect(rounds[0]).toMatchObject({ round: 1, verdict: 'approved', fixMs: null, fixedSha: null, commits: [] });
});

test('the fix of an observations pass still belongs to the round that listed them, lead or no lead', async () => {
  const B = 'b'.repeat(40);
  const id = epicRow({ config: leadConfig, startedAt: 50 });
  slotReview(id, 'reviewer', 1, SHA, { outcome: 'completed', ...pr(SHA), observations: [{ title: 'Rename x' }] });
  run(id, 'fix', 300, 360, { outcome: 'completed', ...pr(B) });
  leadRun(id, B, 1_000, { outcome: 'completed', ...pr(B) });

  expect((await reply()).rounds[0]).toMatchObject({ fixMs: 60, fixedSha: B });
});
