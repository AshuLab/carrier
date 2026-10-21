import { join } from 'node:path';
import { createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import type { Config } from '../../config/schema.ts';
import { resolveRepoConfig } from '../../config/resolve.ts';
import type { AgentRunner } from '../../execution/agent-runner.ts';
import { GitWorkspaces, profileToken, type GitWorkspacesOptions } from '../../execution/git-workspaces.ts';
import type { Workspaces } from '../../execution/workspaces.ts';
import { sessionsOf } from '../../control/sessions.ts';
import { startControlServer, version } from '../../control/server.ts';
import { forgeCwd } from '../../integrations/forge-cwd.ts';
import { GhGitHub, type GhGitHubOptions } from '../../integrations/github.ts';
import { installFileLogging } from '../../logging/logger.ts';
import { realClock, type Clock } from '../../orchestration/clock.ts';
import { createEngine } from '../../orchestration/engine.ts';
import { AuthError, type GitHub } from '../../orchestration/github.ts';
import { sessionDirsFrom, type SessionDirs } from '../../orchestration/retention.ts';
import { startInteractivePanel } from '../dashboard/interactive.ts';
import { tailExecution } from '../dashboard/logs.ts';
import { startPanel, type PanelOutput } from '../dashboard/panel.ts';
import { buildSnapshot, watchedOf } from '../../status/snapshot.ts';
import { profileCredentials, type CredentialsOptions } from '../../harnesses/credentials.ts';
import { HostAgentRunner, type HostRunnerOptions } from '../../harnesses/host-runner.ts';
import { openDatabase } from '../../storage/db.ts';
import { acquireLock } from '../../storage/lock.ts';
import { stopOnSigint } from './interrupt.ts';
import { openUrl } from './open-url.ts';

export class InstanceBusy extends Error {}

/** Everything that touches the outside world, replaceable so a test runs the whole startup without GitHub or agents. */
export interface CarrierDeps {
  installLogging: (file: string, level: LogLevel) => void;
  clock: Clock;
  makeGitHub: (options: GhGitHubOptions) => GitHub;
  makeWorkspaces: (options: GitWorkspacesOptions) => Workspaces;
  makeRunner: (options: HostRunnerOptions) => AgentRunner;
  mint: NonNullable<CredentialsOptions['mint']>;
  botId?: CredentialsOptions['botId'];
  sessionDirs: SessionDirs;
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
  clock: realClock,
  makeGitHub: (options) => new GhGitHub(options),
  makeWorkspaces: (options) => new GitWorkspaces(options),
  makeRunner: (options) => new HostAgentRunner(options),
  mint: (profile, repo) => profileToken(profile)(repo),
  sessionDirs: sessionDirsFrom(),
  panelOut: process.stdout,
  onSigint: stopOnSigint,
  stdin: process.stdin,
  openUrl,
  quit: () => process.kill(process.pid, 'SIGINT'),
});

/**
 * Starts carrier on a validated config: the instance lock, file logging, the engine with the real GitHub (the
 * orchestrator's profile, through Forge), workspaces and the runner of each harness, the panel, and Ctrl+C.
 * Throws InstanceBusy when another carrier holds the `orchestrator/` folder.
 */
export async function startCarrier(config: Config, overrides: Partial<CarrierDeps> = {}) {
  const deps = { ...realDeps(), ...overrides };
  const orchestratorDir = join(config.root, 'orchestrator');
  // First side effect of startup: one instance per orchestrator/ folder.
  const lock = acquireLock(orchestratorDir);
  if (!lock.ok) throw new InstanceBusy(`Another carrier instance is already running on ${orchestratorDir}`);
  // From here on console.* goes to the log file; the terminal is for the panel.
  deps.installLogging(join(orchestratorDir, 'logs', 'orchestrator.log'), config.logLevel);
  createScopedLogger('cli').info('carrier started', { root: config.root, repos: config.repos.length });

  const startedAt = deps.clock.now();
  const db = openDatabase(join(orchestratorDir, 'carrier.db'));
  const repos = config.repos.map((repo) => resolveRepoConfig(config, repo));
  const { limits } = config;
  // Git over the network (clone, fetch) runs as the repo's author profile.
  const authorProfile = (repo: string) => config.profiles[repos.find((r) => r.name === repo)!.agents.author.profile]!;
  const engine = createEngine({
    db,
    clock: deps.clock,
    github: deps.makeGitHub({
      profile: config.profiles[config.orchestratorProfile]!,
      cwd: forgeCwd(config.root),
      timeoutMs: limits.githubCallTimeoutSeconds * 1000,
    }),
    workspaces: deps.makeWorkspaces({ root: config.root, token: (repo) => deps.mint(authorProfile(repo), repo) }),
    runner: deps.makeRunner({ credentials: profileCredentials({ profiles: config.profiles, mint: deps.mint, botId: deps.botId }) }),
    repos,
    pollIntervalMs: config.pollIntervalMinutes * 60_000,
    maxConcurrentEpics: limits.maxConcurrentEpics,
    maxReviews: limits.maxReviews,
    maxExecutionRetries: limits.maxExecutionRetries,
    maxExecutionHours: limits.maxExecutionHours,
    root: config.root,
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
  const snapshot = () =>
    buildSnapshot(db, {
      now: deps.clock.now(),
      maxConcurrentEpics: limits.maxConcurrentEpics,
      maxReviews: limits.maxReviews,
      startedAt,
      repos: config.repos.length,
      nextCheckAt: engine.nextPollAt,
      problem: engine.error instanceof AuthError ? `authentication error for profile ${engine.error.profile}` : engine.error ? 'GitHub is unavailable: it will be tried again' : null,
      paused: engine.paused,
      slices: engine.slices,
      version,
      pollIntervalMs: config.pollIntervalMinutes * 60_000,
      watched: watchedOf(repos, engine.lastCheck),
    });
  const controls = {
    poll: () => engine.pollNow(),
    setPaused: (paused: boolean) => engine.setPaused(paused),
    open: deps.openUrl,
    quit: deps.quit,
    logs: (id: string, count: number) => tailExecution(config.root, id, count),
    sessions: (repo: string, issue: number) => sessionsOf(db, repo, issue, deps.sessionDirs),
  };
  stopControl = (await startControlServer({ orchestratorDir, snapshot, startedAt, controls, stop: shutdown })).close;
  // With a terminal on both sides the panel takes keys; otherwise it only draws (or writes plain lines).
  stopPanel =
    deps.panelOut.isTTY && deps.stdin?.isTTY
      ? startInteractivePanel({
          snapshot,
          out: deps.panelOut,
          stdin: deps.stdin,
          intervalMs: deps.panelIntervalMs,
          now: () => deps.clock.now(),
          controls,
        })
      : startPanel(snapshot, deps.panelOut, deps.panelIntervalMs);
  return { engine, db, close };
}
