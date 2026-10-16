import { realpathSync, rmSync } from 'node:fs';
import { join, sep } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { and, eq, inArray, isNotNull, lte } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';

const DAY = 24 * 60 * 60 * 1000;
export const retentionMs = 30 * DAY;
const log = createScopedLogger('retention');

// Only an epic that is over expires; queued, running, needs_human and repo_removed keep everything.
const finished = ['ready_for_test', 'merged', 'cancelled'] as const;
// Ids come from SQLite but end up in a path: an allowlist keeps `..` and separators out.
const safeId = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;

/**
 * Deletes the execution logs (`logs/executions/<executionId>/`) and the sessions (`sessions/<sessionId>`)
 * under `<root>/orchestrator/` of epics finished or cancelled 30 days or more before `now`.
 * Never touches SQLite rows nor workspaces; a symlink is removed itself, never followed. Returns the paths deleted.
 */
export function purgeExpired(db: Db, root: string, now: number): string[] {
  const rows = db
    .select({ executionId: executions.executionId, sessionId: executions.sessionId })
    .from(executions)
    .innerJoin(epics, eq(epics.id, executions.epicId))
    .where(and(inArray(epics.status, finished), isNotNull(epics.finishedAt), lte(epics.finishedAt, now - retentionMs)))
    .all();

  const base = join(root, 'orchestrator');
  let real: string;
  try {
    real = realpathSync(base);
  } catch {
    return []; // nothing was ever written
  }
  const deleted: string[] = [];
  const remove = (parent: string, id: string | null) => {
    if (id === null || !safeId.test(id)) return;
    try {
      // A parent that resolves outside orchestrator/ (symlinked folder) is not ours to delete from.
      if (!realpathSync(join(base, parent)).startsWith(real + sep)) return;
    } catch {
      return; // folder absent
    }
    const target = join(base, parent, id);
    rmSync(target, { recursive: true, force: true });
    deleted.push(target);
  };
  for (const { executionId, sessionId } of rows) {
    remove(join('logs', 'executions'), executionId);
    remove('sessions', sessionId);
  }
  return deleted;
}

/** Purges now and every 24 hours on the injected clock; a failed purge is logged and tried again next day. */
export function startRetention(db: Db, root: string, clock: Clock): () => void {
  let cancel = () => {};
  let stopped = false;
  const run = async () => {
    try {
      const deleted = purgeExpired(db, root, clock.now());
      if (deleted.length > 0) log.info('purged expired logs and sessions', { count: deleted.length });
    } catch (error) {
      log.error('retention purge failed', error);
    }
    if (!stopped) cancel = clock.after(DAY, run);
  };
  void run();
  return () => {
    stopped = true;
    cancel();
  };
}
