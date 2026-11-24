import { carrierHome, enginePlacesOf } from '../config/places.ts';
import type { TextParams } from '../orchestration/text-params.ts';
import { connectControl, ControlRefused, ControlUnreachable } from '../terminal/cli/control-client.ts';

/** What the running engine did with a file that was just written (ADR 0053): it read it, it kept its settings for a reason, or no engine answers (it reads the file when it starts). */
export type EngineAnswer =
  | { engine: 'applied' | 'notRunning' }
  | { engine: 'refused'; engineReason: { error: string; code?: string; params: TextParams } };

/** Asks the engine of the Carrier folder to read `engine.json` and `providers.json` again, and says what it answered. Never throws: the file is written either way. */
export async function reloadEngine(folder = carrierHome()): Promise<EngineAnswer> {
  const silent = { engine: 'refused', engineReason: { error: 'The engine did not answer, so it may not have applied the change', code: 'providers.engineNoAnswer', params: {} } } as const;
  let client;
  try {
    client = await connectControl(enginePlacesOf(folder).socket, { timeoutMs: 3000 });
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    return error.reason === 'not-running' ? { engine: 'notRunning' } : silent;
  }
  try {
    // an engine that predates `reload` reads the files when it restarts
    if (client.hello.capabilities.includes('reload') === false) return { engine: 'notRunning' };
    await client.request('reload');
    return { engine: 'applied' };
  } catch (error) {
    if (error instanceof ControlRefused) return { engine: 'refused', engineReason: { error: error.message, ...(error.code !== undefined && { code: error.code }), params: error.params } };
    return silent;
  } finally {
    client.close();
  }
}

/** What a request that wrote `providers.json` answers: the part it saved, and what the engine did with the file. */
export const withEngine = async <T extends object>(written: T, folder = carrierHome()) => ({ ...written, ...(await reloadEngine(folder)) });
