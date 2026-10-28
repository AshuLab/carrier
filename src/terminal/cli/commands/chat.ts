import { createInterface } from 'node:readline';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import type { EventEmitter } from 'node:events';
import type { Readable } from 'node:stream';
import { chatAgents } from '../../../config/chat-agents.ts';
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

export const POLL_MS = 200;

/** The chat host's client, started on demand. */
async function hostClient(socketPath: string, config: Config, configPath: string, start: typeof startDetached): Promise<CarrierClient> {
  const client = await connectHost(socketPath);
  if (client !== null) return client;
  await start({ label: 'The chat host', args: ['chat-host', '--config', configPath], socketPath, logPath: join(chatDirOf(config.root), 'logs', 'start.log') });
  const started = await connectHost(socketPath);
  if (started === null) throw new CliError(1, 'The chat host stopped answering right after it started');
  return started;
}

type Reply = { events: Record<string, any>[]; cursor: number; streaming: string };

/**
 * Opens a conversation and runs it in plain lines: one line in, the answer out as it streams. `/quit` leaves and the
 * session stays open. Ctrl+C (`sigint`) while a turn runs interrupts it and returns to the prompt; at the prompt it leaves.
 */
async function converse(client: CarrierClient, { agent, folder, input, pollMs, sigint }: { agent: string; folder: string; input: Readable; pollMs: number; sigint: EventEmitter }) {
  const write = (text: string) => void process.stdout.write(text);
  let opened;
  try {
    opened = (await client.request('open', { agent, folder })) as { session: { id: string; agent: string; folder: string } };
  } catch (error) {
    throw new CliError(1, error instanceof Error ? error.message : String(error));
  }
  const sessionId = opened.session.id;
  write(`Chat ${sessionId} with ${opened.session.agent} in ${opened.session.folder}. /quit leaves it open.\n`);

  let cursor = 0;
  let printed = 0; // characters of the message being written that are already on screen
  const show = (reply: Reply) => {
    let ended = false;
    for (const event of reply.events) {
      if (event.kind === 'assistant') write(`${String(event.text).slice(printed)}\n`), (printed = 0);
      else if (event.kind === 'tool_start') write(`  [${event.tool}${event.arg ? ` ${event.arg}` : ''}]\n`);
      else if (event.kind === 'error') write(`error: ${event.text}\n`);
      else if (event.kind === 'turn_end') {
        ended = true;
        printed = 0;
        if (event.outcome === 'interrupted') write('\n[interrupted]\n');
      }
    }
    if (reply.streaming.length > printed) write(reply.streaming.slice(printed)), (printed = reply.streaming.length);
    cursor = reply.cursor;
    return ended;
  };
  const poll = async () => (await client.request('events', { sessionId, after: cursor, limit: 200 })) as Reply;

  const reader = createInterface({ input });
  const lines = reader[Symbol.asyncIterator]();
  let turning = false;
  const onSigint = () => {
    if (turning === false) return reader.close(); // at the prompt: leave, as /quit does
    client.request('interrupt', { sessionId }).catch((error) => write(`${error instanceof Error ? error.message : String(error)}\n`));
  };
  sigint.on('SIGINT', onSigint);
  try {
    for (;;) {
      write('> ');
      const { value, done } = await lines.next();
      const text = done ? '/quit' : String(value).trim();
      if (text === '/quit') break;
      if (text === '') continue;
      turning = true;
      try {
        await client.request('send', { sessionId, text });
        while (show(await poll()) === false) await sleep(pollMs);
      } catch (error) {
        write(`${error instanceof Error ? error.message : String(error)}\n`);
      } finally {
        turning = false;
      }
    }
  } finally {
    sigint.off('SIGINT', onSigint);
  }
  write('\n');
}

/**
 * `carrier chat --workspace <folder> [--agent <name>]`, `--list` and `--stop`. A host is started on demand by --list and
 * by a chat (`start` is replaceable in tests). `configPath` is absolute. Returns the exit code.
 */
export async function chatCommand(
  flags: { list?: boolean; stop?: boolean; workspace?: string; agent?: string },
  config: Config,
  configPath: string,
  { start = startDetached, input = process.stdin, pollMs = POLL_MS, sigint = process }: { start?: typeof startDetached; input?: Readable; pollMs?: number; sigint?: EventEmitter } = {},
): Promise<number> {
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
    const client = await hostClient(socketPath, config, configPath, start);
    await client.request('list');
    client.close();
    process.stdout.write('No chat sessions.\n'); // the sessions slice prints what the reply holds
    return 0;
  }
  if (flags.workspace !== undefined) {
    const agent = flags.agent ?? chatAgents(config)[0]!.name;
    const client = await hostClient(socketPath, config, configPath, start);
    try {
      await converse(client, { agent, folder: resolve(flags.workspace), input, pollMs, sigint });
    } finally {
      client.close();
    }
    return 0;
  }
  throw new CliError(2, 'Usage: carrier chat --workspace <folder> [--agent <name>] | --list | --stop [--config <path>]');
}
