import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { and, asc, eq, inArray, isNull } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { AgentExit, AgentRunner, AgentTask } from '../execution/agent-runner.ts';
import { parseCallerResult } from '../execution/caller-result.ts';
import { importResult } from '../execution/import-result.ts';
import type { Workspaces } from '../execution/workspaces.ts';
import { callerResults } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { executions, type executionStates } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';
import { GitHubUnavailable, needsHumanLabel, ownedLabels, readyForTestLabel, readyLabel, runningLabel, type GitHub } from './github.ts';
import { reserve } from './reserve.ts';

export type EngineOptions = {
  db: Db;
  github: GitHub;
  clock: Clock;
  repos: EffectiveRepoConfig[];
  pollIntervalMs: number;
  maxConcurrentEpics: number;
  maxExecutionHours: number | 'unlimited';
  runner: AgentRunner;
  workspaces: Workspaces;
  /** Shared root: execution results go under `orchestrator/results/`. */
  root: string;
};

type Epic = typeof epics.$inferSelect;
type Execution = typeof executions.$inferSelect;

// Technical end of the process; whether the epic moves on depends on its result (retries and timeouts: later slices).
const executionStatus: Record<AgentExit, (typeof executionStates)[number]> = {
  ok: 'finished',
  failed: 'failed',
  timed_out: 'timed_out',
  stopped: 'interrupted',
  auth_failed: 'failed',
  session_unavailable: 'failed',
};

