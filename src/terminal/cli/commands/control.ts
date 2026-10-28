import { join } from 'node:path';
import type { Config } from '../../../config/schema.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlUnreachable, type CarrierClient } from '../control-client.ts';

export type ControlName = 'stop' | 'pause' | 'resume' | 'check';

const requests = { stop: 'stop', pause: 'pause', resume: 'resume', check: 'checkNow' } as const;
const confirmations = { stop: 'Carrier stopped', pause: 'Intake paused', resume: 'Intake resumed', check: 'Checking GitHub now' } as const;
const STOP_WAIT_MS = 15_000; // the same limit as the app

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Polls until nothing answers on the socket any more; false when it still does after `STOP_WAIT_MS`. */
export async function socketGone(path: string): Promise<boolean> {
  for (const deadline = Date.now() + STOP_WAIT_MS; Date.now() < deadline; await sleep(100)) {
    try {
      (await connectControl(path, { timeoutMs: 500 })).close();
    } catch {
      return true;
    }
  }
  return false;
}

/** `stop`, `pause`, `resume` and `check` over the control socket of the Carrier running on this config's root. Returns the exit code. */
export async function controlCommand(name: ControlName, config: Config): Promise<number> {
  const path = join(config.root, 'orchestrator', 'control.sock');
  let client: CarrierClient;
  try {
    client = await connectControl(path);
    await client.request(requests[name]);
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw new CliError(1, `Carrier refused: ${error instanceof Error ? error.message : String(error)}`);
    if (error.reason === 'incompatible') throw new CliError(2, 'The running Carrier speaks a protocol this command does not (it expects 1). Update one of them.');
    if (error.reason === 'no-answer') throw new CliError(1, `Carrier does not answer on ${path}`);
    if (name === 'stop') {
      process.stdout.write('Carrier is not running\n');
      return 0;
    }
    throw new CliError(1, 'Carrier is not running');
  }
  client.close();
  if (name === 'stop' && (await socketGone(path)) === false) throw new CliError(1, `Carrier still answers on ${path} after ${STOP_WAIT_MS / 1000} seconds`);
  process.stdout.write(`${confirmations[name]}\n`);
  return 0;
}
