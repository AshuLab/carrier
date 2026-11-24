import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { and, asc, desc, eq, inArray, isNotNull, isNull, lte, ne, notInArray, sql } from 'drizzle-orm';
import type { EnginePlaces } from '../config/places.ts';
import { runtimeOf } from '../config/providers.ts';
import { failoverStepsFor, type Agent, type EffectiveRepoConfig } from '../config/resolve.ts';
import { failoverTriggers, matchesFailoverTrigger } from '../config/schema.ts';
import { savedSkills } from '../config/skills.ts';
import type { HarnessName } from '../harnesses/names.ts';
import type { Skills } from '../harnesses/skills.ts';
import type { AgentExit, AgentFailure, AgentRun, AgentRunner, AgentTask } from '../execution/agent-runner.ts';
import { failureDetail } from '../execution/failure.ts';
import { parseCallerResult } from '../execution/caller-result.ts';
import { importResult } from '../execution/import-result.ts';
import type { Workspaces } from '../execution/workspaces.ts';
import { epicReviewThreads } from '../storage/epic-review-threads.ts';
import { epicSlices } from '../storage/epic-slices.ts';
import { callerResults, supersededOutcome } from '../storage/caller-results.ts';
import type { Db } from '../storage/db.ts';
import { epicEvents, executionEvents, recordEvents } from '../storage/events.ts';
import { executions, slotOf, type executionStates, type Slot } from '../storage/executions.ts';
import { executionOutput, taskContext } from '../logging/logger.ts';
import { epics, type cancelKinds, type needsHumanKinds } from '../storage/schema.ts';
import type { Clock } from './clock.ts';
import { latestBlockers, latestObservations } from './blockers.ts';
import { changesSlices } from './changes-slices.ts';
import { RecoverRefused } from './recover-refused.ts';
import { ResumeRefused } from './resume-refused.ts';
import { endOf } from './final-pr.ts';
import { AuthError, GitHubRejected, GitHubUnavailable, hasLabel, isNotFound, labelStyles, type GitHub, type LabelStyle, type Labels, type PullRequestState, type Slices } from './github.ts';
import { queueOrder, queuePosition, reserve } from './reserve.ts';
import { startRetention, type SessionDirs } from './retention.ts';
import { earliestRetryDue, failingBesides, failureStreak, isOfAttempt, lastBySlot, retryWait } from './retry.ts';
import { agentOfSlot, failoverRoleOf, withAgentOfSlot } from './slots.ts';
import type { QuotaReader } from './quota.ts';
import { isBack, resumeAtOf } from './resume-at.ts';

export type EngineSettings = {
  pollIntervalMs: number;
  maxConcurrentEpics: number;
  maxExecutionHours: number | 'unlimited';
  /** Minutes a process may write nothing before it is killed and retried; absent: no watchdog. */
  idleMinutes?: number;
  /** With it on, an epic that stops in `usage_limit` keeps the time its window comes back as `resumeAt`. */
  autoResume: boolean;
  /** A window that comes back later than this many hours from the stop is not scheduled. */
  autoResumeMaxHours: number;
  /** Technical failures retried per stage after the first attempt. */
  maxExecutionRetries: number;
  /** Reviews of the final PR before the epic goes to a person; fix turns do not count. */
  maxReviews: number;
  /** Reviews of the lead reviewer's exchange with the author before the epic goes to a person (`lead_limit`); the engine does not read it yet. */
  maxLeadRounds: number;
  /** The labels by role: `ready` queues an epic (Carrier takes it off when the epic starts and puts it back to restart a stopped one), `running`, `readyForTest` and `needsHuman` are the ones Carrier writes. */
  labels: Labels;
};

export type EngineOptions = {
  db: Db;
  github: GitHub;
  clock: Clock;
  /** The repos the engine watches now, read where each is used: a reload changes what this returns. */
  repos: () => EffectiveRepoConfig[];
  /** The settings the engine runs on now, read where each is used: a reload changes what this returns. */
  settings: () => EngineSettings;
  runner: AgentRunner;
  workspaces: Workspaces;
  /** Where the quota of an account is read, to know when an exhausted window comes back. */
  quota: QuotaReader;
  /** The engine's places: execution results go under `<state>/results/`, their output under `<logs>/executions/`. */
  places: Pick<EnginePlaces, 'state' | 'logs'>;
  /** Where the CLIs keep sessions, for the 30-day cleanup; the CLIs' own folders by default. */
  sessionDirs?: SessionDirs;
  /** Whether the configuration declares the profile now. */
  profileDeclared: (name: string) => boolean;
  /** Whether the harness of a role finds a skill, asked before a role starts. */
  skills: Skills;
};

const log = createScopedLogger('engine');
const activityEveryMs = 10_000;
const resumeWaitMs = 30_000;
const resumeTickMs = 1_000;
// Slices read outside the poll: at most one read per epic in each window, and a timer as a net for what no event signals.
const sliceWindowMs = 10_000;
const sliceTimerMs = 60_000;
const liveStatuses: Epic['status'][] = ['running', 'needs_human', 'ready_for_test'];
/** What one poll read about the epics: the state of each final PR (with its number: the epic's PR may be another one by the time it is used), and the issues each repo listed as open. */
type SeenThisPoll = { prState: Map<number, { number: number; state: PullRequestState }>; openIssues: Map<string, Set<number>> };

export type RepoCheck = { at: number; ok: boolean; error: string | null };

type Epic = typeof epics.$inferSelect;
type CancelKind = (typeof cancelKinds)[number];
type Execution = typeof executions.$inferSelect;

// Technical end of the process; whether the epic moves on depends on its result (retries and timeouts: later slices).
const sessionLost = 'the agent session is not available';

const noExit = { exitCode: null, signal: null, hostFreeMemMb: null, hostLoad: null };

const failureColumns = (f: AgentFailure | undefined) =>
  f && { failureKind: f.kind, failureDetail: f.detail, exitCode: f.exitCode, signal: f.signal, hostFreeMemMb: f.hostFreeMemMb, hostLoad: f.hostLoad };

const executionStatus: Record<AgentExit, (typeof executionStates)[number]> = {
  ok: 'finished',
  failed: 'failed',
  timed_out: 'timed_out',
  stopped: 'interrupted',
  auth_failed: 'failed',
  session_unavailable: 'failed',
};

