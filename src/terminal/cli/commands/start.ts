import { spawn } from 'node:child_process';
import { closeSync, mkdirSync, openSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import type { Config } from '../../../config/schema.ts';
import { CliError } from '../cli-error.ts';
import { connectControl } from '../control-client.ts';

const POLL_MS = 250;
const GIVE_UP_MS = 15_000;
const LOG_TAIL_LINES = 20;

/** The pid of the Carrier answering on this socket, if one does. */
async function pidAt(socketPath: string): Promise<number | undefined> {
  try {
    const client = await connectControl(socketPath, { timeoutMs: POLL_MS });
    client.close();
    return client.hello.pid;
  } catch {
    return undefined;
  }
}

/**
 * Starts Carrier as a detached run (ADR 0010): the same program with `--config`, in its own session, its output in
 * `orchestrator/logs/start.log`. Returns once the control socket answers; a Carrier already answering is left alone.
 * `configPath` is absolute: the child does not share this process's working directory.
 */
export async function startCommand(config: Config, configPath: string): Promise<number> {
  const orchestratorDir = join(config.root, 'orchestrator');
  const socketPath = join(orchestratorDir, 'control.sock');
  const logPath = join(orchestratorDir, 'logs', 'start.log');

  const running = await pidAt(socketPath);
  if (running !== undefined) {
    process.stdout.write(`Carrier is already running (pid ${running}).\n`);
    return 0;
  }

  mkdirSync(join(orchestratorDir, 'logs'), { recursive: true });
  const logFd = openSync(logPath, 'w'); // replaced at each start
  let exited = false;
  const child = spawn(process.execPath, [...process.execArgv, process.argv[1]!, '--config', configPath], { detached: true, stdio: ['ignore', logFd, logFd] });
  closeSync(logFd);
  child.on('exit', () => (exited = true));
  child.unref();

  for (const deadline = Date.now() + GIVE_UP_MS; exited === false && Date.now() < deadline; await sleep(POLL_MS)) {
    const pid = await pidAt(socketPath);
    if (pid !== undefined) {
      process.stdout.write(`Carrier is running (pid ${pid}). Log: ${logPath}\n`);
      return 0;
    }
  }
  const tail = readFileSync(logPath, 'utf8').trimEnd().split('\n').slice(-LOG_TAIL_LINES);
  throw new CliError(1, exited ? 'Carrier exited before it was ready:' : `Carrier did not answer within ${GIVE_UP_MS / 1000} seconds:`, ...tail, `Log: ${logPath}`);
}
