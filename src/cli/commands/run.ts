import { createScopedLogger } from '@ashulab/universal-logger';
import type { Config } from '../../config/schema.ts';
import { CliError } from '../cli-error.ts';
import { InstanceBusy, startCarrier } from '../compose.ts';

/**
 * Starts the orchestrator; it keeps the process alive until Ctrl+C. On a terminal: "Starting…" until the engine is up,
 * then the arrival line, then the panel. `framed`: the caller (init) already opened the frame the spinner lives in.
 */
export async function runCommand(config: Config, { framed = false } = {}) {
  const announce = process.stdout.isTTY ? (await import('../../ui/clack.ts')).announceStart({ framed }) : undefined;
  try {
    await startCarrier(config, { onArrived: announce?.arrived });
  } catch (error) {
    announce?.failed();
    if (error instanceof InstanceBusy) throw new CliError(1, error.message);
    createScopedLogger('cli').error('startup failed', error); // logging is installed by now: the stack goes to the log file
    throw new CliError(1, `carrier failed to start: ${error instanceof Error ? error.message : String(error)}`);
  }
}
