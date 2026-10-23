import { join } from 'node:path';
import type { Config } from '../../../config/schema.ts';
import type { PanelSnapshot } from '../../../status/types.ts';
import { renderDashboard } from '../../dashboard/dashboard.ts';
import { connectControl, ControlUnreachable, type CarrierClient } from '../control-client.ts';

const out = (text: string) => process.stdout.write(`${text}\n`);
const err = (text: string) => process.stderr.write(`${text}\n`);

/** Connects to the Carrier running on this config's root; when there is none to use, says why and returns the exit code instead: 1 not running or silent, 2 another protocol. */
export async function attach(config: Config): Promise<CarrierClient | number> {
  try {
    return await connectControl(join(config.root, 'orchestrator', 'control.sock'));
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    if (error.reason === 'incompatible') {
      err(`This carrier speaks control protocol 1; the running one speaks ${error.protocol === undefined ? 'something else' : `protocol ${String(error.protocol)}`}. Update the older one so both match.`);
      return 2;
    }
    err(error.reason === 'no-answer' ? 'Carrier is running but does not answer. Try again, or check its log.' : 'Carrier is not running. Start it with "carrier start".');
    return 1;
  }
}

/** Prints the panel of the running Carrier once. Exit 0 it runs; 1 it is not running or does not answer; 2 it speaks another protocol. */
export async function statusCommand(config: Config): Promise<number> {
  const client = await attach(config);
  if (typeof client === 'number') return client;
  try {
    const snapshot = (await client.request('snapshot')) as PanelSnapshot;
    const tty = process.stdout.isTTY === true;
    out(renderDashboard(snapshot, { color: tty, columns: tty ? process.stdout.columns : 100 }).join('\n'));
    return 0;
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    err('Carrier is running but does not answer. Try again, or check its log.');
    return 1;
  } finally {
    client.close();
  }
}
