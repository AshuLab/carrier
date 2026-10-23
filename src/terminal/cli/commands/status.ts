import { join } from 'node:path';
import type { Config } from '../../../config/schema.ts';
import type { PanelSnapshot } from '../../../status/types.ts';
import type { SessionsReply } from '../../../control/replies.ts';
import { renderDashboard } from '../../dashboard/dashboard.ts';
import type { Sessions } from '../../dashboard/history.ts';
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

/**
 * An epic's stages over the socket; null when this engine cannot answer (its hello does not list `sessions`, and nothing is sent)
 * or the request fails or answers `unknown epic`: the epic is then drawn without detail, which never breaks the panel.
 */
export async function stagesOf(client: Pick<CarrierClient, 'hello' | 'request'>, repo: string, issue: number): Promise<Sessions | null> {
  if (client.hello.capabilities.includes('sessions') === false) return null;
  try {
    return ((await client.request('sessions', { repo, issue })) as SessionsReply).sessions;
  } catch {
    return null;
  }
}

/** Prints the panel of the running Carrier once. Exit 0 it runs; 1 it is not running or does not answer; 2 it speaks another protocol. */
export async function statusCommand(config: Config): Promise<number> {
  const client = await attach(config);
  if (typeof client === 'number') return client;
  try {
    const snapshot = (await client.request('snapshot')) as PanelSnapshot;
    const tty = process.stdout.isTTY === true;
    // The cards show the stages of running epics only; one print, so one request each.
    const running = snapshot.epics.filter((e) => e.status === 'running');
    const stages = new Map(await Promise.all(running.map(async (e) => [`${e.repo}#${e.issue}`, await stagesOf(client, e.repo, e.issue)] as const)));
    const detail = (repo: string, issue: number) => stages.get(`${repo}#${issue}`) ?? null;
    out(renderDashboard(snapshot, { color: tty, columns: tty ? process.stdout.columns : 100, detail }).join('\n'));
    return 0;
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    err('Carrier is running but does not answer. Try again, or check its log.');
    return 1;
  } finally {
    client.close();
  }
}
