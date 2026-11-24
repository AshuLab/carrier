import type { TextParams } from './text-params.ts';

/** The words of why `resumeEpic` did nothing more than say no. */
export type ResumeRefusal = 'unknown epic' | 'not stopped' | 'github unavailable' | 'did not restart' | 'unknown option' | 'no such role' | 'no pull request' | 'pull request not open' | 'pull request head changed' | 'extra rounds need a stage' | 'extra rounds need a review limit';

/** Why `resumeEpic` did nothing more than say no; the control socket sends `reason` to the client as it is, with the code and the parameters beside it ([ADR 0055](../../docs/adr/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). */
export class ResumeRefused extends Error {
  code: string;
  reason: ResumeRefusal;
  params: TextParams;

  // Node strips types: `pnpm typecheck` is what refuses a refusal without its code.
  constructor(code: string, reason: ResumeRefusal, params: TextParams = {}) {
    super(reason);
    this.code = code;
    this.reason = reason;
    this.params = params;
  }
}
