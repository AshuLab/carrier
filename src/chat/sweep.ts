import { execFileSync } from 'node:child_process';
import { eq, isNotNull } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { ChatDb } from './db.ts';
import { sessions } from './schema.ts';

const log = createScopedLogger('chat');

/** The process table and the kill, injected so the sweep is tested without touching a real process. */
export interface Processes {
  /** The command line of a process, or undefined when there is none. */
  commandOf(pid: number): string | undefined;
  /** Whether a process group still has a member. */
  groupAlive(pgid: number): boolean;
  /** Signals a whole group; a group already gone is not an error. */
  signalGroup(pgid: number, signal: 'SIGTERM' | 'SIGKILL'): void;
  sleep(ms: number): Promise<void>;
}

export const realProcesses: Processes = {
  commandOf(pid) {
    try {
      return execFileSync('ps', ['-o', 'command=', '-p', String(pid)], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || undefined;
    } catch {
      return undefined; // ps exits 1 when there is no such process
    }
  },
  groupAlive(pgid) {
    try {
      process.kill(-pgid, 0);
      return true;
    } catch (error) {
      return (error as NodeJS.ErrnoException).code === 'EPERM'; // alive but not ours
    }
  },
  signalGroup(pgid, signal) {
    try {
      process.kill(-pgid, signal);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== 'ESRCH') throw error;
    }
  },
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
};

export const SWEEP_GRACE_MS = 5_000;

/**
 * At host start: ends the agent groups a dead host left running (SIGTERM, then SIGKILL after the grace) and closes their
 * sessions, which stay resumable by their native id. A recorded process whose command is not the recorded one is not
 * ours any more (the pid was reused): it is left alone and only the record is cleared. A group that could not be ended
 * keeps its record so the next start tries again. Returns how many groups it ended.
 */
export async function sweepDeadHost(db: ChatDb, processes: Processes = realProcesses, graceMs = SWEEP_GRACE_MS) {
  let ended = 0;
  for (const found of db.select().from(sessions).where(isNotNull(sessions.pid)).all()) {
    try {
      const { pid, pgid, command } = found;
      const ours = pid !== null && pgid !== null && command !== null && processes.commandOf(pid)?.startsWith(command) === true;
      if (ours && processes.groupAlive(pgid)) {
        processes.signalGroup(pgid, 'SIGTERM');
        for (let waited = 0; waited < graceMs && processes.groupAlive(pgid); waited += 100) await processes.sleep(100);
        if (processes.groupAlive(pgid)) processes.signalGroup(pgid, 'SIGKILL');
        ended++;
        log.info('ended an agent a dead host left running', { sessionId: found.id, pgid });
      }
      db.update(sessions).set({ state: 'idle', pid: null, pgid: null, command: null }).where(eq(sessions.id, found.id)).run();
    } catch (error) {
      log.error('sweeping a session of a dead host failed', error);
    }
  }
  return ended;
}
