import { rmSync } from 'node:fs';
import { createServer, type Socket } from 'node:net';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { z } from 'zod';
import { socketPathFits, version, type Hello, type Reply } from '../control/server.ts';
import { ChatRefused } from './runner.ts';

const log = createScopedLogger('chat');

// 1 MiB, not the engine's 16 KiB: a pasted spec is a request.
const MAX_LINE_BYTES = 1024 * 1024;

/** The requests a chat host answers; each slice that adds one adds its name here. */
export type ChatCapability = 'agents' | 'list' | 'open' | 'resume' | 'send' | 'answer' | 'interrupt' | 'setOption' | 'events' | 'close' | 'archive' | 'delete' | 'stop';
const capabilities: ChatCapability[] = ['agents', 'list', 'open', 'resume', 'send', 'answer', 'interrupt', 'setOption', 'events', 'close', 'archive', 'delete', 'stop'];

const id = z.number().int().positive();
const sessionId = z.uuid();
// An allowlist, strict like the engine's: any other command, field or type is rejected before anything acts on it.
export const chatRequest = z.union([
  z.strictObject({ id, cmd: z.literal('agents') }),
  z.strictObject({ id, cmd: z.literal('list'), archived: z.boolean().optional() }),
  z.strictObject({ id, cmd: z.literal('open'), agent: z.string().min(1), folder: z.string().min(1), options: z.record(z.string(), z.string()).optional() }),
  z.strictObject({ id, cmd: z.literal('resume'), sessionId }),
  z.strictObject({ id, cmd: z.literal('send'), sessionId, text: z.string().min(1) }),
  z.strictObject({ id, cmd: z.literal('answer'), sessionId, approvalId: z.string().min(1), choiceId: z.string().min(1) }),
  z.strictObject({ id, cmd: z.literal('interrupt'), sessionId }),
  z.strictObject({ id, cmd: z.literal('setOption'), sessionId, option: z.string().min(1), value: z.string().min(1) }),
  z.strictObject({ id, cmd: z.literal('events'), sessionId, after: z.number().int().min(0).optional(), limit: z.number().int().min(1).max(200) }),
  z.strictObject({ id, cmd: z.literal('close'), sessionId }),
  z.strictObject({ id, cmd: z.literal('archive'), sessionId, archived: z.boolean() }),
  z.strictObject({ id, cmd: z.literal('delete'), sessionId }),
  z.strictObject({ id, cmd: z.literal('stop') }),
]);
type Request = z.infer<typeof chatRequest>;
type Args<C extends Request['cmd']> = Omit<Extract<Request, { cmd: C }>, 'id' | 'cmd'>;

/** What the socket does for the client. A `ChatRefused` thrown here reaches the client with its message; any other error is "internal error". */
export type ChatControls = {
  agents(): unknown;
  list(args: Args<'list'>): unknown;
  open(args: Args<'open'>): Promise<unknown>;
  resume(args: Args<'resume'>): Promise<unknown>;
  send(args: Args<'send'>): unknown;
  answer(args: Args<'answer'>): unknown;
  interrupt(args: Args<'interrupt'>): Promise<unknown>;
  setOption(args: Args<'setOption'>): Promise<unknown>;
  events(args: Args<'events'>): unknown;
  close(args: Args<'close'>): Promise<unknown>;
  archive(args: Args<'archive'>): Promise<unknown>;
  delete(args: Args<'delete'>): Promise<unknown>;
};

async function run(request: Exclude<Request, { cmd: 'stop' }>, controls: ChatControls): Promise<unknown> {
  switch (request.cmd) {
    case 'agents':
      return controls.agents();
    case 'list':
      return controls.list({ archived: request.archived });
    case 'open':
      return controls.open({ agent: request.agent, folder: request.folder, options: request.options });
    case 'resume':
      return controls.resume({ sessionId: request.sessionId });
    case 'send':
      return controls.send({ sessionId: request.sessionId, text: request.text });
    case 'answer':
      return controls.answer({ sessionId: request.sessionId, approvalId: request.approvalId, choiceId: request.choiceId });
    case 'interrupt':
      return controls.interrupt({ sessionId: request.sessionId });
    case 'setOption':
      return controls.setOption({ sessionId: request.sessionId, option: request.option, value: request.value });
    case 'events':
      return controls.events({ sessionId: request.sessionId, after: request.after, limit: request.limit });
    case 'close':
      return controls.close({ sessionId: request.sessionId });
    case 'archive':
      return controls.archive({ sessionId: request.sessionId, archived: request.archived });
    case 'delete':
      return controls.delete({ sessionId: request.sessionId });
  }
}

