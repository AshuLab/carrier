import type { TextParams } from './text-params.ts';

/** Why a reload changed nothing: what a start would print for the file, with the key named; the control socket sends `problem` to the client as it is, with the code and the parameters beside it ([ADR 0055](../../docs/adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). */
export class ReloadRefused extends Error {
  code: string;
  problem: string;
  params: TextParams;

  // Node strips types: `pnpm typecheck` is what refuses a refusal without its code.
  constructor(code: string, problem: string, params: TextParams = {}) {
    super(problem);
    this.code = code;
    this.problem = problem;
    this.params = params;
  }
}
