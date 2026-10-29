import { join } from 'node:path';

/** Where the engine keeps what it owns, inside the Carrier folder (ADR 0016). Only Carrier writes in `dir`. */
export type EnginePlaces = {
  /** `<folder>/engine`: the engine's own folder. */
  dir: string;
  /** The database, the control socket, the lock, the execution results and `forge-cwd/<owner>/<name>`. */
  state: string;
  /** `orchestrator.log`, `executions/<executionId>/` and the start logs. */
  logs: string;
  /** The engine's clones: `<owner>/<repo>`. */
  repos: string;
  /** The review checkouts. */
  reviews: string;
  /** Carrier's own place for an epic's worktree; the engine does not create it. */
  worktrees: string;
};

/** The engine's places, all computed from the Carrier folder here and nowhere else. */
export function enginePlacesOf(folder: string): EnginePlaces {
  const dir = join(folder, 'engine');
  return { dir, state: join(dir, 'state'), logs: join(dir, 'logs'), repos: join(dir, 'repos'), reviews: join(dir, 'reviews'), worktrees: join(dir, 'worktrees') };
}
