import { and, asc, count, desc, eq, gte, inArray, sql } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { latestBlockers } from '../orchestration/blockers.ts';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { ControlSnapshot, EpicOptions, PanelAgent, PanelAgents, PanelEpic, PanelSession } from './types.ts';

const agentOf = ({ harness, model, provider }: EffectiveRepoConfig['agents']['author']): PanelAgent => ({ harness, model, provider: provider ?? null });
const agentsOf = (config: EffectiveRepoConfig): PanelAgents => ({ author: agentOf(config.agents.author), reviewer: agentOf(config.agents.reviewer) });

/** The options of an epic as the panel and the epic's reply list them; undefined for one saved before options existed. */
export const optionsOf = ({ config, authorOption, reviewerOption, choiceDeadline }: { config: EffectiveRepoConfig | null; authorOption: string | null; reviewerOption: string | null; choiceDeadline: number | null }): EpicOptions | undefined => {
  const directory = config?.providers ?? config?.options;
  return directory && { names: Object.keys(directory), author: authorOption, reviewer: reviewerOption, choiceDeadline };
};

/** One row per watched repo: the agents it resolves to and its last poll (not checked yet: null and ok). */
export function watchedOf(repos: EffectiveRepoConfig[], lastCheck: (repo: string) => { at: number; ok: boolean; error: string | null } | undefined): ControlSnapshot['watched'] {
  return repos.map((r) => {
    const check = lastCheck(r.name);
    return { repo: r.name, lastCheckedAt: check?.at ?? null, ok: check?.ok ?? true, error: check?.error ?? null, agents: agentsOf(r) };
  });
}

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
    version, pollIntervalMs, rateLimit = null, watched = [], lastEvent = () => null,
  }: {
    now: number; maxConcurrentEpics: number; maxReviews: number; finishedWindowDays: number; startedAt: number; repos: number; nextCheckAt: number | null; problem: string | null; paused: boolean;
    slices: (repo: string, issue: number) => PanelEpic['slices'];
    version: string;
    pollIntervalMs: number;
    rateLimit?: ControlSnapshot['engine']['rateLimit'];
    watched?: ControlSnapshot['watched'];
    /** The newest event of an execution. */
    lastEvent?: (executionId: string) => PanelSession['last'];
  },
): ControlSnapshot {
  const busy = db.select({ n: count() }).from(epics).where(eq(epics.status, 'running')).get()!.n;
  const queue = db.select({ repo: epics.repo, issue: epics.issue, title: epics.title, queuedAt: epics.queuedAt }).from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all()
    .map((q) => ({ repo: q.repo, issue: q.issue, title: q.title, queuedAt: q.queuedAt }));
  const shown = db.select().from(epics).where(inArray(epics.status, ['running', 'needs_human'])).orderBy(asc(epics.id)).all();
  const lastExecution = (epicId: number) => db.select({ id: executions.executionId }).from(executions).where(eq(executions.epicId, epicId)).orderBy(desc(executions.startedAt), sql`rowid desc`).limit(1).get()?.id ?? null;
  const done = db.select({ id: epics.id, repo: epics.repo, issue: epics.issue, title: epics.title, labels: epics.labels, prNumber: epics.prNumber, finishedAt: epics.finishedAt }).from(epics).where(eq(epics.status, 'ready_for_test')).orderBy(desc(epics.finishedAt)).limit(5).all()
    .map(({ id, labels, ...rest }) => ({ ...rest, labels: labels ?? [], executionId: lastExecution(id) }));
  const finished = db.select({ id: epics.id, repo: epics.repo, issue: epics.issue, title: epics.title, labels: epics.labels, prNumber: epics.prNumber, finishedAt: epics.finishedAt, status: epics.status, cancelReason: epics.cancelReason }).from(epics)
    .where(and(inArray(epics.status, ['merged', 'cancelled']), gte(epics.finishedAt, now - finishedWindowDays * 86_400_000))).orderBy(desc(epics.finishedAt)).all()
    .map(({ id, labels, finishedAt, status, cancelReason, ...rest }) => ({ ...rest, labels: labels ?? [], finishedAt: finishedAt!, status: status as 'merged' | 'cancelled', cancelReason: status === 'cancelled' ? cancelReason : null, executionId: lastExecution(id) }));
  const epicAgents = (e: { config: EffectiveRepoConfig | null }): PanelAgents | null => e.config && agentsOf(e.config);
  const sessions = shown.flatMap((e) => {
    const agent = epicAgents(e);
    const running = db.select({ executionId: executions.executionId, stage: executions.stage, startedAt: executions.startedAt }).from(executions)
      .where(and(eq(executions.epicId, e.id), eq(executions.status, 'running'))).orderBy(desc(executions.startedAt), sql`rowid desc`).limit(1).get();
    if (e.status !== 'running' || !running || !agent) return [];
    const { harness, model } = agent[running.stage === 'review' ? 'reviewer' : 'author'];
    return [{ executionId: running.executionId, repo: e.repo, issue: e.issue, stage: running.stage, round: e.round, harness, model, startedAt: running.startedAt, last: lastEvent(running.executionId) }];
  });
  return {
    now,
    startedAt,
    repos,
    nextCheckAt,
    problem,
    paused,
    done,
    slots: { busy, total: maxConcurrentEpics },
    queue,
    engine: { version, pollIntervalMs, maxConcurrentEpics, rateLimit },
    watched,
    sessions,
    finished,
    epics: shown.map((e) => {
      const blockers = latestBlockers(db, e.id);
      return {
        repo: e.repo,
        issue: e.issue,
        status: e.status as 'running' | 'needs_human',
        stage: e.stage,
        round: e.round,
        maxReviews,
        blockers: blockers.length,
        stageSince: e.stageStartedAt ?? e.startedAt ?? now,
        lastActivityAt: e.lastActivityAt,
        issueUrl: `https://github.com/${e.repo}/issues/${e.issue}`,
        prUrl: e.prNumber === null ? null : `https://github.com/${e.repo}/pull/${e.prNumber}`,
        lastError: e.lastError,
        needsHumanReason: e.needsHumanReason,
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
        options: optionsOf(e),
      };
    }),
  };
}
