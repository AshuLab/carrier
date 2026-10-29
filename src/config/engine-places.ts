import { join } from 'node:path';

/** Where the engine keeps what it owns, inside the Carrier folder (ADR 0016). Only Carrier writes in `dir`. */
export type EnginePlaces = {
  /** `<folder>/engine`: the engine's own folder. */
  dir: string;
  /** The database, the control socket, the lock, the execution results and `forge-cwd/<owner>/<name>`. */
  state: string;
  /** `<state>/control.sock`. */
  socket: string;
  /** `<state>/carrier.db`. */
  db: string;
  /** `orchestrator.log`, `executions/<executionId>/` and the start logs. */
  logs: string;
  /** The engine's clones: `<owner>/<repo>`. */
  repos: string;
  /** The review checkouts. */
  reviews: string;
  /** Carrier's own place for an epic's worktree; the engine does not create it. */
  worktrees: string;
};

/** The control socket in an engine state folder; the server opens it from the folder it is given. */
export const controlSocketIn = (state: string) => join(state, 'control.sock');

/** The engine's places, all computed from the Carrier folder here and nowhere else. */
export function enginePlacesOf(folder: string): EnginePlaces {
  const dir = join(folder, 'engine');
  const state = join(dir, 'state');
  return { dir, state, socket: controlSocketIn(state), db: join(state, 'carrier.db'), logs: join(dir, 'logs'), repos: join(dir, 'repos'), reviews: join(dir, 'reviews'), worktrees: join(dir, 'worktrees') };
}
