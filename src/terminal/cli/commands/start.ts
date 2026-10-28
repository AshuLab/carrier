import { join } from 'node:path';
import type { Config } from '../../../config/schema.ts';
import { pidAt, startDetached } from '../detached.ts';

/**
 * Starts Carrier as a detached run (ADR 0010): the same program with `--config`, in its own session, its output in
 * `orchestrator/logs/start.log`. Returns once the control socket answers; a Carrier already answering is left alone.
 * `configPath` is absolute: the child does not share this process's working directory.
 */
export async function startCommand(config: Config, configPath: string): Promise<number> {
  const orchestratorDir = join(config.root, 'orchestrator');
  const socketPath = join(orchestratorDir, 'control.sock');
  const logPath = join(orchestratorDir, 'logs', 'start.log');

  const running = await pidAt(socketPath);
  if (running !== undefined) {
    process.stdout.write(`Carrier is already running (pid ${running}).\n`);
    return 0;
  }
  const pid = await startDetached({ label: 'Carrier', args: ['--config', configPath], socketPath, logPath });
  process.stdout.write(`Carrier is running (pid ${pid}). Log: ${logPath}\n`);
  return 0;
}
