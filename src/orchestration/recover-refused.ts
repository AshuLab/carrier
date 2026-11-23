/** Why `recoverEpic` did nothing more than say no; the control socket sends `reason` to the client as it is. */
export type RecoverRefusal = 'unknown epic' | 'not running' | 'agent alive' | 'not started' | 'nothing to recover' | 'engine unavailable' | 'github unavailable';
export class RecoverRefused extends Error {
  reason: RecoverRefusal;

  constructor(reason: RecoverRefusal) {
    super(reason);
    this.reason = reason;
  }
}
