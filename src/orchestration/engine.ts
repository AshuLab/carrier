import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { and, asc, desc, eq, inArray, isNotNull, isNull, sql } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { AgentExit, AgentRun, AgentRunner, AgentTask } from '../execution/agent-runner.ts';
import { parseCallerResult, type CallerResult } from '../execution/caller-result.ts';
import { importResult } from '../execution/import-result.ts';
import type { Workspaces } from '../execution/workspaces.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { epicEvents } from '../storage/events.ts';
import { executions, type executionStates } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';
import { endOf } from './final-pr.ts';
import { GitHubUnavailable, needsHumanLabel, ownedLabels, readyForTestLabel, readyLabel, runningLabel, type GitHub } from './github.ts';
import { reserve } from './reserve.ts';
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
};

type Epic = typeof epics.$inferSelect;
type Execution = typeof executions.$inferSelect;

// Technical end of the process; whether the epic moves on depends on its result (retries and timeouts: later slices).
const sessionLost = 'la sesión del agente no está disponible';

const executionStatus: Record<AgentExit, (typeof executionStates)[number]> = {
  ok: 'finished',
  failed: 'failed',
  timed_out: 'timed_out',
  stopped: 'interrupted',
  auth_failed: 'failed',
  session_unavailable: 'failed',
};

