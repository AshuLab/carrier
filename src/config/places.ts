import { homedir } from 'node:os';
import { join } from 'node:path';

// Every path inside the Carrier folder is computed here and nowhere else (ADR 0034).
// The top holds only the files a person edits; each process owns one subfolder, split inside by lifecycle.

export const expandHome = (path: string) => (path === '~' || path.startsWith('~/') ? join(homedir(), path.slice(1)) : path);

/** Carrier's home: `CARRIER_HOME`, else `~/.carrier`. */
export const carrierHome = () => process.env.CARRIER_HOME || join(homedir(), '.carrier');

/** The engine's config, `<folder>/engine.json`: where `carrier init` writes it and where `carrier` looks when there is no `--config`. */
export const engineConfigPathOf = (folder = carrierHome()) => join(folder, 'engine.json');

/** The chat's settings, `<folder>/chat.json`; optional. */
export const chatConfigPathOf = (folder = carrierHome()) => join(folder, 'chat.json');

/** The accounts both processes read, `<folder>/providers.json` (ADR 0020). */
export const providersPathOf = (folder = carrierHome()) => join(folder, 'providers.json');

/** The person's projects, `<folder>/projects.json`, read by the app and the chat host and written by both (ADR 0038). */
export const projectsPathOf = (folder = carrierHome()) => join(folder, 'projects.json');

/** Where the engine keeps what it owns. Only the engine writes in `dir`. */
export type EnginePlaces = {
  /** `<folder>/engine`. */
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

export function enginePlacesOf(folder: string): EnginePlaces {
  const dir = join(folder, 'engine');
  const state = join(dir, 'state');
  return { dir, state, socket: controlSocketIn(state), db: join(state, 'carrier.db'), logs: join(dir, 'logs'), repos: join(dir, 'repos'), reviews: join(dir, 'reviews'), worktrees: join(dir, 'worktrees') };
}

/** The chat socket in a chat state folder; the host opens it from the folder it is given. */
export const chatSocketIn = (state: string) => join(state, 'chat.sock');

/** Where the chat host keeps what it owns. Only the chat host writes in `dir`, except the app's copies of attached files. */
export type ChatPlaces = {
  /** `<folder>/chat`. */
  dir: string;
  /** `chat.db`, `chat.sock` and the lock. */
  state: string;
  /** `<state>/chat.sock`. */
  socket: string;
  logs: string;
  /** Session worktrees: `<owner>/<repo>/<name>`. */
  worktrees: string;
  /** The default projects folder (`projectsFolder` in `chat.json` changes it). */
  projects: string;
  /** The app's copies of dropped files not sent yet: `<id>/<name>`, swept after a day. */
  pending: string;
  /** What belongs to one session and goes with it: `<session>/attachments/<id>/<name>`. */
  sessions: string;
};

export function chatPlacesOf(folder = carrierHome()): ChatPlaces {
  const dir = join(folder, 'chat');
  const state = join(dir, 'state');
  return { dir, state, socket: chatSocketIn(state), logs: join(dir, 'logs'), worktrees: join(dir, 'worktrees'), projects: join(dir, 'projects'), pending: join(dir, 'pending'), sessions: join(dir, 'sessions') };
}
