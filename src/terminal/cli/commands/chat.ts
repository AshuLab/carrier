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

type Option = { id: string; label: string; values: { id: string; label: string }[]; current: string };
type Reply = { events: Record<string, any>[]; cursor: number; streaming: string; options: Option[] };

const HISTORY_EVENTS = 20;

/** How long ago, in the largest whole unit. */
const ageOf = (ms: number) => {
  const minutes = Math.floor(Math.max(ms, 0) / 60_000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes}m ago`;
  if (minutes < 24 * 60) return `${Math.floor(minutes / 60)}h ago`;
  return `${Math.floor(minutes / (24 * 60))}d ago`;
};

const describeOption = (o: Option) => `${o.label} (${o.id}): ${o.current}\n    offers: ${o.values.map((v) => v.id).join(', ')}\n`;

/**
 * Opens a conversation, or resumes a session, and runs it in plain lines: one line in, the answer out as it streams. `/quit` leaves and the
 * session stays open. Ctrl+C (`sigint`) while a turn runs interrupts it and returns to the prompt; at the prompt it leaves.
 */
async function converse(client: CarrierClient, { start, input, pollMs, sigint }: { start: { cmd: 'open'; agent: string; folder: string } | { cmd: 'resume'; sessionId: string }; input: Readable; pollMs: number; sigint: EventEmitter }) {
  const write = (text: string) => void process.stdout.write(text);
  let opened;
  try {
    opened = (await client.request(start.cmd, start.cmd === 'open' ? { agent: start.agent, folder: start.folder } : { sessionId: start.sessionId })) as { session: { id: string; agent: string; folder: string } };
  } catch (error) {
    throw new CliError(1, error instanceof Error ? error.message : String(error));
  }
  const sessionId = opened.session.id;
  write(`Chat ${sessionId} with ${opened.session.agent} in ${opened.session.folder}. /options, /option <id> <value>, /quit leaves it open.\n`);

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

  if (start.cmd === 'resume') {
    // the socket pages forward by cursor only, so the end of the transcript is found by reading to its end
    let tail: Reply['events'] = [];
    for (let page = await poll(); ; page = await poll()) {
      tail = [...tail, ...page.events].slice(-HISTORY_EVENTS);
      cursor = page.cursor;
      if (page.events.length < 200) break;
    }
    for (const event of tail) {
      if (event.kind === 'user') write(`> ${event.text}\n`);
      else if (event.kind === 'assistant') write(`${event.text}\n`);
      else if (event.kind === 'tool_start') write(`  [${event.tool}${event.arg ? ` ${event.arg}` : ''}]\n`);
      else if (event.kind === 'error') write(`error: ${event.text}\n`);
    }
  }

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
      if (text === '/options' || text.startsWith('/option ')) {
        try {
          if (text === '/options') {
            // after the cursor, so what is waiting to be shown is not consumed
            const { options } = (await client.request('events', { sessionId, after: cursor, limit: 1 })) as Reply;
            write(options.map(describeOption).join('') || 'This agent lists no options.\n');
          } else {
            const [id, value, ...extra] = text.split(/\s+/).slice(1);
            if (id === undefined || value === undefined || extra.length > 0) {
              write('Usage: /option <id> <value>\n');
              continue;
            }
            const { options } = (await client.request('setOption', { sessionId, option: id, value })) as Pick<Reply, 'options'>;
            write(describeOption(options.find((o) => o.id === id)!));
          }
        } catch (error) {
          write(`${error instanceof Error ? error.message : String(error)}\n`);
        }
        continue;
      }
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
 * `carrier chat --workspace <folder> [--agent <name>]`, `--resume <id>`, `--list [--archived]`, `--archive|--unarchive|--delete <id>` and `--stop`. A host is started on demand by --list and
 * by a chat (`start` is replaceable in tests). `configPath` is absolute. Returns the exit code.
 */
export async function chatCommand(
  flags: { list?: boolean; archived?: boolean; stop?: boolean; workspace?: string; agent?: string; resume?: string; archive?: string; unarchive?: string; delete?: string },
  config: Config,
  configPath: string,
  { start = startDetached, input = process.stdin, pollMs = POLL_MS, now = Date.now, sigint = process }: { start?: typeof startDetached; input?: Readable; pollMs?: number; now?: () => number; sigint?: EventEmitter } = {},
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
    const { sessions } = (await client.request('list', flags.archived ? { archived: true } : {})) as { sessions: { id: string; agent: string; folder: string; state: string; live: boolean; lastActiveAt: number }[] };
    client.close();
    if (sessions.length === 0) process.stdout.write(flags.archived ? 'No archived chat sessions.\n' : 'No chat sessions.\n');
    // a session whose agent is not running is closed, whatever state it was left in
    for (const s of sessions) process.stdout.write(`${s.id}  ${s.agent}  ${s.live ? s.state : 'closed'}  ${ageOf(now() - s.lastActiveAt)}  ${s.folder}\n`);
    return 0;
  }
  const change =
    flags.archive !== undefined ? ([flags.archive, 'archive', { archived: true }, 'archived'] as const)
    : flags.unarchive !== undefined ? ([flags.unarchive, 'archive', { archived: false }, 'unarchived'] as const)
    : flags.delete !== undefined ? ([flags.delete, 'delete', {}, 'deleted'] as const)
    : undefined;
  if (change !== undefined) {
    const [sessionId, cmd, extra, done] = change;
    const client = await hostClient(socketPath, config, configPath, start);
    try {
      await client.request(cmd, { sessionId, ...extra });
    } catch (error) {
      throw new CliError(1, error instanceof Error ? error.message : String(error));
    } finally {
      client.close();
    }
    process.stdout.write(`Session ${sessionId} ${done}\n`);
    return 0;
  }
  if (flags.resume !== undefined) {
    const client = await hostClient(socketPath, config, configPath, start);
    try {
      await converse(client, { start: { cmd: 'resume', sessionId: flags.resume }, input, pollMs, sigint });
    } finally {
      client.close();
    }
    return 0;
  }
  if (flags.workspace !== undefined) {
    const agent = flags.agent ?? chatAgents(config)[0]!.name;
    const client = await hostClient(socketPath, config, configPath, start);
    try {
      await converse(client, { start: { cmd: 'open', agent, folder: resolve(flags.workspace) }, input, pollMs, sigint });
    } finally {
      client.close();
    }
    return 0;
  }
  throw new CliError(2, 'Usage: carrier chat --workspace <folder> [--agent <name>] | --resume <id> | --list [--archived] | --archive|--unarchive|--delete <id> | --stop [--config <path>]');
}
