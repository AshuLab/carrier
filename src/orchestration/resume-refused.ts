/** Why `resumeEpic` did nothing more than say no; the control socket sends `reason` to the client as it is. */
export type ResumeRefusal = 'unknown epic' | 'not stopped' | 'github unavailable' | 'did not restart';
export class ResumeRefused extends Error {
  reason: ResumeRefusal;

  constructor(reason: ResumeRefusal) {
    super(reason);
    this.reason = reason;
  }
}
