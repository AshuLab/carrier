import { and, asc, count, desc, eq, inArray, sql } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { latestBlockers } from '../orchestration/blockers.ts';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { ControlSnapshot, NeedsHumanKind, PanelAgent, PanelAgents, PanelEpic, PanelSession } from './types.ts';

const agentOf = ({ harness, model, provider }: EffectiveRepoConfig['agents']['author']): PanelAgent => ({ harness, model, provider: provider ?? null });
const agentsOf = (config: EffectiveRepoConfig): PanelAgents => ({ author: agentOf(config.agents.author), reviewer: agentOf(config.agents.reviewer) });

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
 * What the engine does not keep yet comes in through the optional inputs and is empty (null or []) without them.
 */
export function buildSnapshot(
  db: Db,
  {
    now, maxConcurrentEpics, maxReviews, startedAt, repos, nextCheckAt, problem, paused, slices,
    version, pollIntervalMs, rateLimit = null, watched = [], lastEvent = () => null, issueMeta = () => ({}),
  }: {
    now: number; maxConcurrentEpics: number; maxReviews: number; startedAt: number; repos: number; nextCheckAt: number | null; problem: string | null; paused: boolean;
    slices: (repo: string, issue: number) => PanelEpic['slices'];
    version: string;
    pollIntervalMs: number;
    rateLimit?: ControlSnapshot['engine']['rateLimit'];
    watched?: ControlSnapshot['watched'];
    /** The newest event of an execution. */
    lastEvent?: (executionId: string) => PanelSession['last'];
    /** What only GitHub knows about an issue (and the branch and the kind of stop, which are not stored yet). */
    issueMeta?: (repo: string, issue: number) => { title?: string; labels?: string[]; branch?: string; needsHumanKind?: NeedsHumanKind };
  },
): ControlSnapshot {
  const busy = db.select({ n: count() }).from(epics).where(eq(epics.status, 'running')).get()!.n;
  const queue = db.select({ repo: epics.repo, issue: epics.issue, queuedAt: epics.queuedAt }).from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all()
    .map((q) => ({ repo: q.repo, issue: q.issue, title: issueMeta(q.repo, q.issue).title ?? null, queuedAt: q.queuedAt }));
  const shown = db.select().from(epics).where(inArray(epics.status, ['running', 'needs_human'])).orderBy(asc(epics.id)).all();
  const lastExecution = (epicId: number) => db.select({ id: executions.executionId }).from(executions).where(eq(executions.epicId, epicId)).orderBy(desc(executions.startedAt), sql`rowid desc`).limit(1).get()?.id ?? null;
  const done = db.select({ id: epics.id, repo: epics.repo, issue: epics.issue, prNumber: epics.prNumber, finishedAt: epics.finishedAt }).from(epics).where(eq(epics.status, 'ready_for_test')).orderBy(desc(epics.finishedAt)).limit(5).all()
    .map(({ id, ...rest }) => ({ ...rest, executionId: lastExecution(id) }));
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
    epics: shown.map((e) => {
      const meta = issueMeta(e.repo, e.issue);
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
        title: meta.title ?? null,
        labels: meta.labels ?? [],
        queuedAt: e.queuedAt,
        startedAt: e.startedAt,
        finishedAt: e.finishedAt,
        branch: meta.branch ?? null,
        workspace: e.workspace,
        needsHumanKind: meta.needsHumanKind ?? null,
        blockerTitles: blockers.slice(0, maxBlockerTitles).map((b) => b.title.slice(0, maxBlockerTitleLength)),
        agents: epicAgents(e),
      };
    }),
  };
}
