import { spawn } from 'node:child_process';
import { closeSync, mkdirSync, openSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { CliError } from './cli-error.ts';
import { connectControl } from './control-client.ts';

const POLL_MS = 250;
const GIVE_UP_MS = 15_000;
const LOG_TAIL_LINES = 20;

/** The pid of whoever answers on this socket, if one does. */
export async function pidAt(socketPath: string): Promise<number | undefined> {
  try {
    const client = await connectControl(socketPath, { timeoutMs: POLL_MS });
    client.close();
    return client.hello.pid;
  } catch {
    return undefined;
  }
}

/**
 * Starts this program as a detached run (ADR 0010): in its own session, its output in `logPath` (replaced at each start).
 * Returns the pid once `socketPath` answers; throws a CliError with the end of the log when it exits or stays silent.
 * `args` are absolute where they name files: the child does not share this process's working directory.
 */
export async function startDetached({ label, args, socketPath, logPath }: { label: string; args: string[]; socketPath: string; logPath: string }): Promise<number> {
  mkdirSync(dirname(logPath), { recursive: true });
  const logFd = openSync(logPath, 'w');
  let exited = false;
  const child = spawn(process.execPath, [...process.execArgv, process.argv[1]!, ...args], { detached: true, stdio: ['ignore', logFd, logFd] });
  closeSync(logFd);
  child.on('exit', () => (exited = true));
  child.unref();

  for (const deadline = Date.now() + GIVE_UP_MS; exited === false && Date.now() < deadline; await sleep(POLL_MS)) {
    const pid = await pidAt(socketPath);
    if (pid !== undefined) return pid;
  }
  const tail = readFileSync(logPath, 'utf8').trimEnd().split('\n').slice(-LOG_TAIL_LINES);
  throw new CliError(1, exited ? `${label} exited before it was ready:` : `${label} did not answer within ${GIVE_UP_MS / 1000} seconds:`, ...tail, `Log: ${logPath}`);
}
