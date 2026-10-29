import { readdirSync, realpathSync, rmSync } from 'node:fs';
import { homedir } from 'node:os';
import { isAbsolute, join, sep } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { and, eq, inArray, isNotNull, lte } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';

const DAY = 24 * 60 * 60 * 1000;
export const retentionMs = 30 * DAY;
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

const log = createScopedLogger('retention');

// Entries of a folder; absent means that CLI never ran here, anything else (permissions, IO) is logged: a purge that cannot look is not a clean one.
const entries = (dir: string) => {
  try {
    return readdirSync(dir, { withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') log.error('cannot list a session folder', error, { dir });
    return [];
  }
};
// Folders to walk down into: a symlink is never followed out of the CLI's own tree.
const folders = (dir: string) => entries(dir).filter((e) => e.isDirectory()).map((e) => e.name);
const files = (dir: string) => entries(dir).map((e) => e.name);

/**
 * The files of a session, found by its id (docs/research/headless-agents.md): Claude keeps
 * `projects/<cwd with / and . as ->/<id>.jsonl` (plus `<id>/` for what it spawned, only beside its transcript),
 * Codex `sessions/YYYY/MM/DD/rollout-<date>-<id>.jsonl`. Nothing a CLI reported is used as a path, only the id.
 */
function sessionFiles({ claude, codex }: SessionDirs, ids: string[]): string[] {
  const found: string[] = [];
  const wanted = new Set(ids);
  const projects = join(claude, 'projects');
  for (const folder of folders(projects)) {
    const present = files(join(projects, folder));
    for (const entry of present) {
      if (!entry.endsWith('.jsonl') || !wanted.has(entry.slice(0, -'.jsonl'.length))) continue;
      found.push(join(projects, folder, entry));
      const spawned = entry.slice(0, -'.jsonl'.length);
      if (present.includes(spawned)) found.push(join(projects, folder, spawned));
    }
  }
  const sessions = join(codex, 'sessions');
  for (const year of folders(sessions)) for (const month of folders(join(sessions, year))) for (const day of folders(join(sessions, year, month))) {
    for (const file of files(join(sessions, year, month, day))) {
      const id = /^rollout-\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-(.+)\.jsonl$/.exec(file)?.[1];
      if (id !== undefined && wanted.has(id)) found.push(join(sessions, year, month, day, file));
    }
  }
  return found;
}

/**
 * Deletes the execution logs (`<logs>/executions/<executionId>/`) and the sessions the CLIs saved
 * for them, of epics finished or cancelled 30 days or more before `now`, and the events stored from those logs.
 * Never touches other SQLite rows nor workspaces; a symlink is removed itself, never followed. Returns the paths deleted.
 */
export function purgeExpired(db: Db, logs: string, now: number, sessionDirs: SessionDirs = sessionDirsFrom()): string[] {
  const rows = db
    .select({ executionId: executions.executionId, sessionId: executions.sessionId, configDir: executions.configDir })
    .from(executions)
    .innerJoin(epics, eq(epics.id, executions.epicId))
    .where(and(inArray(epics.status, finished), isNotNull(epics.finishedAt), lte(epics.finishedAt, now - retentionMs)))
    .all();

  // The events are a copy of the logs: they go when the logs do.
  db.transaction((tx) => {
    for (const { executionId } of rows) tx.delete(executionEvents).where(eq(executionEvents.executionId, executionId)).run();
  });

  const deleted: string[] = [];
  const remove = (target: string) => {
    rmSync(target, { recursive: true, force: true });
    deleted.push(target);
  };
  // Each session is looked up in the folder of the execution that wrote it; a row that predates the column uses the environment's own.
  const idsByFolder = new Map<string | null, string[]>();
  for (const { sessionId, configDir } of rows) {
    if (sessionId === null || !safeId.test(sessionId)) continue;
    if (configDir !== null && !isAbsolute(configDir)) {
      log.warn('ignoring a recorded config folder that is not an absolute path', { configDir });
      continue;
    }
    idsByFolder.set(configDir, [...(idsByFolder.get(configDir) ?? []), sessionId]);
  }
  for (const [folder, ids] of idsByFolder) {
    for (const file of sessionFiles(folder === null ? sessionDirs : { claude: folder, codex: folder }, ids)) if (!deleted.includes(file)) remove(file);
  }

  let real: string;
  try {
    real = realpathSync(logs);
  } catch {
    return deleted; // no logs folder: no logs were ever written
  }
  try {
    // A folder that resolves outside the logs folder (symlinked) is not ours to delete from.
    if (!realpathSync(join(logs, 'executions')).startsWith(real + sep)) return deleted;
  } catch {
    return deleted; // folder absent
  }
  for (const { executionId } of rows) if (safeId.test(executionId)) remove(join(logs, 'executions', executionId));
  return deleted;
}

/** Purges now and every 24 hours on the injected clock; a failed purge is logged and tried again next day. */
export function startRetention(db: Db, logs: string, clock: Clock, sessionDirs?: SessionDirs): () => void {
  let cancel = () => {};
  let stopped = false;
  const run = async () => {
    try {
      const deleted = purgeExpired(db, logs, clock.now(), sessionDirs);
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
