/** Why `resumeEpic` did nothing more than say no; the control socket sends `reason` to the client as it is. */
export type ResumeRefusal = 'unknown epic' | 'not stopped' | 'github unavailable' | 'did not restart' | 'unknown option' | 'no such role' | 'no pull request' | 'pull request not open' | 'pull request head changed' | 'extra rounds need a stage' | 'extra rounds need a review limit';
export class ResumeRefused extends Error {
  reason: ResumeRefusal;

  constructor(reason: ResumeRefusal) {
    super(reason);
    this.reason = reason;
  }
}
