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
import { createProjects, ghLogin, ghRepos, ghToken, type GithubRepos } from './projects.ts';
import { openChatDatabase } from './db.ts';
import { idleExit } from './idle.ts';
import { startChatServer } from './server.ts';
import { binaryFound, createSessions, type ChatSessionsDeps } from './sessions.ts';
import { realProcesses, sweepDeadHost, type Processes } from './sweep.ts';

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
  /** The process table and the kill the start-up sweep uses. */
  processes: Processes;
}

const realGithub = ({ githubCallTimeoutSeconds }: ChatSettings): GithubRepos => ({
  repos: (page) => ghRepos(page, githubCallTimeoutSeconds * 1000),
  login: () => ghLogin(githubCallTimeoutSeconds * 1000),
});

const realDeps = (settings: ChatSettings): ChatHostDeps => ({ installLogging: installFileLogging, clock: realClock, exit: process.exit, signals: true, runners: { claude: claudeChatRunner(), codex: codexChatRunner() }, env: process.env, git: realGit, token: ghToken, github: realGithub(settings), binaryFound, processes: realProcesses });

/**
 * Runs the chat host from the Carrier folder alone (`CARRIER_HOME`, else `~/.carrier`): its own lock, database and socket under
 * `chat/state/` and its log under `chat/logs/`, sharing nothing with the engine. Its settings are `chat/chat.json`'s, read once here
 * (the projects folder again at each request); a file that is wrong throws ChatConfigInvalid before anything is created.
 * Throws HostBusy when another host holds the lock. Resolves once the socket answers;
 * the returned `stop()` is the one shutdown (`stop` request, idle exit, signals).
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
  const sessions = createSessions({ db, agents: settings.agents, clock: deps.clock, runners: deps.runners, env: deps.env, git: deps.git, binaryFound: deps.binaryFound, onLiveChange: () => idle?.recheck() });
  const projects = createProjects({ git: deps.git, token: deps.token, github: deps.github });
  const close = () => {
    idle?.stop();
    closeServer();
    db.$client.close();
    lock.release();
  };
  let stopping: Promise<void> | undefined;
  const stop = () =>
    (stopping ??= (async () => {
      await sessions.closeAll();
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
    closeServer = (await startChatServer({ stateDir, startedAt: deps.clock.now(), controls: { ...sessions, cloneRepo: projects.cloneRepo, createProject: projects.createProject, githubRepos: projects.githubRepos }, stop, clients })).close;
  } catch (error) {
    close();
    throw error;
  }
  if (deps.signals) for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) process.on(signal, () => void stop());
  log.info('chat host started', { folder: carrierHome() });
  return { stop };
}
