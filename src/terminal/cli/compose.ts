import { chmodSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { configureUniversalLogger, createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import { enginePlacesOf } from '../../config/places.ts';
import type { Config } from '../../config/schema.ts';
import { resolveRepoConfig } from '../../config/resolve.ts';
import type { AgentRunner } from '../../execution/agent-runner.ts';
import { GitWorkspaces, profileToken, type GitWorkspacesOptions } from '../../execution/git-workspaces.ts';
import type { Workspaces } from '../../execution/workspaces.ts';
import { epicOf } from '../../control/epic.ts';
import { eventsOf, lastEventOf } from '../../control/events.ts';
import { cardsMemo, fileDiff, filesOf } from '../../control/files.ts';
import { inheritedConfigDirs, sessionsOf } from '../../control/sessions.ts';
import { startControlServer, version, type Controls } from '../../control/server.ts';
import { listAvailableRepos } from '../../integrations/available-repos.ts';
import { forgeCwd } from '../../integrations/forge-cwd.ts';
import { GhGitHub, type GhGitHubOptions } from '../../integrations/github.ts';
import { installFileLogging } from '../../logging/logger.ts';
import { realClock, type Clock } from '../../orchestration/clock.ts';
import { createEngine } from '../../orchestration/engine.ts';
import { AuthError, type GitHub } from '../../orchestration/github.ts';
import type { QuotaReader } from '../../orchestration/quota.ts';
import { createQuotas } from '../../usage/quotas.ts';
import { realUsagePorts } from '../../usage/real.ts';
import { configProblem } from '../../config/problems.ts';
import { ReloadRefused } from '../../orchestration/reload-refused.ts';
import { sessionDirsFrom, type SessionDirs } from '../../orchestration/retention.ts';
import { renderDashboard } from '../dashboard/dashboard.ts';
import { startInteractivePanel } from '../dashboard/interactive.ts';
import { tailExecution } from '../dashboard/logs.ts';
import { startPanel, type PanelOutput } from '../dashboard/panel.ts';
import { buildSnapshot, watchedOf } from '../../status/snapshot.ts';
import { declaredProfile, profileCredentials, type CredentialsOptions } from '../../harnesses/credentials.ts';
import { HostAgentRunner, type HostRunnerOptions } from '../../harnesses/host-runner.ts';
import { createSkills, type Skills } from '../../harnesses/skills.ts';
import { openDatabase } from '../../storage/db.ts';
import { acquireLock } from '../../storage/lock.ts';
import { CliError, InvalidConfig } from './cli-error.ts';
import { stopOnSigint } from './interrupt.ts';
import { openUrl } from './open-url.ts';

/** How often a panel that writes to something that is not a terminal looks at the snapshot, when the caller gives no interval. */
const PLAIN_PANEL_MS = 10_000;

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
  /** Reads the quota of an account from its provider now, for the wake-up of an epic stopped on its quota. */
  makeQuota: () => QuotaReader;
  /** Whether the harness of a role finds a skill. */
  skills: Skills;
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
  makeQuota: () => {
    const quotas = createQuotas(realUsagePorts);
    return (target) => quotas(target, { refresh: true });
  },
  skills: createSkills(),
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
  let repos = config.repos.map((repo) => resolveRepoConfig(config, repo)); // replaced with the config by a reload
  // Profiles are looked up by name when used, so a reload reaches the next token, clone and GitHub call; one removed while an epic names it fails that run naming it.
  const declared = (name: string) => declaredProfile(config.profiles, name);
  // Git over the network (clone, fetch) runs as the repo's current author profile (a reload that changes it reaches the next clone or fetch of a running epic too).
  // A repo a reload has just removed has none: its epic is parked, and this run fails cleanly instead of reading a missing entry.
  const authorProfile = (repo: string) => {
    const found = repos.find((r) => r.name === repo);
    if (!found) throw new Error(`repo "${repo}" is not in the configuration`);
    return declared(found.agents.author.profile);
  };
  const timeoutMs = () => config.limits.githubCallTimeoutSeconds * 1000;
  const github = deps.makeGitHub({ profile: () => declared(config.orchestratorProfile), cwd: forgeCwd(places), timeoutMs });
  const engine = createEngine({
    db,
    clock: deps.clock,
    github,
    // async: a profile or repo that is gone throws inside authorProfile, and the caller must get a rejection, not a synchronous throw
    workspaces: deps.makeWorkspaces({ places, token: async (repo) => deps.mint(authorProfile(repo), repo) }),
    quota: deps.makeQuota(),
    skills: deps.skills,
    runner: deps.makeRunner({ credentials: profileCredentials({ profiles: () => config.profiles, mint: deps.mint, botId: deps.botId }) }),
    repos: () => repos,
    profileDeclared: (name) => Object.hasOwn(config.profiles, name),
    settings: () => ({
      pollIntervalMs: config.pollIntervalMinutes * 60_000,
      maxConcurrentEpics: config.limits.maxConcurrentEpics,
      maxReviews: config.limits.maxReviews,
      maxLeadRounds: config.limits.maxLeadRounds,
      maxExecutionRetries: config.limits.maxExecutionRetries,
      maxExecutionHours: config.limits.maxExecutionHours,
      idleMinutes: config.limits.idleMinutes,
      autoResume: config.limits.autoResume,
      autoResumeMaxHours: config.limits.autoResumeMaxHours,
      labels: config.labels,
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
      labels: config.labels,
      rateLimit: limit && { ...limit, profile: 'orchestrator' },
      watched: watchedOf(repos, engine.lastCheck),
      lastEvent: (executionId) => lastEventOf(db, executionId),
    });
  };
  const cards = cardsMemo(() => deps.clock.now());
  const controls = {
    poll: () => engine.pollNow(),
    setPaused: (paused: boolean) => engine.setPaused(paused),
    open: deps.openUrl,
    quit: deps.quit,
    logs: (id: string, count: number) => tailExecution(places.logs, id, count),
    sessions: (repo: string, issue: number) => sessionsOf(db, repo, issue, inheritedConfigDirs()),
    events: (executionId: string, after: number, limit: number) => eventsOf(db, executionId, after, limit),
    epic: (repo: string, issue: number) => epicOf(db, repo, issue),
    files: (repo: string, issue: number, executionId?: string) => filesOf(db, places.repos, repo, issue, executionId, cards),
    fileDiff: (repo: string, issue: number, section: string, path: string) => fileDiff(db, places.repos, repo, issue, section, path, cards),
    availableRepos: (page: number) => deps.listRepos(page, timeoutMs()),
    resumeEpic: (repo: string, issue: number, chosen: Parameters<Controls['resumeEpic']>[2]) => engine.resumeEpic(repo, issue, chosen),
    recoverEpic: (repo: string, issue: number) => engine.recoverEpic(repo, issue),
    reload: () =>
      engine.reload(() => {
        try {
          const next = loadConfig();
          const nextRepos = next.repos.map((repo) => resolveRepoConfig(next, repo));
          deps.setLogLevel(next.logLevel); // before anything is swapped: if it throws, the reload changes nothing and says so
          repos = nextRepos;
          config = next;
        } catch (error) {
          if (error instanceof CliError) {
            const words = error.lines.join('\n'); // what a start prints for the file
            const problem = error instanceof InvalidConfig ? error.errors.map(configProblem).find((found) => found !== null) : undefined;
            throw problem ? new ReloadRefused(problem.code, words, problem.params) : new ReloadRefused('config.invalid', words);
          }
          throw error;
        }
      }),
  };
  // Before the recovery: the snapshot and the read requests only read SQLite, and a check or a resume asked meanwhile shares the start's recovery.
  // Until then the snapshot has no next check, which the app and the panel show as starting.
  try {
    stopControl = (await startControlServer({ stateDir: places.state, snapshot, startedAt, controls, stop: shutdown })).close;
    await engine.start();
  } catch (error) {
    await engine.shutdown(); // recovery may have launched agents already
    close();
    throw error;
  }
  // Only now: until the engine is up the terminal belongs to whoever is waiting for it (the "Starting…" spinner).
  deps.onArrived?.();
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
      // Not a terminal (a detached `carrier start` writes to start.log, and nobody watches it): a line per change, looked for every ten seconds, so a state that
      // lasts less than that does not show; a terminal still redraws every second.
      : startPanel(snapshot, deps.panelOut, deps.panelIntervalMs ?? (deps.panelOut.isTTY ? undefined : PLAIN_PANEL_MS), (s, columns) => renderDashboard(s, { columns, detail }));
  return { engine, db, close };
}
