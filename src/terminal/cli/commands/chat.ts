import { join } from 'node:path';
import type { Config } from '../../../config/schema.ts';
import { chatDirOf, chatSocketOf } from '../../../chat/server.ts';
import { CliError } from '../cli-error.ts';
import { connectControl, ControlUnreachable, type CarrierClient } from '../control-client.ts';
import { startDetached } from '../detached.ts';
import { socketGone } from './control.ts';

/** A client on the chat host's socket; null when no host answers. */
async function connectHost(path: string): Promise<CarrierClient | null> {
  try {
    return await connectControl(path);
  } catch (error) {
    if (error instanceof ControlUnreachable === false) throw error;
    if (error.reason === 'not-running') return null;
    if (error.reason === 'incompatible') throw new CliError(2, 'The running chat host speaks a protocol this command does not (it expects 1). Update one of them.');
    throw new CliError(1, `The chat host does not answer on ${path}`);
  }
}

/** `carrier chat --list` and `--stop`. A host is started on demand by --list (`start` is replaceable in tests). `configPath` is absolute. Returns the exit code. */
export async function chatCommand(flags: { list?: boolean; stop?: boolean }, config: Config, configPath: string, { start = startDetached }: { start?: typeof startDetached } = {}): Promise<number> {
  const socketPath = chatSocketOf(config.root);
  if (flags.stop) {
    const client = await connectHost(socketPath);
    if (client === null) {
      process.stdout.write('No chat host is running\n');
      return 0;
    }
    await client.request('stop');
    client.close();
    if ((await socketGone(socketPath)) === false) throw new CliError(1, `The chat host still answers on ${socketPath} after 15 seconds`);
    process.stdout.write('Chat host stopped\n');
    return 0;
  }
  if (flags.list) {
    let client = await connectHost(socketPath);
    if (client === null) {
      await start({ label: 'The chat host', args: ['chat-host', '--config', configPath], socketPath, logPath: join(chatDirOf(config.root), 'logs', 'start.log') });
      client = await connectHost(socketPath);
      if (client === null) throw new CliError(1, 'The chat host stopped answering right after it started');
    }
    await client.request('list');
    client.close();
    process.stdout.write('No chat sessions.\n'); // the sessions slice prints what the reply holds
    return 0;
  }
  throw new CliError(2, 'Usage: carrier chat --list | --stop [--config <path>]');
}
