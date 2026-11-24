import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { epicEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics, epicStates } from '../storage/schema.ts';
import { renderPanel } from '../terminal/dashboard/plain.ts';
import { buildSnapshot, optionsOf, watchedOf } from './snapshot.ts';
import { defaultLabels } from '../orchestration/github.ts';

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
const snapshot = (now = 100_000) => buildSnapshot(db, { now, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 40_000, repos: 2, nextCheckAt: 160_000, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 300_000, labels: defaultLabels });

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

test('an epic shows its own cap of rounds: the granted roundLimit, else the live maxReviews', () => {
  add(1, 'running', { round: 5, roundLimit: 10 });
  add(2, 'running', { round: 2 });
  expect(snapshot().epics.map((e) => [e.issue, e.maxReviews])).toEqual([[1, 10], [2, 5]]);
});

test('an epic stopped with a resumeAt carries it, and one with none has no such field', () => {
  add(1, 'needs_human', { needsHumanKind: 'usage_limit', resumeAt: 190_000 });
  add(2, 'needs_human', { needsHumanKind: 'usage_limit' });
  const [waiting, plain] = snapshot().epics;
  expect(waiting).toMatchObject({ issue: 1, resumeAt: 190_000 });
  expect(plain).not.toHaveProperty('resumeAt');
  expect(renderPanel(snapshot()).join('\n')).toContain('resumes: in 1m 30s');
});

