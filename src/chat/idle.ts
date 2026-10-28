import type { Clock } from '../orchestration/clock.ts';

export const IDLE_EXIT_MS = 60_000;

/**
 * The host's exit rule: it ends `afterMs` after the later of its start and the last client leaving, as long as no
 * session is live. A client arriving or a session living cancels the countdown; `recheck()` re-arms it when the live count drops.
 */
export function idleExit({ clock, afterMs = IDLE_EXIT_MS, live, exit }: { clock: Clock; afterMs?: number; live: () => number; exit: () => Promise<void> }) {
  let clients = 0;
  let cancel: (() => void) | undefined;
  const arm = () => {
    cancel?.();
    cancel = clients === 0 && live() === 0 ? clock.after(afterMs, exit) : undefined;
  };
  arm();
  return {
    joined: () => void (clients++, arm()),
    left: () => void (clients--, arm()),
    recheck: arm,
    stop: () => cancel?.(),
  };
}
