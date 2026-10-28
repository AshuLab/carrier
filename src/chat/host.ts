import { join } from 'node:path';
import { createScopedLogger, type LogLevel } from '@ashulab/universal-logger';
import type { Config } from '../config/schema.ts';
import { installFileLogging } from '../logging/logger.ts';
import { realClock, type Clock } from '../orchestration/clock.ts';
import { acquireLock } from '../storage/lock.ts';
import { openChatDatabase } from './db.ts';
import { idleExit } from './idle.ts';
import { chatDirOf, startChatServer } from './server.ts';
import { binaryFound, createSessions, type ChatSessionsDeps } from './sessions.ts';

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
  /** The runner of each harness. None is registered yet: the providers' adapters come with their own slices. */
  runners: ChatSessionsDeps['runners'];
  env: NodeJS.ProcessEnv;
  binaryFound: ChatSessionsDeps['binaryFound'];
}

const realDeps = (): ChatHostDeps => ({ installLogging: installFileLogging, clock: realClock, exit: process.exit, signals: true, runners: {}, env: process.env, binaryFound });

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
  let closeServer = () => {};
  let idle: ReturnType<typeof idleExit> | undefined;
  const sessions = createSessions({ db, config, clock: deps.clock, runners: deps.runners, env: deps.env, binaryFound: deps.binaryFound, onLiveChange: () => idle?.recheck() });
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
    closeServer = (await startChatServer({ chatDir, startedAt: deps.clock.now(), controls: sessions, stop, clients })).close;
  } catch (error) {
    close();
    throw error;
  }
  if (deps.signals) for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) process.on(signal, () => void stop());
  log.info('chat host started', { root: config.root });
  return { stop };
}
