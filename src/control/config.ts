import { editBehavior, setWatchedRepos, type BehaviorChanges } from '../config/engine-edit.ts';
import { ReloadRefused } from '../orchestration/reload-refused.ts';
import type { TextParams } from '../orchestration/text-params.ts';

// The `config` capability of the engine's socket (ADR 0053): the requests that change `engine.json`. The file is written by `config/engine-edit.ts`; the engine then runs on it.

/** A request that changes `engine.json`, as `carrier config` reads it from standard input (the socket's request without its `id`). */
export type EngineConfigRequest = { cmd: 'setWatchedRepos'; repos: string[] } | { cmd: 'editBehavior'; changes: BehaviorChanges };

/** What the engine did with the file that was saved: ran on it, kept its settings and says why (a text code, its params and its words), or was not there to be asked. */
export type EngineOutcome = { engine: 'applied' | 'notRunning' } | { engine: 'refused'; reason: { code: string; params: TextParams; error: string } };
export type ConfigReply = { saved: Record<string, unknown> } & EngineOutcome;

/** Writes the file `file` of the Carrier folder `folder`; throws a `ConfigRefused` and leaves it as it was when the change is refused. */
export function writeEngineConfig(request: EngineConfigRequest, file: string, folder: string): { saved: Record<string, unknown> } {
  return request.cmd === 'setWatchedRepos' ? setWatchedRepos(request.repos, file, folder) : editBehavior(request.changes, file, folder);
}

/** The reply once the file is saved: `reload` makes the running engine read it (none: nobody to ask), and a refusal of it leaves the file saved. */
export function withEngine(saved: { saved: Record<string, unknown> }, reload?: () => void): ConfigReply {
  if (reload === undefined) return { ...saved, engine: 'notRunning' };
  try {
    reload();
    return { ...saved, engine: 'applied' };
  } catch (error) {
    if (error instanceof ReloadRefused) return { ...saved, engine: 'refused', reason: { code: error.code, params: error.params, error: error.problem } };
    throw error;
  }
}
