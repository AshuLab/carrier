import { join } from 'node:path';
import { createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import { carrierHome } from '../config/default-path.ts';
import { installFileLogging } from '../logging/logger.ts';
import { realClock, type Clock } from '../orchestration/clock.ts';
import { acquireLock } from '../storage/lock.ts';
import { claudeChatRunner } from './claude.ts';
import { codexChatRunner } from './codex.ts';
import { chatConfigProblem, chatDirOf, chatLogsOf, chatStateOf, readChatConfig, type ChatSettings } from './config.ts';
import { realGit, type Git } from './git.ts';
import { createProjects, ghBranches, ghLogin, ghRepos, ghToken, type GithubRepos } from './projects.ts';
import { openChatDatabase } from './db.ts';
import { idleExit } from './idle.ts';
import { startChatServer } from './server.ts';
import { realProbes, type HealthProbes } from './health.ts';
import { binaryFound, createSessions, type ChatSessionsDeps, type SessionAges } from './sessions.ts';
import { realProcesses, sweepDeadHost, type Processes } from './sweep.ts';

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
  /** The runner of each harness. */
  runners: ChatSessionsDeps['runners'];
  env: NodeJS.ProcessEnv;
  git: Git;
  /** The token of the person's `gh` login, for the clones. */
  token: () => Promise<string>;
  /** The person's GitHub repositories and login, for the list. */
  github: GithubRepos;
  binaryFound: ChatSessionsDeps['binaryFound'];
  probes: HealthProbes;
  /** The process table and the kill the start-up sweep uses. */
  processes: Processes;
}

const realGithub = ({ githubCallTimeoutSeconds }: ChatSettings): GithubRepos => ({
  repos: (page) => ghRepos(page, githubCallTimeoutSeconds * 1000),
  login: () => ghLogin(githubCallTimeoutSeconds * 1000),
  branches: (repo) => ghBranches(repo, githubCallTimeoutSeconds * 1000),
});

const realDeps = (settings: ChatSettings): ChatHostDeps => ({ installLogging: installFileLogging, clock: realClock, exit: process.exit, signals: true, runners: { claude: claudeChatRunner(), codex: codexChatRunner() }, env: process.env, git: realGit, token: ghToken, github: realGithub(settings), binaryFound, probes: realProbes, processes: realProcesses });

/**
 * Runs the chat host from the Carrier folder alone (`CARRIER_HOME`, else `~/.carrier`): its own lock, database and socket under
 * `chat/state/` and its log under `chat/logs/`, sharing nothing with the engine. Its settings are `chat/chat.json`'s, read at start (the
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
  const stateDir = chatStateOf();
  const lock = acquireLock(stateDir);
  if (!lock.ok) throw new HostBusy(`Another chat host is already running on ${chatDirOf()}`);
  deps.installLogging(join(chatLogsOf(), 'chat-host.log'), settings.logLevel);
  const log = createScopedLogger('chat');
  const db = openChatDatabase(join(stateDir, 'chat.db'));
  await sweepDeadHost(db, deps.processes); // the lock is ours, so any recorded process belongs to a host that died
  let closeServer = () => {};
  let idle: ReturnType<typeof idleExit> | undefined;
  // `list` says from the ages in chat.json, read fresh; a wrong file keeps the last ages that were good.
  let ages: SessionAges = settings;
  const currentAges = () => {
    const current = readChatConfig();
    if (current.ok) ages = current.settings;
    return ages;
  };
  const projects = createProjects({ git: deps.git, token: deps.token, github: deps.github, clock: deps.clock });
  const sessions = createSessions({ db, agents: settings.agents, clock: deps.clock, runners: deps.runners, env: deps.env, git: deps.git, projects, binaryFound: deps.binaryFound, probes: deps.probes, ages: currentAges, onLiveChange: () => idle?.recheck() });
  // The clock's pass, at start and every hour while the host runs; the ages are read from chat.json each time, and a wrong file skips the pass.
  let cancelPass = () => {};
  let stopped = false;
  let passInFlight: Promise<void> = Promise.resolve();
  const runPass = async () => {
    try {
      const current = readChatConfig();
      if (current.ok) await sessions.applyClock(current.settings);
      else log.error('the session lifecycle pass was skipped', new Error(chatConfigProblem(carrierHome(), current.errors)));
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
    db.$client.close();
    lock.release();
  };
  let stopping: Promise<void> | undefined;
  const stop = () =>
    (stopping ??= (async () => {
      stopped = true;
      await sessions.closeAll(); // also tells the pass in flight to leave the next session alone
      await passInFlight; // so the database is not closed under a worktree that is half removed
      close();
      log.info('chat host stopped');
      deps.exit(0);
    })());
  idle = idleExit({ clock: deps.clock, afterMs: deps.idleMs, live: sessions.liveCount, exit: stop });
  try {
    const clients = {
      joined: () => void (idle?.joined(), sessions.clientJoined()),
      left: () => void (idle?.left(), sessions.clientLeft()),
    };
    closeServer = (await startChatServer({ stateDir, startedAt: deps.clock.now(), controls: { ...sessions, cloneRepo: projects.cloneRepo, createProject: projects.createProject, githubRepos: projects.githubRepos, repoBranches: projects.repoBranches }, stop, clients })).close;
  } catch (error) {
    close();
    throw error;
  }
  if (deps.signals) for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) process.on(signal, () => void stop());
  await clockPass();
  log.info('chat host started', { folder: carrierHome() });
  return { stop };
}
