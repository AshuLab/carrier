import { createScopedLogger } from '@ashulab/universal-logger';
import { ChatConfigInvalid, HostBusy, startChatHost } from '../../../chat/host.ts';
import { CliError } from '../cli-error.ts';

/** `carrier chat-host`: the chat host in the foreground, from the Carrier folder alone, until a `stop` request, the idle exit or a signal. How a client's host runs, and how to debug it. */
export async function chatHostCommand() {
  try {
    await startChatHost();
  } catch (error) {
    if (error instanceof HostBusy) throw new CliError(1, error.message);
    if (error instanceof ChatConfigInvalid) throw new CliError(1, ...error.message.split('\n'));
    createScopedLogger('cli').error('chat host failed to start', error); // logging is installed by now: the stack goes to the log file
    throw new CliError(1, `the chat host failed to start: ${error instanceof Error ? error.message : String(error)}`);
  }
  process.stdout.write(`Chat host running (pid ${process.pid}).\n`);
}
