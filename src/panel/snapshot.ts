import { asc, count, desc, eq, inArray } from 'drizzle-orm';
import { latestBlockers } from '../orchestration/blockers.ts';
import type { Db } from '../storage/db.ts';
import { epics } from '../storage/schema.ts';
import type { PanelSnapshot } from './render.ts';

/** What the panel shows, read from SQLite: slots, the queue (oldest first) and each epic that is running or waiting for a person. */
export function buildSnapshot(
  db: Db,
  { now, maxConcurrentEpics, maxReviews, startedAt, repos, nextCheckAt, problem }: { now: number; maxConcurrentEpics: number; maxReviews: number; startedAt: number; repos: number; nextCheckAt: number | null; problem: string | null },
): PanelSnapshot {
  const busy = db.select({ n: count() }).from(epics).where(eq(epics.status, 'running')).get()!.n;
  const queue = db.select({ repo: epics.repo, issue: epics.issue }).from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all();
  const shown = db.select().from(epics).where(inArray(epics.status, ['running', 'needs_human'])).orderBy(asc(epics.id)).all();
  const done = db.select({ repo: epics.repo, issue: epics.issue, prNumber: epics.prNumber, finishedAt: epics.finishedAt }).from(epics).where(eq(epics.status, 'ready_for_test')).orderBy(desc(epics.finishedAt)).limit(5).all();
  return {
    now,
    startedAt,
    repos,
    nextCheckAt,
    problem,
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
    })),
  };
}
