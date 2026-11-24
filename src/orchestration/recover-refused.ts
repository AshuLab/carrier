import type { TextParams } from './text-params.ts';

/** The words of why `recoverEpic` did nothing more than say no. */
export type RecoverRefusal = 'unknown epic' | 'not running' | 'agent alive' | 'not started' | 'nothing to recover' | 'engine unavailable' | 'github unavailable';

/** Why `recoverEpic` did nothing more than say no; the control socket sends `reason` to the client as it is, with the code and the parameters beside it ([ADR 0055](../../docs/adr/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). */
export class RecoverRefused extends Error {
  code: string;
  reason: RecoverRefusal;
  params: TextParams;

  // Node strips types: `pnpm typecheck` is what refuses a refusal without its code.
  constructor(code: string, reason: RecoverRefusal, params: TextParams = {}) {
    super(reason);
    this.code = code;
    this.reason = reason;
    this.params = params;
  }
}
