import { enginePlacesOf } from '../../../config/places.ts';
import type { EpicTarget } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlUnreachable, type CarrierClient } from '../control-client.ts';

// What the engine's short refusal means for the person, and what to do next.
const refusals: Record<string, (target: string) => string> = {
  'unknown epic': (target) => `Carrier does not know ${target}. Use the owner/repo#issue that carrier status shows.`,
  'not running': (target) => `${target} is not running, so there is nothing to recover. An epic that stopped for a person is resumed with carrier restart.`,
  'agent alive': (target) => `An agent of ${target} is alive or about to start, so nothing was changed. If the epic does not move, try again in a moment.`,
  'not started': (target) => `${target} has not started its first stage yet: the next check launches it.`,
  'engine unavailable': () => 'Carrier is stopping or cannot act now (its agent profile was rejected), so nothing changed.',
  'github unavailable': () => 'GitHub did not answer, so nothing changed. Try again in a moment.',
};

/** `carrier recover <owner/repo>#<issue>`: asks the engine to continue a running epic whose agent is not alive. Returns the exit code. */
export async function recoverCommand(folder: string, { repo, issue }: EpicTarget): Promise<number> {
  const path = enginePlacesOf(folder).socket;
  let client: CarrierClient;
  try {
    client = await connectControl(path);
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    if (error.reason === 'incompatible') throw new CliError(2, 'The running Carrier speaks a protocol this command does not (it expects 1). Update one of them.');
    if (error.reason === 'no-answer') throw new CliError(1, `Carrier does not answer on ${path}`);
    throw new CliError(1, 'Carrier is not running');
  }
  try {
    // an engine that does not list `recoverEpic` would only answer "invalid request"
    if (client.hello.capabilities.includes('recoverEpic') === false) throw new CliError(1, 'The running Carrier is too old to recover an epic: restart it to get this command.');
    await client.request('recoverEpic', { repo, issue });
  } catch (error) {
    if (error instanceof CliError) throw error;
    if (error instanceof ControlUnreachable) throw new CliError(1, `Carrier does not answer on ${path}`);
    const reason = error instanceof Error ? error.message : String(error);
    throw new CliError(1, refusals[reason]?.(`${repo}#${issue}`) ?? `Carrier refused: ${reason}`);
  } finally {
    client.close();
  }
  process.stdout.write(`Recovered ${repo}#${issue}\n`);
  return 0;
}