export function createEngine({ db, github, clock, repos, settings, runner, workspaces, quota, places, sessionDirs, profileDeclared, skills }: EngineOptions) {
  let error: GitHubUnavailable | AuthError | null = null;
  let nextPollAt: number | null = null;
  let paused = false; // intake only: nothing new is reserved, what is running goes on
  let polling: Promise<void> | null = null;
  // A reload came in while a poll was listing the old repos: one more poll runs when that one ends.
  let pollAgain = false;
  // The orchestrator's profile failed: no GitHub call is made until the poll's probe succeeds. Never another profile.
  let suspended: AuthError | null = null;
  let cancel: (() => void) | null = null;
  let stopRetention: (() => void) | null = null;
  // By repo and the names Carrier creates there (its status labels, and the stage and reason ones named): a reload that renames one makes the repo lack a label again.
  const labelledRepos = new Set<string>();
  // Slice progress GitHub reported on the last good read, by repo and issue; not stored, so it is empty until the first poll after a start.
  const progress = new Map<string, Map<number, Slices | null>>();
  // The last poll of each repo, in memory only: when, whether it worked and why not. Empty until the first poll after a start.
  const checks = new Map<string, RepoCheck>();
  // Runs of this process still going, to stop them when the epic ends from outside.
  const active = new Map<string, AgentRun>();
  // Set by shutdown(): from then on nothing polls, reserves, launches or writes to GitHub.
  let stopping = false;

  // Creates the owned labels a repo lacks, with their colour and description; never touches existing ones nor creates `ready` (Solve's).
  // Runs right before the first label write on a repo; the repo is remembered only once every label exists, so a failure is retried by the next write.
  async function ensureLabels(repo: string) {
    const key = [repo, ...ownedLabels()].join('\n');
    if (labelledRepos.has(key)) return;
    const existing = await github.listLabels(repo);
    for (const [name, style] of owned()) if (!hasLabel(existing, name)) await github.createLabel(repo, name, style);
    labelledRepos.add(key);
  }

  // Every label Carrier may write now, with the style it is created in: the three of the status, then those of the stages and of the stops, when named.
  const owned = (): [string, LabelStyle][] => {
    const { running, readyForTest, needsHuman, stages, reasons } = settings().labels;
    return [
      [running, labelStyles.running],
      [readyForTest, labelStyles.readyForTest],
      [needsHuman, labelStyles.needsHuman],
      ...Object.values(stages ?? {}).map((name): [string, LabelStyle] => [name, labelStyles.stage]),
      ...Object.values(reasons ?? {}).map((name): [string, LabelStyle] => [name, labelStyles.reason]),
    ];
  };
  const ownedLabels = () => owned().map(([name]) => name);
  // Whether a stage change has to reach the issue: only when some stage has a label.
  const stageLabelled = () => Object.keys(settings().labels.stages ?? {}).length > 0;

  // The owned labels an epic shows: its status's, and the one of its stage while it runs or of its kind of stop while it waits, when those are named.
  const wantedLabels = ({ status, stage, needsHumanKind }: Pick<Epic, 'status' | 'stage' | 'needsHumanKind'>): string[] => {
    const { running, readyForTest, needsHuman, stages, reasons } = settings().labels;
    const stageLabel = stage && stages?.[stage];
    const reasonLabel = needsHumanKind && reasons?.[needsHumanKind];
    if (status === 'running') return stageLabel ? [running, stageLabel] : [running];
    if (status === 'needs_human') return reasonLabel ? [needsHuman, reasonLabel] : [needsHuman];
    if (status === 'ready_for_test') return [readyForTest];
    return []; // merged and cancelled (stopped from outside) show none
  };

  // An epic a person sent back to the queue: nothing of the previous attempt is kept, the executions stay as history.
  const restart = (queuedAt: number) => ({
    status: 'queued' as const, queuedAt, startedAt: null, config: null, labelPending: false, stage: null, stageStartedAt: null, workspace: null,
    lastActivityAt: null, lastError: null, round: null, prNumber: null, prHeadSha: null, pr: null, reviewedSha: null, verification: null, observationsPassAt: null,
    needsHumanReason: null, needsHumanKind: null, finishedAt: null, authorOption: null, reviewerOption: null, recoveries: 0, autoResumes: 0, headRepeats: 0, unansweredObservations: null, unansweredReason: null, retryAt: null, resumeStage: null, roundLimit: null, resumeAt: null,
  });
  // The rounds an epic may have: what a resume granted it, else the live setting (a changed `maxReviews` applies at the epic's next review).
  // The cancels that lost no work: `ready` coming back before the epic had an execution puts it in the queue again.
  const requeueable: (CancelKind | null)[] = ['ready_removed', 'issue_closed'];
  const roundCap = (epic: Epic) => epic.roundLimit ?? settings().maxReviews;
  // An epic a person resumed at `review` or `fix` (resume from a stage): it takes the same way through the queue, but keeps its round, pull request,
  // worktree and the rest of where it stood; `resumeStage` tells `begin` where to start.
  const requeueKeeping = (queuedAt: number) => ({
    status: 'queued' as const, queuedAt, startedAt: null, config: null, labelPending: false, stage: null, stageStartedAt: null,
    lastActivityAt: null, lastError: null, needsHumanReason: null, needsHumanKind: null, finishedAt: null, authorOption: null, reviewerOption: null, recoveries: 0, autoResumes: 0, headRepeats: 0, unansweredObservations: null, unansweredReason: null, retryAt: null, resumeAt: null,
  });

  // The labels a poll read of each issue (`repo#issue`), kept up to date by Carrier's own writes and emptied when the poll ends:
  // a status change removes only what the issue has, and outside a poll (a request) it reads the issue once.
  const polledLabels = new Map<string, string[]>();
  const configured = (repo: string) => repos().some((r) => r.name === repo);

  // Mirrors the epic's status on its issue: its labels, none of the other owned ones, and no `ready` in any status (a queued epic is not written here).
  // Only the labels the issue has are removed, one request each.
  const applyLabels = async (epic: Epic) => {
    const { id, repo, issue, status } = epic;
    if (stopping || suspended || parked(id) || !configured(repo)) return; // labelPending stays true: the next run reflects it
    await ensureLabels(repo);
    if (parked(id) || !configured(repo)) return; // the repo left the configuration while its labels were read: GitHub is not touched for it
    const wanted = wantedLabels(epic);
    const key = `${repo}#${issue}`;
    const present = polledLabels.get(key) ?? (await github.getIssue(repo, issue)).labels;
    if (parked(id) || !configured(repo)) return;
    const remove = [...ownedLabels().filter((l) => !wanted.includes(l)), settings().labels.ready].filter((l) => hasLabel(present, l));
    await github.setLabels(repo, issue, { add: wanted, remove });
    if (polledLabels.has(key)) polledLabels.set(key, [...present.filter((l) => !hasLabel(remove, l)), ...wanted.filter((l) => !hasLabel(present, l))]);
    // A stage or a stop that changed while the labels were written still has its own to write: only the state just written clears the mark.
    const now = fresh(id);
    if (now.status === status && now.stage === epic.stage && now.needsHumanKind === epic.needsHumanKind) db.update(epics).set({ labelPending: false }).where(eq(epics.id, id)).run();
  };

  const fresh = (id: number) => db.select().from(epics).where(eq(epics.id, id)).get()!;
  // The epic ended from outside or its repo left the configuration: what an `await` in its path comes back to must not write over that.
  const outside = (id: number) => ['merged', 'cancelled', 'repo_removed'].includes(fresh(id).status);
  const parked = (id: number) => fresh(id).status === 'repo_removed';
  const stillRunning = (id: number) => fresh(id).status === 'running';
  // Parking an epic ends the continuations it had: one that read the epoch before an `await` and finds it changed was parked, and maybe restored,
  // meanwhile, and the restore already took the epic from where it was. Going on would be a second launch of the same stage.
  const epochs = new Map<number, number>();
  const epochOf = (id: number) => epochs.get(id) ?? 0;
  const unchanged = (id: number, epoch: number) => stillRunning(id) && epochOf(id) === epoch;
  // Epics whose `ship` claimed the stage and has not yet inserted its execution (the workspace is being prepared): a recovery that finds no execution
  // yet must not take such a launch for a cut one and start a second author.
  const launching = new Set<number>();

  // GitHub refusing one repo (not found, no access) is that repo's check failing, not the cycle's: the others go on, the repo shows why, and
  // nothing is reserved for it until the next cycle. What is about everyone (the profile, GitHub down) and anything else still goes up.
  const rejected = new Set<string>();
  function refuse(repo: string, e: GitHubRejected) {
    log.error('GitHub refused a repo', e, { repo });
    rejected.add(repo);
    checks.set(repo, { at: clock.now(), ok: false, error: e.message });
  }
  // GitHub unavailable for one repo (a timeout, a 5xx, a network error) when the poll reads it is the same: the repo is skipped for the cycle with its reason,
  // the others go on, and the longest wait GitHub asked for among those failures is the wait before the next cycle. Only a poll fills this: it is empty outside one.
  // A rate limit is the account's, not a repo's: it is never skipped, it ends the poll (`endsPoll`).
  const skipped = new Set<string>();
  let longestWait = 0;
  const endsPoll = (e: unknown) => e instanceof AuthError || (e instanceof GitHubUnavailable && e.kind === 'rate_limited');
  function skip(repo: string, e: GitHubUnavailable) {
    log.warn('GitHub unavailable for a repo, skipping it this cycle', { repo, error: e.message });
    skipped.add(repo);
    longestWait = Math.max(longestWait, e.retryAfterMs ?? 0);
    checks.set(repo, { at: clock.now(), ok: false, error: e.message });
  }
  async function forRepo(repo: string, step: () => Promise<unknown>) {
    if (skipped.has(repo)) return false;
    try {
      await step();
      return true;
    } catch (e) {
      if (!(e instanceof GitHubRejected)) throw e;
      refuse(repo, e);
      return false;
    }
  }

  // GitHub being down is expected (the next poll retries), and so is a failing orchestrator profile; anything else is a bug and surfaces.
  const failed = (e: unknown) => {
    if (e instanceof AuthError) suspended = e;
    else if (!(e instanceof GitHubUnavailable)) throw e;
    error = e;
  };

  // The epic leaves `running` for `needs_human`; the label follows (labelPending) and the slot is free.
  const toNeedsHuman = (writer: Pick<Db, 'update'>, id: number, kind: (typeof needsHumanKinds)[number], reason: string) =>
    writer.update(epics).set({ status: 'needs_human', needsHumanKind: kind, needsHumanReason: reason, finishedAt: clock.now(), labelPending: true, retryAt: null }).where(eq(epics.id, id)).run();

  // What the database says when it cannot be read or written: about the whole engine, never about one epic.
  const isDatabaseError = (e: unknown) => [e, (e as Error | undefined)?.cause].some((x) => typeof (x as NodeJS.ErrnoException | undefined)?.code === 'string' && (x as NodeJS.ErrnoException).code!.startsWith('SQLITE_'));

  // An unexpected error on one epic's path (settling a result, a retry, a failover): the epic stops for a person with the error as one redacted line,
  // the execution it left `running` ends failed, and the others go on. Safe to repeat.
  async function stopEpic(epicId: number, e: unknown) {
    const reason = failureDetail(e instanceof Error ? e.message : String(e)) || 'unknown error';
    for (const { executionId } of db.select().from(executions).where(and(eq(executions.epicId, epicId), eq(executions.status, 'running'))).all()) {
      const run = active.get(executionId);
      if (run) await run.stop(); // its own end is recorded when it settles
      else db.update(executions).set({ status: 'failed', finishedAt: clock.now(), error: reason }).where(eq(executions.executionId, executionId)).run();
    }
    if (stillRunning(epicId)) toNeedsHuman(db, epicId, 'engine_error', reason);
    await freeSlot().catch((err) => log.error('freeing the slot of a stopped epic failed', err));
  }

  // One pending item of the poll (a finished execution, a retry): an unexpected error in it stops that epic and the poll goes on; what is about
  // everyone (the profile, GitHub down, the database) goes up and stops the poll, which logs it with its message.
  async function isolating(epicId: number, repo: string, step: () => Promise<void>) {
    try {
      await forRepo(repo, step);
    } catch (e) {
      if (e instanceof AuthError || e instanceof GitHubUnavailable || isDatabaseError(e)) throw e;
      log.error('pending work failed', e, { epicId });
      await stopEpic(epicId, e);
    }
  }

  // Mirrors the label, then launches the author unless the epic already has one; an epic restarted on options chosen takes them first.
  // `epoch` is the epic's when the caller read the row: a park and a restore in between made it another launch's to make.
  const begin = async (epic: Epic, epoch = epochOf(epic.id)) => {
    if (stopping) return;
    await applyLabels(epic);
    if (epic.status !== 'running' || epic.stage !== null || !unchanged(epic.id, epoch)) return;
    const restarted = restarts.get(epic.id);
    restarts.delete(epic.id);
    const start = restarted ? onChosen(epic.id, declaredOnly(epic, restarted)) : epic;
    if (start.resumeStage) await launchResumed(start, start.resumeStage, epoch);
    else await launch(start, 'ship', epoch);
  };

  // The stage a resume asked for, claimed like `launch` claims ship: the claim also clears the ask, and the stage runs with the epic's round, pull request,
  // worktree and session as they were. The new attempt (`startedAt`, set by the reserve) has its retries back.
  async function launchResumed(epic: Epic, stage: 'review' | 'fix', epoch: number) {
    if (stopping || !unchanged(epic.id, epoch)) return;
    const claimed = db.update(epics).set({ stage, stageStartedAt: clock.now(), recoveries: 0, resumeStage: null, ...(stageLabelled() && { labelPending: true }) }).where(and(eq(epics.id, epic.id), isNull(epics.stage), eq(epics.status, 'running'))).returning().get();
    if (!claimed) return;
    launching.add(epic.id);
    try {
      await execute(claimed, stage);
    } finally {
      launching.delete(epic.id);
    }
  }

  // The options a person picked when restarting a stopped epic, by epic id, until the poll that requeues it reserves it again.
  // ponytail: in memory, an engine restart in between falls back to the roles as saved; persist it if that bites.
  const restarts = new Map<number, Partial<Record<'author' | 'reviewer', string>>>();
  const declaredOnly = ({ id, config }: Epic, chosen: Partial<Record<'author' | 'reviewer', string>>) =>
    Object.fromEntries(
      Object.entries(chosen).filter(([role, name]) => {
        const declared = Object.hasOwn((config?.providers ?? config?.options) ?? {}, name);
        if (!declared) log.warn('the option chosen at the restart is not declared any more, the role starts on its default', { epicId: id, role, option: name });
        return declared;
      }),
    );

  // Puts each role on the option chosen at the restart (a role left out keeps its saved one), records them, and returns the epic as saved.
  function onChosen(id: number, chosen: Partial<Record<'author' | 'reviewer', string>>) {
    const { config } = fresh(id);
    const roleOn = (role: 'author' | 'reviewer') => {
      const name = chosen[role];
      return name === undefined ? config!.agents[role] : onOption(config!, role === 'author' ? null : 'reviewer', name);
    };
    const agents = { author: roleOn('author'), reviewer: roleOn('reviewer') };
    return db
      .update(epics)
      .set({ config: { ...config!, agents }, authorOption: agents.author.option ?? null, reviewerOption: agents.reviewer.option ?? null })
      .where(eq(epics.id, id))
      .returning()
      .get();
  }

  // Running epics with no stage: the start failed (GitHub was down while the author's session was rebuilt). Each starts now, on the options already saved.
  async function resumeStarts() {
    if (stopping || suspended) return;
    const pending = db.select().from(epics).where(and(eq(epics.status, 'running'), isNull(epics.stage))).orderBy(asc(epics.id)).all();
    const epochsRead = pending.map((epic) => epochOf(epic.id));
    for (const [i, epic] of pending.entries()) await forRepo(epic.repo, () => (epic.resumeStage ? launchResumed(epic, epic.resumeStage, epochsRead[i]!) : launch(epic, 'ship', epochsRead[i])));
  }

  const defaultHarnessModels: Record<HarnessName, string> = {
    claude: 'sonnet',
    codex: 'gpt-5.3-codex',
    agy: 'gemini-3.8-flash-low',
  };

  // The triggers that move a role: none while it has no steps.
  const failoverTriggersOf = (failover: EffectiveRepoConfig['failover'], slot: Slot | null) => (failoverStepsFor(failover, failoverRoleOf(slot)).length > 0 ? (failover?.triggers ?? failoverTriggers) : []);

  // The role of the epic's saved config pointed at another of its saved options or providers: same profile and persona.
  // `stepModel` is the model a failover step settled on; without it, the account's, then the role's own on the same harness, else the harness's default.
  // `stepEffort` is the step's own effort; without it the role's.
  const onOption = (config: NonNullable<Epic['config']>, slot: Slot | null, name: string, stepModel?: string, stepEffort?: Agent['effort']): Agent => {
    const roleAgent = agentOfSlot(config, slot);
    if (!roleAgent) throw new Error(`the epic's saved configuration has no agent for ${slot ?? 'the author'}`);
    const { profile, persona, model } = roleAgent;
    const effort = stepEffort ?? roleAgent.effort;
    const provider = (config.providers ?? config.options)?.[name];
    if (!provider) throw new Error(`provider "${name}" is not declared in config.providers`);
    const modelStr: string = stepModel ?? provider.model ?? (provider.harness === roleAgent.harness ? model : defaultHarnessModels[provider.harness] ?? model);
    return {
      profile,
      model: modelStr,
      harness: provider.harness,
      ...(provider.provider && { provider: provider.provider }),
      ...(provider.configDir && { configDir: provider.configDir }),
      ...runtimeOf(provider),
      ...(persona && { persona }),
      ...(effort && { effort }),
      option: name,
      providerName: name,
    };
  };

  // With failover on, the role that ran out moves to the first option of `order` that has not run out in this epic and its stage runs
  // again as a rebuilt session, no retry spent. `why` is what to add to the stop reason when it could not move.
  async function failOver(epicId: number, stage: AgentTask['stage'], failedExecution: Execution): Promise<{ relaunched: true } | { relaunched: false; why: string }> {
    const epic = fresh(epicId);
    const epoch = epochOf(epicId);
    const { config } = epic;
    const slot = slotOf(failedExecution);
    const steps = failoverStepsFor(config?.failover, failoverRoleOf(slot));
    if (!config || steps.length === 0) return { relaunched: false, why: '' };
    const triggers = config.failover?.triggers ?? failoverTriggers;
    if (!matchesFailoverTrigger(triggers, failedExecution.failureKind, failedExecution.failureDetail)) return { relaunched: false, why: '' };
    const failoverKinds = [
      ...(triggers.includes('usage_limit') ? (['usage_limit'] as const) : []),
      ...((triggers.includes('service_down') || triggers.includes('rate_limit')) ? (['api_error', 'spawn_error'] as const) : []),
    ];
    // A step is tried by the provider and the model it ran on: the slot's own and every step that failed.
    // Only this attempt's and this slot's: a resume gives back the options that ran out in the one before, and another reviewer's options are not this one's.
    const ranOut = db.select({ option: executions.option, model: executions.model, startedAt: executions.startedAt, stage: executions.stage, reviewer: executions.reviewer }).from(executions).where(and(eq(executions.epicId, epicId), inArray(executions.failureKind, failoverKinds))).orderBy(asc(sql`rowid`)).all().filter((run) => isOfAttempt(run, epic) && slotOf(run) === slot);
    const modelOf = ({ provider, model }: { provider: string; model?: string }) => {
      const account = (config.providers ?? config.options)?.[provider];
      return model ?? account?.model ?? (account && defaultHarnessModels[account.harness]);
    };
    const hasRunOut = (step: { provider: string; model?: string }) => ranOut.some((run) => run.option === step.provider && run.model === modelOf(step));
    const next = steps.find((step) => !hasRunOut(step));
    if (next === undefined) return { relaunched: false, why: `; no step left in failover, ran out: ${[...new Set(ranOut.map((run) => `${run.option ?? '?'} ${run.model ?? '?'}`))].join(', ')}` };
    if (stopping || epic.status !== 'running') return { relaunched: true };
    // Read only; GitHub being down is not a reason to stop: the agent verifies the state first anyway.
    const found = await github.findPullRequest(epic.repo, epic.issue).catch((e) => (failed(e), null));
    if (!unchanged(epicId, epoch)) return { relaunched: true }; // parked while GitHub was asked: nothing is written for it, a restore takes it from here
    db.transaction((tx) => {
      const from = agentOfSlot(config, slot)!;
      tx.update(epics).set({ config: withAgentOfSlot(config, slot, onOption(config, slot, next.provider, modelOf(next), next.effort)), ...(slot === null ? { authorOption: next.provider } : slot === 'reviewer' && { reviewerOption: next.provider }) }).where(eq(epics.id, epicId)).run();
      tx.insert(epicEvents).values({ epicId, at: clock.now(), type: 'option_switched', data: { role: slot ?? 'author', from: from.option ?? null, fromModel: from.model, to: next.provider, toModel: modelOf(next), stage } }).run();
    });
    await execute(fresh(epicId), stage, failedExecution, { pr: found && { number: found.number, headSha: found.headSha } });
    return { relaunched: true };
  }

  // A resume that keeps the epic's stage needs its pull request open and its head to be the stored one.
  // A resume at review looks at whatever the head is (ADR 0047): it passes `onMoved`, which is told the head found instead of refusing.
  async function pullRequestRefusal(epic: Epic, onMoved?: (headSha: string) => void): Promise<'no pull request' | 'pull request not open' | 'pull request head changed' | undefined> {
    if (epic.prNumber === null) return 'no pull request';
    const found = await github.getPullRequest(epic.repo, epic.prNumber);
    if (found?.state !== 'open') return 'pull request not open';
    if (found.headSha === epic.prHeadSha) return;
    if (!onMoved) return 'pull request head changed';
    onMoved(found.headSha);
  }

  // What the probe of each option's account says now: the option of this execution and the ones that ran out earlier in this attempt, in its slot.
  // An option that is a local server, or whose probe does not answer, says nothing.
  async function probeRanOut(epic: Epic, execution: Execution) {
    const earlier = db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.failureKind, 'usage_limit'))).all().filter((run) => isOfAttempt(run, epic) && slotOf(run) === slotOf(execution));
    const runs = new Map([execution, ...earlier].map((run) => [`${run.option}\n${run.model}`, run]));
    const ranOut = await Promise.all([...runs.values()].map(async (run) => {
      if (run.provider !== null || !(run.harness === 'claude' || run.harness === 'codex' || run.harness === 'agy')) return undefined;
      const command = run.option ? epic.config?.providers?.[run.option]?.command : undefined;
      try {
        return { run, model: run.model, snapshot: await quota({ provider: run.harness, ...(run.configDir && { configDir: run.configDir }), ...(command && { command }) }) };
      } catch (e) {
        log.error('the quota check failed', e, { epicId: epic.id });
        return undefined;
      }
    }));
    return ranOut.filter((r) => r !== undefined);
  }

  // The automatic resumes in a row an epic gets (ADR 0049).
  const maxAutoResumes = 3;

  // An epic stopped on its quota whose `resumeAt` has passed: the provider is asked again, without its cache, and only when an option it ran out of shows its
  // window below 100% the epic resumes, from the stage where it stopped and on that option. Otherwise it waits for the next poll, and nothing is guessed.
  // The resume is the one of a person (the queue, a slot), made by the engine; with the engine paused, or `autoResume` off now, nothing resumes.
  async function wakeUp() {
    if (stopping || suspended || paused || !settings().autoResume) return;
    const configured = repos().map((r) => r.name);
    const due = db.select().from(epics).where(and(eq(epics.status, 'needs_human'), eq(epics.needsHumanKind, 'usage_limit'), isNotNull(epics.resumeAt), lte(epics.resumeAt, clock.now()), inArray(epics.repo, configured))).orderBy(asc(epics.id)).all();
    for (const epic of due) await isolating(epic.id, epic.repo, () => wakeOne(epic));
  }

  async function wakeOne(epic: Epic) {
    const stage = epic.stage === 'review' || epic.stage === 'fix' ? epic.stage : null;
    if (epic.autoResumes >= maxAutoResumes) return;
    // Like a resume from a stage: the pull request must be open with the head the epic stored, or the stage would work on something else.
    if (stage) {
      const refusal = await pullRequestRefusal(epic);
      if (refusal) {
        // Not what the stage would work on, and nothing in the epic changes that by itself: it stops waiting (no read of GitHub at every poll, no promise in the
        // panel) and a person's resume decides. The reason keeps the way out and says why it will not go on.
        log.warn('the epic does not wake up', { epicId: epic.id, refusal });
        db.update(epics).set({ resumeAt: null, needsHumanReason: epic.needsHumanReason?.replace(/ · resumes by itself at \S+/, ` · it will not resume by itself: ${refusal}`) }).where(and(eq(epics.id, epic.id), eq(epics.status, 'needs_human'), eq(epics.resumeAt, epic.resumeAt!))).run();
        return;
      }
    }
    // Each slot is asked on its own last execution: the ones of the stage's slots that failed, else the epic's newest (a stop with no failure of its own to read).
    const failed = lastBySlot(db, epic).filter((last) => (slotOf(last) !== null) === (epic.stage === 'review') && last.failureKind !== null);
    const newest = db.select().from(executions).where(eq(executions.epicId, epic.id)).orderBy(desc(sql`rowid`)).get();
    let back: Awaited<ReturnType<typeof probeRanOut>>[number] | undefined;
    for (const last of failed.length > 0 ? failed : newest ? [newest] : []) {
      back = (await probeRanOut(epic, last)).find(isBack);
      if (back) break;
    }
    if (!back) return;
    const woken = slotOf(back.run);
    // What a person's resume puts: a queued epic whose issue lost `ready` is cancelled when it is reserved.
    await github.setLabels(epic.repo, epic.issue, { add: [settings().labels.ready], remove: [] });
    const woke = db.transaction((tx) => {
      const queuedAt = queuePosition(tx, clock.now()); // after the epics already waiting, and in this write so none enters between
      const moved = tx.update(epics)
        .set({ ...(stage ? { ...requeueKeeping(queuedAt), resumeStage: stage } : restart(queuedAt)), autoResumes: epic.autoResumes + 1 })
        .where(and(eq(epics.id, epic.id), eq(epics.status, 'needs_human'), eq(epics.resumeAt, epic.resumeAt!))) // a person resumed it, or it ended, while the probe answered
        .returning().get();
      if (moved) tx.insert(epicEvents).values({ epicId: epic.id, at: queuedAt, type: 'auto_resumed', data: { stage: epic.stage, option: back.run.option ?? null, resumeAt: epic.resumeAt, count: epic.autoResumes + 1 } }).run();
      return moved;
    });
    // The option that came back, always: the requeue freezes the repo's default again, so the one the role holds now (where failover left it) is not kept by itself.
    if (woke && back.run.option && (woken === null || woken === 'reviewer')) restarts.set(epic.id, { [woken === null ? 'author' : 'reviewer']: back.run.option }); // the extra reviewers and the lead are put back on their option by the slices that run them
  }

  // A stage ended on its usage limit: another option of the failover list, or the epic stops for a person. The reason says how to go on
  // (the panel cuts long lines, so the way out comes before the agent's own detail, which carries the reset time).
  // With `autoResume` on it also says when the window comes back, and the epic keeps that time as `resumeAt` when it is within `autoResumeMaxHours`.
  async function onUsageLimit(epicId: number, execution: Execution) {
    const moved = await failOver(epicId, execution.stage, execution);
    if (moved.relaunched || !stillRunning(epicId)) return;
    const { autoResume, autoResumeMaxHours } = settings(); // read once: a reload applies to the next stop
    const spent = fresh(epicId).autoResumes >= maxAutoResumes;
    // A server error says nothing about the quota: no window to probe, no promise to resume by itself.
    const serverError = execution.failureKind === 'api_error' && /\bHTTP 5\d\d\b/.test(execution.failureDetail ?? '');
    const back = autoResume && !spent && !serverError ? resumeAtOf(await probeRanOut(fresh(epicId), execution)) : undefined;
    if (!stillRunning(epicId)) return; // the probe took time: the epic may have ended or been parked meanwhile
    const { repo, issue } = fresh(epicId);
    const role = slotOf(execution) ?? 'author';
    const detail = execution.failureDetail ? ` · ${execution.failureDetail}` : '';
    const scheduled = back !== undefined && back - clock.now() <= autoResumeMaxHours * 3_600_000;
    const when = back === undefined ? '' : new Date(back).toISOString();
    const wake = !autoResume || serverError ? ''
      : spent ? ` · it already resumed by itself ${maxAutoResumes} times in a row: it will not again`
      : back === undefined ? ' · it will not resume by itself: the provider did not say when the window comes back'
      : scheduled ? ` · resumes by itself at ${when}`
      : ` · the window comes back at ${when}, more than ${autoResumeMaxHours} h away: it will not resume by itself`;
    db.transaction((tx) => {
      const option = execution.option ?? execution.harness;
      const what = serverError
        ? `the provider answered the ${execution.stage} execution on option ${option} with a server error, not a usage limit · wait and resume the epic, or carrier restart ${repo}#${issue} --${role} <option>`
        : `the ${execution.stage} execution ran out of usage on option ${option} · carrier restart ${repo}#${issue} --${role} <option>`;
      toNeedsHuman(tx, epicId, 'usage_limit', `${what}${wake}${detail}${moved.why}`);
      if (scheduled) {
        tx.update(epics).set({ resumeAt: back }).where(eq(epics.id, epicId)).run();
        tx.insert(epicEvents).values({ epicId, at: clock.now(), type: 'auto_resume_scheduled', data: { resumeAt: back } }).run();
      }
    });
    await freeSlot();
  }

  // Launches the author (ship, fix) or the reviewer (review) for the epic's current stage.
  async function launch(epic: Epic, stage: AgentTask['stage'], epoch = epochOf(epic.id)) {
    if (stopping) return;
    let rebuild: Parameters<typeof execute>[3];
    if (stage === 'ship') {
      // An author on another option than the one that wrote the epic's session cannot continue it: a new session, rebuilt like a lost one.
      // Read before the claim: if GitHub is down this throws with the stage still free (startChosen puts the wait back).
      const before = lastAuthor(epic.id);
      const optionNow = epic.config!.agents.author.option ?? null;
      if (before && (before.option ?? null) !== optionNow) {
        const pr = await github.findPullRequest(epic.repo, epic.issue);
        rebuild = { pr: pr && { number: pr.number, headSha: pr.headSha } };
      }
      if (!unchanged(epic.id, epoch)) return; // parked (and maybe restored) since the caller read the epic: the restore launches it
      // Claim the launch first: concurrent reconciles (a result freeing a slot, the poll) never start a second author.
      const claimed = db.update(epics).set({ stage: 'ship', stageStartedAt: clock.now(), recoveries: 0, ...(stageLabelled() && { labelPending: true }) }).where(and(eq(epics.id, epic.id), isNull(epics.stage), eq(epics.status, 'running'))).returning().get();
      if (!claimed) return;
      launching.add(epic.id);
      if (rebuild) db.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: 'session_rebuilt', data: { stage, from: before!.option, to: optionNow, pr: rebuild.pr } }).run();
    }
    try {
      await execute(epic, stage, undefined, rebuild);
    } finally {
      launching.delete(epic.id);
    }
  }

  // The reason to stop for the first skill the person named and the role's harness does not find, none when every one is found, default or cannot be told.
  async function missingSkill(epic: Epic, slot: Slot | null, folder: string): Promise<string | undefined> {
    const { ship, review, fix } = savedSkills(epic.config);
    const agent = agentOfSlot(epic.config!, slot)!;
    const role = slot ?? 'author';
    const invoked = slot === null ? [['ship', ship], ['fix', fix]] as const : [['review.review', review.review], ['review.publish', review.publish]] as const;
    for (const [key, skill] of invoked) {
      if (skill === null || !skill.named) continue;
      if ((await skills.has(agent.harness, agent.configDir, folder, skill.name)) !== 'absent') continue;
      const account = agent.configDir ?? `the default folder of ${agent.harness}`;
      // The places each reader looks in (`src/harnesses/skills.ts`): Antigravity has no account folder, and Codex reads its plugin cache instead of listing plugins.
      const where = {
        claude: `in the account folder (${account}), the repo (${folder}) and the plugins it lists`,
        codex: `in the account folder (${account}), ~/.agents/skills, the repo (${folder}), /etc/codex/skills and its plugin cache`,
        agy: `in the repo (${folder}), ~/.gemini and the plugins it lists`,
      }[agent.harness];
      return `the skill ${skill.name} (skills.${key}) is not installed for the ${role}: ${agent.harness} looked where it finds skills, ${where} · install it, or name another in skills.${key}, then resume the epic`;
    }
    return undefined;
  }

  // Starts an execution of the stage; `retryOf` is the failed or interrupted one it replaces: same session, verify
  // the real state first. `rebuild` (the session is gone) starts a new session instead, with the PR as GitHub has it now.
  async function execute(epic: Epic, stage: AgentTask['stage'], retryOf?: Execution, rebuild?: { pr: { number: number; headSha: string } | null }) {
    const reviewing = stage === 'review';
    // A retry stays in the slot of the execution it replaces; a review no one gave a slot is the mandatory reviewer's.
    const slot: Slot | null = retryOf ? slotOf(retryOf) : reviewing ? 'reviewer' : null;
    const epoch = epochOf(epic.id);
    // A fix on another option than the one that wrote the author's session cannot continue it (the wake-up went on the option that came back, a resume switched
    // `--author`): a new session, rebuilt like a lost one, on the pull request the epic stored.
    const before = stage === 'fix' && !retryOf?.sessionId && !rebuild ? lastAuthor(epic.id) : undefined; // a retry that has a session of its own continues it
    const optionNow = epic.config!.agents.author.option ?? null;
    const switched = before !== undefined && (before.option ?? null) !== optionNow;
    if (switched) rebuild = { pr: null };
    const resumeSession = rebuild ? undefined : (retryOf?.sessionId ?? (stage === 'fix' ? authorSession(epic.id) : stage === 'ship' && !retryOf ? sameOptionSession(epic) : undefined));
    let pr = rebuild?.pr ?? (epic.prNumber ? { number: epic.prNumber, headSha: epic.prHeadSha! } : undefined);
    let workspace: string;
    let reviewedCommit: string | undefined; // the commit the reviewer's checkout is at: the head it is given
    try {
      if (stage === 'fix') {
        // Where `ship` left the epic's worktree: a session resumed anywhere else would act in another cwd.
        if (!epic.workspace) throw new Error('the epic has no saved worktree');
        if (!(await workspaces.exists(epic.workspace))) throw new Error(`the saved workspace ${epic.workspace} does not exist`);
        workspace = epic.workspace;
      } else if (reviewing) {
        const checkout = await workspaces.prepareReviewer(epic.repo, epic.issue, epic.prNumber!);
        workspace = checkout.path;
        reviewedCommit = checkout.commit;
        pr = { number: epic.prNumber!, headSha: reviewedCommit };
      } else workspace = await workspaces.prepareAuthor(epic.repo, epic.issue);
    } catch (e) {
      log.error('could not prepare the workspace', e, { repo: epic.repo, epic: epic.issue, stage });
      if (!unchanged(epic.id, epoch)) return; // parked while the workspace was prepared: it keeps where it was
      toNeedsHuman(db, epic.id, 'workspace', `could not prepare the workspace: ${e instanceof Error ? e.message : String(e)}`);
      return applyLabels(fresh(epic.id));
    }
    // A skill the person named that the role's harness does not find stops the epic here, before an execution exists or a run is spent. Every launch, resume,
    // wake-up, failover and `restart --author|--reviewer` comes through here; Solve's defaults and an answer that cannot tell never stop it.
    const missing = await missingSkill(epic, slot, workspace);
    if (missing) {
      if (!unchanged(epic.id, epoch)) return;
      toNeedsHuman(db, epic.id, 'skill_missing', missing);
      return applyLabels(fresh(epic.id));
    }
    const executionId = randomUUID();
    const resultPath = join(places.state, 'results', `${executionId}.json`);
    const { maxExecutionHours: hoursLimit, idleMinutes } = settings(); // read once: the run keeps the timeout and the idle limit it launches with
    // A fix right after a review that completed is the observations pass; after one that asked for changes, it answers the blockers.
    const observations = stage === 'fix' ? latestObservations(db, epic.id) : null;
    const agent = agentOfSlot(epic.config!, slot);
    if (!agent) throw new Error(`the epic's saved configuration has no agent for ${slot}`);
    const task: AgentTask = {
      executionId,
      repo: epic.repo,
      epic: epic.issue,
      stage,
      ...(slot !== null && { reviewer: slot }),
      ...agent,
      sharedIdentity: epic.config!.sharedIdentity === true,
      skills: savedSkills(epic.config),
      workspace,
      resultPath,
      timeoutMs: hoursLimit === 'unlimited' ? null : hoursLimit * 3_600_000,
      ...(idleMinutes !== undefined && { idleMs: idleMinutes * 60_000 }),
      ...(resumeSession && { resumeSession }),
      context: {
        previousSummaries: reviewing || rebuild ? previousSummaries(epic.id) : [],
        ...(observations ? { observations } : (stage === 'fix' || (reviewing && (epic.round ?? 0) > 1)) && { blockers: latestBlockers(db, epic.id) }),
        ...(retryOf && { verifyStateFirst: true }),
        ...(pr && { pr }),
        ...(epic.round && { round: epic.round }),
      },
    };
    if (stopping || !unchanged(epic.id, epoch)) return; // the repo may have left the configuration (and come back) while the workspace was prepared
    if (switched) db.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: 'session_rebuilt', data: { stage, from: before!.option, to: optionNow, pr: pr ?? null } }).run();
    db.insert(executions)
      .values({ executionId, epicId: epic.id, stage, reviewer: slot, harness: task.harness, model: task.model, provider: task.provider ?? null, option: task.option ?? null, configDir: task.configDir ?? null, workspace, round: epic.round, headSha: reviewedCommit ?? null, resultPath, startedAt: clock.now() })
      .run();
    const context = taskContext({ repo: epic.repo, epic: epic.issue, executionId, stage, reviewer: slot, round: epic.round });
    log.info('execution started', context);
    const run = runner.run(task);
    active.set(executionId, run);
    const output = executionOutput(places.logs, executionId);
    // The panel's "last activity": a SQLite write at most every 10 s, not one per chunk.
    let activityAt: number | null = null;
    run.onOutput((stream, chunk) => {
      output.write(stream, chunk);
      const now = clock.now();
      if (activityAt !== null && now - activityAt < activityEveryMs) return;
      activityAt = now;
      db.update(epics).set({ lastActivityAt: now }).where(eq(epics.id, epic.id)).run();
    });
    const sliceCalls = new Set<string>(); // calls of this execution that started and have not ended; gone with it
    // A failed insert must not break the run: the log still has everything, and the replay script can fill the rows.
    run.onEvent((events) => {
      try {
        recordEvents(db, executionId, events, clock.now());
      } catch (e) {
        log.error('could not store the events of a chunk', e, context);
      }
      // A command that changes the slices is only a signal to look, and GitHub shows the change once it has ended, error or not.
      for (const { kind, callId, arg } of events) {
        if (callId === undefined) continue;
        if (kind === 'tool_start' && arg !== undefined && changesSlices(arg)) sliceCalls.add(callId);
        else if (kind === 'tool_end' && sliceCalls.delete(callId)) readSlicesSoon(epic.id, epic.repo, epic.issue);
      }
    });
    run.onSession((sessionId) => db.update(executions).set({ sessionId }).where(eq(executions.executionId, executionId)).run());
    track(
      run.done.then(async ({ exit, sessionId, failure: processFailure, usage }) => {
        active.delete(executionId);
        output.flush();
        (exit === 'ok' ? log.info : log.warn)('execution ended', { ...context, exit });
        // ADR 0050: an execution of the profile that ends with no authentication signal clears the memory of a first one (a run we stopped says nothing).
        if (exit !== 'auth_failed' && exit !== 'stopped') authSignals.delete(task.profile);
        // The first signal of a profile is a technical failure like any other; the second stops the profile. A profile a reload removed is neither.
        const firstSignal = exit === 'auth_failed' && profileDeclared(task.profile) && !authSignals.has(task.profile);
        if (firstSignal) authSignals.add(task.profile);
        const triggers = failoverTriggersOf(epic.config?.failover, slot);
        const isFailoverFailure = exit === 'failed' && processFailure?.kind !== undefined && matchesFailoverTrigger(triggers, processFailure.kind, processFailure.detail);
        const outOfCredits = exit === 'failed' && processFailure?.kind === 'usage_limit';
        // Like a timeout, failover leaves no error on the execution: it is not a retryable failure and ends the streak.
        const failure = (outOfCredits || isFailoverFailure) ? undefined : { failed: `the agent process ended with an error (${processFailure?.kind ?? 'unknown'}${processFailure?.detail ? `: ${processFailure.detail}` : ''})`, auth_failed: authError(task.profile, processFailure?.detail), session_unavailable: sessionLost }[exit as 'failed'];
        // The ends with their own handling carry no failure from the runner: their kind follows from the exit.
        const endFailure: Partial<Record<AgentExit, Pick<AgentFailure, 'kind' | 'detail'>>> = {
          failed: { kind: 'unknown', detail: '' },
          auth_failed: { kind: 'auth', detail: `profile ${task.profile}` },
          session_unavailable: { kind: 'session_lost', detail: sessionLost },
          timed_out: { kind: 'timeout', detail: `exceeded ${task.timeoutMs! / 3_600_000} h` },
        };
        db.update(executions)
          .set({ status: executionStatus[exit], finishedAt: clock.now(), ...(sessionId && { sessionId }), ...(usage && { usage }), ...(failure && { error: failure }), ...failureColumns(processFailure ?? (endFailure[exit] && { ...noExit, ...endFailure[exit] })) })
          .where(eq(executions.executionId, executionId))
          .run();
        // The counters go back to 0 when an execution ends, unless another slot's failure is still being recovered: that slot's count is not this one's to reset.
        const reset = failingBesides(db, epic, slot) ? {} : { recoveries: 0, ...(!outOfCredits && { autoResumes: 0 }) };
        if (failure || Object.keys(reset).length > 0) db.update(epics).set({ ...reset, ...(failure && { lastError: failure }) }).where(eq(epics.id, epic.id)).run();
        if (exit === 'ok') await settle(db.select().from(executions).where(eq(executions.executionId, executionId)).get()!);
        else if (isFailoverFailure || outOfCredits) {
          // Retrying the same option only burns the retries.
          await onUsageLimit(epic.id, db.select().from(executions).where(eq(executions.executionId, executionId)).get()!);
        }
        else if (exit === 'failed' || exit === 'session_unavailable' || firstSignal) {
          // The wait is a due time read from the slot's rows, never a sleep: `retry` starts it once due, from its timer or from the poll after a restart.
          // The epic shows the earliest due time of its slots.
          showDue(epic.id);
          await retry(epic.id, slot);
        }
        else if (exit === 'auth_failed') {
          if (profileDeclared(task.profile)) await stopProfile(task.profile, processFailure?.detail);
          else {
            // A reload removed the profile: every run that names it fails the same way and says nothing about the others, so only this epic
            // stops, naming it. The runs already going keep the token they started with.
            if (stillRunning(epic.id)) toNeedsHuman(db, epic.id, 'auth', `profile ${task.profile} was removed from the configuration: put it back, then restart the epic`);
            await freeSlot();
          }
        } else if (exit === 'timed_out') {
          // Session and workspace stay as they are; a person decides how to go on.
          if (stillRunning(epic.id)) toNeedsHuman(db, epic.id, 'timeout', timeoutReason(stage, endFailure.timed_out!.detail));
          await freeSlot();
        }
      }),
      epic.id,
    );
  }

  // `detail` is what the execution stored, `exceeded N h`: the limit as it was when the run started.
  const timeoutReason = (stage: string, detail: string | null) =>
    `the ${stage} execution exceeded the time limit${detail?.startsWith('exceeded ') ? ` of ${detail.slice('exceeded '.length)}` : ''} (limits.maxExecutionHours) · session and worktree are kept: raise the limit or set it to "unlimited", then resume the epic`;

  // The profiles that sent one authentication signal and have had no execution end without one since. Not saved: a restart forgets it and costs one more signal.
  const authSignals = new Set<string>();
  const authError = (profile: string, detail?: string) => `authentication error for profile ${profile}${detail ? `: ${failureDetail(detail)}` : ''}`;

  // The profile's authentication signal repeated: the running epics that use it stop for a person, with their runs, and the others go on.
  // `detail` is the message of the error, redacted like any other reason. The profile is never swapped for another one.
  async function stopProfile(profile: string, detail?: string) {
    for (const epic of db.select().from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) {
      const { author, reviewer } = epic.config!.agents;
      if (author.profile !== profile && reviewer.profile !== profile) continue;
      toNeedsHuman(db, epic.id, 'auth', authError(profile, detail));
      const running = db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).all();
      await Promise.all(running.map(({ executionId }) => active.get(executionId)?.stop()));
    }
    // Only now, with every run of the profile stopped: a signal that ends one while it is stopped would otherwise count as a first one and be remembered again.
    authSignals.delete(profile); // the person's fix is a new start: the next signal is a first one again
    await freeSlot();
  }

  // Relaunches the slot's stage whose last execution failed technically, until the retries run out. Each slot has its own retry in flight and its own timer.
  const retrying = new Set<string>();
  // The timers of the retries that wait for their due time; the engine's stop cancels them, and the poll finds what a restart lost.
  const retryTimers = new Map<string, () => void>();
  const retryKey = (epicId: number, slot: Slot | null) => `${epicId}:${slot ?? 'author'}`;
  const retryingEpic = (epicId: number) => [...retrying].some((key) => key.startsWith(`${epicId}:`));
  // The due time an epic shows is the earliest of the slots that wait for one, leaving out the one that is launching.
  const showDue = (epicId: number, launching?: Slot | null) => {
    const epic = fresh(epicId);
    db.update(epics).set({ retryAt: earliestRetryDue(db, epic, launching === undefined ? [] : [launching]) }).where(eq(epics.id, epicId)).run();
  };
  async function retry(epicId: number, slot: Slot | null) {
    const key = retryKey(epicId, slot);
    if (stopping || suspended || retrying.has(key)) return;
    retrying.add(key);
    try {
      const epic = fresh(epicId);
      const epoch = epochOf(epicId);
      const streak = failureStreak(db, epic, slot);
      const [last, ...earlier] = streak;
      if (epic.status !== 'running' || !last) return;
      if (earlier.length >= settings().maxExecutionRetries) {
        const idle = last.failureDetail?.startsWith('no output for ') ? ' · limits.idleMinutes ended it: raise it or remove it' : '';
        // A process failure's error already names its kind; an invalid result's is only the message, so it gets the same shape.
        const failure = last.failureKind === 'invalid_result' ? `the agent ended with an invalid result (invalid_result: ${last.error})` : last.error;
        toNeedsHuman(db, epicId, 'retries_exhausted', `ran out of ${last.stage} retries (${earlier.length + 1} attempts): ${failure}${idle}`);
        return await freeSlot();
      }
      const wait = retryWait(streak);
      const waiting = wait > 0 ? (last.finishedAt ?? 0) + wait - clock.now() : 0;
      if (waiting > 0) {
        if (!retryTimers.has(key)) {
          retryTimers.set(key, clock.after(waiting, async () => {
            retryTimers.delete(key);
            track(isolating(epicId, epic.repo, () => retry(epicId, slot)));
          }));
        }
        return;
      }
      // Read only: what the failed execution may have left on GitHub. A failed query is not an attempt, the poll tries again.
      const pr = await github.findPullRequest(epic.repo, epic.issue);
      if (!unchanged(epicId, epoch)) return; // parked while GitHub was asked: no event, no launch; the next check retries it if it is back
      // A lost session is rebuilt, not resumed: new session, same profile, context from SQLite and GitHub.
      const lost = last.failureKind === 'session_lost';
      showDue(epicId, slot);
      retryTimers.get(key)?.();
      retryTimers.delete(key);
      db.insert(epicEvents)
        .values({ epicId, at: clock.now(), type: lost ? 'session_rebuilt' : 'execution_retried', data: { stage: last.stage, failed: last.executionId, attempt: earlier.length + 2, error: last.error, pr } })
        .run();
      await execute(epic, last.stage, last, lost ? { pr: pr && { number: pr.number, headSha: pr.headSha } } : undefined);
    } finally {
      retrying.delete(key);
    }
  }

  // Running epics with a slot whose last execution failed and was not relaunched yet (GitHub was down, or the engine restarted): each slot on its own.
  async function retryPending() {
    for (const epic of db.select().from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all()) {
      for (const last of lastBySlot(db, epic)) await isolating(epic.id, epic.repo, () => retry(epic.id, slotOf(last)));
    }
  }

  // Summaries the caller left in earlier review and fix turns, oldest first.
  const previousSummaries = (epicId: number) =>
    db
      .select({ result: callerResults.result })
      .from(callerResults)
      .innerJoin(executions, eq(executions.executionId, callerResults.executionId))
      .where(and(eq(executions.epicId, epicId), inArray(executions.stage, ['review', 'fix']), ne(callerResults.outcome, supersededOutcome)))
      .orderBy(asc(executions.startedAt))
      .all()
      .map(({ result }) => (JSON.parse(result) as { summary: string }).summary);

  // Where the author left off, and the option that wrote it.
  const lastAuthor = (epicId: number) =>
    db
      .select({ sessionId: executions.sessionId, option: executions.option })
      .from(executions)
      .where(and(eq(executions.epicId, epicId), inArray(executions.stage, ['ship', 'fix']), isNotNull(executions.sessionId)))
      .orderBy(desc(sql`rowid`))
      .get();
  // The fix turn resumes it.
  const authorSession = (epicId: number) => lastAuthor(epicId)?.sessionId ?? undefined;
  // A ship that starts again continues the author's session only on the option that wrote it.
  const sameOptionSession = (epic: Epic) => {
    const before = lastAuthor(epic.id);
    return before && (before.option ?? null) === (epic.config!.agents.author.option ?? null) ? (before.sessionId ?? undefined) : undefined;
  };

  const inflight = new Set<Promise<void>>();
  // Epics with stage work in flight (the run and what handles its end: settling, a retry, a failover), by how many: the poll's recovery leaves them alone.
  const handling = new Map<number, number>();
  // `epicId` is the epic the work is about: an unexpected error in it stops that epic and nothing else (ADR 0046).
  const track = (work: Promise<void>, epicId?: number) => {
    if (epicId !== undefined) handling.set(epicId, (handling.get(epicId) ?? 0) + 1);
    const tracked: Promise<void> = work
      .catch(async (e) => {
        log.error('stage work failed', e);
        if (epicId === undefined || e instanceof AuthError || e instanceof GitHubUnavailable || isDatabaseError(e)) return failed(e);
        await stopEpic(epicId, e);
      })
      .finally(() => {
        inflight.delete(tracked);
        if (epicId !== undefined) handling.set(epicId, handling.get(epicId)! - 1);
      });
    inflight.add(tracked);
  };

  // Does the final PR the caller reported hold up against what GitHub says? Returns why not, or null.
  function prProblem({ issue }: Epic, found: Awaited<ReturnType<GitHub['getPullRequest']>>, pr: { number: number; headSha: string }, stage: Execution['stage']) {
    if (!found) return `PR #${pr.number} does not exist`;
    if (found.state !== 'open') return `PR #${pr.number} is not open`;
    if (!new RegExp(`\\bcloses #${issue}(?!\\d)`, 'i').test(found.body)) return `PR #${pr.number} does not reference the epic (missing "Closes #${issue}")`;
    // A review's moved head is not a problem of the pull request: it is reviewed again (ADR 0047), `settle` decides.
    if (stage !== 'review' && found.headSha !== pr.headSha) return `the head of PR #${pr.number} is ${found.headSha}, not ${pr.headSha}`;
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

  // A review of a head that moved is made again at most this many times in a row; the next move stops the epic.
  const maxHeadRepeats = 2;

  // Errors of `git worktree list` per ship execution whose result was left to be settled again; the count is lost on a restart, which only gives it three more.
  const maxWorktreeListRetries = 3;
  const worktreeListFailures = new Map<string, number>();

  // Imports the result of a finished execution and moves the epic. Safe to repeat: the import is idempotent.
  async function settle(execution: Execution) {
    if (stopping || suspended) return; // stays `finished` without a result: the next run imports it
    const epic = fresh(execution.epicId);
    if (outside(epic.id)) {
      worktreeListFailures.delete(execution.executionId); // cancelled or parked between two tries of `git worktree list`: its count goes
      return; // ended from outside or stopped: nothing new moves
    }
    const epoch = epochOf(epic.id);
    const expected = expectedOf(epic, execution);
    const raw = readResult(execution);
    const parsed = parseCallerResult(raw, expected);
    const context = taskContext({ repo: epic.repo, epic: epic.issue, executionId: execution.executionId, stage: execution.stage, reviewer: slotOf(execution), round: epic.round });
    // A review's result carries the commit its checkout was made at (ADR 0047), else it judged something the reviewer was not given.
    const wrongHead = parsed.ok && parsed.result.outcome !== 'needs_human' && execution.headSha !== null && parsed.result.pr.headSha !== execution.headSha
      ? `the review reports head ${parsed.result.pr.headSha}, not ${execution.headSha}, the commit its checkout was made at`
      : null;
    if (!parsed.ok || wrongHead) {
      const message = parsed.ok ? wrongHead! : raw === null ? 'no result file was written' : parsed.message;
      log.warn('invalid caller result', { ...context, reason: message });
      db.update(executions).set({ status: 'invalid_result', error: message, ...failureColumns({ ...noExit, kind: 'invalid_result', detail: failureDetail(message) }) }).where(eq(executions.executionId, execution.executionId)).run();
      db.update(epics).set({ lastError: message }).where(eq(epics.id, epic.id)).run();
      return retry(epic.id, slotOf(execution));
    }
    let problem: { kind: 'workspace' | 'pr_invalid'; text: string } | null = null;
    let movedTo: string | null = null; // a review whose head moved while it ran: the head GitHub has now, which the next review is made on
    let superseded = false; // that review judged a head that is not the pull request's any more, whether the epic reviews again or stops at the repeat cap
    let workspace: string | undefined;
    let branch: string | undefined; // the final PR's branch
    if (parsed.result.outcome !== 'needs_human') {
      const { pr } = parsed.result;
      const found = await github.getPullRequest(epic.repo, pr.number);
      const invalid = prProblem(epic, found, pr, execution.stage);
      if (invalid) problem = { kind: 'pr_invalid', text: invalid };
      else if (execution.stage === 'review' && found!.headSha !== pr.headSha) {
        superseded = true;
        if (epic.headRepeats >= maxHeadRepeats) problem = { kind: 'pr_invalid', text: `the head of PR #${pr.number} changed during the review ${epic.headRepeats + 1} times in a row` };
        else movedTo = found!.headSha;
      }
      if (!problem && execution.stage === 'ship') {
        // Solve put the epic's worktree where its solve.md says: read it back from git, keep the real path for the fix turns.
        branch = found!.headRef;
        let listError: unknown;
        try {
          workspace = (await workspaces.findWorktree(epic.repo, branch)) ?? undefined;
          worktreeListFailures.delete(execution.executionId);
        } catch (e) {
          listError = e;
          log.error('could not list the worktrees', e, context);
        }
        if (listError !== undefined) {
          // An error of git is not a missing worktree: the execution stays `finished` without a result and the next poll settles it again, up to three times.
          const failures = (worktreeListFailures.get(execution.executionId) ?? 0) + 1;
          if (failures <= maxWorktreeListRetries) {
            worktreeListFailures.set(execution.executionId, failures);
            return;
          }
          worktreeListFailures.delete(execution.executionId);
          problem = { kind: 'workspace', text: `could not list the worktrees of the clone of ${epic.repo} after ${failures} attempts: ${listError instanceof Error ? listError.message : String(listError)}` };
        } else if (!workspace) problem = { kind: 'workspace', text: `could not find the worktree for branch ${branch} in the clone of ${epic.repo}` };
      }
    }
    if (outside(epic.id) || epochOf(epic.id) !== epoch) return; // it ended, or was parked (and maybe restored) while GitHub was asked: stays `finished` without a result, the next run imports it
    const imported = importResult(db, raw, expected, (tx, result) => {
      // A stage change reaches the issue when a stage has a label: the label follows (labelPending) like a status change does.
      const update = (set: Partial<Epic>) => tx.update(epics).set({ ...set, ...(set.stage !== undefined && { recoveries: 0, autoResumes: 0, ...(stageLabelled() && { labelPending: true }) }) }).where(eq(epics.id, epic.id)).run();
      if (execution.stage === 'review' && !problem && !movedTo) tx.update(epics).set({ headRepeats: 0 }).where(eq(epics.id, epic.id)).run(); // a review completed on its own head
      // The verdict judged a head that is not the pull request's any more: kept as the execution it is, never read by a later round (a resume at review included).
      if (superseded) tx.update(callerResults).set({ outcome: supersededOutcome }).where(eq(callerResults.executionId, execution.executionId)).run();
      if (result.outcome === 'needs_human') toNeedsHuman(tx, epic.id, 'agent_needs_human', result.reason);
      else if (problem) toNeedsHuman(tx, epic.id, problem.kind, problem.text);
      else if (movedTo) {
        // The stage and round stay: the same stage reviews the new head.
        tx.update(epics).set({ prHeadSha: movedTo, headRepeats: epic.headRepeats + 1 }).where(eq(epics.id, epic.id)).run();
        tx.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: 'review_repeated', data: { executionId: execution.executionId, round: epic.round, from: result.pr.headSha, to: movedTo, repeats: epic.headRepeats + 1 } }).run();
        tx.insert(executionEvents).values({ executionId: execution.executionId, at: clock.now(), kind: 'note', payload: { text: `The head of PR #${result.pr.number} moved from ${result.pr.headSha} to ${movedTo} while this review ran: its verdict is set aside and the new head is reviewed again.` } }).run(); // what the events reply of this execution shows
      }
      else if (execution.stage === 'ship') update({ stage: 'review', stageStartedAt: clock.now(), round: 1, prNumber: result.pr.number, prHeadSha: result.pr.headSha, workspace, branch });
      // The pass ended with the head that was reviewed: nothing to review again, the reviewer's verification stands.
      else if (execution.stage === 'fix' && latestObservations(db, epic.id) && result.pr.headSha === epic.reviewedSha) update({ status: 'ready_for_test', finishedAt: clock.now(), labelPending: true });
      else if (execution.stage === 'fix') update({ stage: 'review', stageStartedAt: clock.now(), round: (epic.round ?? 0) + 1, prHeadSha: result.pr.headSha });
      // The round stays: the fix turn answers it, and the next review numbers the following one.
      else if (result.outcome === 'changes_requested') {
        if ((epic.round ?? 0) >= roundCap(epic)) toNeedsHuman(tx, epic.id, 'review_limit', `review limit: round ${epic.round} of ${roundCap(epic)} still has requested changes`);
        else update({ stage: 'fix', stageStartedAt: clock.now() });
      }
      // The one observations pass: the author answers them on the same round, and the reviewed head and verification wait for how it ends.
      else if (result.outcome === 'completed' && result.observations?.length && epic.observationsPassAt === null && (epic.round ?? 0) < roundCap(epic)) {
        update({ stage: 'fix', stageStartedAt: clock.now(), observationsPassAt: clock.now(), reviewedSha: result.pr.headSha, verification: result.verification });
      }
      else {
        // Observations a review listed that no pass will answer: how many, and whether the pass was taken or the round was the last its cap allows.
        const left = result.outcome === 'completed' ? (result.observations?.length ?? 0) : 0;
        update({
          status: 'ready_for_test', reviewedSha: result.pr.headSha, verification: result.verification, finishedAt: clock.now(), labelPending: true,
          ...(left > 0 && { unansweredObservations: left, unansweredReason: epic.observationsPassAt === null ? 'last_round' : 'already_taken' }),
        });
      }
    });
    // The last error is cleared by a result, unless another slot's failure is still being recovered: it is that error.
    if (!('duplicate' in imported) && !failingBesides(db, epic, slotOf(execution))) db.update(epics).set({ lastError: null }).where(eq(epics.id, epic.id)).run();
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
  // Parked epics (needs_human, ready_for_test) end the same way: a person merges or closes outside Carrier.
  async function stopEnded(seen: SeenThisPoll) {
    for (const epic of db.select().from(epics).where(and(inArray(epics.status, ['running', 'needs_human', 'ready_for_test']), inArray(epics.repo, repos().map((r) => r.name)))).orderBy(asc(epics.id)).all()) {
      await forRepo(epic.repo, async () => {
        const read = seen.prState.get(epic.id);
        const end = await unlessGone(epic.id, () => endOf(github, epic, { prState: read?.number === epic.prNumber ? read?.state : undefined, issueOpen: seen.openIssues.get(epic.repo)?.has(epic.issue) === true }));
        if (end) await finish(epic, end);
      });
    }
  }

  // The epic ended outside Carrier: its status and event are written, its runs stopped. `labelPending` is false when the issue cannot be written to.
  async function finish(epic: Epic, end: { status: 'merged' | 'cancelled'; reason: string; cancelKind?: CancelKind }, labelPending = true) {
    const ended = db.update(epics)
      .set({ status: end.status, ...(end.status === 'cancelled' && { cancelReason: end.reason, cancelKind: end.cancelKind ?? null }), finishedAt: clock.now(), labelPending, resumeAt: null })
      .where(and(eq(epics.id, epic.id), inArray(epics.status, ['running', 'needs_human', 'ready_for_test']))) // parked while GitHub was asked: `repo_removed` stays
      .returning()
      .get();
    if (!ended) return;
    db.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: `epic_${end.status}`, data: { reason: end.reason } }).run();
    const running = db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).all();
    await Promise.all(running.map(({ executionId }) => active.get(executionId)?.stop()));
  }

  // An epic's issue answering 404 or 410 while its repo answers normally is gone: the epic is cancelled and its repo's other epics go on.
  // GitHub also answers 404 for a repo the token lost access to, so the repo is asked first: one that does not answer normally rejects there,
  // which is the repo's refusal for the caller's `forRepo`, and no epic of it is cancelled.
  async function ifGone(repo: string, e: unknown) {
    if (!isNotFound(e)) return false;
    await github.listLabels(repo);
    return true;
  }
  const goneReason = 'the epic issue no longer exists';
  async function unlessGone<T>(id: number, step: () => Promise<T>) {
    try {
      return await step();
    } catch (e) {
      const epic = fresh(id);
      if (!(await ifGone(epic.repo, e))) throw e;
      await finish(epic, { status: 'cancelled', reason: goneReason, cancelKind: 'issue_gone' }, false);
    }
  }

  // A merged or cancelled epic's worktrees, reviewer checkout and pushed branches go, always: the code is on GitHub.
  // Also catches up epics that ended before this existed. A failure is logged and tried again at the next poll; it never blocks anything.
  // Read apart from the clean-up so a poll with nothing to clean awaits nothing more.
  const endedToClean = () =>
    db.select().from(epics).where(and(inArray(epics.status, ['merged', 'cancelled']), isNull(epics.cleanedAt), inArray(epics.repo, repos().map((r) => r.name)))).orderBy(asc(epics.id)).all()
      .filter((epic) => !db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).get()); // still stopping: next poll
  async function cleanUpEnded(ended: Epic[]) {
    for (const epic of ended) {
      try {
        const { kept } = await workspaces.cleanUp(epic.repo, epic.issue, epic.branch);
        if (kept.length > 0) log.warn('kept worktrees with unsaved work and local branches that are not on the remote', { repo: epic.repo, issue: epic.issue, kept });
        // Marked as cleaned even with something kept: the cleanup would keep it again at every poll. The event is where it shows.
        db.transaction((tx) => {
          tx.update(epics).set({ cleanedAt: clock.now() }).where(eq(epics.id, epic.id)).run();
          if (kept.length === 0) return;
          tx.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: 'cleanup_kept', data: { kept } }).run();
          // What the events reply of the epic's last execution shows: the app reads no epic event.
          const last = tx.select({ executionId: executions.executionId }).from(executions).where(eq(executions.epicId, epic.id)).orderBy(desc(sql`rowid`)).limit(1).get();
          if (last) tx.insert(executionEvents).values({ executionId: last.executionId, at: clock.now(), kind: 'note', payload: { text: `The clean-up of this ended epic kept what has unsaved work or is not on the remote: ${kept.join(', ')}. Delete it by hand when it is no longer needed.` } }).run();
        });
      } catch (e) {
        log.warn('could not clean up an ended epic, trying again at the next poll', { repo: epic.repo, issue: epic.issue, error: (e as Error).message });
      }
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
    for (const { execution } of pending) await isolating(execution.epicId, fresh(execution.epicId).repo, () => settle(execution));
  }

  // SQLite is the authority: a label that did not reach GitHub is retried here.
  async function reconcileLabels() {
    const pending = db
      .select()
      .from(epics)
      .where(and(inArray(epics.status, ['running', 'needs_human', 'ready_for_test', 'merged', 'cancelled']), eq(epics.labelPending, true)))
      .orderBy(asc(epics.id))
      .all();
    const epochsRead = pending.map((epic) => epochOf(epic.id));
    for (const [i, epic] of pending.entries()) await forRepo(epic.repo, () => begin(epic, epochsRead[i]));
  }

  // Starts the oldest queued epics until the concurrency limit or the queue is exhausted.
  async function fillSlots() {
    for (;;) {
      if (stopping || suspended || paused) return;
      const epic = reserve(db, { maxConcurrent: settings().maxConcurrentEpics, now: clock.now(), repos: repos().filter((r) => !rejected.has(r.name) && !skipped.has(r.name)) });
      if (!epic) return;
      const epoch = epochOf(epic.id);
      const cancelWith = (cancelReason: string, cancelKind: CancelKind) =>
        db.update(epics).set({ status: 'cancelled', cancelReason, cancelKind, finishedAt: clock.now(), labelPending: false }).where(and(eq(epics.id, epic.id), eq(epics.status, 'running'))).run();
      let issue;
      try {
        issue = await github.getIssue(epic.repo, epic.issue);
      } catch (e) {
        let gone = false;
        try {
          gone = await ifGone(epic.repo, e);
        } catch (probe) {
          e = probe; // the repo does not answer normally: its refusal below
        }
        if (gone) {
          cancelWith(goneReason, 'issue_gone');
          continue;
        }
        // Could not check it: give the slot back, the epic keeps its place in the queue.
        db.update(epics).set({ status: 'queued', startedAt: null, config: null, labelPending: false, authorOption: null, reviewerOption: null }).where(and(eq(epics.id, epic.id), eq(epics.status, 'running'))).run();
        if (e instanceof GitHubRejected) {
          refuse(epic.repo, e); // that repo gets nothing more this cycle; the next epics of the others go on
          continue;
        }
        throw e;
      }
      if (!stillRunning(epic.id)) continue; // parked while GitHub was asked: it keeps where it was
      polledLabels.set(`${epic.repo}#${epic.issue}`, issue.labels); // the freshest read: the label write that follows removes only what is there
      if (issue.state === 'closed') cancelWith('closed before it started', 'issue_closed');
      else if (!hasLabel(issue.labels, settings().labels.ready)) cancelWith('ready label removed', 'ready_removed');
      else {
        // Its slices exist before it is ready: read them now so the app has the list from the first second, not after the next poll.
        // Not `forRepo`: the extra turns it adds to this await change when a run that just ended gets its result imported, which tests depend on.
        try {
          await readEpicSlices(epic.repo, epic.id, epic.issue);
          if (stillRunning(epic.id)) await begin(epic, epoch); // GitHubUnavailable here leaves it reserved, labelPending; a refusal too, the next cycle labels it
        } catch (e) {
          if (!(e instanceof GitHubRejected)) throw e;
          refuse(epic.repo, e);
        }
      }
    }
  }

  // The runs of a parked epic, until they have ended and their execution says so (the done handler runs before this settles): an epic restored
  // before that finds its execution still `running` and has nothing to continue from.
  const ending = new Map<number, Promise<void>>();

  // A repo missing from the config stops its pending epics, untouched, with where they were, and the agent runs active on them (their executions
  // end `interrupted`); a repo back resumes them there (a `needs_human` one stays stopped). No GitHub call, label change, execution or retry for either.
  // The parking is synchronous, so a reload has parked a removed repo's epics by the time it answers; only the stops are waited for, by whoever wants to.
  // `restored` are the epics it brought back, which may need their stage launched again.
  function reconcileRepos() {
    const configured = repos().map((r) => r.name);
    const now = clock.now();
    const stops: Promise<void>[] = [];
    const restored: number[] = [];
    for (const epic of db.select().from(epics).where(and(inArray(epics.status, ['queued', 'running', 'needs_human']), notInArray(epics.repo, configured))).all()) {
      const reason = 'the repo is no longer in the configuration';
      db.update(epics).set({ status: 'repo_removed', removedFrom: epic.status, removedReason: reason, resumeAt: null }).where(eq(epics.id, epic.id)).run();
      db.insert(epicEvents).values({ epicId: epic.id, at: now, type: 'repo_removed', data: { from: epic.status, reason } }).run();
      epochs.set(epic.id, epochOf(epic.id) + 1);
      const runs = db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).all().flatMap(({ executionId }) => active.get(executionId) ?? []);
      if (runs.length === 0) continue;
      const stopped = Promise.all(runs.map(async (run) => (await run.stop(), await run.done)));
      stops.push(stopped.then(() => {}));
      const settled = stopped.then(() => {}, () => {}); // a failed stop is reported through `stops`; whoever waits for the end only needs it to be over
      ending.set(epic.id, settled);
      void settled.then(() => ending.get(epic.id) === settled && ending.delete(epic.id));
    }
    for (const epic of db.select().from(epics).where(and(eq(epics.status, 'repo_removed'), inArray(epics.repo, configured))).all()) {
      db.update(epics).set({ status: epic.removedFrom!, removedFrom: null, removedReason: null }).where(eq(epics.id, epic.id)).run();
      db.insert(epicEvents).values({ epicId: epic.id, at: now, type: 'repo_restored', data: { to: epic.removedFrom } }).run();
      restored.push(epic.id);
    }
    return { stopped: Promise.all(stops), restored };
  }

  // Continues one running epic from where it was: what the restart or a repo coming back found it in.
  // True when it did something (launched, settled or parked the epic), false when the epic's state is one a recovery does not move.
  async function recoverEpic(id: number): Promise<boolean> {
    const epic = fresh(id);
    // A review stage goes on from the last execution of each reviewer's slot, so each is recovered on its own; any other stage, from the epic's newest
    // (a review that has none yet is the stage the author's last execution handed over).
    const reviewers = epic.stage === 'review' ? lastBySlot(db, epic).filter((last) => slotOf(last) !== null) : [];
    const newest = db.select().from(executions).where(eq(executions.epicId, id)).orderBy(desc(sql`rowid`)).get();
    let acted = false;
    for (const last of reviewers.length > 0 ? reviewers : [newest && isOfAttempt(newest, epic) ? newest : undefined]) { // an earlier attempt's last execution is not this stop
      if (acted && !stillRunning(id)) break; // an earlier slot stopped the epic
      acted = (await recoverFrom(fresh(id), last)) || acted;
    }
    return acted;
  }

  // Continues the epic from one execution, the last of the slot being recovered (none: the epic has not started one).
  async function recoverFrom(epic: Epic, last: Execution | undefined): Promise<boolean> {
    const id = epic.id;
    log.info('recovering epic', { repo: epic.repo, epic: epic.issue, stage: epic.stage, lastStatus: last?.status });
    if (!last) {
      // A launch of this engine that claimed the stage and is still preparing its workspace is not a cut one: it makes the execution itself.
      if (launching.has(id)) return false;
      // A resumed stage claimed and cut before its execution: it starts that stage again, never ship.
      if (epic.stage === 'review' || epic.stage === 'fix') {
        launching.add(id);
        try {
          await execute(epic, epic.stage);
        } finally {
          launching.delete(id);
        }
        return true;
      }
      // Stopped between claiming the launch and inserting the execution: no agent ever ran, so launching is not a blind restart.
      db.update(epics).set({ stage: null }).where(eq(epics.id, id)).run();
      await launch(fresh(id), 'ship');
    } else if (last.status === 'timed_out') {
      // The run ended while the epic was parked, so its end handler did not stop it for a person: it does now, as that handler does.
      toNeedsHuman(db, id, 'timeout', timeoutReason(last.stage, last.failureDetail));
      await freeSlot();
    } else if (last.status === 'interrupted') {
      if (epic.stage !== last.stage) return false; // the epic moved on (or has no stage yet): this cut execution is not where it stands
      // The agent may have written its result just before the cut: import it once instead of launching again.
      if (parseCallerResult(readResult(last), expectedOf(epic, last)).ok) {
        db.update(executions).set({ status: 'finished' }).where(eq(executions.executionId, last.executionId)).run();
        await settle({ ...last, status: 'finished' });
      } else await execute(epic, last.stage, last);
    } else if (
      epic.stage !== null &&
      last.status === 'failed' &&
      (last.failureKind === 'usage_limit' ||
        matchesFailoverTrigger(failoverTriggersOf(epic.config?.failover, slotOf(last)), last.failureKind, last.failureDetail))
    ) {
      // Stopped before the epic moved on: no agent is running and none would be launched. A requeued epic (no stage yet) keeps its old
      // executions: that history is not this stop, the restart's own launch (begin, resumeStarts) takes it from here.
      await onUsageLimit(id, last);
    } else if (last.status === 'finished' && epic.stage) {
      const result = db.select().from(callerResults).where(eq(callerResults.executionId, last.executionId)).get();
      if (!result) return false;
      // With several reviewers, a slot whose result stands in the round the epic is at has nothing to launch: the round goes on with the slots that have none.
      // With one, the import moves the stage (or supersedes the result), so that state is not reached; if it were, it relaunches the stage as it always did.
      const several = epic.config !== null && agentOfSlot(epic.config, 'reviewer-2') !== undefined;
      if (several && last.stage === epic.stage && last.round === epic.round && result.outcome !== supersededOutcome) return false;
      await launch(epic, epic.stage); // imported, but the next stage was never launched
    } else return false;
    return true;
  }

  // The poll's recovery (ADR 0046): a running epic with a stage and nothing alive or scheduled for it is continued from its real state, with the guards of a
  // launch (stage work in flight, a launch, a retry, a reload's restore, the epoch). The count is saved with the epic: after three in a row it stops in `engine_error`.
  const maxRecoveries = 3;
  // Epics a command is recovering: the poll's recovery leaves them alone, and a second command is refused.
  const asked = new Set<number>();
  const busy = (id: number) => (handling.get(id) ?? 0) > 0 || launching.has(id) || retryingEpic(id) || restoring.has(id) || asked.has(id);
  async function recoverStuck() {
    if (stopping || suspended) return;
    const stuck = db.select().from(epics).where(and(eq(epics.status, 'running'), isNotNull(epics.stage))).orderBy(asc(epics.id)).all();
    const epochsRead = stuck.map(({ id }) => epochOf(id));
    for (const [i, { id, repo }] of stuck.entries()) {
      if (epochOf(id) !== epochsRead[i] || !stillRunning(id) || busy(id) || rejected.has(repo)) continue; // a repo GitHub refused this cycle holds back what waits on it (a retry): no recovery is counted
      const { recoveries, stage } = fresh(id);
      if (recoveries >= maxRecoveries) {
        await stopEpic(id, new Error(`the poll recovered this epic ${maxRecoveries} times in a row and it is still stuck at ${stage}`));
        continue;
      }
      let acted = false;
      try {
        if (!(await forRepo(repo, async () => (acted = await recoverEpic(id))))) continue; // a refusal of the repo is no recovery: tried again at the next check
      } catch (e) {
        if (e instanceof AuthError || e instanceof GitHubUnavailable || isDatabaseError(e)) throw e;
        log.error('recovering an epic failed', e, { repo, epicId: id });
        await stopEpic(id, e);
        continue;
      }
      if (!acted || !stillRunning(id)) continue; // it moved nothing (a retry owns the epic, or it left that stage), or it parked the epic (a timeout): neither is a recovery
      db.transaction((tx) => {
        tx.update(epics).set({ recoveries: sql`${epics.recoveries} + 1` }).where(eq(epics.id, id)).run();
        tx.insert(epicEvents).values({ epicId: id, at: clock.now(), type: 'recovered', data: { stage, attempt: recoveries + 1 } }).run();
      });
    }
  }

  // Epics a reload brought back from `repo_removed`, recovered by the next poll like a restart recovers every running epic. Only these: a reload on a
  // live engine must not run the cold-start recovery, which takes an epic with a launch in flight (stage claimed, no execution yet) for one that was cut.
  const restoring = new Set<number>();
  async function restore() {
    for (const id of [...restoring]) {
      await ending.get(id); // a repo back before its runs ended continues from them once they have
      if (stillRunning(id)) {
        const repo = fresh(id).repo;
        if (rejected.has(repo)) continue; // GitHub refused the repo this cycle: it waits in `restoring` for the next
        // A refusal is that repo's, as anywhere else in the cycle: the entry stays (the recovery did not happen) and the others go on.
        if (!(await forRepo(repo, () => unlessGone(id, () => recoverEpic(id))))) continue;
      }
      restoring.delete(id);
    }
  }

  // Restart, before anything is reserved: stop what the previous process left alive, then continue each running
  // epic from where it was. Safe to repeat (GitHub may be down halfway): what it relaunched is `active` or running.
  async function recover() {
    // Orphans first: no second agent may start on a workspace while the first still acts on it. An orphan is an execution
    // this engine folder's SQLite launched: the process list is the machine's, and a live agent of another carrier is not ours to stop.
    const ownExecution = (id: string) => db.select({ id: executions.executionId }).from(executions).where(eq(executions.executionId, id)).get() !== undefined;
    for (const id of await runner.listActive()) if (!active.has(id) && ownExecution(id)) {
      log.warn('stopping orphan execution', { executionId: id });
      await runner.stop(id);
    }
    for (const { executionId } of db.select().from(executions).where(eq(executions.status, 'running')).all()) {
      if (active.has(executionId)) continue;
      db.update(executions).set({ status: 'interrupted', finishedAt: clock.now() }).where(eq(executions.executionId, executionId)).run();
    }
    void reconcileRepos().stopped.catch((e) => log.error('stopping the runs of a removed repo failed', e));
    const running = db.select({ id: epics.id }).from(epics).where(eq(epics.status, 'running')).orderBy(asc(epics.id)).all();
    const epochsRead = new Map(running.map(({ id }) => [id, epochOf(id)]));
    for (const { id } of running) {
      // A reload parked it, and maybe restored it, since the list was read: restore() takes it from where it is, not this loop.
      if (epochOf(id) !== epochsRead.get(id)) continue;
      const { repo, issue } = fresh(id);
      await forRepo(repo, () => unlessGone(id, async () => {
        await github.getIssue(repo, issue); // a deleted issue ends its epic here, before an agent is launched for it
        await recoverEpic(id);
      }));
      if (epochOf(id) === epochsRead.get(id)) restoring.delete(id);
    }
    // SQLite is the authority: labels that differ on GitHub are put back.
    for (const epic of db.select().from(epics).where(and(inArray(epics.status, ['running', 'needs_human', 'ready_for_test']), inArray(epics.repo, repos().map((r) => r.name)))).orderBy(asc(epics.id)).all()) {
      await forRepo(epic.repo, () => unlessGone(epic.id, async () => {
        const { labels } = await github.getIssue(epic.repo, epic.issue);
        const wanted = wantedLabels(epic);
        if (ownedLabels().some((l) => hasLabel(labels, l) !== hasLabel(wanted, l)) || (epic.status === 'running' && hasLabel(labels, settings().labels.ready))) await applyLabels(epic);
      }));
    }
  }
  // One recovery at a time: a check asked while the start recovers waits for that one, never a second recoverEpic on the same epic. A failed one is
  // forgotten, so the next check tries again.
  let recovering: Promise<void> | null = null;
  // The start's recovery is running: it launches epics by itself, so a request that continues one is refused until it ends.
  let recoveringNow = false;
  const recoverOnce = () => {
    if (!recovering) {
      recoveringNow = true;
      recovering = recover()
        .catch((e) => {
          recovering = null;
          throw e;
        })
        .finally(() => (recoveringNow = false));
    }
    return recovering;
  };

  // What the repo's one listing says: the progress of each epic, the title and labels of those Carrier already holds (whatever their status), and which issues are open.
  function takeOpen(repo: string, open: { issue: number; title: string; labels: string[]; slices: Slices | null }[], seen: SeenThisPoll) {
    seen.openIssues.set(repo, new Set(open.map(({ issue }) => issue)));
    progress.set(repo, new Map(open.map(({ issue, slices }) => [issue, slices])));
    for (const { issue, title, labels } of open) {
      polledLabels.set(`${repo}#${issue}`, labels);
      db.update(epics).set({ title, labels }).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).run();
    }
  }

  // The one refresh rule of the caches of GitHub (ADR 0008), shared by the slices and the pull request block: live epics (running, parked)
  // are read every poll; a finished one keeps what it has and is read once only when it has nothing cached, e.g. it ended before the cache existed.
  function toRefresh(repo: string, hasCache: (epic: { id: number; prNumber: number | null; pr: unknown }) => boolean) {
    return db.select({ id: epics.id, issue: epics.issue, status: epics.status, prNumber: epics.prNumber, pr: epics.pr }).from(epics).where(eq(epics.repo, repo)).orderBy(asc(epics.id)).all()
      .filter((e) => liveStatuses.includes(e.status) || (['merged', 'cancelled'].includes(e.status) && !hasCache(e)));
  }

  // The slices of each epic to refresh, replacing its rows. A cache of GitHub: nothing the engine decides reads it back.
  // A failed read keeps the last rows and the poll goes on.
  // One read at a time per epic, whoever asks (the poll, an event, the timer): a read waits for the one in flight, so it starts after
  // the other has written and an older answer never lands over a newer one.
  const sliceReads = new Map<number, Promise<void>>();
  function readEpicSlices(repo: string, id: number, issue: number) {
    const inFlight = sliceReads.get(id);
    const read = inFlight ? inFlight.then(() => readSlicesNow(repo, id, issue)) : readSlicesNow(repo, id, issue);
    const settled = read.catch(() => {});
    sliceReads.set(id, settled);
    void settled.then(() => { if (sliceReads.get(id) === settled) sliceReads.delete(id); });
    return read;
  }

  async function readSlicesNow(repo: string, id: number, issue: number) {
    try {
      const { slices, truncated } = await github.readSlices(repo, issue);
      const readAt = clock.now();
      db.transaction((tx) => {
        tx.delete(epicSlices).where(eq(epicSlices.epicId, id)).run();
        if (slices.length > 0) tx.insert(epicSlices).values(slices.map((slice) => ({ ...slice, epicId: id, readAt, truncated }))).run();
      });
    } catch (e) {
      if (endsPoll(e)) throw e;
      log.error('slices read failed, keeping the last rows', e);
    }
  }

  // Reads one epic's slices now, or once at the end of the window when one was read less than sliceWindowMs ago: a burst makes one read
  // per window and the last change is seen; one slower than the window is followed by the next, never overlapped (readEpicSlices).
  const sliceReadAt = new Map<number, number>();
  const sliceReadLater = new Map<number, () => void>();
  function readSlicesSoon(id: number, repo: string, issue: number) {
    if (stopping || suspended || parked(id) || sliceReadLater.has(id)) return;
    const read = async () => {
      sliceReadLater.delete(id);
      if (stopping || suspended || parked(id)) return; // the repo left the configuration while the read waited for its window
      sliceReadAt.set(id, clock.now());
      try {
        await readEpicSlices(repo, id, issue);
      } catch (e) {
        failed(e); // only a rejected profile or a rate limit gets here: it suspends the engine or records the error like in a poll
      }
    };
    const wait = (sliceReadAt.get(id) ?? -sliceWindowMs) + sliceWindowMs - clock.now();
    if (wait <= 0) track(read());
    else sliceReadLater.set(id, clock.after(wait, read));
  }

  // The net: every minute, whatever the events said, the slices of the live epics (also a slice taken by hand on GitHub).
  let cancelSliceTimer: (() => void) | null = null;
  const sliceTimer = () => {
    if (stopping) return;
    cancelSliceTimer = clock.after(sliceTimerMs, async () => {
      const configured = repos().map((r) => r.name);
      for (const { id, repo, issue } of db.select().from(epics).where(and(inArray(epics.status, liveStatuses), inArray(epics.repo, configured))).orderBy(asc(epics.id)).all()) readSlicesSoon(id, repo, issue);
      sliceTimer();
    });
  };
  const stopSliceReads = () => {
    cancelSliceTimer?.();
    for (const cancelRead of sliceReadLater.values()) cancelRead();
  };

  async function refreshSlices(repo: string) {
    const stored = new Set(db.select({ id: epicSlices.epicId }).from(epicSlices).all().map((r) => r.id));
    for (const { id, issue } of toRefresh(repo, (e) => stored.has(e.id))) await readEpicSlices(repo, id, issue);
  }

  // The pull request block and review threads of each epic to refresh that has a PR, one query per epic and none for one without. A cache of GitHub
  // like the slices: a failed read keeps the last block and rows; a PR that GitHub does not know leaves them as they were.
  async function refreshPullRequests(repo: string, seen: SeenThisPoll) {
    for (const { id, prNumber } of toRefresh(repo, (e) => e.pr !== null || e.prNumber === null)) {
      if (prNumber === null) continue;
      try {
        const read = await github.readPullRequest(repo, prNumber);
        if (read === null) continue;
        const { pr, threads, truncated, state } = read;
        seen.prState.set(id, { number: prNumber, state });
        const readAt = clock.now();
        db.transaction((tx) => {
          tx.update(epics).set({ pr }).where(eq(epics.id, id)).run();
          tx.delete(epicReviewThreads).where(eq(epicReviewThreads.epicId, id)).run();
          if (threads.length > 0) tx.insert(epicReviewThreads).values(threads.map((thread, position) => ({ ...thread, epicId: id, position, readAt, truncated }))).run();
        });
      } catch (e) {
        if (endsPoll(e)) throw e;
        log.error('pull request read failed, keeping the last block and threads', e);
      }
    }
  }

  // Returns the wait until the next poll.
  async function poll(): Promise<number> {
    if (stopping) return settings().pollIntervalMs;
    const read = new Set<string>();
    // What this poll read about the epics, so `stopEnded` does not ask again for it (never what the caches hold: ADR 0008).
    const seen: SeenThisPoll = { prState: new Map(), openIssues: new Map() };
    rejected.clear();
    skipped.clear();
    longestWait = 0;
    try {
      // Fetch every repo before writing: a rate limit or a failing profile on any of them leaves the queue untouched.
      const found: { repo: string; issue: number; title: string; labels: string[] }[] = [];
      await recoverOnce();
      for (const { name: repo } of repos()) {
        // GitHub answering for this one repo that it cannot be read (not found, no access) is that repo's check; the others go on.
        // What is about the whole cycle (the profile, GitHub down) stops it below.
        // GitHub unavailable for it (not a rate limit) skips it for the cycle the same way, and nothing of it is queued.
        const ok = await forRepo(repo, async () => {
          try {
            // The one listing of the repo this cycle: the epics that carry the epic label, oldest first, and `ready` is read from their labels.
            const open = await github.listOpenEpics(repo, settings().labels.epic);
            takeOpen(repo, open, seen);
            const listed = open.filter(({ labels }) => hasLabel(labels, settings().labels.ready));
            await refreshSlices(repo);
            await refreshPullRequests(repo, seen);
            found.push(...listed.map(({ issue, title, labels }) => ({ repo, issue, title, labels })));
          } catch (e) {
            if (!(e instanceof GitHubUnavailable) || endsPoll(e)) throw e;
            skip(repo, e);
          }
        });
        if (ok && !skipped.has(repo)) checks.set(repo, { at: clock.now(), ok: true, error: null });
        read.add(repo); // a repo that failed has its own error: the one below is not written over it
      }
      if (skipped.size < repos().length || repos().length === 0) suspended = null; // a listing worked: the orchestrator's profile is back, the cycle goes on
      db.transaction((tx) => {
        // A reload may have removed a repo while the lists were read: nothing is queued for a repo that is not configured now.
        const configured = new Set(repos().map((r) => r.name));
        for (const epic of found.filter(({ repo }) => configured.has(repo))) {
          const known = tx.select().from(epics).where(and(eq(epics.repo, epic.repo), eq(epics.issue, epic.issue))).get();
          if (!known) {
            tx.insert(epics).values({ ...epic, queuedAt: queuePosition(tx, clock.now()) }).run();
            continue;
          }
          tx.update(epics).set({ title: epic.title, labels: epic.labels }).where(eq(epics.id, known.id)).run();
          // Carrier never leaves `ready` on a stopped epic, so finding it on a `needs_human` one is a person saying "go on":
          // it starts again from ship, which reuses the epic's worktree and PR, or from the stage the person asked for, which keeps where it stood.
          // Not while Carrier's own write is pending: a removal of `ready` that failed while the epic ran left it there, and it is not a person's.
          if (known.status === 'needs_human' && !known.labelPending) {
            const queuedAt = queuePosition(tx, clock.now());
            tx.update(epics).set(known.resumeStage ? requeueKeeping(queuedAt) : restart(queuedAt)).where(eq(epics.id, known.id)).run();
          } else if (known.status === 'cancelled' && requeueable.includes(known.cancelKind as CancelKind) && !tx.select({ id: executions.executionId }).from(executions).where(eq(executions.epicId, known.id)).get()) {
            // Cancelled before it started (no execution yet) and `ready` is back: no work was lost, so it goes back in the line with nothing of the cancel left on it.
            const queuedAt = queuePosition(tx, clock.now());
            tx.update(epics).set({ ...restart(queuedAt), cancelReason: null, cancelKind: null, cleanedAt: null }).where(eq(epics.id, known.id)).run();
            tx.insert(epicEvents).values({ epicId: known.id, at: queuedAt, type: 'requeued', data: { kind: known.cancelKind, reason: known.cancelReason } }).run();
          }
        }
      });
      await stopEnded(seen);
      await wakeUp();
      // After the probe: a suspended engine makes no GitHub call, and a restored epic's recovery makes some. After stopEnded: an epic whose PR
      // was merged or closed while its repo was parked ends there and is not launched just to be stopped.
      await restore();
      await settlePending();
      await retryPending();
      await recoverStuck();
      await resumeStarts();
      await reconcileLabels();
      await fillSlots();
      const ended = endedToClean();
      if (ended.length > 0) await cleanUpEnded(ended);
      error = null;
      return Math.max(settings().pollIntervalMs, longestWait);
    } catch (e) {
      log.error('poll failed', e);
      failed(e);
      // Only an expected failure gets here (`failed` rethrows the rest): the repos not read this cycle share it.
      const reason = e instanceof AuthError ? `authentication error for profile ${e.profile}` : (e as Error).message;
      for (const { name } of repos()) if (!read.has(name)) checks.set(name, { at: clock.now(), ok: false, error: reason });
      return Math.max(settings().pollIntervalMs, longestWait, (e instanceof GitHubUnavailable && e.retryAfterMs) || 0);
    } finally {
      skipped.clear();
      polledLabels.clear();
    }
  }

  // One poll at a time: a poll asked for by a person while the timer's is running is that one.
  const runPoll = () => {
    if (polling) return polling;
    polling = (async () => {
      try {
        schedule(await poll());
      } catch (e) {
        // `poll` lets through what is neither GitHub being down nor a failing profile. It is logged, and the next check is armed all the same: one bad
        // cycle must not end the polling, which nothing on screen would tell (a reload cancels the timer before it polls).
        log.error('poll failed unexpectedly, the next one is armed', e);
        schedule(settings().pollIntervalMs);
      } finally {
        polling = null;
      }
      // A reload asked while that poll listed the old repos: one more now, with the new ones, and its interval is the next wait.
      if (pollAgain && !stopping) {
        pollAgain = false;
        cancel?.();
        await runPoll();
      }
    })();
    return polling;
  };
  const schedule = (ms: number) => {
    if (stopping) return;
    cancel?.(); // a check asked during the start's recovery arms its own: only one chain of polls
    nextPollAt = clock.now() + ms;
    cancel = clock.after(ms, runPoll);
  };

  return {
    async start() {
      stopRetention = startRetention(db, places, clock, sessionDirs);
      // GitHub down: retried every cycle until it works.
      try {
        await recoverOnce();
      } catch (err) {
        log.error('startup step failed', err);
        failed(err);
      }
      schedule(settings().pollIntervalMs);
      sliceTimer();
    },
    stop() {
      cancel?.();
      stopSliceReads();
      for (const cancelRetry of retryTimers.values()) cancelRetry();
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
      stopSliceReads();
      for (const cancelRetry of retryTimers.values()) cancelRetry();
      stopRetention?.();
      await Promise.all([...active.values()].map((run) => run.stop()));
      while (inflight.size > 0) await Promise.all([...inflight]);
    },
    /** Resolves when no execution is being followed any more. */
    async idle() {
      while (inflight.size > 0) await Promise.all([...inflight]);
    },
    /**
     * Runs `swap`, which replaces what `settings()` returns (and throws ReloadRefused, changing nothing, when the next ones are not valid), then
     * polls now: the next poll is armed from then with the interval now in force, and a poll already running is that one.
     */
    reload(swap: () => void) {
      swap();
      // Repos that left are parked and their runs stopped now, and the check that follows resumes what a repo that came back had running.
      // The new settings are live by now: a failure here (SQLite) is logged, not the reload's, which the client would read as the settings not applied.
      try {
        const { stopped, restored } = reconcileRepos();
        for (const id of restored) restoring.add(id);
        void stopped.catch((e) => log.error('stopping the runs of a removed repo failed', e));
      } catch (e) {
        log.error('parking the epics of a removed repo failed', e);
      }
      // A poll that is running listed the old repos: it is not that check, so one more follows it.
      if (polling) pollAgain = true;
      else void this.pollNow().catch((e) => log.error('check after a reload failed', e));
    },
    /** Polls now instead of waiting for the interval, then goes on from there. */
    pollNow() {
      if (stopping) return Promise.resolve();
      cancel?.();
      return runPoll();
    },
    /**
     * Puts `ready` on a stopped epic's issue, as a person does, and checks now; resolves once the epic is no longer in
     * needs_human. It restarts on the option named for each role and on the one it has for a role left out.
     * With `from` `review` or `fix` the epic keeps its round, pull request and worktree and starts at that stage, when its pull request is open with the head it has stored;
     * at `review` an open pull request whose head moved is accepted and the epic stores the new head, which the `resumed` event reports.
     * One that stopped on the review limit then gets `extraRounds` more rounds from the current one, `maxReviews` when none is named.
     * Rejects with ResumeRefused: nothing was changed unless it is `did not restart`, which leaves the label for the next check.
     */
    async resumeEpic(repo: string, issue: number, chosen: { author?: string; reviewer?: string; from?: 'ship' | 'review' | 'fix'; extraRounds?: number } = {}) {
      // The socket answers while the start recovers, and the recovery is not the epic's wait: it is waited for on its own, up to the same 30 seconds, and
      // refused before anything is touched when it takes longer (the label is not put, the chosen options are not kept), so the client has not given up first.
      if (recovering) {
        let giveUp = () => {};
        const waited = await Promise.race([
          recovering.then(() => true, () => true),
          new Promise<boolean>((resolve) => (giveUp = clock.after(resumeWaitMs, async () => resolve(false)))),
        ]);
        giveUp();
        if (!waited) throw new ResumeRefused('did not restart');
      }
      const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
      if (!epic) throw new ResumeRefused('unknown epic');
      if (epic.status !== 'needs_human') throw new ResumeRefused('not stopped');
      // The requeue freezes the epic's options again from the configuration the engine runs with, so that is what the names are checked against.
      const repoConfig = repos().find((r) => r.name === repo);
      const declared = (repoConfig?.providers ?? repoConfig?.options) ?? {};
      if ([chosen.author, chosen.reviewer].some((name) => name !== undefined && !Object.hasOwn(declared, name))) throw new ResumeRefused('unknown option');
      const keeping = chosen.from === 'review' || chosen.from === 'fix' ? chosen.from : null;
      if (chosen.extraRounds !== undefined && !keeping) throw new ResumeRefused('extra rounds need a stage');
      if (chosen.extraRounds !== undefined && epic.needsHumanKind !== 'review_limit') throw new ResumeRefused('extra rounds need a review limit');
      let adopted: string | undefined;
      if (keeping) {
        let refusal;
        try {
          refusal = await pullRequestRefusal(epic, keeping === 'review' ? (headSha) => (adopted = headSha) : undefined);
        } catch (e) {
          if (e instanceof GitHubUnavailable || e instanceof AuthError) throw new ResumeRefused('github unavailable');
          throw e;
        }
        if (refusal) throw new ResumeRefused(refusal);
      }
      // A role left out keeps the option it has: the epic is not asked again.
      const author = chosen.author ?? epic.authorOption;
      const reviewer = chosen.reviewer ?? epic.reviewerOption;
      // Saved with the epic before the label goes on: a restart of the engine, or a check that finds the label later, takes the same stage. Any resume sets it, so an old ask never lingers.
      // The rounds granted go with it, counted from the round the epic is at; a resume that grants none leaves the cap as it was.
      // It also takes the wake-up's time away now: a poll that probes while the label is put must not resume the epic itself over what was asked here.
      // The epic was read before GitHub was asked, so the write holds only while it is still stopped (a wake-up may have moved it meanwhile).
      const grant = chosen.extraRounds ?? (epic.needsHumanKind === 'review_limit' ? settings().maxReviews : undefined);
      // `labelPending` goes too: the poll takes the `ready` of a stopped epic with a write still pending for Carrier's own, and this one is a person's.
      const saved = db.update(epics).set({ labelPending: false, resumeStage: keeping, resumeAt: null, prHeadSha: adopted ?? epic.prHeadSha, roundLimit: keeping && grant !== undefined ? (epic.round ?? 0) + grant : epic.roundLimit }).where(and(eq(epics.id, epic.id), eq(epics.status, 'needs_human'))).returning().get();
      if (!saved) throw new ResumeRefused('not stopped');
      restarts.set(epic.id, { ...(author && { author }), ...(reviewer && { reviewer }) });
      try {
        await github.setLabels(repo, issue, { add: [settings().labels.ready], remove: [] });
      } catch (e) {
        restarts.delete(epic.id);
        db.update(epics).set({ labelPending: epic.labelPending, resumeStage: null, resumeAt: epic.resumeAt, prHeadSha: epic.prHeadSha, roundLimit: epic.roundLimit }).where(and(eq(epics.id, epic.id), eq(epics.status, 'needs_human'))).run();
        if (e instanceof GitHubUnavailable || e instanceof AuthError) throw new ResumeRefused('github unavailable');
        throw e;
      }
      // Not awaited: the wait below has the deadline. A poll already running is the one that answers, but it may have listed
      // before the label went on: once it settles with the epic still stopped, one more check is asked for.
      const check = () => this.pollNow().catch((e) => log.error('check for a resumed epic failed', e));
      let settled = false;
      void check().then(() => (settled = true));
      let again = false;
      const deadline = clock.now() + resumeWaitMs;
      while (fresh(epic.id).status === 'needs_human') {
        if (clock.now() >= deadline) {
          restarts.delete(epic.id);
          throw new ResumeRefused('did not restart');
        }
        if (settled && !again) {
          again = true;
          void check();
        }
        await new Promise<void>((resolve) => clock.after(resumeTickMs, async () => resolve()));
      }
      // Every resume says what asked for it, as `recover` does; a plain one is from ship.
      db.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: 'resumed', data: { from: chosen.from ?? 'ship', by: 'command', ...(adopted && { headAdopted: { from: epic.prHeadSha, to: adopted } }) } }).run();
    },
    /**
     * Continues one running epic whose agent is not alive, from its real state, through the code of the poll's recovery (ADR 0044); resolves once it was continued.
     * Rejects with RecoverRefused when it is unknown, not running, has an execution alive or in flight, the engine cannot act now, or the epic's state is one the recovery does not move.
     */
    async recoverEpic(repo: string, issue: number) {
      if (stopping || suspended || recoveringNow) throw new RecoverRefused('engine unavailable');
      const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
      if (!epic) throw new RecoverRefused('unknown epic');
      if (epic.status !== 'running') throw new RecoverRefused('not running');
      if (epic.stage === null) throw new RecoverRefused('not started'); // the poll's launch has not claimed it yet
      if (busy(epic.id) || db.select().from(executions).where(and(eq(executions.epicId, epic.id), eq(executions.status, 'running'))).get()) throw new RecoverRefused('agent alive');
      asked.add(epic.id);
      try {
        let acted = false;
        if (!(await forRepo(repo, async () => (acted = await recoverEpic(epic.id))))) throw new RecoverRefused('github unavailable');
        if (!acted) throw new RecoverRefused('nothing to recover'); // a state the recovery does not move (a retry owns it, or the epic left that stage): not a recovery
      } catch (e) {
        if (e instanceof RecoverRefused) throw e;
        if (e instanceof AuthError || e instanceof GitHubUnavailable) throw new RecoverRefused('github unavailable');
        if (isDatabaseError(e) === false) {
          log.error('recovering an epic failed', e, { repo, epicId: epic.id });
          await stopEpic(epic.id, e);
        }
        throw e;
      } finally {
        asked.delete(epic.id);
      }
      db.insert(epicEvents).values({ epicId: epic.id, at: clock.now(), type: 'recovered', data: { stage: epic.stage, by: 'command' } }).run();
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
    /** The last poll of a repo; undefined until the first one after a start. */
    lastCheck: (repo: string) => checks.get(repo),
    /** Queued epics, oldest first. */
    queue: () => db.select().from(epics).where(eq(epics.status, 'queued')).orderBy(...queueOrder).all(),
  };
}
