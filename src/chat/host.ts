import { join } from 'node:path';
import { createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import { carrierHome, chatPlacesOf } from '../config/places.ts';
import { installFileLogging } from '../logging/logger.ts';
import { realClock, type Clock } from '../orchestration/clock.ts';
import { acquireLock } from '../storage/lock.ts';
import { chatAgentsOf } from './account.ts';
import { sweepPending } from './attachments.ts';
import { claudeChatRunner } from './claude.ts';
import { codexChatRunner } from './codex.ts';
import { chatConfigProblem, editChatSettings, readChatConfig, type ChatSettings } from './config.ts';
import { createDisk, measureWithDu, type Measure } from './disk.ts';
import { realGit, type Git } from './git.ts';
import { realShell, type Shell } from './shell.ts';
import { createProjects, ghBranches, ghLogin, ghRepos, ghToken, type GithubRepos } from './projects.ts';
import { ghPullRequests, type PullRequests } from './pull-requests.ts';
import { openChatDatabase } from './db.ts';
import { idleExit } from './idle.ts';
import { capabilities } from './mcp/capabilities.ts';
import { agents } from './mcp/agents.ts';
import { delegateStart, delegateWait } from './mcp/delegate.ts';
import { history } from './mcp/history.ts';
import { McpSessionRegistry, startMcpServer, type McpServer } from './mcp.ts';
import { startChatServer } from './server.ts';
import { realTextGenerator, type TextGenerator } from './text-generator.ts';
import { realMachine, type Machine } from '../doctor/detect.ts';
import { realProbes, type HealthProbes } from './health.ts';
import { binaryFound, createSessions, IDLE_CLOSE_MS, type ChatSessionsDeps, type LiveSettings } from './sessions.ts';
import { realProcesses, sweepDeadHost, type Processes } from './sweep.ts';
import { createUsage, type UsageDeps } from '../usage/service.ts';
import { realHistoryPorts, realUsagePorts } from '../usage/real.ts';

const HOUR_MS = 3_600_000;

export class HostBusy extends Error {}
/** `chat.json` cannot be read or does not match its schema; the message names the file and each key. */
export class ChatConfigInvalid extends Error {}

/** What touches the outside world, replaceable so a test runs the whole host without installing logging or ending the process. */
export interface ChatHostDeps {
  installLogging: (file: string, level: LogLevel) => void;
  clock: Clock;
  /** Called once the host has closed everything. */
  exit: (code: number) => void;
  idleMs?: number;
  /** Whether SIGINT, SIGTERM and SIGHUP end the host. */
  signals: boolean;
  /** Registers what runs when an exception reaches the top, so the agents are closed before the host exits; with signals, and none given, it is `process.on('uncaughtException')`. */
  onCrash?: (handler: (error: unknown) => void) => void;
  /** The runner of each harness. */
  runners: ChatSessionsDeps['runners'];
  env: NodeJS.ProcessEnv;
  git: Git;
  /** What runs a project's actions. */
  shell: Shell;
  /** How many bytes a folder takes, for the projects' sizes. */
  measure: Measure;
  /** The token of the person's `gh` login, for the clones. */
  token: () => Promise<string>;
  /** The person's GitHub repositories and login, for the list. */
  github: GithubRepos;
  /** The pull requests of the sessions, read with the same login; a test that says nothing has none. */
  pulls?: PullRequests;
  binaryFound: ChatSessionsDeps['binaryFound'];
  probes: HealthProbes;
  machine: Machine;
  /** The process table and the kill the start-up sweep uses. */
  processes: Processes;
  /** Starts the chat MCP's loopback server. */
  startMcp: typeof startMcpServer;
  /** What writes a session's title: the generator `providers.json` names, unless a test replaces it. */
  textGenerator: TextGenerator;
  /** What the `usage` request touches on the machine; the real ports unless a test replaces them (the clock is the host's). */
  usage: Pick<UsageDeps, 'ports' | 'history'>;
}

const realGithub = ({ githubCallTimeoutSeconds }: ChatSettings): GithubRepos => ({
  repos: (page) => ghRepos(page, githubCallTimeoutSeconds * 1000),
  login: () => ghLogin(githubCallTimeoutSeconds * 1000),
  branches: (repo) => ghBranches(repo, githubCallTimeoutSeconds * 1000),
});

const realDeps = (settings: ChatSettings): ChatHostDeps => ({ installLogging: installFileLogging, clock: realClock, exit: process.exit, signals: true, runners: { claude: claudeChatRunner(), codex: codexChatRunner() }, env: process.env, git: realGit, shell: realShell, measure: measureWithDu, token: ghToken, github: realGithub(settings), pulls: ghPullRequests(settings.githubCallTimeoutSeconds * 1000), binaryFound, probes: realProbes, machine: realMachine, processes: realProcesses, startMcp: startMcpServer, usage: { ports: realUsagePorts, history: realHistoryPorts }, textGenerator: realTextGenerator() });

/**
 * Runs the chat host from the Carrier folder alone (`CARRIER_HOME`, else `~/.carrier`): its own lock, database and socket under
 * `chat/state/` and its log under `chat/logs/`, sharing nothing with the engine. Its settings are `chat.json`'s, read at start (the
 * projects folder again at each request, the session ages at each `list` and at each hourly pass); a file that is wrong at start throws
 * ChatConfigInvalid before anything is created. Throws HostBusy when another host holds the lock. Resolves once the socket answers and
 * the first pass of the session clock is done; the returned `stop()` is the one shutdown (`stop` request, idle exit, signals), and it
 * waits for a pass in flight.
 */
export async function startChatHost(overrides: Partial<ChatHostDeps> = {}) {
  const loaded = readChatConfig();
  if (loaded.ok === false) throw new ChatConfigInvalid(chatConfigProblem(carrierHome(), loaded.errors));
  const { settings } = loaded;
  const deps = { ...realDeps(settings), ...overrides };
  const stateDir = chatPlacesOf().state;
  const lock = acquireLock(stateDir);
  if (!lock.ok) throw new HostBusy(`Another chat host is already running on ${chatPlacesOf().dir}`);
  deps.installLogging(join(chatPlacesOf().logs, 'chat-host.log'), settings.logLevel);
  const log = createScopedLogger('chat');
  const db = openChatDatabase(join(stateDir, 'chat.db'));
  await sweepDeadHost(db, deps.processes); // the lock is ours, so any recorded process belongs to a host that died
  let closeServer = () => {};
  const mcpTools = [capabilities, history, agents, delegateStart, delegateWait];
  let mcpServer: McpServer | undefined;
  const mcpRegistry = new McpSessionRegistry(deps.clock);
  let idle: ReturnType<typeof idleExit> | undefined;
  // `list` says from the ages in chat.json, read fresh; a wrong file keeps the last ages that were good.
  let ages: LiveSettings = settings;
  const currentAges = () => {
    const current = readChatConfig();
    if (current.ok) ages = current.settings;
    return ages;
  };
  const usage = createUsage({ ports: { ...deps.usage.ports, clock: deps.clock }, history: deps.usage.history, db, folder: carrierHome(), agents: () => chatAgentsOf(settings.agents), env: deps.env });
  const disk = createDisk({ db, clock: deps.clock, git: deps.git, measure: deps.measure });
  const projects = createProjects({ git: deps.git, token: deps.token, github: deps.github, clock: deps.clock, onCloneChange: () => idle?.recheck() });
  // the last value read, not the file: a conversation names its session several times a second (`list` and the clock pass read the file)
  const idleCloseMs = () => (ages.idleCloseMinutes === undefined ? IDLE_CLOSE_MS : ages.idleCloseMinutes * 60_000);
  const sessions = createSessions({ db, agents: () => chatAgentsOf(settings.agents), idleCloseMs, clock: deps.clock, runners: deps.runners, env: deps.env, git: deps.git, shell: deps.shell, projects, binaryFound: deps.binaryFound, probes: deps.probes, machine: deps.machine, ages: currentAges, pulls: deps.pulls, textGenerator: deps.textGenerator, onLiveChange: () => idle?.recheck(), mcp: { registry: mcpRegistry, url: () => mcpServer?.url, tools: mcpTools.map((tool) => tool.name) } });
  // The clock's pass, at start and every hour while the host runs; the ages are read from chat.json each time, and a wrong file skips the pass.
  let cancelPass = () => {};
  let stopped = false;
  let passInFlight: Promise<void> = Promise.resolve();
  const runPass = async () => {
    sweepPending(deps.clock.now());
    try {
      const current = readChatConfig();
      if (current.ok) {
        ages = current.settings;
        await sessions.applyClock(current.settings);
      } else log.error('the session lifecycle pass was skipped', new Error(chatConfigProblem(carrierHome(), current.errors)));
    } catch (error) {
      log.error('the session lifecycle pass failed', error);
    }
  };
  const clockPass = async () => {
    if (stopped) return;
    passInFlight = runPass();
    await passInFlight;
    if (!stopped) cancelPass = deps.clock.after(HOUR_MS, clockPass);
  };
  const close = () => {
    stopped = true;
    idle?.stop();
    cancelPass();
    closeServer();
    mcpRegistry.revokeAll();
    mcpServer?.close().catch((error) => log.error('closing the chat MCP failed', error));
    db.$client.close();
    lock.release();
  };
  let stopping: Promise<void> | undefined;
  const stop = (code = 0) =>
    (stopping ??= (async () => {
      stopped = true;
      await sessions.closeAll(); // also tells the pass in flight to leave the next session alone
      await projects.stop();
      disk.stop();
      await passInFlight; // so the database is not closed under a worktree that is half removed
      close();
      log.info('chat host stopped');
      deps.exit(code);
    })());
  idle = idleExit({ clock: deps.clock, afterMs: deps.idleMs, live: () => sessions.liveCount() + projects.cloningCount(), exit: stop });
  // The MCP is up before the socket answers; one that cannot bind leaves the host without it, and each session says so.
  try {
    mcpServer = await deps.startMcp({ registry: mcpRegistry, sessions: sessions.mcpView, tools: mcpTools });
  } catch (error) {
    log.error('the chat MCP could not start; sessions open without it', error);
  }
  try {
    const clients = {
      joined: () => void idle?.joined(),
      left: () => void idle?.left(),
    };
    closeServer = (await startChatServer({ stateDir, startedAt: deps.clock.now(), controls: { ...sessions, ...usage, projectDisk: disk.projectDisk, cloneRepo: projects.cloneRepo, cloneProject: projects.cloneProject, projectClones: projects.projectClones, dismissClone: projects.dismissClone, newProject: projects.newProject, createProject: projects.createProject, githubRepos: projects.githubRepos, repoBranches: projects.repoBranches, editChatSettings: ({ changes }) => editChatSettings(changes) }, stop, clients })).close;
  } catch (error) {
    close();
    throw error;
  }
  if (deps.signals) for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) process.on(signal, () => void stop());
  // Node would end at once, and the agents are in their own process groups: they would run on until the next host sweeps them.
  const onCrash = deps.onCrash ?? (deps.signals ? (handler: (error: unknown) => void) => void process.on('uncaughtException', handler) : undefined);
  onCrash?.((error) => {
    log.error('the chat host crashed; closing its sessions before it exits', error);
    setTimeout(() => deps.exit(1), 10_000).unref(); // a stop that hangs still ends the process
    stop(1).catch((failure) => {
      log.error('stopping the chat host after a crash failed', failure);
      deps.exit(1);
    });
  });
  await clockPass();
  log.info('chat host started', { folder: carrierHome() });
  return { stop };
}
