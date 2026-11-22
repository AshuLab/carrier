import { execFile } from 'node:child_process';
import { existsSync, realpathSync } from 'node:fs';
import { sep } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { eq } from 'drizzle-orm';
import { carrierHome } from '../config/places.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import { checkFolder } from './folder.ts';
import type { Git } from './git.ts';
import { worktreesDir } from './names.ts';
import { projectSizes } from './schema.ts';
import { listWorktrees } from './worktree.ts';

const log = createScopedLogger('chat');

const DAY = 86_400_000;

/** Bytes a folder takes on disk. */
export type Measure = (folder: string, signal: AbortSignal) => Promise<number>;

/** The real measurer: `du -sk`, which walks the folder and counts the blocks it takes (a hard link once). It exits non-zero when it cannot read a file, but its total still counts what it could. */
export const measureWithDu: Measure = (folder, signal) =>
  new Promise((resolve, reject) => {
    execFile('du', ['-sk', folder], { signal, timeout: 30 * 60_000, encoding: 'utf8' }, (error, stdout) => {
      const kilobytes = Number.parseInt(stdout, 10);
      if (Number.isNaN(kilobytes) === false && signal.aborted === false) return resolve(kilobytes * 1024);
      reject(error ?? new Error('du printed no size'));
    });
  });

export type ProjectFigure = { folder: string; bytes: number | null; measuredAt: number | null; parts: Record<string, number> };
export type ProjectDisk = { projects: ProjectFigure[]; measuring: string[] };

export type DiskDeps = { db: ChatDb; clock: Clock; git: Git; measure: Measure };

/**
 * What projects take on disk. A figure is a project's main clone and its worktrees (those git lists under `worktrees/` that are still there), measured one folder at a time
 * in the background, one project at a time, and kept with when it was taken in `project_sizes`. `projectDisk` answers what is known at once: `stale` queues the projects never
 * measured or measured a day ago or more, `now` queues all it is asked about, and `measuring` says which of them are queued or running.
 */
export function createDisk({ db, clock, git, measure }: DiskDeps) {
  const queue: string[] = [];
  let running: string | undefined;
  const stopping = new AbortController();

  /** The folders of a project: its own, then each worktree under the worktrees folder that is on disk. A folder that is not a repository is only its own. */
  async function foldersOf(folder: string): Promise<string[]> {
    const base = checkFolder(folder, carrierHome());
    const listed = await listWorktrees(git, base).catch(() => []);
    const real = (path: string) => (existsSync(path) ? realpathSync(path) : path);
    const root = real(worktreesDir()) + sep;
    return [base, ...listed.slice(1).map(({ path }) => path).filter((path) => existsSync(path) && real(path).startsWith(root))];
  }

  async function measureProject(folder: string) {
    const parts: Record<string, number> = {};
    for (const part of await foldersOf(folder)) parts[part] = await measure(part, stopping.signal);
    if (stopping.signal.aborted) return;
    const row = { folder, bytes: Object.values(parts).reduce((sum, bytes) => sum + bytes, 0), parts, measuredAt: clock.now() };
    db.insert(projectSizes).values(row).onConflictDoUpdate({ target: projectSizes.folder, set: row }).run();
  }

  async function pump() {
    if (running !== undefined) return;
    for (let next = queue.shift(); next !== undefined; next = queue.shift()) {
      running = next;
      try {
        await measureProject(next);
      } catch (error) {
        if (stopping.signal.aborted === false) log.error('a project could not be measured', error);
      }
    }
    running = undefined;
  }

  return {
    projectDisk({ folders, refresh }: { folders: string[]; refresh?: 'stale' | 'now' }): ProjectDisk {
      const now = clock.now();
      const projects: ProjectFigure[] = [];
      for (const folder of folders) {
        try {
          checkFolder(folder, carrierHome());
        } catch {
          continue; // a folder that is gone or not allowed has no figure to show
        }
        const found = db.select().from(projectSizes).where(eq(projectSizes.folder, folder)).get();
        const due = refresh === 'now' || (refresh === 'stale' && (found === undefined || now - found.measuredAt >= DAY));
        if (due && folder !== running && queue.includes(folder) === false) queue.push(folder);
        projects.push({ folder, bytes: found?.bytes ?? null, measuredAt: found?.measuredAt ?? null, parts: found?.parts ?? {} });
      }
      void pump();
      return { projects, measuring: projects.map((project) => project.folder).filter((folder) => folder === running || queue.includes(folder)) };
    },

    /** Stops the measure that runs and forgets the rest, so nothing is written to a database that is closing. */
    stop() {
      queue.length = 0;
      stopping.abort();
    },
  };
}
