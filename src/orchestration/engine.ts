import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { and, asc, desc, eq, inArray, isNotNull, isNull, notInArray, sql } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { AgentExit, AgentRun, AgentRunner, AgentTask } from '../execution/agent-runner.ts';
import { parseCallerResult } from '../execution/caller-result.ts';
import { importResult } from '../execution/import-result.ts';
import type { Workspaces } from '../execution/workspaces.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { epicEvents } from '../storage/events.ts';
import { executions, type executionStates } from '../storage/executions.ts';
import { executionOutput, taskContext } from '../logging/logger.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';
import { latestBlockers } from './blockers.ts';
import { endOf } from './final-pr.ts';
import { AuthError, GitHubUnavailable, labelStyles, needsHumanLabel, ownedLabels, readyForTestLabel, readyLabel, runningLabel, type GitHub, type Slices } from './github.ts';
import { reserve } from './reserve.ts';
import { startRetention, type SessionDirs } from './retention.ts';
import { failureStreak } from './retry.ts';

export type EngineOptions = {
  db: Db;
  github: GitHub;
  clock: Clock;
  repos: EffectiveRepoConfig[];
  pollIntervalMs: number;
  maxConcurrentEpics: number;
  maxExecutionHours: number | 'unlimited';
  /** Technical failures retried per stage after the first attempt. */
  maxExecutionRetries: number;
  /** Reviews of the final PR before the epic goes to a person; fix turns do not count. */
  maxReviews: number;
  runner: AgentRunner;
  workspaces: Workspaces;
  /** Shared root: execution results go under `orchestrator/results/`. */
  root: string;
  /** Where the CLIs keep sessions, for the 30-day cleanup; the CLIs' own folders by default. */
  sessionDirs?: SessionDirs;
};

const log = createScopedLogger('engine');
const activityEveryMs = 10_000;

type Epic = typeof epics.$inferSelect;
type Execution = typeof executions.$inferSelect;

// Technical end of the process; whether the epic moves on depends on its result (retries and timeouts: later slices).
const sessionLost = 'the agent session is not available';

const executionStatus: Record<AgentExit, (typeof executionStates)[number]> = {
  ok: 'finished',
  failed: 'failed',
  timed_out: 'timed_out',
  stopped: 'interrupted',
  auth_failed: 'failed',
  session_unavailable: 'failed',
};

