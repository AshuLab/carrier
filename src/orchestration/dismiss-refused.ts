import type { TextParams } from './text-params.ts';

/** The words of why `dismissEpic` did nothing more than say no. */
export type DismissRefusal = 'unknown epic' | 'not closed';

/** Why `dismissEpic` did nothing more than say no; the control socket sends `reason` to the client as it is, with the code and the parameters beside it ([ADR 0055](../../docs/adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). */
export class DismissRefused extends Error {
  code: string;
  reason: DismissRefusal;
  params: TextParams;

  // Node strips types: `pnpm typecheck` is what refuses a refusal without its code.
  constructor(code: string, reason: DismissRefusal, params: TextParams = {}) {
    super(reason);
    this.code = code;
    this.reason = reason;
    this.params = params;
  }
}
