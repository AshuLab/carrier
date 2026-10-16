import { readdirSync, realpathSync, rmSync } from 'node:fs';
import { homedir } from 'node:os';
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

/** Where each CLI keeps its sessions: the config folders the agents run with, as their environment says. */
export type SessionDirs = { claude: string; codex: string };

export const sessionDirsFrom = (env: NodeJS.ProcessEnv = process.env): SessionDirs => ({
  claude: env.CLAUDE_CONFIG_DIR ?? join(homedir(), '.claude'),
  codex: env.CODEX_HOME ?? join(homedir(), '.codex'),
});

const names = (dir: string) => {
  try {
    return readdirSync(dir);
  } catch {
    return []; // absent: that CLI never ran here
  }
};

/**
 * The files of a session, found by its id (docs/research/headless-agents.md): Claude keeps
 * `projects/<cwd with / and . as ->/<id>.jsonl` (plus `<id>/` for what it spawned), Codex
 * `sessions/YYYY/MM/DD/rollout-<date>-<id>.jsonl`. Nothing a CLI reported is used as a path, only the id.
 */
function sessionFiles({ claude, codex }: SessionDirs, ids: string[]): string[] {
  const found: string[] = [];
  const wanted = new Set(ids);
  const projects = join(claude, 'projects');
  for (const folder of names(projects)) {
    for (const entry of names(join(projects, folder))) if (wanted.has(entry.replace(/\.jsonl$/, ''))) found.push(join(projects, folder, entry));
  }
  const sessions = join(codex, 'sessions');
  for (const year of names(sessions)) for (const month of names(join(sessions, year))) for (const day of names(join(sessions, year, month))) {
    for (const file of names(join(sessions, year, month, day))) {
      const id = /^rollout-\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-(.+)\.jsonl$/.exec(file)?.[1];
      if (id !== undefined && wanted.has(id)) found.push(join(sessions, year, month, day, file));
    }
  }
  return found;
}

/**
 * Deletes the execution logs (`orchestrator/logs/executions/<executionId>/`) and the sessions the CLIs saved
 * for them, of epics finished or cancelled 30 days or more before `now`. Never touches SQLite rows nor
 * workspaces; a symlink is removed itself, never followed. Returns the paths deleted.
 */
export function purgeExpired(db: Db, root: string, now: number, sessionDirs: SessionDirs = sessionDirsFrom()): string[] {
  const rows = db
    .select({ executionId: executions.executionId, sessionId: executions.sessionId })
    .from(executions)
    .innerJoin(epics, eq(epics.id, executions.epicId))
    .where(and(inArray(epics.status, finished), isNotNull(epics.finishedAt), lte(epics.finishedAt, now - retentionMs)))
    .all();

  const deleted: string[] = [];
  const remove = (target: string) => {
    rmSync(target, { recursive: true, force: true });
    deleted.push(target);
  };
  const sessionIds = rows.flatMap(({ sessionId }) => (sessionId !== null && safeId.test(sessionId) ? [sessionId] : []));
  if (sessionIds.length > 0) for (const file of sessionFiles(sessionDirs, sessionIds)) remove(file);

  const base = join(root, 'orchestrator');
  let real: string;
  try {
    real = realpathSync(base);
  } catch {
    return deleted; // no orchestrator folder: no logs were ever written
  }
  try {
    // A folder that resolves outside orchestrator/ (symlinked) is not ours to delete from.
    if (!realpathSync(join(base, 'logs', 'executions')).startsWith(real + sep)) return deleted;
  } catch {
    return deleted; // folder absent
  }
  for (const { executionId } of rows) if (safeId.test(executionId)) remove(join(base, 'logs', 'executions', executionId));
  return deleted;
}

/** Purges now and every 24 hours on the injected clock; a failed purge is logged and tried again next day. */
export function startRetention(db: Db, root: string, clock: Clock, sessionDirs?: SessionDirs): () => void {
  let cancel = () => {};
  let stopped = false;
  const run = async () => {
    try {
      const deleted = purgeExpired(db, root, clock.now(), sessionDirs);
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
