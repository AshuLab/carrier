import { and, asc, count, desc, eq, gte, inArray, isNull, lt, or, sql } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { latestBlockers, latestLeadBlockers } from '../orchestration/blockers.ts';
import { agentOfSlot, roundSlots } from '../orchestration/slots.ts';
import type { Labels } from '../orchestration/github.ts';
import { latestRoundTally, leadApproval } from '../orchestration/round.ts';
import { lastBySlot } from '../orchestration/retry.ts';
import { queueOrder } from '../orchestration/reserve.ts';
import type { Db } from '../storage/db.ts';
import { redact } from '../logging/redact.ts';
import { executions, slotOf } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { ControlSnapshot, EpicOptions, PanelAgent, PanelAgents, PanelEpic, PanelReviewers, PanelSession } from './types.ts';

const agentOf = ({ harness, model, provider }: EffectiveRepoConfig['agents']['author']): PanelAgent => ({ harness, model, provider: provider ?? null });
/** An extra reviewer beside its harness, model and provider: its key, name and type, which an epic saved before the names lacks. */
const extraAgentOf = (extra: NonNullable<EffectiveRepoConfig['agents']['extraReviewers']>[number]): PanelAgent => ({ ...agentOf(extra), ...(typeof extra.key === 'string' && { key: extra.key, name: extra.name, type: extra.type }) });
const agentsOf = (config: EffectiveRepoConfig): PanelAgents => ({ author: agentOf(config.agents.author), reviewer: agentOf(config.agents.reviewer), ...(config.agents.leadReviewer && { lead: agentOf(config.agents.leadReviewer) }) });

/** The options of an epic as the panel and the epic's reply list them; undefined for one saved before options existed. */
export const optionsOf = ({ config, authorOption, reviewerOption }: { config: EffectiveRepoConfig | null; authorOption: string | null; reviewerOption: string | null }): EpicOptions | undefined => {
  const directory = config?.providers ?? config?.options;
  const { extraReviewers = [], leadReviewer } = config?.agents ?? {};
  const keyed = extraReviewers.filter((extra) => typeof extra.key === 'string'); // an epic saved before the names has none
  return directory && { names: Object.keys(directory), author: authorOption, reviewer: reviewerOption, ...(keyed.length > 0 && { extraReviewers: Object.fromEntries(keyed.map((extra) => [extra.key, extra.option ?? null])) }), ...(leadReviewer && { lead: leadReviewer.option ?? null }) };
};

/** One row per watched repo: the agents it resolves to and its last poll (not checked yet: null and ok). */
export function watchedOf(repos: EffectiveRepoConfig[], lastCheck: (repo: string) => { at: number; ok: boolean; error: string | null } | undefined): ControlSnapshot['watched'] {
  return repos.map((r) => {
    const check = lastCheck(r.name);
    return { repo: r.name, lastCheckedAt: check?.at ?? null, ok: check?.ok ?? true, error: check?.error ?? null, agents: agentsOf(r) };
  });
}

const maxNoVerdictWhy = 200;

/** A field that is there only when it has a value. */
const spread = <K extends string, V>(key: K, value: V | undefined) => (value === undefined ? {} : ({ [key]: value } as Record<K, V>));

/** How the epic's latest decided round came out, for an epic with several reviewers that has one: the reason of each reviewer with no verdict is redacted, since an agent wrote it. */
const reviewersOf = (db: Db, epic: { id: number; startedAt: number | null; config: EffectiveRepoConfig | null }): PanelReviewers | undefined => {
  const slots = roundSlots(epic.config);
  const tally = slots.length > 1 ? latestRoundTally(db, epic, slots) : undefined;
  return tally && { given: tally.given, of: tally.of, none: tally.none.map(({ slot, why }) => ({ slot, why: redact(why).slice(0, maxNoVerdictWhy) })) };
};

const maxBlockerTitles = 10;
const maxBlockerTitleLength = 200;

/**
 * What the panel shows, read from SQLite: slots, the queue (oldest first) and each epic that is running or waiting for a person.
 * What the engine does not keep in SQLite comes in through the optional inputs and is empty (null or []) without them.
 */