export function createEngine({ db, github, clock, repos, pollIntervalMs, maxConcurrentEpics, maxExecutionHours, maxExecutionRetries, maxReviews, runner, workspaces, root, sessionDirs }: EngineOptions) {
  let error: GitHubUnavailable | AuthError | null = null;
  let nextPollAt: number | null = null;
  let paused = false; // intake only: nothing new is reserved, what is running goes on
  let polling = false;
  // The orchestrator's profile failed: no GitHub call is made until the poll's probe succeeds. Never another profile.
  let suspended: AuthError | null = null;
  let cancel: (() => void) | null = null;
  let stopRetention: (() => void) | null = null;
  const labelledRepos = new Set<string>();
  // Slice progress GitHub reported on the last good read, by repo and issue; not stored, so it is empty until the first poll after a start.
  const progress = new Map<string, Map<number, Slices | null>>();
  // Runs of this process still going, to stop them when the epic ends from outside.
  const active = new Map<string, AgentRun>();
  // Set by shutdown(): from then on nothing polls, reserves, launches or writes to GitHub.
  let stopping = false;

  // Creates the owned labels a repo lacks, with their colour and description; never touches existing ones nor creates `ready` (Solve's).
  async function ensureLabels() {
    for (const { name } of repos) {
      if (stopping) return;
      if (labelledRepos.has(name)) continue;
      const existing = await github.listLabels(name);
      for (const label of ownedLabels) if (!existing.includes(label)) await github.createLabel(name, label, labelStyles[label]);
      labelledRepos.add(name);
    }
  }

  // The one owned label each status shows; merged and cancelled (stopped from outside) show none.
  const labelOf = (status: Epic['status']) =>
    ({ running: runningLabel, needs_human: needsHumanLabel, ready_for_test: readyForTestLabel })[status as 'running'] as string | undefined;

  // An epic a person sent back to the queue: nothing of the previous attempt is kept, the executions stay as history.
  const restart = (queuedAt: number) => ({
    status: 'queued' as const, queuedAt, startedAt: null, config: null, labelPending: false, stage: null, stageStartedAt: null, workspace: null,
    lastActivityAt: null, lastError: null, round: null, prNumber: null, prHeadSha: null, reviewedSha: null, verification: null,
    needsHumanReason: null, finishedAt: null,
  });

  // Mirrors the epic's status on its issue: its label, none of the other owned ones, and no `ready` while running.
  const applyLabels = async ({ id, repo, issue, status }: Epic) => {
    if (stopping || suspended) return; // labelPending stays true: the next run reflects it
    const wanted = labelOf(status);
    await github.setLabels(repo, issue, {
      add: wanted ? [wanted] : [],
      remove: [...ownedLabels.filter((l) => l !== wanted), ...(status === 'running' ? [readyLabel] : [])],
    });
    db.update(epics).set({ labelPending: false }).where(eq(epics.id, id)).run();
  };

  const fresh = (id: number) => db.select().from(epics).where(eq(epics.id, id)).get()!;

  // GitHub being down is expected (the next poll retries), and so is a failing orchestrator profile; anything else is a bug and surfaces.
  const failed = (e: unknown) => {
    if (e instanceof AuthError) suspended = e;
    else if (!(e instanceof GitHubUnavailable)) throw e;
    error = e;
  };

  // The epic leaves `running` for `needs_human`; the label follows (labelPending) and the slot is free.
  const toNeedsHuman = (writer: Pick<Db, 'update'>, id: number, reason: string) =>
    writer.update(epics).set({ status: 'needs_human', needsHumanReason: reason, finishedAt: clock.now(), labelPending: true }).where(eq(epics.id, id)).run();

  // Mirrors the label, then launches the author unless the epic already has one.
  const begin = async (epic: Epic) => {
    if (stopping) return;
    await applyLabels(epic);
    if (epic.status === 'running' && epic.stage === null) await launch(epic, 'ship');
  };

  // Launches the author (ship, fix) or the reviewer (review) for the epic's current stage.
  async function launch(epic: Epic, stage: AgentTask['stage']) {
    if (stopping) return;
    if (stage === 'ship') {
      // Claim the launch first: concurrent reconciles (a result freeing a slot, the poll) never start a second author.
      const claimed = db.update(epics).set({ stage: 'ship', stageStartedAt: clock.now() }).where(and(eq(epics.id, epic.id), isNull(epics.stage))).returning().get();
      if (!claimed) return;
    }
    await execute(epic, stage);
  }

  // Starts an execution of the stage; `retryOf` is the failed or interrupted one it replaces: same session, verify
  // the real state first. `rebuild` (the session is gone) starts a new session instead, with the PR as GitHub has it now.
  async function execute(epic: Epic, stage: AgentTask['stage'], retryOf?: Execution, rebuild?: { pr: { number: number; headSha: string } | null }) {
    const reviewing = stage === 'review';
    const resumeSession = rebuild ? undefined : (retryOf?.sessionId ?? (stage === 'fix' ? authorSession(epic.id) : undefined));
    const pr = rebuild?.pr ?? (epic.prNumber ? { number: epic.prNumber, headSha: epic.prHeadSha! } : undefined);
    let workspace: string;
    try {
      if (stage === 'fix') {
        // Where `ship` left the epic's worktree: a session resumed anywhere else would act in another cwd.
        if (!epic.workspace) throw new Error('the epic has no saved worktree');
        workspace = epic.workspace;
      } else workspace = reviewing ? await workspaces.prepareReviewer(epic.repo, epic.issue, epic.prNumber!) : await workspaces.prepareAuthor(epic.repo, epic.issue);
    } catch (e) {
      log.error('could not prepare the workspace', e, { repo: epic.repo, epic: epic.issue, stage });
      toNeedsHuman(db, epic.id, `could not prepare the workspace: ${e instanceof Error ? e.message : String(e)}`);
      return applyLabels(fresh(epic.id));
    }
    const executionId = randomUUID();
    const resultPath = join(root, 'orchestrator', 'results', `${executionId}.json`);
    const task: AgentTask = {
      executionId,
      repo: epic.repo,
      epic: epic.issue,
      stage,
      ...(reviewing ? epic.config!.agents.reviewer : epic.config!.agents.author),
      workspace,
      resultPath,
      timeoutMs: maxExecutionHours === 'unlimited' ? null : maxExecutionHours * 3_600_000,
      ...(resumeSession && { resumeSession }),
      context: {
        previousSummaries: reviewing || rebuild ? previousSummaries(epic.id) : [],
        ...(stage === 'fix' && { blockers: latestBlockers(db, epic.id) }),
        ...(retryOf && { verifyStateFirst: true }),
        ...(pr && { pr }),
        ...(epic.round && { round: epic.round }),
      },
    };
    if (stopping) return;
    db.insert(executions).values({ executionId, epicId: epic.id, stage, resultPath, startedAt: clock.now() }).run();
    const context = taskContext({ repo: epic.repo, epic: epic.issue, executionId, stage, round: epic.round });
    log.info('execution started', context);
    const run = runner.run(task);
    active.set(executionId, run);
    const writeOutput = executionOutput(root, executionId);
    // The panel's "last activity": a SQLite write at most every 10 s, not one per chunk.
    let activityAt: number | null = null;
    run.onOutput((stream, chunk) => {
      writeOutput(stream, chunk);
      const now = clock.now();
      if (activityAt !== null && now - activityAt < activityEveryMs) return;
      activityAt = now;
      db.update(epics).set({ lastActivityAt: now }).where(eq(epics.id, epic.id)).run();
    });
    run.onSession((sessionId) => db.update(executions).set({ sessionId }).where(eq(executions.executionId, executionId)).run());
    track(
      run.done.then(async ({ exit, sessionId }) => {
        active.delete(executionId);
        (exit === 'ok' ? log.info : log.warn)('execution ended', { ...context, exit });
        const failure = { failed: 'the agent process ended with an error', auth_failed: `authentication error for profile ${task.profile}`, session_unavailable: sessionLost }[exit as 'failed'];
        db.update(executions)
          .set({ status: executionStatus[exit], finishedAt: clock.now(), ...(sessionId && { sessionId }), ...(failure && { error: failure }) })
          .where(eq(executions.executionId, executionId))
          .run();
        if (failure) db.update(epics).set({ lastError: failure }).where(eq(epics.id, epic.id)).run();
        if (exit === 'ok') await settle(db.select().from(executions).where(eq(executions.executionId, executionId)).get()!);
        else if (exit === 'failed' || exit === 'session_unavailable') await retry(epic.id);
        else if (exit === 'auth_failed') await stopProfile(task.profile);
        else if (exit === 'timed_out') {
          // Session and workspace stay as they are; a person decides how to go on.
          toNeedsHuman(db, epic.id, `the ${stage} execution exceeded the time limit`);
          await freeSlot();
        }
      }),
    );
  }

  // Forge rejected a profile: the running epics that use it stop for a person, with their runs; the others go on.
  // The profile is never swapped for another one.
  async function stopProfile(profile: string) {
    for (const epic of db.select().from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) {
      const { author, reviewer } = epic.config!.agents;
      if (author.profile !== profile && reviewer.profile !== profile) continue;
      toNeedsHuman(db, epic.id, `authentication error for profile ${profile}`);
      const running = db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).all();
      await Promise.all(running.map(({ executionId }) => active.get(executionId)?.stop()));
    }
    await freeSlot();
  }

  // Relaunches the stage whose last execution failed technically, until the retries run out.
  const retrying = new Set<number>();
  async function retry(epicId: number) {
    if (stopping || suspended || retrying.has(epicId)) return;
    retrying.add(epicId);
    try {
      const epic = fresh(epicId);
      const [last, ...earlier] = failureStreak(db, epicId);
      if (epic.status !== 'running' || !last) return;
      if (earlier.length >= maxExecutionRetries) {
        toNeedsHuman(db, epicId, `ran out of ${last.stage} retries (${earlier.length + 1} attempts): ${last.error}`);
        return await freeSlot();
      }
      // Read only: what the failed execution may have left on GitHub. A failed query is not an attempt, the poll tries again.
      const pr = await github.findPullRequest(epic.repo, epic.issue);
      // A lost session is rebuilt, not resumed: new session, same profile, context from SQLite and GitHub.
      const lost = last.error === sessionLost;
      db.insert(epicEvents)
        .values({ epicId, at: clock.now(), type: lost ? 'session_rebuilt' : 'execution_retried', data: { stage: last.stage, failed: last.executionId, attempt: earlier.length + 2, error: last.error, pr } })
        .run();
      await execute(epic, last.stage, last, lost ? { pr: pr && { number: pr.number, headSha: pr.headSha } } : undefined);
    } finally {
      retrying.delete(epicId);
    }
  }

  // Running epics whose last execution failed and was not relaunched yet (GitHub was down).
  async function retryPending() {
    for (const { id } of db.select({ id: epics.id }).from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) await retry(id);
  }

  // Summaries the caller left in earlier review and fix turns, oldest first.
  const previousSummaries = (epicId: number) =>
    db
      .select({ result: callerResults.result })
      .from(callerResults)
      .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
      .where(and(eq(executions.epicId, epicId), inArray(executions.stage, ['review', 'fix'])))
      .orderBy(asc(executions.startedAt))
      .all()
      .map(({ result }) => (JSON.parse(result) as { summary: string }).summary);

  // Where the author left off: the fix turn resumes it.
  const authorSession = (epicId: number) =>
    db
      .select({ sessionId: executions.sessionId })
      .from(executions)
      .where(and(eq(executions.epicId, epicId), inArray(executions.stage, ['ship', 'fix']), isNotNull(executions.sessionId)))
      .orderBy(desc(sql`rowid`))
      .get()?.sessionId ?? undefined;

  const inflight = new Set<Promise<void>>();
  const track = (work: Promise<void>) => {
    const tracked: Promise<void> = work
      .catch((e) => {
        log.error('stage work failed', e);
        failed(e);
      })
      .finally(() => inflight.delete(tracked));
    inflight.add(tracked);
  };

  // Does the final PR the caller reported hold up against what GitHub says? Returns why not, or null.
  function prProblem({ issue }: Epic, found: Awaited<ReturnType<GitHub['getPullRequest']>>, pr: { number: number; headSha: string }, stage: Execution['stage']) {
    if (!found) return `PR #${pr.number} does not exist`;
    if (found.state !== 'open') return `PR #${pr.number} is not open`;
    if (!new RegExp(`\\bcloses #${issue}(?!\\d)`, 'i').test(found.body)) return `PR #${pr.number} does not reference the epic (missing "Closes #${issue}")`;
    if (found.headSha !== pr.headSha) {
      return stage === 'review' ? 'the head changed during the review' : `the head of PR #${pr.number} is ${found.headSha}, not ${pr.headSha}`;
    }
    return null;
  }

  const expectedOf = (epic: Epic, execution: Execution) => ({ executionId: execution.executionId, repo: epic.repo, epic: epic.issue, stage: execution.stage });

  // The file the caller left, null when there is none (the parser reports it).
  function readResult({ resultPath }: Execution) {
    try {
      return readFileSync(resultPath, 'utf8');
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e;
      return null;
    }
  }

  // Imports the result of a finished execution and moves the epic. Safe to repeat: the import is idempotent.
  async function settle(execution: Execution) {
    if (stopping || suspended) return; // stays `finished` without a result: the next run imports it
    const epic = fresh(execution.epicId);
    if (epic.status === 'merged' || epic.status === 'cancelled' || epic.status === 'repo_removed') return; // ended from outside or stopped: nothing new moves
    const expected = expectedOf(epic, execution);
    const raw = readResult(execution);
    const parsed = parseCallerResult(raw, expected);
    const context = taskContext({ repo: epic.repo, epic: epic.issue, executionId: execution.executionId, stage: execution.stage, round: epic.round });
    if (!parsed.ok) {
      log.warn('invalid caller result', { ...context, reason: parsed.message });
      db.update(executions).set({ status: 'invalid_result', error: parsed.message }).where(eq(executions.executionId, execution.executionId)).run();
      db.update(epics).set({ lastError: parsed.message }).where(eq(epics.id, epic.id)).run();
      return retry(epic.id);
    }
    let problem: string | null = null;
    let workspace: string | undefined;
    if (parsed.result.outcome !== 'needs_human') {
      const { pr } = parsed.result;
      const found = await github.getPullRequest(epic.repo, pr.number);
      problem = prProblem(epic, found, pr, execution.stage);
      if (!problem && execution.stage === 'ship') {
        // Solve put the epic's worktree where its solve.md says: read it back from git, keep the real path for the fix turns.
        const branch = found!.headRef;
        try {
          workspace = (await workspaces.findWorktree(epic.repo, branch)) ?? undefined;
        } catch (e) {
          log.error('could not list the worktrees', e, context);
        }
        if (!workspace) problem = `could not find the worktree for branch ${branch} in the clone of ${epic.repo}`;
      }
    }
    const imported = importResult(db, raw, expected, (tx, result) => {
      const update = (set: Partial<Epic>) => tx.update(epics).set(set).where(eq(epics.id, epic.id)).run();
      if (result.outcome === 'needs_human') toNeedsHuman(tx, epic.id, result.reason);
      else if (problem) toNeedsHuman(tx, epic.id, problem);
      else if (execution.stage === 'ship') update({ stage: 'review', stageStartedAt: clock.now(), round: 1, prNumber: result.pr.number, prHeadSha: result.pr.headSha, workspace });
      else if (execution.stage === 'fix') update({ stage: 'review', stageStartedAt: clock.now(), round: (epic.round ?? 0) + 1, prHeadSha: result.pr.headSha });
      // The round stays: the fix turn answers it, and the next review numbers the following one.
      else if (result.outcome === 'changes_requested') {
        if ((epic.round ?? 0) >= maxReviews) toNeedsHuman(tx, epic.id, `review limit: round ${epic.round} of ${maxReviews} still has requested changes`);
        else update({ stage: 'fix', stageStartedAt: clock.now() });
      }
      else update({ status: 'ready_for_test', reviewedSha: result.pr.headSha, verification: result.verification, finishedAt: clock.now(), labelPending: true });
    });
    if (!('duplicate' in imported)) db.update(epics).set({ lastError: null }).where(eq(epics.id, epic.id)).run();
    log.info('result imported', { ...context, outcome: parsed.result.outcome, duplicate: 'duplicate' in imported });
    const next = fresh(epic.id);
    // ship and fix hand over to the reviewer, a review with changes hands over to the author.
    if (!('duplicate' in imported) && next.status === 'running' && next.stage && next.stage !== 'ship') await launch(next, next.stage);
    await freeSlot();
  }

  // A result arrived: reflect it on the issue and give the freed slot to the next epic without waiting for the poll.
  async function freeSlot() {
    await reconcileLabels();
    await fillSlots();
  }

  // The final PR was merged or the epic issue / final PR closed without merge: the epic stops and its
  // executions too. Sessions and history stay; the label follows (labelPending) and the slot is free.
  async function stopEnded() {
    for (const epic of db.select().from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) {
      const end = await endOf(github, epic);
      if (!end) continue;
      db.update(epics)
        .set({ status: end.status, ...(end.status === 'cancelled' && { cancelReason: end.reason }), finishedAt: clock.now(), labelPending: true })
        .where(eq(epics.id, epic.id))
        .run();
      db.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: `epic_${end.status}`, data: { reason: end.reason } }).run();
      const running = db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).all();
      await Promise.all(running.map(({ executionId }) => active.get(executionId)?.stop()));
    }
  }

  // Finished executions whose result could not be imported yet (GitHub was down).
  async function settlePending() {
    const pending = db
      .select({ execution: executions })
      .from(executions)
      .leftJoin(callerResults, eq(callerResults.executionId, executions.executionId))
      .where(and(eq(executions.status, 'finished'), isNull(callerResults.executionId)))
      .orderBy(asc(executions.startedAt))
      .all();
    for (const { execution } of pending) await settle(execution);
  }

  // SQLite is the authority: a label that did not reach GitHub is retried here.
  async function reconcileLabels() {
    const pending = db
      .select()
      .from(epics)
      .where(and(inArray(epics.status, ['running', 'needs_human', 'ready_for_test', 'merged', 'cancelled']), eq(epics.labelPending, true)))
      .orderBy(asc(epics.id))
      .all();
    for (const epic of pending) await begin(epic);
  }

  // Starts the oldest queued epics until the concurrency limit or the queue is exhausted.
  async function fillSlots() {
    for (;;) {
      if (stopping || suspended || paused) return;
      const epic = reserve(db, { maxConcurrent: maxConcurrentEpics, now: clock.now(), repos });
      if (!epic) return;
      const cancelWith = (cancelReason: string) =>
        db.update(epics).set({ status: 'cancelled', cancelReason, finishedAt: clock.now(), labelPending: false }).where(eq(epics.id, epic.id)).run();
      let issue;
      try {
        issue = await github.getIssue(epic.repo, epic.issue);
      } catch (e) {
        // Could not check it: give the slot back, the epic keeps its place in the queue.
        db.update(epics).set({ status: 'queued', startedAt: null, config: null, labelPending: false }).where(eq(epics.id, epic.id)).run();
        throw e;
      }
      if (issue.state === 'closed') cancelWith('cerrada antes de iniciar');
      else if (!issue.labels.includes(readyLabel)) cancelWith('ready removido');
      else await begin(epic); // GitHubUnavailable here leaves it reserved, labelPending
    }
  }

  // Restart, before anything is reserved: stop what the previous process left alive, then continue each running
  // epic from where it was. Safe to repeat (GitHub may be down halfway): what it relaunched is `active` or running.
  let recovered = false;
  async function recover() {
    // Orphans first: no second agent may start on a workspace while the first still acts on it.
    for (const id of await runner.listActive()) if (!active.has(id)) {
      log.warn('stopping orphan execution', { executionId: id });
      await runner.stop(id);
    }
    for (const { executionId } of db.select().from(executions).where(eq(executions.status, 'running')).all()) {
      if (active.has(executionId)) continue;
      db.update(executions).set({ status: 'interrupted', finishedAt: clock.now() }).where(eq(executions.executionId, executionId)).run();
    }
    // A repo missing from the config stops its pending epics, untouched, with where they were; a repo back resumes them
    // there (a `needs_human` one stays stopped). No GitHub call, label change, execution or retry for either.
    const configured = repos.map((r) => r.name);
    const now = clock.now();
    for (const epic of db.select().from(epics).where(and(inArray(epics.status, ['queued', 'running', 'needs_human']), notInArray(epics.repo, configured))).all()) {
      const reason = 'the repo is no longer in the configuration';
      db.update(epics).set({ status: 'repo_removed', removedFrom: epic.status, removedReason: reason }).where(eq(epics.id, epic.id)).run();
      db.insert(epicEvents).values({ epicId: epic.id, at: now, type: 'repo_removed', data: { from: epic.status, reason } }).run();
    }
    for (const epic of db.select().from(epics).where(and(eq(epics.status, 'repo_removed'), inArray(epics.repo, configured))).all()) {
      db.update(epics).set({ status: epic.removedFrom!, removedFrom: null, removedReason: null }).where(eq(epics.id, epic.id)).run();
      db.insert(epicEvents).values({ epicId: epic.id, at: now, type: 'repo_restored', data: { to: epic.removedFrom } }).run();
    }
    for (const { id } of db.select({ id: epics.id }).from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) {
      const epic = fresh(id);
      const last = db.select().from(executions).where(eq(executions.epicId, id)).orderBy(desc(sql`rowid`)).get();
      log.info('recovering epic', { repo: epic.repo, epic: epic.issue, stage: epic.stage, lastStatus: last?.status });
      if (!last) {
        // Stopped between claiming the launch and inserting the execution: no agent ever ran, so launching is not a blind restart.
        db.update(epics).set({ stage: null }).where(eq(epics.id, id)).run();
        await launch(fresh(id), 'ship');
      } else if (last.status === 'interrupted') {
        // The agent may have written its result just before the cut: import it once instead of launching again.
        if (parseCallerResult(readResult(last), expectedOf(epic, last)).ok) {
          db.update(executions).set({ status: 'finished' }).where(eq(executions.executionId, last.executionId)).run();
          await settle({ ...last, status: 'finished' });
        } else await execute(epic, last.stage, last);
      } else if (last.status === 'finished' && epic.stage && db.select().from(callerResults).where(eq(callerResults.executionId, last.executionId)).get()) {
        await launch(epic, epic.stage); // imported, but the next stage was never launched
      }
    }
    // SQLite is the authority: labels that differ on GitHub are put back.
    for (const epic of db.select().from(epics).where(and(inArray(epics.status, ['running', 'needs_human', 'ready_for_test']), inArray(epics.repo, configured))).orderBy(asc(epics.id)).all()) {
      const { labels } = await github.getIssue(epic.repo, epic.issue);
      const wanted = labelOf(epic.status);
      if (ownedLabels.some((l) => labels.includes(l) !== (l === wanted)) || (epic.status === 'running' && labels.includes(readyLabel))) await applyLabels(epic);
    }
    recovered = true;
  }

  // A failed read keeps the last known values and the poll goes on: progress is only for show. A rejected profile is not "only for show".
  async function refreshProgress(repo: string) {
    try {
      progress.set(repo, new Map((await github.listOpenEpics(repo)).map(({ issue, slices }) => [issue, slices])));
    } catch (e) {
      if (e instanceof AuthError) throw e;
      log.error('slice progress read failed, keeping the last values', e);
    }
  }

  // Returns the wait until the next poll.
  async function poll(): Promise<number> {
    if (stopping) return pollIntervalMs;
    try {
      // Fetch every repo before writing: a failure on any of them leaves the queue untouched.
      const found: { repo: string; issue: number }[] = [];
      await ensureLabels();
      if (!recovered) await recover();
      for (const { name: repo } of repos) {
        for (const { issue } of await github.listReadyEpics(repo)) found.push({ repo, issue });
        await refreshProgress(repo);
      }
      suspended = null; // listing worked: the orchestrator's profile is back, the cycle goes on
      const queuedAt = clock.now();
      db.transaction((tx) => {
        for (const epic of found) {
          tx.insert(epics).values({ ...epic, queuedAt }).onConflictDoNothing().run();
          // Carrier never leaves `ready` on a stopped epic, so finding it on a `needs_human` one is a person saying "go on":
          // it starts again from ship, which reuses the epic's worktree and PR.
          tx.update(epics).set(restart(queuedAt)).where(and(eq(epics.repo, epic.repo), eq(epics.issue, epic.issue), eq(epics.status, 'needs_human'))).run();
        }
      });
      await stopEnded();
      await settlePending();
      await retryPending();
      await reconcileLabels();
      await fillSlots();
      error = null;
      return pollIntervalMs;
    } catch (e) {
      log.error('poll failed', e);
      failed(e);
      return Math.max(pollIntervalMs, (e instanceof GitHubUnavailable && e.retryAfterMs) || 0);
    }
  }

  // One poll at a time: a poll asked for by a person while the timer's is running is that one.
  const runPoll = async () => {
    if (polling) return;
    polling = true;
    try {
      schedule(await poll());
    } finally {
      polling = false;
    }
  };
  const schedule = (ms: number) => {
    if (stopping) return;
    nextPollAt = clock.now() + ms;
    cancel = clock.after(ms, runPoll);
  };

  return {
    async start() {
      stopRetention = startRetention(db, root, clock, sessionDirs);
      // GitHub down: retried every cycle until it works.
      for (const step of [ensureLabels, recover]) {
        try {
          await step();
        } catch (err) {
          log.error('startup step failed', err);
          failed(err);
        }
      }
      schedule(pollIntervalMs);
    },
    stop() {
      cancel?.();
      stopRetention?.();
    },
    /**
     * Ctrl+C: stops polling and reserving, then stops every active run without waiting for its stage.
     * Their executions end `interrupted` (session ids already saved), the epics stay `running` and
     * nothing is written to GitHub. Resolves once those states are in SQLite.
     */
    async shutdown() {
      stopping = true;
      cancel?.();
      stopRetention?.();
      await Promise.all([...active.values()].map((run) => run.stop()));
      while (inflight.size > 0) await Promise.all([...inflight]);
    },
    /** Resolves when no execution is being followed any more. */
    async idle() {
      while (inflight.size > 0) await Promise.all([...inflight]);
    },
    /** Polls now instead of waiting for the interval, then goes on from there. */
    pollNow() {
      if (stopping) return Promise.resolve();
      cancel?.();
      return runPoll();
    },
    /** Stops (or resumes) taking epics from the queue; running epics are not touched. Resuming fills the free slots at once. */
    setPaused(value: boolean) {
      paused = value;
      return value ? Promise.resolve() : this.pollNow();
    },
    get paused() {
      return paused;
    },
    /** When the next poll is due (ms since epoch); null before the first one is scheduled. */
    get nextPollAt() {
      return nextPollAt;
    },
    /** Last GitHub failure, null once a poll succeeds. */
    get error() {
      return error;
    },
    /** Slices closed out of the total on the last good read; null until the first one or when GitHub sends none. */
    slices: (repo: string, issue: number) => progress.get(repo)?.get(issue) ?? null,
    /** Queued epics, oldest first. */
    queue: () => db.select().from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all(),
  };
}
