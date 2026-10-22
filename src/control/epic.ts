import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { createScopedLogger } from '@ashulab/universal-logger';
import { and, desc, eq, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import type { Db } from '../storage/db.ts';
import { callerResults } from '../storage/caller-results.ts';
import { epicReviewThreads } from '../storage/epic-review-threads.ts';
import { epicSlices } from '../storage/epic-slices.ts';
import { executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { Blocker, EpicReply } from './replies.ts';
import { agentOf } from './sessions.ts';

const log = createScopedLogger('control');

// The reply is bounded: with these, a round weighs at most about 60 KB, far under the client's 8 MiB line.
export const MAX_ROUNDS = 50;
const MAX_BLOCKERS = 50;
const MAX_COMMITS = 50;
const MAX_TEXT = 200;
const MAX_URL = 500;
const MAX_ACTIVITY = 80;
const MAX_LIVE_EVENTS = 500; // per kind, newest first, of the one running execution

type Round = EpicReply['rounds'][number];
type Found = { id: string | null; title: string; url: string | null };

/** A title compared without caring for case or spacing. */
const normal = (title: string) => title.trim().replace(/\s+/g, ' ').toLowerCase();

/** The same blocker in two rounds: by id when both have one, else by title. */
const same = (a: Found, b: Found) => (a.id !== null && b.id !== null ? a.id === b.id : normal(a.title) === normal(b.title));

/**
 * Blockers of a round against the open ones of the round before it in the same attempt: the same blocker is carried, one that
 * disappeared is fixed, a new one is new. A mark is exact when ids settle it (the first round has nothing to match, so new is certain);
 * otherwise it comes from matching titles and is approximate. `resolved` is what the reviewer said it considers fixed.
 */
function marked(current: Found[], previous: Found[] | null, resolved: string[]): Blocker[] {
  const prior = previous ?? [];
  const blocker = (b: Found, mark: Blocker['mark'], approximate: boolean): Blocker => ({ id: b.id, title: b.title, url: b.url, mark, approximate });
  const allIds = (list: Found[]) => list.every(({ id }) => id !== null);
  return [
    ...current.map((b) => blocker(b, prior.some((p) => same(b, p)) ? 'carried' : 'new', previous !== null && (b.id === null || !allIds(prior)))),
    ...prior
      .filter((p) => current.some((b) => same(b, p)) === false)
      .map((p) => blocker(p, 'fixed', !(p.id !== null && (resolved.includes(p.id) || allIds(current))))),
  ].slice(0, MAX_BLOCKERS);
}

/** git in a folder; null when the folder is gone (expected: an epic's worktree is removed when it ends) or git failed (logged). */
export function git(cwd: string, args: string[]): string | null {
  if (existsSync(cwd) === false) return null;
  try {
    // no optional locks: reading an agent's worktree must not refresh its index under the agent's own commit
    return execFileSync('git', args, { cwd, encoding: 'utf8', timeout: 5_000, maxBuffer: 32 * 1024 * 1024, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' }, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    log.warn('git failed in an epic worktree', { cwd, args: args[0], error: String(error) });
    return null;
  }
}

// A range of two shas never changes, so asking git once is enough (this is polled every few seconds).
// ponytail: unbounded, one entry per fixed round; evict if a very long-lived engine ever matters.
const commitCache = new Map<string, Round['commits']>();

/** The commits a fix added between the head the review saw and the head it left; empty when there is no worktree to ask. */
function commitsBetween(cwd: string | null, from: string, to: string): Round['commits'] {
  if (cwd === null) return [];
  const key = `${cwd}\0${from}..${to}`;
  const cached = commitCache.get(key);
  if (cached) return cached;
  const out = git(cwd, ['log', `--max-count=${MAX_COMMITS}`, '--format=%H%x00%s', `${from}..${to}`]);
  if (out === null) return [];
  const commits = out.split('\n').filter(Boolean).map((line) => {
    const [sha = '', subject = ''] = line.split('\0');
    return { sha, subject: subject.slice(0, MAX_TEXT) };
  });
  commitCache.set(key, commits);
  return commits;
}

/**
 * The lane and the activity of the agent building each slice, by slice number: the agent is the one whose newest `task` event
 * names the slice and has no status (a second `task` event ends it). Only the running author execution is read, newest events
 * first and capped, so it never grows with the table. The lane is a hint: `lane` in an event's payload, else `--lane-N` in a call's argument.
 */
function liveHints(db: Db, epicId: number): Map<number, { lane: number | null; activity: string | null }> {
  const hints = new Map<number, { lane: number | null; activity: string | null }>();
  const running = db
    .select({ executionId: executions.executionId })
    .from(executions)
    .where(and(eq(executions.epicId, epicId), eq(executions.stage, 'ship'), eq(executions.status, 'running')))
    .orderBy(desc(sql`executions.rowid`))
    .get();
  if (running === undefined) return hints;
  const newest = (kind: 'task' | 'tool_start') =>
    db.select().from(executionEvents).where(and(eq(executionEvents.executionId, running.executionId), eq(executionEvents.kind, kind))).orderBy(desc(executionEvents.id)).limit(MAX_LIVE_EVENTS).all();
  const calls = newest('tool_start');
  const seen = new Set<string>();
  for (const task of newest('task')) {
    if (task.agentId === null || seen.has(task.agentId)) continue;
    seen.add(task.agentId);
    const slice = task.payload?.slice;
    if (task.status !== null || slice === undefined || hints.has(slice)) continue;
    const mine = calls.filter((call) => call.agentId === task.agentId);
    const lane = mine.map((call) => call.payload?.lane ?? Number(/--lane-(\d+)/.exec(call.arg ?? '')?.[1] ?? NaN)).find((n) => Number.isNaN(n) === false);
    const call = mine[0];
    hints.set(slice, { lane: lane ?? null, activity: call === undefined ? null : [call.tool, call.arg].filter((part) => part !== null).join(' ').replace(/\s+/g, ' ').slice(0, MAX_ACTIVITY) });
  }
  return hints;
}

/**
 * The stage timeline, review rounds, worktrees and branch of an epic; null for one the engine does not know.
 * Built from the executions and the stored results, so it also reads an epic that has finished. A round is a review that
 * left a result: technical retries leave none and make no round. An epic put back in the queue starts new rounds from 1
 * after the old ones, which stay in the list. `slices` is the cache of GitHub the poll keeps (ADR 0008); `pr` is the block the poll cached from GitHub, null while the epic has no pull request, and `threads` the pull request's review threads cached with it.
 */
export function epicOf(db: Db, repo: string, issue: number): EpicReply | null {
  const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const runs = db
    .select({ run: executions, result: callerResults.result })
    .from(executions)
    .leftJoin(callerResults, eq(callerResults.executionId, executions.executionId))
    .where(eq(executions.epicId, epic.id))
    .orderBy(sql`executions.rowid`)
    .all();

  // Rounds, attempt by attempt: a ship after a review or a fix is an epic that started again.
  let attempt = 0;
  let worked = false; // a review or a fix ran in this attempt
  let open: Found[] | null = null; // the previous round's open blockers; null before the first round
  const found: { round: Round; attempt: number; fixed: boolean }[] = [];
  for (const { run, result } of runs) {
    if (run.stage === 'ship') {
      if (worked) {
        attempt++;
        worked = false;
        open = null;
      }
      continue;
    }
    worked = true;
    const last = found.at(-1);
    if (run.stage === 'fix') {
      if (last === undefined || last.attempt !== attempt) continue;
      last.fixed = true;
      if (result === null) continue; // a retry or one still running
      const parsed = JSON.parse(result) as CallerResult;
      last.round.fixMs = run.finishedAt === null ? null : run.finishedAt - run.startedAt;
      last.round.fixedSha = parsed.outcome === 'completed' ? parsed.pr.headSha : null;
      continue;
    }
    if (result === null) continue;
    const parsed = JSON.parse(result) as CallerResult;
    if (parsed.outcome === 'needs_human') continue; // the reviewer stopped: no verdict to show
    const blockers: Found[] = parsed.outcome === 'changes_requested' ? parsed.blockers.map(({ id, title, url }) => ({ id: id ?? null, title: title.slice(0, MAX_TEXT), url: url !== undefined && url.length <= MAX_URL ? url : null })) : [];
    found.push({
      attempt,
      fixed: false,
      round: {
        round: run.round ?? (found.filter((f) => f.attempt === attempt).length + 1),
        reviewer: agentOf(run, epic.config),
        verdict: parsed.outcome === 'completed' ? 'approved' : 'changes_requested',
        blockers: marked(blockers, open, parsed.resolved ?? []),
        reviewMs: run.finishedAt === null ? null : run.finishedAt - run.startedAt,
        fixMs: null,
        reviewedSha: parsed.pr.headSha,
        fixedSha: null,
        commits: [],
      },
    });
    open = blockers;
  }
  const hitLimit = epic.status === 'needs_human' && epic.needsHumanReason?.startsWith('review limit') === true;
  const rounds = found.slice(-MAX_ROUNDS).map(({ round, attempt: of, fixed }) => {
    // Nothing answered it and nothing follows: the epic stopped there for the limit.
    if (round.verdict === 'changes_requested' && fixed === false && (of < attempt || hitLimit)) round.verdict = 'limit_reached';
    if (round.reviewedSha !== null && round.fixedSha !== null) round.commits = commitsBetween(epic.workspace, round.reviewedSha, round.fixedSha);
    return round;
  });

  // The stages of the current attempt: queued, then each contiguous run of a stage, then ready.
  const stages: EpicReply['stages'] = [{ stage: 'queued', startedAt: epic.queuedAt, endedAt: epic.startedAt }];
  if (epic.startedAt !== null) {
    const startedAt = epic.startedAt;
    const segments: { stage: 'ship' | 'review' | 'fix'; startedAt: number }[] = [];
    for (const { run } of runs) {
      if (run.startedAt >= startedAt && segments.at(-1)?.stage !== run.stage) segments.push({ stage: run.stage, startedAt: segments.length === 0 ? startedAt : run.startedAt });
    }
    // reserved, the clone still being prepared: no execution yet
    if (segments.length === 0 && epic.stage !== null) segments.push({ stage: epic.stage, startedAt });
    const ended = epic.status === 'running' ? null : epic.finishedAt;
    stages.push(...segments.map((segment, i) => ({ ...segment, endedAt: segments[i + 1]?.startedAt ?? ended })));
    if (epic.status === 'ready_for_test' && epic.finishedAt !== null) stages.push({ stage: 'ready', startedAt: epic.finishedAt, endedAt: null });
  }

  const reviewer = runs.findLast(({ run }) => run.stage === 'review' && run.workspace !== null)?.run.workspace ?? null;
  const worktrees: EpicReply['worktrees'] = [
    ...(epic.workspace === null ? [] : [{ kind: 'epic' as const, lane: null, path: epic.workspace }]),
    ...(reviewer === null ? [] : [{ kind: 'reviewer' as const, lane: null, path: reviewer }]),
  ];
  // ponytail: read from the worktree's HEAD until the epic row records its branch
  const branch = epic.workspace === null ? null : (git(epic.workspace, ['symbolic-ref', '--short', 'HEAD'])?.trim() || null);

  const slices = db.select().from(epicSlices).where(eq(epicSlices.epicId, epic.id)).orderBy(epicSlices.number).all();
  const threads = db.select().from(epicReviewThreads).where(eq(epicReviewThreads.epicId, epic.id)).orderBy(epicReviewThreads.position).all();
  const hints = liveHints(db, epic.id);
  return { stages, rounds, slices: slices.map(({ number, title, state, blockedBy, prNumber, closedAt, readAt }) => ({ number, title, state, blockedBy, prNumber, closedAt, readAt, lane: null, activity: null, ...(state === 'in_progress' && hints.get(number)) })), slicesTruncated: slices.some((s) => s.truncated), threads: threads.map(({ epicId, position, readAt, truncated, ...thread }) => thread), threadsTruncated: threads.some((t) => t.truncated), worktrees, branch, pr: epic.pr };
}