async function answer(line: string, controls: ChatControls, stopAfterReply: () => void): Promise<Reply> {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return { id: null, ok: false, error: 'invalid JSON' };
  }
  const parsed = chatRequest.safeParse(value);
  if (parsed.success === false) {
    // the id is echoed only when it is a valid one, so the client can match the error
    const given = typeof value === 'object' && value !== null ? id.safeParse((value as { id?: unknown }).id) : null;
    return { id: given?.success ? given.data : null, ok: false, error: 'invalid request' };
  }
  if (parsed.data.cmd === 'stop') {
    stopAfterReply();
    return { id: parsed.data.id, ok: true };
  }
  try {
    return { id: parsed.data.id, ok: true, data: await run(parsed.data, controls) };
  } catch (error) {
    if (error instanceof ChatRefused) return { id: parsed.data.id, ok: false, error: error.message };
    log.error(`${parsed.data.cmd} failed`, error);
    return { id: parsed.data.id, ok: false, error: 'internal error' };
  }
}

/**
 * Opens `<chat dir>/chat.sock`: newline-delimited JSON, a hello on connect and one reply per request, like the engine's.
 * The caller holds the chat lock, so a socket file already there is a leftover of a crash. Unlike the engine, a socket
 * that cannot open rejects: a host without it is of no use. `clients` is told when a client connects or leaves.
 * `close()` is synchronous and removes the file.
 */
export async function startChatServer({ chatDir, startedAt, controls, stop, clients }: { chatDir: string; startedAt: number; controls: ChatControls; stop: () => Promise<void>; clients: { joined(): void; left(): void } }): Promise<{ close: () => void }> {
  const path = join(chatDir, 'chat.sock');
  const { fits, bytes } = socketPathFits(path);
  if (fits === false) throw new Error(`${path} is ${bytes} bytes, too long for a socket; use a shorter shared root`);
  const sockets = new Set<Socket>();
  const hello: Hello = { event: 'hello', protocol: 1, pid: process.pid, startedAt, version, capabilities };
  const send = (socket: Socket, message: Hello | Reply, written?: () => void) => void socket.write(`${JSON.stringify(message)}\n`, written);

  const server = createServer((socket) => {
    sockets.add(socket);
    clients.joined();
    socket.setEncoding('utf8');
    // a client that goes away mid-write is routine, not a failure
    socket.on('error', (error) => log.debug('chat connection error', error));
    socket.on('close', () => {
      sockets.delete(socket);
      clients.left();
    });
    send(socket, hello);
    let pending = '';
    let replies = Promise.resolve(); // one reply per request, in the order asked: a slow `open` does not let a later reply overtake it
    socket.on('data', (chunk: string) => {
      pending += chunk;
      for (let end = pending.indexOf('\n'); end >= 0; end = pending.indexOf('\n')) {
        const line = pending.slice(0, end);
        pending = pending.slice(end + 1);
        if (Buffer.byteLength(line) > MAX_LINE_BYTES) return tooLong(socket);
        // `stop`: the reply is flushed first, then the shutdown runs
        replies = replies.then(async () => {
          let afterReply: (() => void) | undefined;
          const reply = await answer(line, controls, () => void (afterReply = () => void stop().catch((error) => log.error('stop failed', error))));
          send(socket, reply, afterReply);
        });
      }
      if (Buffer.byteLength(pending) > MAX_LINE_BYTES) tooLong(socket);
    });
  });
  const tooLong = (socket: Socket) => {
    socket.removeAllListeners('data'); // nothing more is read from this client
    socket.end(`${JSON.stringify({ id: null, ok: false, error: 'line too long' })}\n`);
  };
  server.on('error', (error) => log.error('chat socket error', error));

  rmSync(path, { force: true });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    // bind is synchronous: with this umask the file is born 0600, and the umask is back before anything else runs
    const umask = process.umask(0o177);
    try {
      server.listen(path, resolve);
    } finally {
      process.umask(umask);
    }
  });
  return {
    close: () => {
      server.close();
      for (const socket of sockets) socket.destroy();
      rmSync(path, { force: true });
    },
  };
}

export const chatDirOf = (root: string) => join(root, 'chat');
export const chatSocketOf = (root: string) => join(chatDirOf(root), 'chat.sock');