export function buildSnapshot(
  db: Db,
  {
    now, maxConcurrentEpics, maxReviews, finishedWindowDays, startedAt, repos, nextCheckAt, problem, paused, slices,
    version, pollIntervalMs, labels, rateLimit = null, watched = [], lastEvent = () => null,
  }: {
    now: number; maxConcurrentEpics: number; maxReviews: number; finishedWindowDays: number; startedAt: number; repos: number; nextCheckAt: number | null; problem: string | null; paused: boolean;
    slices: (repo: string, issue: number) => PanelEpic['slices'];
    version: string;
    pollIntervalMs: number;
    labels: Labels;
    rateLimit?: ControlSnapshot['engine']['rateLimit'];
    watched?: ControlSnapshot['watched'];
    /** The newest event of an execution. */
    lastEvent?: (executionId: string) => PanelSession['last'];
  },
): ControlSnapshot {
  const busy = db.select({ n: count() }).from(epics).where(eq(epics.status, 'running')).get()!.n;
  const queue = db.select({ repo: epics.repo, issue: epics.issue, title: epics.title, queuedAt: epics.queuedAt }).from(epics).where(eq(epics.status, 'queued')).orderBy(...queueOrder).all()
    .map((q) => ({ repo: q.repo, issue: q.issue, title: q.title, queuedAt: q.queuedAt }));
  const shown = db.select().from(epics).where(inArray(epics.status, ['running', 'needs_human'])).orderBy(asc(epics.id)).all();
  // The execution an epic names is the newest of the author or of the mandatory reviewer: which other reviewer ended last does not move it.
  const lastExecution = (epicId: number) => db.select({ id: executions.executionId }).from(executions).where(and(eq(executions.epicId, epicId), or(isNull(executions.reviewer), eq(executions.reviewer, 'reviewer')))).orderBy(desc(executions.startedAt), sql`rowid desc`).limit(1).get()?.id ?? null;
  const done = db.select({ id: epics.id, repo: epics.repo, issue: epics.issue, title: epics.title, labels: epics.labels, prNumber: epics.prNumber, finishedAt: epics.finishedAt, unansweredObservations: epics.unansweredObservations, unansweredReason: epics.unansweredReason, startedAt: epics.startedAt, config: epics.config, reviewedSha: epics.reviewedSha, approvedSha: epics.approvedSha }).from(epics).where(eq(epics.status, 'ready_for_test')).orderBy(desc(epics.finishedAt)).limit(5).all()
    .map(({ id, labels, unansweredObservations, unansweredReason, startedAt, config, reviewedSha, approvedSha, ...rest }) => ({ ...rest, labels: labels ?? [], executionId: lastExecution(id), ...(reviewedSha !== null && { reviewedSha }), ...(approvedSha !== null && { approvedSha, ...spread('leadApproval', leadApproval(db, { id, startedAt })) }), ...(unansweredObservations !== null && unansweredReason !== null && { unansweredObservations: { count: unansweredObservations, reason: unansweredReason } }), ...spread('reviewers', reviewersOf(db, { id, startedAt, config })) }));
  const finished = db.select({ id: epics.id, repo: epics.repo, issue: epics.issue, title: epics.title, labels: epics.labels, prNumber: epics.prNumber, finishedAt: epics.finishedAt, status: epics.status, cancelReason: epics.cancelReason }).from(epics)
    .where(and(inArray(epics.status, ['merged', 'cancelled']), gte(epics.finishedAt, now - finishedWindowDays * 86_400_000), or(isNull(epics.dismissedAt), lt(epics.dismissedAt, epics.finishedAt)))).orderBy(desc(epics.finishedAt)).all()
    .map(({ id, labels, finishedAt, status, cancelReason, ...rest }) => ({ ...rest, labels: labels ?? [], finishedAt: finishedAt!, status: status as 'merged' | 'cancelled', cancelReason: status === 'cancelled' ? cancelReason : null, executionId: lastExecution(id) }));
  // A restart marks the role that failed, which says more than the stage when the review had several: the slot of the execution of the attempt that failed, else the last one.
  const optionsWithFailed = (e: Parameters<typeof optionsOf>[0] & { id: number; status: string; startedAt: number | null }) => {
    const options = optionsOf(e);
    if (e.status !== 'needs_human' || (options?.extraReviewers === undefined && options?.lead === undefined)) return options;
    const lasts = lastBySlot(db, e).sort((a, b) => b.startedAt - a.startedAt);
    const stopped = lasts.find((last) => last.failureKind !== null) ?? lasts[0];
    const failed: EpicOptions['failed'] = (stopped && slotOf(stopped)) || 'author';
    return { ...options!, failed };
  };
  const epicAgents = (e: { config: EffectiveRepoConfig | null }): PanelAgents | null => {
    const extra = e.config?.agents.extraReviewers ?? [];
    return e.config && { ...agentsOf(e.config), ...(extra.length > 0 && { extraReviewers: extra.map(extraAgentOf) }) };
  };
  // A session for each running execution of a running epic, in the order they were launched; the harness and the model are the ones the execution ran with, and the saved role's agent only for a row that has none.
  const sessions = shown.flatMap((e) => {
    if (e.status !== 'running') return [];
    const running = db.select({ executionId: executions.executionId, stage: executions.stage, reviewer: executions.reviewer, startedAt: executions.startedAt, harness: executions.harness, model: executions.model }).from(executions)
      .where(and(eq(executions.epicId, e.id), eq(executions.status, 'running'))).orderBy(asc(executions.startedAt), sql`rowid asc`).all();
    return running.flatMap((run) => {
      const slot = slotOf(run);
      const saved = e.config && agentOfSlot(e.config, slot);
      const harness = (run.harness ?? saved?.harness) as PanelAgent['harness'] | undefined;
      if (harness === undefined) return [];
      // The app's stage is a strict enum without `lead`: the lead's session is a review, flagged.
      return [{ executionId: run.executionId, repo: e.repo, issue: e.issue, stage: run.stage === 'lead' ? 'review' as const : run.stage, ...(run.stage === 'lead' && { lead: true as const }), round: e.round, harness, model: run.model ?? saved?.model ?? '', ...(slot !== null && { reviewer: slot }), startedAt: run.startedAt, last: lastEvent(run.executionId) }];
    });
  });
  return {
    now,
    startedAt,
    repos,
    nextCheckAt,
    problem,
    paused,
    labels,
    done,
    slots: { busy, total: maxConcurrentEpics },
    queue,
    engine: { version, pollIntervalMs, maxConcurrentEpics, rateLimit },
    watched,
    sessions,
    finished,
    epics: shown.map((e) => {
      const blockers = [...latestBlockers(db, e), ...latestLeadBlockers(db, e.id)]; // the lead's open ones too, while the author fixes them
      return {
        repo: e.repo,
        issue: e.issue,
        status: e.status as 'running' | 'needs_human',
        stage: e.stage === 'lead' ? 'review' : e.stage, // the app's stage has no `lead`: it is a review, flagged
        ...(e.stage === 'lead' && { lead: true as const }),
        round: e.round,
        maxReviews: e.roundLimit ?? maxReviews,
        blockers: blockers.length,
        stageSince: e.stageStartedAt ?? e.startedAt ?? now,
        lastActivityAt: e.lastActivityAt,
        issueUrl: `https://github.com/${e.repo}/issues/${e.issue}`,
        prUrl: e.prNumber === null ? null : `https://github.com/${e.repo}/pull/${e.prNumber}`,
        lastError: e.lastError,
        needsHumanReason: e.needsHumanReason,
        ...(e.needsHumanCode !== null && { needsHumanCode: e.needsHumanCode, needsHumanParams: e.needsHumanParams ?? {} }),
        slices: slices(e.repo, e.issue),
        executionId: lastExecution(e.id),
        title: e.title,
        labels: e.labels ?? [],
        queuedAt: e.queuedAt,
        startedAt: e.startedAt,
        finishedAt: e.finishedAt,
        branch: e.branch,
        workspace: e.workspace,
        needsHumanKind: e.needsHumanKind,
        blockerTitles: blockers.slice(0, maxBlockerTitles).map((b) => b.title.slice(0, maxBlockerTitleLength)),
        agents: epicAgents(e),
        options: optionsWithFailed(e),
        ...spread('reviewers', reviewersOf(db, e)),
        ...(e.reviewedSha !== null && { reviewedSha: e.reviewedSha }),
        ...(e.approvedSha !== null && { approvedSha: e.approvedSha, ...spread('leadApproval', leadApproval(db, e)) }),
        ...(e.resumeAt !== null && { resumeAt: e.resumeAt }),
        ...(e.status === 'running' && e.retryAt !== null && { retryAt: e.retryAt }),
      };
    }),
  };
}
