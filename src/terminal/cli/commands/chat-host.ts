import { createScopedLogger } from '@ashulab/universal-logger';
import type { Config } from '../../../config/schema.ts';
import { HostBusy, startChatHost } from '../../../chat/host.ts';
import { CliError } from '../cli-error.ts';

/** `carrier chat-host`: the chat host in the foreground, until a `stop` request, the idle exit or a signal. How a client's host runs, and how to debug it. */
export async function chatHostCommand(config: Config, configPath: string) {
  try {
    await startChatHost(config, { configPath });
  } catch (error) {
    if (error instanceof HostBusy) throw new CliError(1, error.message);
    createScopedLogger('cli').error('chat host failed to start', error); // logging is installed by now: the stack goes to the log file
    throw new CliError(1, `the chat host failed to start: ${error instanceof Error ? error.message : String(error)}`);
  }
  process.stdout.write(`Chat host running (pid ${process.pid}).\n`);
}