test('a running epic waiting to retry carries its due time, and one that is not waiting has no such field', () => {
  add(1, 'running', { retryAt: 130_000 });
  add(2, 'running');
  add(3, 'needs_human', { needsHumanKind: 'retries_exhausted', retryAt: 130_000 });
  const [waiting, plain, stopped] = snapshot().epics;
  expect(waiting).toMatchObject({ issue: 1, retryAt: 130_000 });
  expect(plain).not.toHaveProperty('retryAt');
  expect(stopped).not.toHaveProperty('retryAt');
  expect(renderPanel(snapshot()).join('\n')).toContain('retries: in 30s');
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

test('an epic stopped by an engine error carries the kind and the reason', () => {
  add(7, 'needs_human', { needsHumanKind: 'engine_error', needsHumanReason: 'boom' });
  expect(snapshot().epics[0]).toMatchObject({ status: 'needs_human', needsHumanKind: 'engine_error', needsHumanReason: 'boom' });
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
  expect(buildSnapshot(db, { now: 1, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 2, nextCheckAt: null, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 1, labels: defaultLabels, watched }).watched).toBe(watched);
});

test('a running epic with a frozen config lists its running execution as a session, without the profile; blocker titles are capped', () => {
  const agent = { profile: 'secret-profile', option: 'o', harness: 'claude' as const, model: 'm-author' };
  const config = { name: 'acme/web', agents: { author: agent, reviewer: { profile: 'other', option: 'o', harness: 'codex' as const, model: 'm-review', provider: 'ollama' as const } } };
  const epic = add(7, 'running', { config, round: 2 });
  db.insert(executions).values({ executionId: 'e1', epicId: epic.id, stage: 'review', status: 'finished', resultPath: '/r', startedAt: 10 }).run();
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
  const build = (finishedWindowDays: number) => buildSnapshot(db, { now: 20 * 86_400_000, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 300_000, labels: defaultLabels });
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
  expect(buildSnapshot(db, { now: 1, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: true, slices, version: '0.1.0', pollIntervalMs: 300_000, labels: defaultLabels }).paused).toBe(true);
});

test('a ready-for-test epic carries its unanswered observations only when it has them', () => {
  add(1, 'ready_for_test', { finishedAt: 5000, unansweredObservations: 3, unansweredReason: 'last_round' });
  add(2, 'ready_for_test', { finishedAt: 4000 });
  expect(snapshot().done.map((d) => [d.issue, d.unansweredObservations])).toEqual([[1, { count: 3, reason: 'last_round' }], [2, undefined]]);
});

test('an epic carries its slices once they are known and null before', () => {
  add(12, 'running');
  add(13, 'running');
  expect(snapshot().epics.map((e) => e.slices)).toEqual([null, null]);
  slices = (repo, issue) => (repo === 'acme/web' && issue === 12 ? { done: 3, total: 5 } : null);
  expect(snapshot().epics.map((e) => e.slices)).toEqual([{ done: 3, total: 5 }, null]);
});

test('a restart is offered every account the epic declares, and no deadline comes with them', () => {
  const providers = { claude: { harness: 'claude' as const }, codex: { harness: 'codex' as const }, spare: { harness: 'claude' as const } };
  const options = optionsOf({ config: { providers, agents: {} } as never, authorOption: 'claude', reviewerOption: 'codex' });
  expect(options).toEqual({ names: ['claude', 'codex', 'spare'], author: 'claude', reviewer: 'codex' });
});

test('the snapshot reads the executions of an epic by index and never walks the whole table', () => {
  // a few dozen epics of every state, each with several executions: what a snapshot asks per epic must not grow with all of them
  for (let issue = 1; issue <= 30; issue++) {
    const epic = add(issue, (['running', 'needs_human', 'ready_for_test', 'merged'] as const)[issue % 4]!, { finishedAt: issue % 4 === 3 ? 99_000 : null });
    for (const stage of ['ship', 'review', 'fix'] as const) {
      db.insert(executions).values({ executionId: `x${issue}-${stage}`, epicId: epic.id, stage, resultPath: '/r', startedAt: issue, status: stage === 'fix' ? 'running' : 'finished' }).run();
    }
  }
  const statements: string[] = [];
  const traced = drizzle(new Database(join(dir, 'carrier.db'), { readonly: true, verbose: (sql) => statements.push(String(sql)) }));
  buildSnapshot(traced, { now: 100_000, maxConcurrentEpics: 3, maxReviews: 5, finishedWindowDays: 15, startedAt: 40_000, repos: 2, nextCheckAt: 160_000, problem: null, paused: false, slices, version: '0.1.0', pollIntervalMs: 300_000, labels: defaultLabels });
  const reads = statements.filter((sql) => /^\s*select\b/i.test(sql) && /\bexecutions\b|\bexecution_events\b/.test(sql));
  expect(reads.length).toBeGreaterThan(30);
  // without `ANALYZE` the planner does not look at how many rows a table has, so the plan is the same on any machine and any size
  const walks = reads.flatMap((sql) => (traced.$client.prepare(`explain query plan ${sql}`).all() as { detail: string }[]).map((row) => row.detail)).filter((detail) => /\bSCAN (executions|execution_events)\b/.test(detail));
  traced.$client.close();
  expect(walks).toEqual([]);
});

test('the execution the snapshot names for an epic is the newest of the author or of the mandatory reviewer, whichever other slot ended last', () => {
  const { id } = add(1, 'running', { stage: 'review' });
  const run = (executionId: string, startedAt: number, extra: Partial<typeof executions.$inferInsert>) =>
    db.insert(executions).values({ executionId, epicId: id, stage: 'review', status: 'finished', resultPath: '/r.json', startedAt, ...extra }).run();
  run('ship', 1_000, { stage: 'ship' });
  run('main', 2_000, { reviewer: 'reviewer' });
  run('extra', 3_000, { reviewer: 'reviewer-2' }); // the newest, of another slot
  run('lead', 4_000, { reviewer: 'lead' });
  expect(snapshot().epics[0]).toMatchObject({ issue: 1, executionId: 'main' });

  run('main-again', 5_000, { stage: 'review', reviewer: null }); // a review row with no slot written is the mandatory reviewer's
  expect(snapshot().epics[0]).toMatchObject({ executionId: 'main-again' });
});

test('the session of a running extra reviewer reads its agent from the epic\'s saved configuration', () => {
  const agent = { profile: 'p', harness: 'claude' as const, model: 'opus' };
  const config = { name: 'acme/web', agents: { author: agent, reviewer: { ...agent, harness: 'codex' as const, model: 'gpt' }, extraReviewers: [{ ...agent, harness: 'agy' as const, model: 'flash' }] } } as NonNullable<(typeof epics.$inferInsert)['config']>;
  const { id } = add(1, 'running', { stage: 'review', config });
  db.insert(executions).values({ executionId: 'x', epicId: id, stage: 'review', reviewer: 'reviewer-2', status: 'running', resultPath: '/r.json', startedAt: 1_000 }).run();
  expect(snapshot().sessions).toMatchObject([{ executionId: 'x', stage: 'review', harness: 'agy', model: 'flash' }]);
});

// --- a round of several reviewers, and a session for each running execution of an epic ---

const agentOf = (harness: 'claude' | 'codex' | 'agy', model: string) => ({ profile: `${harness}-p`, harness, model });
const severalConfig = { name: 'acme/web', agents: { author: agentOf('claude', 'opus'), reviewer: agentOf('codex', 'gpt'), extraReviewers: [agentOf('agy', 'flash'), { ...agentOf('claude', 'sonnet'), provider: 'ollama' as const }] } } as unknown as NonNullable<(typeof epics.$inferInsert)['config']>;
const run = (epicId: number, executionId: string, startedAt: number, extra: Partial<typeof executions.$inferInsert> = {}) =>
  db.insert(executions).values({ executionId, epicId, stage: 'review', status: 'finished', resultPath: '/r.json', startedAt, ...extra }).run();
const verdict = (executionId: string, outcome: 'completed' | 'changes_requested' | 'needs_human') => db.insert(callerResults).values({ executionId, outcome, result: JSON.stringify({ outcome, blockers: [] }) }).run();
const none = (epicId: number, round: number, headSha: string, slot: string, why: string, at = 2_000) =>
  db.insert(epicEvents).values({ epicId, at, type: 'reviewer_no_verdict', data: { round, headSha, none: { slot, kind: 'agent_needs_human', why } } }).run();

test('the snapshot lists a session for each running execution of an epic, with the harness and the model each ran with from its own record, and its reviewer slot', () => {
  const { id } = add(1, 'running', { stage: 'review', round: 1, startedAt: 500, config: severalConfig });
  run(id, 'author', 1_000, { stage: 'ship' });
  run(id, 'main', 2_000, { reviewer: 'reviewer', status: 'running', harness: 'codex', model: 'gpt' });
  run(id, 'second', 2_100, { reviewer: 'reviewer-2', status: 'running', harness: 'claude', model: 'opus-failover' }); // a failover left the saved agent (agy, flash)
  run(id, 'third', 2_200, { reviewer: 'reviewer-3', status: 'running' }); // no record of its own: the saved agent
  run(id, 'done', 2_300, { reviewer: 'reviewer-2', status: 'finished', harness: 'agy', model: 'flash' });

  expect(snapshot().sessions).toEqual([
    { executionId: 'main', repo: 'acme/web', issue: 1, stage: 'review', round: 1, harness: 'codex', model: 'gpt', startedAt: 2_000, last: null, reviewer: 'reviewer' },
    { executionId: 'second', repo: 'acme/web', issue: 1, stage: 'review', round: 1, harness: 'claude', model: 'opus-failover', startedAt: 2_100, last: null, reviewer: 'reviewer-2' },
    { executionId: 'third', repo: 'acme/web', issue: 1, stage: 'review', round: 1, harness: 'claude', model: 'sonnet', startedAt: 2_200, last: null, reviewer: 'reviewer-3' },
  ]);
});

test('a session of the author names no reviewer slot, and an epic with a single running execution has a single session', () => {
  const { id } = add(1, 'running', { stage: 'ship', config: severalConfig });
  run(id, 'author', 1_000, { stage: 'ship', status: 'running' });
  const [session, ...more] = snapshot().sessions;
  expect(more).toEqual([]);
  expect(session).toMatchObject({ executionId: 'author', stage: 'ship', harness: 'claude', model: 'opus' });
  expect(session).not.toHaveProperty('reviewer');
});

test('an epic with several reviewers carries how many gave a verdict out of how many were configured, and why each other gave none, for its latest decided round', () => {
  const { id } = add(1, 'running', { stage: 'fix', round: 1, startedAt: 500, prHeadSha: 'H1', reviewedSha: 'H1', config: severalConfig });
  for (const [slot, at] of [['reviewer', 1_000], ['reviewer-2', 1_100], ['reviewer-3', 1_200]] as const) run(id, slot, at, { reviewer: slot, round: 1, headSha: 'H1' });
  verdict('reviewer', 'changes_requested');
  verdict('reviewer-3', 'completed');
  verdict('reviewer-2', 'needs_human');
  none(id, 1, 'H1', 'reviewer-2', 'cannot verify the migration');

  expect(snapshot().epics[0]).toMatchObject({ reviewers: { given: 2, of: 3, none: [{ slot: 'reviewer-2', why: 'cannot verify the migration' }] }, reviewedSha: 'H1' });
});

test('the count is of the latest round that was decided, not of one still waiting for a reviewer, and not of a head a moved pull request set aside', () => {
  const { id } = add(1, 'running', { stage: 'review', round: 2, startedAt: 500, config: { ...severalConfig, agents: { ...severalConfig.agents, extraReviewers: [agentOf('agy', 'flash')] } } as never });
  run(id, 'a1', 1_000, { reviewer: 'reviewer', round: 1, headSha: 'H1' });
  run(id, 'b1', 1_100, { reviewer: 'reviewer-2', round: 1, headSha: 'H1' });
  verdict('a1', 'completed');
  verdict('b1', 'completed');
  run(id, 'a2', 2_000, { reviewer: 'reviewer', round: 2, headSha: 'H2' }); // round 2 waits for reviewer-2
  verdict('a2', 'completed');
  run(id, 'b2', 2_100, { reviewer: 'reviewer-2', round: 2, headSha: 'H2', status: 'running' });

  expect(snapshot().epics[0]!.reviewers).toEqual({ given: 2, of: 2, none: [] }); // round 1's

  db.update(callerResults).set({ outcome: 'superseded' }).where(eq(callerResults.executionId, 'a1')).run(); // round 1's head moved: nothing decided is left
  expect(snapshot().epics[0]).not.toHaveProperty('reviewers');
});

test('an epic with one reviewer carries no count, and neither does an epic that has no round yet', () => {
  const one = { name: 'acme/web', agents: { author: agentOf('claude', 'opus'), reviewer: agentOf('codex', 'gpt') } } as unknown as NonNullable<(typeof epics.$inferInsert)['config']>;
  const { id } = add(1, 'running', { stage: 'fix', round: 1, startedAt: 500, config: one });
  run(id, 'a', 1_000, { reviewer: 'reviewer', round: 1, headSha: 'H1' });
  verdict('a', 'changes_requested');
  add(2, 'running', { stage: 'ship', startedAt: 500, config: severalConfig });

  const [single, early] = snapshot().epics;
  expect(single).not.toHaveProperty('reviewers');
  expect(early).not.toHaveProperty('reviewers');
});

test('a ready-for-test epic with fewer verdicts than reviewers carries the count too', () => {
  const { id } = add(1, 'ready_for_test', { round: 1, startedAt: 500, finishedAt: 5_000, reviewedSha: 'H1', config: severalConfig });
  run(id, 'a', 1_000, { reviewer: 'reviewer', round: 1, headSha: 'H1' });
  verdict('a', 'completed');
  none(id, 1, 'H1', 'reviewer-2', 'ran out of usage');
  none(id, 1, 'H1', 'reviewer-3', 'the skill mine is not installed');

  expect(snapshot().done[0]!.reviewers).toEqual({ given: 1, of: 3, none: [{ slot: 'reviewer-2', why: 'ran out of usage' }, { slot: 'reviewer-3', why: 'the skill mine is not installed' }] });
});

test('the agents of the extra reviewers come with the epic, and an epic with none has no such field', () => {
  add(1, 'running', { config: severalConfig });
  add(2, 'running', { config: { name: 'acme/web', agents: { author: agentOf('claude', 'opus'), reviewer: agentOf('codex', 'gpt') } } as never });
  const [several, single] = snapshot().epics;
  expect(several!.agents).toEqual({ author: { harness: 'claude', model: 'opus', provider: null }, reviewer: { harness: 'codex', model: 'gpt', provider: null }, extraReviewers: [{ harness: 'agy', model: 'flash', provider: null }, { harness: 'claude', model: 'sonnet', provider: 'ollama' }] });
  expect(single!.agents).toEqual({ author: { harness: 'claude', model: 'opus', provider: null }, reviewer: { harness: 'codex', model: 'gpt', provider: null } });
});

// --- the lead reviewer: the app's stage has no `lead`, so the snapshot reports a review with a flag ---

const leadConfig = { ...severalConfig, agents: { ...severalConfig.agents, leadReviewer: agentOf('claude', 'opus-lead') } } as unknown as NonNullable<(typeof epics.$inferInsert)['config']>;

test('the stage lead is reported as review with a lead flag, never as lead, in the epic and in the session of the lead', () => {
  const { id } = add(1, 'running', { stage: 'lead', round: 2, leadRound: 1, startedAt: 500, config: leadConfig, reviewedSha: 'H1' });
  run(id, 'lead-run', 2_000, { stage: 'lead', reviewer: 'lead', status: 'running', harness: 'claude', model: 'opus-lead' });
  add(2, 'running', { stage: 'review', round: 1, config: leadConfig });

  const s = snapshot();
  expect(s.epics[0]).toMatchObject({ issue: 1, stage: 'review', lead: true, round: 2, reviewedSha: 'H1' });
  expect(s.epics[1]).not.toHaveProperty('lead');
  expect(s.sessions).toEqual([{ executionId: 'lead-run', repo: 'acme/web', issue: 1, stage: 'review', lead: true, round: 2, harness: 'claude', model: 'opus-lead', startedAt: 2_000, last: null, reviewer: 'lead' }]);
  expect(JSON.stringify(s)).not.toContain('"stage":"lead"');
  expect(renderPanel(s).join('\n')).toContain('#1'); // the terminal panel reads the same stage
});

test('the blockers of an epic in the lead\'s exchange are the lead\'s open ones, and the reviewers\' that were answered are not counted', () => {
  const { id } = add(1, 'running', { stage: 'fix', round: 1, leadRound: 1, startedAt: 500, config: leadConfig });
  const answer = (executionId: string, stage: 'review' | 'lead', outcome: string, result: object) => {
    db.insert(executions).values({ epicId: id, stage, reviewer: stage === 'lead' ? 'lead' : 'reviewer', executionId, resultPath: '/r', startedAt: 0 }).run();
    db.insert(callerResults).values({ executionId, outcome, result: JSON.stringify(result) }).run();
  };
  answer('r1', 'review', 'completed', { outcome: 'completed' });
  answer('l1', 'lead', 'changes_requested', { blockers: [{ title: 'the rollback is untested' }] });

  expect(snapshot().epics[0]).toMatchObject({ stage: 'fix', blockers: 1, blockerTitles: ['the rollback is untested'] });
});

test('the agent of the lead is listed with those of the epic, and only when the epic has one', () => {
  add(1, 'running', { stage: 'lead', config: leadConfig });
  add(2, 'running', { stage: 'review', config: severalConfig });
  const [withLead, without] = snapshot().epics;
  expect(withLead!.agents).toMatchObject({ lead: { harness: 'claude', model: 'opus-lead', provider: null } });
  expect(without!.agents).not.toHaveProperty('lead');
});

test('an epic that was approved carries the head the lead approved beside the head the reviewers agreed on, and whether its result says it submitted an approval; one without a lead carries none of them', () => {
  const approved = add(1, 'ready_for_test', { finishedAt: 90_000, startedAt: 500, reviewedSha: 'H1', approvedSha: 'H2' });
  const quiet = add(2, 'ready_for_test', { finishedAt: 80_000, startedAt: 500, reviewedSha: 'H1', approvedSha: 'H1' });
  add(3, 'ready_for_test', { finishedAt: 70_000 });
  db.insert(epicEvents).values({ epicId: approved.id, at: 89_000, type: 'lead_completed', data: { headSha: 'H2', approval: { submitted: true, url: 'https://github.com/acme/web/pull/1#pullrequestreview-1' } } }).run();
  db.insert(epicEvents).values({ epicId: quiet.id, at: 79_000, type: 'lead_completed', data: { headSha: 'H1', approval: { submitted: false } } }).run();

  const [first, second, third] = snapshot().done;
  expect(first).toMatchObject({ issue: 1, reviewedSha: 'H1', approvedSha: 'H2', leadApproval: true });
  expect(second).toMatchObject({ approvedSha: 'H1', leadApproval: false });
  for (const field of ['reviewedSha', 'approvedSha', 'leadApproval']) expect(third).not.toHaveProperty(field);
  const running = add(4, 'running', { stage: 'review', reviewedSha: 'H3' });
  db.update(epics).set({ approvedSha: 'H3' }).where(eq(epics.id, running.id)).run();
  expect(snapshot().epics.find((e) => e.issue === 4)).toMatchObject({ reviewedSha: 'H3', approvedSha: 'H3' }); // no event yet: the flag is absent
  expect(snapshot().epics.find((e) => e.issue === 4)).not.toHaveProperty('leadApproval');
});
