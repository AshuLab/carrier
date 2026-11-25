import { enginePlacesOf } from '../../../config/places.ts';
import type { EpicTarget } from '../args.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlRefused, ControlUnreachable, type CarrierClient } from '../control-client.ts';

// What each refusal code means for the person, and what to do next.
export const refusals: Record<string, (target: string) => string> = {
  'epic.unknown': (target) => `Carrier does not know ${target}. Use the owner/repo#issue that carrier status shows.`,
  'recover.notRunning': (target) => `${target} is not running, so there is nothing to recover. An epic that stopped for a person is resumed with carrier restart.`,
  'recover.agentAlive': (target) => `An agent of ${target} is alive or about to start, so nothing was changed. If the epic does not move, try again in a moment.`,
  'recover.notStarted': (target) => `${target} has not started its first stage yet: the next check launches it.`,
  'recover.nothingToRecover': (target) => `${target} is in a state a recovery does not move (a retry or the next check takes it from here), so nothing was changed.`,
  'recover.engineUnavailable': () => 'Carrier is stopping, still recovering its epics at start, or cannot act now (its agent profile was rejected), so nothing changed.',
  'github.unavailable': () => 'GitHub did not answer, so nothing changed. Try again in a moment.',
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
    const code = error instanceof ControlRefused ? error.code : undefined;
    const words = error instanceof Error ? error.message : String(error);
    throw new CliError(1, (code === undefined ? undefined : refusals[code]?.(`${repo}#${issue}`)) ?? `Carrier refused: ${words}`);
  } finally {
    client.close();
  }
  process.stdout.write(`Recovered ${repo}#${issue}\n`);
  return 0;
}
