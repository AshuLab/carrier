import { chmodSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { configureUniversalLogger, createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import { enginePlacesOf } from '../../config/engine-places.ts';
import type { Config } from '../../config/schema.ts';
import { resolveRepoConfig } from '../../config/resolve.ts';
import type { AgentRunner } from '../../execution/agent-runner.ts';
import { GitWorkspaces, profileToken, type GitWorkspacesOptions } from '../../execution/git-workspaces.ts';
import type { Workspaces } from '../../execution/workspaces.ts';
import { epicOf } from '../../control/epic.ts';
import { eventsOf, lastEventOf } from '../../control/events.ts';
import { fileDiff, filesOf } from '../../control/files.ts';
import { inheritedConfigDirs, sessionsOf } from '../../control/sessions.ts';
import { startControlServer, version } from '../../control/server.ts';
import { listAvailableRepos } from '../../integrations/available-repos.ts';
import { forgeCwd } from '../../integrations/forge-cwd.ts';
import { GhGitHub, type GhGitHubOptions } from '../../integrations/github.ts';
import { installFileLogging } from '../../logging/logger.ts';
import { realClock, type Clock } from '../../orchestration/clock.ts';
import { createEngine } from '../../orchestration/engine.ts';
import { AuthError, type GitHub } from '../../orchestration/github.ts';
import { ReloadRefused } from '../../orchestration/reload-refused.ts';
import { sessionDirsFrom, type SessionDirs } from '../../orchestration/retention.ts';
import { renderDashboard } from '../dashboard/dashboard.ts';
import { startInteractivePanel } from '../dashboard/interactive.ts';
import { tailExecution } from '../dashboard/logs.ts';
import { startPanel, type PanelOutput } from '../dashboard/panel.ts';
import { buildSnapshot, watchedOf } from '../../status/snapshot.ts';
import { profileCredentials, type CredentialsOptions } from '../../harnesses/credentials.ts';
import { HostAgentRunner, type HostRunnerOptions } from '../../harnesses/host-runner.ts';
import { openDatabase } from '../../storage/db.ts';
import { acquireLock } from '../../storage/lock.ts';
import { CliError } from './cli-error.ts';
import { stopOnSigint } from './interrupt.ts';
import { openUrl } from './open-url.ts';

export class InstanceBusy extends Error {}

/** Everything that touches the outside world, replaceable so a test runs the whole startup without GitHub or agents. */
export interface CarrierDeps {
  installLogging: (file: string, level: LogLevel) => void;
  /** Applies the log level of a reloaded config to the logging `installLogging` set up. */
  setLogLevel: (level: LogLevel) => void;
  clock: Clock;
  makeGitHub: (options: GhGitHubOptions) => GitHub;
  makeWorkspaces: (options: GitWorkspacesOptions) => Workspaces;
  makeRunner: (options: HostRunnerOptions) => AgentRunner;
  mint: NonNullable<CredentialsOptions['mint']>;
  botId?: CredentialsOptions['botId'];
  sessionDirs: SessionDirs;
  /** The repos the gh login can push to, for the app's "add a repo"; rejects when GitHub cannot be read. */
  listRepos: (page: number, timeoutMs: number) => ReturnType<typeof listAvailableRepos>;
  panelOut: PanelOutput;
  panelIntervalMs?: number;
  onSigint: (...args: Parameters<typeof stopOnSigint>) => () => Promise<void>;
  /** The engine is up, before the panel takes the screen: the moment to say so. Not called when the startup fails. */
  onArrived?: () => void;
  /** Where keys come from; the panel takes them only when this and the panel's output are both a terminal. */
  stdin?: Parameters<typeof startInteractivePanel>[0]['stdin'];
  /** Opens a GitHub page in the browser. */
  openUrl: (url: string) => void;
  /** The `q` key: ends the process the same way Ctrl+C would. */
  quit: () => void;
}

const realDeps = (): CarrierDeps => ({
  installLogging: installFileLogging,
  setLogLevel: (minLevel) => configureUniversalLogger({ minLevel }),
  clock: realClock,
  makeGitHub: (options) => new GhGitHub(options),
  makeWorkspaces: (options) => new GitWorkspaces(options),
  makeRunner: (options) => new HostAgentRunner(options),
  mint: (profile, repo) => profileToken(profile)(repo),
  sessionDirs: sessionDirsFrom(),
  listRepos: listAvailableRepos,
  panelOut: process.stdout,
  onSigint: stopOnSigint,
  stdin: process.stdin,
  openUrl,
  quit: () => process.kill(process.pid, 'SIGINT'),
});

/**
 * Starts carrier on a validated config and the Carrier folder it keeps its files in: the instance lock, file logging, the engine with the real GitHub (the
 * orchestrator's profile, through Forge), workspaces and the runner of each harness, the panel, and Ctrl+C.
 * `loadConfig` produces the next config from the same config path and Carrier folder it started with (`loadConfigFile` in production): a reload calls it.
 * Throws InstanceBusy when another carrier holds the folder's `engine/state/`.
 */
export async function startCarrier(started: Config, folder: string, loadConfig: () => Config, overrides: Partial<CarrierDeps> = {}) {
  let config = started; // replaced by a reload; everything that follows the settings reads it where it is used
  const deps = { ...realDeps(), ...overrides };
  const places = enginePlacesOf(folder);
  // First side effect of startup: one instance per Carrier folder.
  const lock = acquireLock(places.state);
  if (!lock.ok) throw new InstanceBusy(`Another carrier instance is already running on ${places.state}`);
  mkdirSync(places.logs, { recursive: true });
  chmodSync(places.logs, 0o700); // execution output is for the user only
  // From here on console.* goes to the log file; the terminal is for the panel.
  deps.installLogging(join(places.logs, 'orchestrator.log'), config.logLevel);
  createScopedLogger('cli').info('carrier started', { folder, repos: config.repos.length });

  const startedAt = deps.clock.now();
  const db = openDatabase(places.db);
  const repos = config.repos.map((repo) => resolveRepoConfig(config, repo));
  // Profiles are looked up by name when used, so a reload reaches the next token, clone and GitHub call; one removed while an epic names it fails that run naming it.
  const declared = (name: string) => {
    const profile = config.profiles[name];
    if (!profile) throw new Error(`profile "${name}" is not declared`);
    return profile;
  };
  // Git over the network (clone, fetch) runs as the repo's author profile.
  const authorProfile = (repo: string) => declared(repos.find((r) => r.name === repo)!.agents.author.profile);
  const timeoutMs = () => config.limits.githubCallTimeoutSeconds * 1000;
  const github = deps.makeGitHub({
    get profile() {
      return declared(config.orchestratorProfile);
    },
    cwd: forgeCwd(places),
    get timeoutMs() {
      return timeoutMs();
    },
  });
  const engine = createEngine({
    db,
    clock: deps.clock,
    github,
    workspaces: deps.makeWorkspaces({ places, token: async (repo) => deps.mint(authorProfile(repo), repo) }),
    runner: deps.makeRunner({ credentials: profileCredentials({ profiles: () => config.profiles, mint: deps.mint, botId: deps.botId }) }),
    repos,
    settings: () => ({
      pollIntervalMs: config.pollIntervalMinutes * 60_000,
      maxConcurrentEpics: config.limits.maxConcurrentEpics,
      maxReviews: config.limits.maxReviews,
      maxExecutionRetries: config.limits.maxExecutionRetries,
      maxExecutionHours: config.limits.maxExecutionHours,
    }),
    places,
    sessionDirs: deps.sessionDirs,
  });
  let stopPanel = () => {}; // the panel starts once the engine is up
  let stopControl = () => {};
  const close = () => {
    stopControl(); // before the lock goes: a socket without the lock is what a takeover looks like
    stopPanel();
    engine.stop();
    db.$client.close();
    lock.release();
  };
  // Before the engine starts: its recovery may launch agents already, and Ctrl+C has to stop them.
  const shutdown = deps.onSigint({ engine, close });
  try {
    await engine.start();
  } catch (error) {
    await engine.shutdown(); // recovery may have launched agents already
    close();
    throw error;
  }
  // Only now: until the engine is up the terminal belongs to whoever is waiting for it (the "Starting…" spinner).
  deps.onArrived?.();
  const snapshot = () => {
    const limit = github.rateLimit();
    return buildSnapshot(db, {
      now: deps.clock.now(),
      maxConcurrentEpics: config.limits.maxConcurrentEpics,
      maxReviews: config.limits.maxReviews,
      finishedWindowDays: config.finishedWindowDays,
      startedAt,
      repos: repos.length,
      nextCheckAt: engine.nextPollAt,
      problem: engine.error instanceof AuthError ? `authentication error for profile ${engine.error.profile}` : engine.error ? 'GitHub is unavailable: it will be tried again' : null,
      paused: engine.paused,
      slices: engine.slices,
      version,
      pollIntervalMs: config.pollIntervalMinutes * 60_000,
      rateLimit: limit && { ...limit, profile: 'orchestrator' },
      watched: watchedOf(repos, engine.lastCheck),
      lastEvent: (executionId) => lastEventOf(db, executionId),
    });
  };
  const controls = {
    poll: () => engine.pollNow(),
    setPaused: (paused: boolean) => engine.setPaused(paused),
    open: deps.openUrl,
    quit: deps.quit,
    logs: (id: string, count: number) => tailExecution(places.logs, id, count),
    sessions: (repo: string, issue: number) => sessionsOf(db, repo, issue, inheritedConfigDirs()),
    events: (executionId: string, after: number, limit: number) => eventsOf(db, executionId, after, limit),
    epic: (repo: string, issue: number) => epicOf(db, repo, issue),
    files: (repo: string, issue: number, executionId?: string) => filesOf(db, places.repos, repo, issue, executionId),
    fileDiff: (repo: string, issue: number, section: string, path: string) => fileDiff(db, places.repos, repo, issue, section, path),
    availableRepos: (page: number) => deps.listRepos(page, timeoutMs()),
    resumeEpic: (repo: string, issue: number, chosen: { author?: string; reviewer?: string }) => engine.resumeEpic(repo, issue, chosen),
    reload: () =>
      engine.reload(() => {
        try {
          config = loadConfig();
        } catch (error) {
          if (error instanceof CliError) throw new ReloadRefused(error.lines.join('\n')); // what a start prints for the file
          throw error;
        }
        deps.setLogLevel(config.logLevel);
      }),
  };
  stopControl = (await startControlServer({ stateDir: places.state, snapshot, startedAt, controls, stop: shutdown })).close;
  const detail = (repo: string, issue: number) => controls.sessions(repo, issue)?.sessions ?? null;
  // With a terminal on both sides the panel takes keys; otherwise it only draws (or writes plain lines).
  stopPanel =
    deps.panelOut.isTTY && deps.stdin?.isTTY
      ? startInteractivePanel({
          snapshot,
          out: deps.panelOut,
          stdin: deps.stdin,
          intervalMs: deps.panelIntervalMs,
          now: () => deps.clock.now(),
          controls: { ...controls, detail },
        })
      : startPanel(snapshot, deps.panelOut, deps.panelIntervalMs, (s, columns) => renderDashboard(s, { columns, detail }));
  return { engine, db, close };
}
