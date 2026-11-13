/** Why a reload changed nothing: what a start would print for the file, with the key named; the control socket sends `problem` to the client as it is. */
export class ReloadRefused extends Error {
  problem: string;

  constructor(problem: string) {
    super(problem);
    this.problem = problem;
  }
}