export function createEngine({ db, github, clock, repos, pollIntervalMs, maxConcurrentEpics, maxExecutionHours, runner, workspaces, root }: EngineOptions) {
  let error: GitHubUnavailable | null = null;
  let cancel: (() => void) | null = null;
  const labelledRepos = new Set<string>();

  // Creates the owned labels a repo lacks; never touches existing ones nor creates `ready`.
  async function ensureLabels() {
    for (const { name } of repos) {
      if (labelledRepos.has(name)) continue;
      const existing = await github.listLabels(name);
      for (const label of ownedLabels) if (!existing.includes(label)) await github.createLabel(name, label);
      labelledRepos.add(name);
    }
  }

  // Mirrors the epic's status on its issue.
  const applyLabels = async ({ id, repo, issue, status }: Epic) => {
    const change =
      status === 'needs_human'
        ? { add: [needsHumanLabel], remove: [runningLabel] }
        : status === 'ready_for_test'
          ? { add: [readyForTestLabel], remove: [runningLabel] }
          : { add: [runningLabel], remove: [readyLabel] };
    await github.setLabels(repo, issue, change);
    db.update(epics).set({ labelPending: false }).where(eq(epics.id, id)).run();
  };

  const fresh = (id: number) => db.select().from(epics).where(eq(epics.id, id)).get()!;

  // The epic leaves `running` for `needs_human`; the label follows (labelPending) and the slot is free.
  const toNeedsHuman = (writer: Pick<Db, 'update'>, id: number, reason: string) =>
    writer.update(epics).set({ status: 'needs_human', needsHumanReason: reason, finishedAt: clock.now(), labelPending: true }).where(eq(epics.id, id)).run();

  // Mirrors the label, then launches the author unless the epic already has one.
  const begin = async (epic: Epic) => {
    await applyLabels(epic);
    if (epic.status === 'running' && epic.stage === null) await launch(epic, 'ship');
  };

  // Launches the author (ship) or the reviewer (review) for the epic's current stage.
  async function launch(epic: Epic, stage: 'ship' | 'review') {
    if (stage === 'ship') {
      // Claim the launch first: concurrent reconciles (a result freeing a slot, the poll) never start a second author.
      const claimed = db.update(epics).set({ stage: 'ship' }).where(and(eq(epics.id, epic.id), isNull(epics.stage))).returning().get();
      if (!claimed) return;
    }
    let workspace: string;
    try {
      workspace = stage === 'ship' ? await workspaces.prepareAuthor(epic.repo, epic.issue) : await workspaces.prepareReviewer(epic.repo, epic.issue, epic.prNumber!);
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
      ...(stage === 'ship' ? epic.config!.agents.author : epic.config!.agents.reviewer),
      workspace,
      resultPath,
      timeoutMs: maxExecutionHours === 'unlimited' ? null : maxExecutionHours * 3_600_000,
      context:
        stage === 'ship'
          ? { previousSummaries: [] }
          : { pr: { number: epic.prNumber!, headSha: epic.prHeadSha! }, round: epic.round!, previousSummaries: previousSummaries(epic.id) },
    };
    db.insert(executions).values({ executionId, epicId: epic.id, stage, resultPath, startedAt: clock.now() }).run();
    const run = runner.run(task);
    run.onSession((sessionId) => db.update(executions).set({ sessionId }).where(eq(executions.executionId, executionId)).run());
    track(
      run.done.then(async ({ exit, sessionId }) => {
        db.update(executions)
          .set({ status: executionStatus[exit], finishedAt: clock.now(), ...(sessionId && { sessionId }) })
          .where(eq(executions.executionId, executionId))
          .run();
        if (exit === 'ok') await settle(db.select().from(executions).where(eq(executions.executionId, executionId)).get()!);
      }),
    );
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

  // Imports the result of a finished execution and moves the epic. Safe to repeat: the import is idempotent.
  async function settle(execution: Execution) {
    const epic = fresh(execution.epicId);
    const expected = { executionId: execution.executionId, repo: epic.repo, epic: epic.issue, stage: execution.stage };
    let raw: string | null = null;
    try {
      raw = readFileSync(execution.resultPath, 'utf8');
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== 'ENOENT') throw e; // a missing file is reported by the parser
    }
    const parsed = parseCallerResult(raw, expected);
    if (!parsed.ok) {
      db.update(executions).set({ status: 'invalid_result' }).where(eq(executions.executionId, execution.executionId)).run();
      return;
    }
    const problem = parsed.result.outcome === 'needs_human' ? null : await prProblem(epic, parsed.result.pr, execution.stage);
    const imported = importResult(db, raw, expected, (tx, result) => {
      const update = (set: Partial<Epic>) => tx.update(epics).set(set).where(eq(epics.id, epic.id)).run();
      if (result.outcome === 'needs_human') toNeedsHuman(tx, epic.id, result.reason);
      else if (problem) toNeedsHuman(tx, epic.id, problem);
      else if (execution.stage === 'ship') update({ stage: 'review', round: 1, prNumber: result.pr.number, prHeadSha: result.pr.headSha });
      // The round stays: the fix turn answers it, and the next review (a later slice) numbers the following one.
      else if (result.outcome === 'changes_requested') update({ stage: 'fix' });
      else update({ status: 'ready_for_test', reviewedSha: result.pr.headSha, verification: result.verification, finishedAt: clock.now(), labelPending: true });
    });
    const next = fresh(epic.id);
    if (!('duplicate' in imported) && execution.stage === 'ship' && next.status === 'running' && next.stage === 'review') await launch(next, 'review');
    await freeSlot();
  }

  // A result arrived: reflect it on the issue and give the freed slot to the next epic without waiting for the poll.
  async function freeSlot() {
    await reconcileLabels();
    await fillSlots();
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
      .where(and(inArray(epics.status, ['running', 'needs_human', 'ready_for_test']), eq(epics.labelPending, true)))
      .orderBy(asc(epics.id))
      .all();
    for (const epic of pending) await begin(epic);
  }

  // Starts the oldest queued epics until the concurrency limit or the queue is exhausted.
  async function fillSlots() {
    for (;;) {
      const epic = reserve(db, { maxConcurrent: maxConcurrentEpics, now: clock.now(), repos });
      if (!epic) return;
      const cancelWith = (cancelReason: string) =>
        db.update(epics).set({ status: 'cancelled', cancelReason, finishedAt: clock.now() }).where(eq(epics.id, epic.id)).run();
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

  // Returns the wait until the next poll.
  async function poll(): Promise<number> {
    try {
      // Fetch every repo before writing: a failure on any of them leaves the queue untouched.
      const found: { repo: string; issue: number }[] = [];
      await ensureLabels();
      for (const { name: repo } of repos) {
        for (const { issue } of await github.listReadyEpics(repo)) found.push({ repo, issue });
      }
      const queuedAt = clock.now();
      db.transaction((tx) => {
        for (const epic of found) tx.insert(epics).values({ ...epic, queuedAt }).onConflictDoNothing().run();
      });
      await settlePending();
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
    cancel = clock.after(ms, async () => schedule(await poll()));
  };

  return {
    async start() {
      try {
        await ensureLabels();
      } catch (e) {
        if (!(e instanceof GitHubUnavailable)) throw e;
        error = e; // retried every cycle until it works
      }
      schedule(pollIntervalMs);
    },
    stop: () => cancel?.(),
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
