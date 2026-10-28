import { join } from 'node:path';
import { createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import { defaults } from '../config/load.ts';
import type { Config } from '../config/schema.ts';
import { installFileLogging } from '../logging/logger.ts';
import { realClock, type Clock } from '../orchestration/clock.ts';
import { acquireLock } from '../storage/lock.ts';
import { claudeChatRunner } from './claude.ts';
import { codexChatRunner } from './codex.ts';
import { realGit, type Git } from './git.ts';
import { createProjects, ghLogin, ghRepos, ghToken, type GithubRepos } from './projects.ts';
import { openChatDatabase } from './db.ts';
import { idleExit } from './idle.ts';
import { chatDirOf, startChatServer } from './server.ts';
import { binaryFound, createSessions, type ChatSessionsDeps } from './sessions.ts';
import { realProcesses, sweepDeadHost, type Processes } from './sweep.ts';

export class HostBusy extends Error {}

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
  /** The config file the host was started from: the projects folder is read from it at each request. Absent: the config the host started with. */
  configPath?: string;
  binaryFound: ChatSessionsDeps['binaryFound'];
  /** The process table and the kill the start-up sweep uses. */
  processes: Processes;
}

const githubTimeoutMs = defaults.limits.githubCallTimeoutSeconds * 1000;
const realGithub: GithubRepos = { repos: (page) => ghRepos(page, githubTimeoutMs), login: () => ghLogin(githubTimeoutMs) };

const realDeps = (): ChatHostDeps => ({ installLogging: installFileLogging, clock: realClock, exit: process.exit, signals: true, runners: { claude: claudeChatRunner(), codex: codexChatRunner() }, env: process.env, git: realGit, token: ghToken, github: realGithub, binaryFound, processes: realProcesses });

/**
 * Runs the chat host: its own lock, log, database and socket under `<root>/chat/`, sharing nothing with the engine's
 * `orchestrator/` folder. Throws HostBusy when another host holds the lock. Resolves once the socket answers;
 * the returned `stop()` is the one shutdown (`stop` request, idle exit, signals).
 */
export async function startChatHost(config: Config, overrides: Partial<ChatHostDeps> = {}) {
  const deps = { ...realDeps(), ...overrides };
  const chatDir = chatDirOf(config.root);
  const lock = acquireLock(chatDir);
  if (!lock.ok) throw new HostBusy(`Another chat host is already running on ${chatDir}`);
  deps.installLogging(join(chatDir, 'logs', 'chat-host.log'), config.logLevel);
  const log = createScopedLogger('chat');
  const db = openChatDatabase(join(chatDir, 'chat.db'));
  await sweepDeadHost(db, deps.processes); // the lock is ours, so any recorded process belongs to a host that died
  let closeServer = () => {};
  let idle: ReturnType<typeof idleExit> | undefined;
  const sessions = createSessions({ db, config, clock: deps.clock, runners: deps.runners, env: deps.env, git: deps.git, binaryFound: deps.binaryFound, onLiveChange: () => idle?.recheck() });
  const projects = createProjects({ git: deps.git, token: deps.token, github: deps.github, config, configPath: deps.configPath });
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
    closeServer = (await startChatServer({ chatDir, startedAt: deps.clock.now(), controls: { ...sessions, cloneRepo: projects.cloneRepo, createProject: projects.createProject, githubRepos: projects.githubRepos }, stop, clients })).close;
  } catch (error) {
    close();
    throw error;
  }
  if (deps.signals) for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) process.on(signal, () => void stop());
  log.info('chat host started', { root: config.root });
  return { stop };
}
