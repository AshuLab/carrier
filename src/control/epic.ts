import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { promisify } from 'node:util';
import { createScopedLogger } from '@ashulab/universal-logger';
import { and, desc, eq, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import { withGit } from '../execution/git-binary.ts';
import type { Db } from '../storage/db.ts';
import { callerResults, supersededOutcome } from '../storage/caller-results.ts';
import { epicReviewThreads } from '../storage/epic-review-threads.ts';
import { epicSlices } from '../storage/epic-slices.ts';
import { executionEvents } from '../storage/events.ts';
import { executions, reviewerSlots, slotOf, type Slot } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { Blocker, EpicReply } from './replies.ts';
import { optionsOf } from '../status/snapshot.ts';
import { agentOf } from './sessions.ts';
import { latestRoundTally, leadApproval } from '../orchestration/round.ts';
import { roundSlots } from '../orchestration/slots.ts';
import { redact } from '../logging/redact.ts';

const log = createScopedLogger('control');
const execFileAsync = promisify(execFile);

// The reply is bounded: with these, a round weighs at most about 60 KB, far under the client's 8 MiB line.
export const MAX_ROUNDS = 50;
const MAX_BLOCKERS = 50;
const MAX_OBSERVATIONS = 50;
const MAX_COMMITS = 50;
const MAX_TEXT = 200;
const MAX_URL = 500;
const MAX_ACTIVITY = 80;
const MAX_NO_VERDICT_WHY = 200;
const MAX_LIVE_EVENTS = 500; // per kind, newest first, of the one running execution

type Round = EpicReply['rounds'][number];
type Verdicts = Extract<CallerResult, { outcome: 'completed' | 'changes_requested' }>;
/** A review that gave a verdict, and a round with the reviews it has so far: `key` is the attempt, the round and the head. */
type Entry = { key: string; attempt: number; reviews: { run: typeof executions.$inferSelect; parsed: Verdicts; slot: Slot }[]; fixed: boolean; fixMs: number | null; fixedSha: string | null };
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

// At most four git processes at once for the socket's handlers: an epic of many lanes waits its turn instead of forking dozens.
const MAX_GIT = 4;
let running = 0;
const queue: (() => void)[] = [];
export async function limited<T>(work: () => Promise<T>): Promise<T> {
  if (running >= MAX_GIT) await new Promise<void>((go) => queue.push(go)); // the slot is handed over: `running` stays as it was
  else running++;
  try {
    return await work();
  } finally {
    const next = queue.shift();
    if (next === undefined) running--;
    else next();
  }
}

/** One git process in a slot of `limited`, its input closed at once (execFile leaves a pipe open: a command that read it would wait for the timeout). */
export const runGit = (cwd: string, args: string[], maxBuffer: number) =>
  limited(() =>
    withGit((binary) => {
      const run = execFileAsync(binary, args, { cwd, encoding: 'utf8', timeout: 5_000, maxBuffer, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' } });
      run.child.stdin?.end();
      return run;
    }),
  );

/** git in a folder; null when the folder is gone (expected: an epic's worktree is removed when it ends) or git failed (logged). */
export async function git(cwd: string, args: string[]): Promise<string | null> {
  if (existsSync(cwd) === false) return null;
  try {
    // no optional locks: reading an agent's worktree must not refresh its index under the agent's own commit
    const { stdout } = await runGit(cwd, args, 32 * 1024 * 1024);
    return stdout;
  } catch (error) {
    log.warn('git failed in an epic worktree', { cwd, args: args[0], error: String(error) });
    return null;
  }
}

// A range of two shas never changes, so asking git once is enough (this is polled every few seconds).
// Oldest entry out past the cap, so a long-lived engine does not grow with every round it ever saw.
const MAX_CACHED_RANGES = 500;
const commitCache = new Map<string, Round['commits']>();

/** The commits a fix added between the head the review saw and the head it left; empty when there is no worktree to ask. */
async function commitsBetween(cwd: string | null, from: string, to: string): Promise<Round['commits']> {
  if (cwd === null) return [];
  const key = `${cwd}\0${from}..${to}`;
  const cached = commitCache.get(key);
  if (cached) return cached;
  const out = await git(cwd, ['log', `--max-count=${MAX_COMMITS}`, '--format=%H%x00%s', `${from}..${to}`]);
  if (out === null) return [];
  const commits = out.split('\n').filter(Boolean).map((line) => {
    const [sha = '', subject = ''] = line.split('\0');
    return { sha, subject: subject.slice(0, MAX_TEXT) };
  });
  if (commitCache.size >= MAX_CACHED_RANGES) commitCache.delete(commitCache.keys().next().value!);
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
    db
      .select({ agentId: executionEvents.agentId, status: executionEvents.status, payload: executionEvents.payload, tool: executionEvents.tool, arg: executionEvents.arg })
      .from(executionEvents)
      .where(and(eq(executionEvents.executionId, running.executionId), eq(executionEvents.kind, kind)))
      .orderBy(desc(executionEvents.id))
      .limit(MAX_LIVE_EVENTS)
      .all();
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
export async function epicOf(db: Db, repo: string, issue: number): Promise<EpicReply | null> {
  const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const runs = db
    .select({ run: executions, result: callerResults.result, outcome: callerResults.outcome })
    .from(executions)
    .leftJoin(callerResults, eq(callerResults.executionId, executions.executionId))
    .where(eq(executions.epicId, epic.id))
    .orderBy(sql`executions.rowid`)
    .all();

  // Rounds, attempt by attempt: a ship after a review or a fix is an epic that started again.
  // A round is its number and the head its reviews were given, however many reviewers it has; a review of a head that moved is of no round, and neither is any other review on that head.
  let attempt = 0;
  let worked = false; // a review or a fix ran in this attempt
  let leading = false; // the lead has reviewed since the last review of the reviewers: a fix now is the lead's exchange
  const entries: Entry[] = [];
  const dead = new Set<string>(); // the rounds and heads a verdict was set aside on
  for (const { run, result, outcome } of runs) {
    if (outcome === supersededOutcome) {
      if (run.stage === 'review' && run.headSha !== null) dead.add(`${attempt}:${run.round}:${run.headSha}`);
      continue; // a review of a head that moved: no verdict, and no round of its own
    }
    if (run.stage === 'ship') {
      if (worked) {
        attempt++;
        worked = false;
        leading = false;
      }
      continue;
    }
    worked = true;
    if (run.stage === 'lead') {
      leading = true;
      continue; // the lead's exchange is no round: the round's verdicts are the reviewers'
    }
    const last = entries.at(-1);
    if (run.stage === 'fix') {
      if (leading) continue; // the author answering the lead: it answers no round of the reviewers
      if (last === undefined || last.attempt !== attempt) continue;
      last.fixed = true;
      if (result === null) continue; // a retry or one still running
      const parsed = JSON.parse(result) as CallerResult;
      last.fixMs = run.finishedAt === null ? null : run.finishedAt - run.startedAt;
      last.fixedSha = parsed.outcome === 'completed' ? parsed.pr.headSha : null;
      continue;
    }
    leading = false; // a review of the reviewers: the lead's exchange starts over
    if (result === null) continue;
    const parsed = JSON.parse(result) as CallerResult;
    if (parsed.outcome === 'needs_human') continue; // the reviewer stopped: no verdict to show
    const slot = slotOf(run)!;
    const key = `${attempt}:${run.round}:${run.headSha}`;
    // The same slot twice on one round and head is a round started again (a resume at review), which a round of its own as it always was.
    const entry = entries.findLast((e) => e.key === key && !e.fixed && !e.reviews.some((r) => r.slot === slot));
    const review = { run, parsed, slot };
    if (entry) entry.reviews.push(review);
    else entries.push({ key, attempt, reviews: [review], fixed: false, fixMs: null, fixedSha: null });
  }
  const toFound = ({ id, title, url }: { id?: string; title: string; url?: string }): Found => ({ id: id ?? null, title: title.slice(0, MAX_TEXT), url: url !== undefined && url.length <= MAX_URL ? url : null });
  const found: { round: Round; attempt: number; fixed: boolean }[] = [];
  let open = new Map<Slot, Found[]>(); // each reviewer's open blockers of the round before, in this attempt; none before the first round
  let openOf = -1;
  for (const entry of entries.filter((e) => !dead.has(e.key))) {
    if (entry.attempt !== openOf) {
      openOf = entry.attempt;
      open = new Map();
    }
    const reviews = entry.reviews.toSorted((x, y) => reviewerSlots.indexOf(x.slot) - reviewerSlots.indexOf(y.slot));
    const shown = reviews.map(({ run, parsed, slot }) => {
      const blockers: Found[] = parsed.outcome === 'changes_requested' ? parsed.blockers.map(toFound) : [];
      const observations: Found[] = parsed.outcome === 'completed' ? (parsed.observations ?? []).slice(0, MAX_OBSERVATIONS).map(toFound) : [];
      const reviewed = { run, slot, agent: agentOf(run, epic.config), verdict: parsed.outcome === 'completed' ? ('approved' as const) : ('changes_requested' as const), blockers: marked(blockers, open.get(slot) ?? null, parsed.resolved ?? []), observations, headSha: parsed.pr.headSha };
      open.set(slot, blockers);
      return reviewed;
    });
    // The mandatory reviewer stands for the round as the app reads it; when it gave no verdict, the first that did.
    const main = shown.find((r) => r.slot === 'reviewer') ?? shown[0]!;
    const others = shown.filter((r) => r !== main).map(({ slot, agent, verdict, blockers, observations }) => ({ slot, agent, verdict, blockers, observations }));
    found.push({
      attempt: entry.attempt,
      fixed: entry.fixed,
      round: {
        round: main.run.round ?? (found.filter((f) => f.attempt === entry.attempt).length + 1),
        reviewer: main.agent,
        verdict: main.verdict,
        blockers: main.blockers,
        observations: main.observations,
        reviewMs: main.run.finishedAt === null ? null : main.run.finishedAt - main.run.startedAt,
        fixMs: entry.fixMs,
        reviewedSha: main.headSha,
        fixedSha: entry.fixedSha,
        commits: [],
        ...(others.length > 0 && { otherReviewers: others }),
      },
    });
  }
  // read with the rows above, before git is waited for: the reply is one cut of the database, not one that a poll can change in between
  const slices = db.select().from(epicSlices).where(eq(epicSlices.epicId, epic.id)).orderBy(epicSlices.number).all();
  const threads = db.select().from(epicReviewThreads).where(eq(epicReviewThreads.epicId, epic.id)).orderBy(epicReviewThreads.position).all();
  const hints = liveHints(db, epic.id);

  const hitLimit = epic.status === 'needs_human' && epic.needsHumanKind === 'review_limit';
  const rounds = await Promise.all(found.slice(-MAX_ROUNDS).map(async ({ round, attempt: of, fixed }) => {
    // Nothing answered it and nothing follows: the epic stopped there for the limit.
    if (fixed === false && (of < attempt || hitLimit)) {
      if (round.verdict === 'changes_requested') round.verdict = 'limit_reached';
      for (const other of round.otherReviewers ?? []) if (other.verdict === 'changes_requested') other.verdict = 'limit_reached';
    }
    if (round.reviewedSha !== null && round.fixedSha !== null) round.commits = await commitsBetween(epic.workspace, round.reviewedSha, round.fixedSha);
    return round;
  }));

  // The stages of the current attempt: queued, then each contiguous run of a stage, then ready.
  const stages: EpicReply['stages'] = [{ stage: 'queued', startedAt: epic.queuedAt, endedAt: epic.startedAt }];
  if (epic.startedAt !== null) {
    const startedAt = epic.startedAt;
    const segments: { stage: 'ship' | 'review' | 'fix' | 'lead'; startedAt: number; slots: Slot[] }[] = [];
    for (const { run } of runs) {
      if (run.startedAt < startedAt) continue;
      if (segments.at(-1)?.stage !== run.stage) segments.push({ stage: run.stage, startedAt: segments.length === 0 ? startedAt : run.startedAt, slots: [] });
      const slot = run.stage === 'review' ? slotOf(run) : null;
      if (slot !== null && !segments.at(-1)!.slots.includes(slot)) segments.at(-1)!.slots.push(slot);
    }
    // reserved, the clone still being prepared: no execution yet
    if (segments.length === 0 && epic.stage !== null) segments.push({ stage: epic.stage, startedAt, slots: [] });
    const ended = epic.status === 'running' ? null : epic.finishedAt;
    stages.push(...segments.map(({ stage, startedAt, slots }, i) => ({ stage, startedAt, endedAt: segments[i + 1]?.startedAt ?? ended, ...(slots.length > 1 && { reviewers: slots }) })));
    if (epic.status === 'ready_for_test' && epic.finishedAt !== null) stages.push({ stage: 'ready', startedAt: epic.finishedAt, endedAt: null });
  }

  const reviewer = runs.findLast(({ run }) => run.stage === 'review' && run.workspace !== null)?.run.workspace ?? null;
  const lead = epic.config?.agents.leadReviewer;
  const approved = leadApproval(db, epic);
  const slots = roundSlots(epic.config);
  const tally = slots.length > 1 ? latestRoundTally(db, epic, slots) : undefined; // the reason of a reviewer with no verdict is redacted: an agent wrote it
  const worktrees: EpicReply['worktrees'] = [
    ...(epic.workspace === null ? [] : [{ kind: 'epic' as const, lane: null, path: epic.workspace }]),
    ...(reviewer === null ? [] : [{ kind: 'reviewer' as const, lane: null, path: reviewer }]),
  ];
  // the row records the branch once ship is validated; before that the worktree's HEAD is the only place it is
  const branch = epic.branch ?? (epic.workspace === null ? null : ((await git(epic.workspace, ['symbolic-ref', '--short', 'HEAD']))?.trim() || null));

  return { stages, rounds, slices: slices.map(({ number, title, state, blockedBy, prNumber, prState, prMergedAt, closedAt, readAt }) => ({ number, title, state, blockedBy, prNumber, prState, prMergedAt, closedAt, readAt, lane: null, activity: null, ...(state === 'in_progress' && hints.get(number)) })), slicesTruncated: slices.some((s) => s.truncated), threads: threads.map(({ epicId, position, readAt, truncated, ...thread }) => thread), threadsTruncated: threads.some((t) => t.truncated), worktrees, branch, options: optionsOf(epic), ...(epic.unansweredObservations !== null && epic.unansweredReason !== null && { unansweredObservations: { count: epic.unansweredObservations, reason: epic.unansweredReason } }), pr: epic.pr, ...(tally && { reviewers: { given: tally.given, of: tally.of, none: tally.none.map(({ slot, why }) => ({ slot, why: redact(why).slice(0, MAX_NO_VERDICT_WHY) })) } }), ...(epic.reviewedSha !== null && { reviewedSha: epic.reviewedSha }), ...(epic.approvedSha !== null && { approvedSha: epic.approvedSha, ...(approved !== undefined && { leadApproval: approved }) }), ...(lead && { lead: { harness: lead.harness, model: lead.model, provider: lead.provider ?? null } }) };
}
