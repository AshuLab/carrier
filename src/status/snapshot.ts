import { asc, count, desc, eq, inArray, sql } from 'drizzle-orm';
import { latestBlockers } from '../orchestration/blockers.ts';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { PanelEpic, PanelSnapshot } from './types.ts';

/** What the panel shows, read from SQLite: slots, the queue (oldest first) and each epic that is running or waiting for a person. */
export function buildSnapshot(
  db: Db,
  { now, maxConcurrentEpics, maxReviews, startedAt, repos, nextCheckAt, problem, paused, slices }: { now: number; maxConcurrentEpics: number; maxReviews: number; startedAt: number; repos: number; nextCheckAt: number | null; problem: string | null; paused: boolean; slices: (repo: string, issue: number) => PanelEpic['slices'] },
): PanelSnapshot {
  const busy = db.select({ n: count() }).from(epics).where(eq(epics.status, 'running')).get()!.n;
  const queue = db.select({ repo: epics.repo, issue: epics.issue }).from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all();
  const shown = db.select().from(epics).where(inArray(epics.status, ['running', 'needs_human'])).orderBy(asc(epics.id)).all();
  const lastExecution = (epicId: number) => db.select({ id: executions.executionId }).from(executions).where(eq(executions.epicId, epicId)).orderBy(desc(executions.startedAt), sql`rowid desc`).limit(1).get()?.id ?? null;
  const done = db.select({ id: epics.id, repo: epics.repo, issue: epics.issue, prNumber: epics.prNumber, finishedAt: epics.finishedAt }).from(epics).where(eq(epics.status, 'ready_for_test')).orderBy(desc(epics.finishedAt)).limit(5).all()
    .map(({ id, ...rest }) => ({ ...rest, executionId: lastExecution(id) }));
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
    epics: shown.map((e) => ({
      repo: e.repo,
      issue: e.issue,
      status: e.status as 'running' | 'needs_human',
      stage: e.stage,
      round: e.round,
      maxReviews,
      blockers: latestBlockers(db, e.id).length,
      stageSince: e.stageStartedAt ?? e.startedAt ?? now,
      lastActivityAt: e.lastActivityAt,
      issueUrl: `https://github.com/${e.repo}/issues/${e.issue}`,
      prUrl: e.prNumber === null ? null : `https://github.com/${e.repo}/pull/${e.prNumber}`,
      lastError: e.lastError,
      needsHumanReason: e.needsHumanReason,
      slices: slices(e.repo, e.issue),
      executionId: lastExecution(e.id),
    })),
  };
}
