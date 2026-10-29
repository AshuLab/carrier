import { join } from 'node:path';
import { enginePlacesOf } from '../../../config/engine-places.ts';
import { pidAt, startDetached } from '../detached.ts';

/**
 * Starts Carrier as a detached run (ADR 0010): the same program with `--config`, in its own session, its output in
 * `<folder>/engine/logs/start.log`. Returns once the control socket answers; a Carrier already answering is left alone.
 * `folder` is the Carrier folder; `configPath` is absolute: the child does not share this process's working directory.
 */
export async function startCommand(folder: string, configPath: string): Promise<number> {
  const places = enginePlacesOf(folder);
  const socketPath = places.socket;
  const logPath = join(places.logs, 'start.log');

  const running = await pidAt(socketPath);
  if (running !== undefined) {
    process.stdout.write(`Carrier is already running (pid ${running}).\n`);
    return 0;
  }
  const pid = await startDetached({ label: 'Carrier', args: ['--config', configPath], socketPath, logPath });
  process.stdout.write(`Carrier is running (pid ${pid}). Log: ${logPath}\n`);
  return 0;
}
