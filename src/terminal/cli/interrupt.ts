import { createScopedLogger } from '@ashulab/universal-logger';

const log = createScopedLogger('cli');

type Target = { engine: { shutdown(): Promise<void> }; close: () => void };
type Options = {
  /** How long the engine gets to stop before the shutdown gives up. */
  timeoutMs?: number;
  exit?: (code: number) => void;
};

async function stopEngine({ engine, close }: Target, timeoutMs: number) {
  let code = 0;
  let timer: NodeJS.Timeout | undefined;
  const limit = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error(`engine did not stop within ${timeoutMs} ms`)), timeoutMs);
  });
  try {
    await Promise.race([engine.shutdown(), limit]);
  } catch (error) {
    log.error('shutdown failed', error);
    code = 1;
  } finally {
    clearTimeout(timer);
    close();
  }
  return code;
}

/**
 * The one shutdown: stop the engine without waiting for stages, then free the instance lock and exit with 0 (1 when the
 * engine failed to stop or did not within `timeoutMs`: its executions stay `running` and the next start recovers them).
 * Callable from anywhere, not only from a signal handler; calling it again returns the shutdown already under way.
 */
export function createShutdown(target: Target, { timeoutMs = 20_000, exit = process.exit }: Options = {}) {
  let running: Promise<void> | undefined;
  const shutdown = () => (running ??= stopEngine(target, timeoutMs).then(exit));
  return Object.defineProperty(shutdown, 'running', { get: () => running !== undefined }) as typeof shutdown & { readonly running: boolean };
}

// Ctrl+C, SIGTERM (kill) and SIGHUP (closed terminal) all run the one shutdown; a second signal while it runs exits at once.
export function stopOnSigint(target: Target, { exit = process.exit, ...options }: Options = {}) {
  const shutdown = createShutdown(target, { ...options, exit });
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP'] as const) {
    process.on(signal, () => (shutdown.running ? exit(130) : void shutdown()));
  }
  return shutdown;
}