export function createEngine({ db, github, clock, repos, pollIntervalMs, maxConcurrentEpics, maxExecutionHours, maxExecutionRetries, maxReviews, runner, workspaces, root }: EngineOptions) {
  let error: GitHubUnavailable | null = null;
  let cancel: (() => void) | null = null;
  const labelledRepos = new Set<string>();
  // Runs of this process still going, to stop them when the epic ends from outside.
  const active = new Map<string, AgentRun>();
  // Set by shutdown(): from then on nothing polls, reserves, launches or writes to GitHub.
  let stopping = false;

  // Creates the owned labels a repo lacks; never touches existing ones nor creates `ready`.
  async function ensureLabels() {
    for (const { name } of repos) {
      if (stopping) return;
      if (labelledRepos.has(name)) continue;
      const existing = await github.listLabels(name);
      for (const label of ownedLabels) if (!existing.includes(label)) await github.createLabel(name, label);
      labelledRepos.add(name);
    }
  }

  // The one owned label each status shows; merged and cancelled (stopped from outside) show none.
  const labelOf = (status: Epic['status']) =>
    ({ running: runningLabel, needs_human: needsHumanLabel, ready_for_test: readyForTestLabel })[status as 'running'] as string | undefined;

  // Mirrors the epic's status on its issue: its label, none of the other owned ones, and no `ready` while running.
  const applyLabels = async ({ id, repo, issue, status }: Epic) => {
    if (stopping) return; // labelPending stays true: the next run reflects it
    const wanted = labelOf(status);
    await github.setLabels(repo, issue, {
      add: wanted ? [wanted] : [],
      remove: [...ownedLabels.filter((l) => l !== wanted), ...(status === 'running' ? [readyLabel] : [])],
    });
    db.update(epics).set({ labelPending: false }).where(eq(epics.id, id)).run();
  };

  const fresh = (id: number) => db.select().from(epics).where(eq(epics.id, id)).get()!;

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
      const claimed = db.update(epics).set({ stage: 'ship' }).where(and(eq(epics.id, epic.id), isNull(epics.stage))).returning().get();
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
      workspace = reviewing ? await workspaces.prepareReviewer(epic.repo, epic.issue, epic.prNumber!) : await workspaces.prepareAuthor(epic.repo, epic.issue);
    } catch (e) {
      toNeedsHuman(db, epic.id, `no se pudo preparar el workspace: ${e instanceof Error ? e.message : String(e)}`);
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
        ...(stage === 'fix' && { blockers: latestBlockers(epic.id) }),
        ...(retryOf && { verifyStateFirst: true }),
        ...(pr && { pr }),
        ...(epic.round && { round: epic.round }),
      },
    };
    if (stopping) return;
    db.insert(executions).values({ executionId, epicId: epic.id, stage, resultPath, startedAt: clock.now() }).run();
    const run = runner.run(task);
    active.set(executionId, run);
    run.onSession((sessionId) => db.update(executions).set({ sessionId }).where(eq(executions.executionId, executionId)).run());
    track(
      run.done.then(async ({ exit, sessionId }) => {
        active.delete(executionId);
        db.update(executions)
          .set({
            status: executionStatus[exit],
            finishedAt: clock.now(),
            ...(sessionId && { sessionId }),
            ...(exit === 'failed' && { error: 'el proceso del agente terminó con error' }),
            ...(exit === 'session_unavailable' && { error: sessionLost }),
          })
          .where(eq(executions.executionId, executionId))
          .run();
        if (exit === 'ok') await settle(db.select().from(executions).where(eq(executions.executionId, executionId)).get()!);
        else if (exit === 'failed' || exit === 'session_unavailable') await retry(epic.id);
        else if (exit === 'timed_out') {
          // Session and workspace stay as they are; a person decides how to go on.
          toNeedsHuman(db, epic.id, `la ejecución de ${stage} superó el límite de tiempo`);
          await freeSlot();
        }
      }),
    );
  }

  // Relaunches the stage whose last execution failed technically, until the retries run out.
  const retrying = new Set<number>();
  async function retry(epicId: number) {
    if (stopping || retrying.has(epicId)) return;
    retrying.add(epicId);
    try {
      const epic = fresh(epicId);
      const [last, ...earlier] = failureStreak(db, epicId);
      if (epic.status !== 'running' || !last) return;
      if (earlier.length >= maxExecutionRetries) {
        toNeedsHuman(db, epicId, `se agotaron los reintentos de ${last.stage} (${earlier.length + 1} intentos): ${last.error}`);
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

  // The blockers of the latest review: what the fix turn has to answer.
  const latestBlockers = (epicId: number) => {
    const last = db
      .select({ result: callerResults.result })
      .from(callerResults)
      .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
      .where(and(eq(executions.epicId, epicId), eq(executions.stage, 'review'), eq(callerResults.outcome, 'changes_requested')))
      .orderBy(desc(sql`executions.rowid`))
      .get();
    return last ? (JSON.parse(last.result) as Extract<CallerResult, { outcome: 'changes_requested' }>).blockers : [];
  };

  const inflight = new Set<Promise<void>>();
  // GitHub being down is expected (the next poll retries); anything else is a bug and surfaces.
  const track = (work: Promise<void>) => {
    const tracked: Promise<void> = work
      .catch((e) => {
        if (!(e instanceof GitHubUnavailable)) throw e;
        error = e;
      })
      .finally(() => inflight.delete(tracked));
    inflight.add(tracked);
  };

  // Does the final PR the caller reported hold up against GitHub? Returns why not, or null.
  async function prProblem({ repo, issue }: Epic, pr: { number: number; headSha: string }, stage: Execution['stage']) {
    const found = await github.getPullRequest(repo, pr.number);
    if (!found) return `el PR #${pr.number} no existe`;
    if (found.state !== 'open') return `el PR #${pr.number} no está abierto`;
    if (!new RegExp(`\\bcloses #${issue}(?!\\d)`, 'i').test(found.body)) return `el PR #${pr.number} no referencia la épica (falta "Closes #${issue}")`;
    if (found.headSha !== pr.headSha) {
      return stage === 'review' ? 'el head cambió durante la revisión' : `el head del PR #${pr.number} es ${found.headSha}, no ${pr.headSha}`;
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
    if (stopping) return; // stays `finished` without a result: the next run imports it
    const epic = fresh(execution.epicId);
    if (epic.status === 'merged' || epic.status === 'cancelled') return; // ended from outside: nothing new moves
    const expected = expectedOf(epic, execution);
    const raw = readResult(execution);
    const parsed = parseCallerResult(raw, expected);
    if (!parsed.ok) {
      db.update(executions).set({ status: 'invalid_result', error: parsed.message }).where(eq(executions.executionId, execution.executionId)).run();
      return retry(epic.id);
    }
    const problem = parsed.result.outcome === 'needs_human' ? null : await prProblem(epic, parsed.result.pr, execution.stage);
    const imported = importResult(db, raw, expected, (tx, result) => {
      const update = (set: Partial<Epic>) => tx.update(epics).set(set).where(eq(epics.id, epic.id)).run();
      if (result.outcome === 'needs_human') toNeedsHuman(tx, epic.id, result.reason);
      else if (problem) toNeedsHuman(tx, epic.id, problem);
      else if (execution.stage === 'ship') update({ stage: 'review', round: 1, prNumber: result.pr.number, prHeadSha: result.pr.headSha });
      else if (execution.stage === 'fix') update({ stage: 'review', round: (epic.round ?? 0) + 1, prHeadSha: result.pr.headSha });
      // The round stays: the fix turn answers it, and the next review numbers the following one.
      else if (result.outcome === 'changes_requested') {
        if ((epic.round ?? 0) >= maxReviews) toNeedsHuman(tx, epic.id, `límite de revisiones: la ronda ${epic.round} de ${maxReviews} sigue con cambios pedidos`);
        else update({ stage: 'fix' });
      }
      else update({ status: 'ready_for_test', reviewedSha: result.pr.headSha, verification: result.verification, finishedAt: clock.now(), labelPending: true });
    });
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
      if (stopping) return;
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
    for (const id of await runner.listActive()) if (!active.has(id)) await runner.stop(id);
    for (const { executionId } of db.select().from(executions).where(eq(executions.status, 'running')).all()) {
      if (active.has(executionId)) continue;
      db.update(executions).set({ status: 'interrupted', finishedAt: clock.now() }).where(eq(executions.executionId, executionId)).run();
    }
    for (const { id } of db.select({ id: epics.id }).from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) {
      const epic = fresh(id);
      const last = db.select().from(executions).where(eq(executions.epicId, id)).orderBy(desc(sql`rowid`)).get();
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
    for (const epic of db.select().from(epics).where(inArray(epics.status, ['running', 'needs_human', 'ready_for_test'])).orderBy(asc(epics.id)).all()) {
      const { labels } = await github.getIssue(epic.repo, epic.issue);
      const wanted = labelOf(epic.status);
      if (ownedLabels.some((l) => labels.includes(l) !== (l === wanted)) || (epic.status === 'running' && labels.includes(readyLabel))) await applyLabels(epic);
    }
    recovered = true;
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
      }
      const queuedAt = clock.now();
      db.transaction((tx) => {
        for (const epic of found) tx.insert(epics).values({ ...epic, queuedAt }).onConflictDoNothing().run();
      });
      await stopEnded();
      await settlePending();
      await retryPending();
      await reconcileLabels();
      await fillSlots();
      error = null;
      return pollIntervalMs;
    } catch (e) {
      if (!(e instanceof GitHubUnavailable)) throw e;
      error = e;
      return Math.max(pollIntervalMs, e.retryAfterMs ?? 0);
    }
  }

  const schedule = (ms: number) => {
    if (stopping) return;
    cancel = clock.after(ms, async () => schedule(await poll()));
  };

  return {
    async start() {
      // GitHub down: retried every cycle until it works.
      for (const step of [ensureLabels, recover]) {
        try {
          await step();
        } catch (e) {
          if (!(e instanceof GitHubUnavailable)) throw e;
          error = e;
        }
      }
      schedule(pollIntervalMs);
    },
    stop: () => cancel?.(),
    /**
     * Ctrl+C: stops polling and reserving, then stops every active run without waiting for its stage.
     * Their executions end `interrupted` (session ids already saved), the epics stay `running` and
     * nothing is written to GitHub. Resolves once those states are in SQLite.
     */
    async shutdown() {
      stopping = true;
      cancel?.();
      await Promise.all([...active.values()].map((run) => run.stop()));
      while (inflight.size > 0) await Promise.all([...inflight]);
    },
    /** Resolves when no execution is being followed any more. */
    async idle() {
      while (inflight.size > 0) await Promise.all([...inflight]);
    },
    /** Last GitHub failure, null once a poll succeeds. */
    get error() {
      return error;
    },
    /** Queued epics, oldest first. */
    queue: () => db.select().from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all(),
  };
}
