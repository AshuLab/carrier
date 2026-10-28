import { rmSync } from 'node:fs';
import { createServer, type Socket } from 'node:net';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { z } from 'zod';
import { socketPathFits, version, type Hello, type Reply } from '../control/server.ts';

const log = createScopedLogger('chat');

// 1 MiB, not the engine's 16 KiB: a pasted spec is a request.
const MAX_LINE_BYTES = 1024 * 1024;

/** The requests a chat host answers; each slice that adds one adds its name here. */
export type ChatCapability = 'list' | 'stop';
const capabilities: ChatCapability[] = ['list', 'stop'];

const id = z.number().int().positive();
// An allowlist, strict like the engine's: any other command, field or type is rejected before anything acts on it.
export const chatRequest = z.union([z.strictObject({ id, cmd: z.literal('list') }), z.strictObject({ id, cmd: z.literal('stop') })]);

/** What the socket does for the client. */
export type ChatControls = {
  list(): unknown;
};

function answer(line: string, controls: ChatControls, stopAfterReply: () => void): Reply {
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
    return { id: parsed.data.id, ok: true, data: controls.list() };
  } catch (error) {
    log.error('list failed', error);
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
    socket.on('data', (chunk: string) => {
      pending += chunk;
      for (let end = pending.indexOf('\n'); end >= 0; end = pending.indexOf('\n')) {
        const line = pending.slice(0, end);
        pending = pending.slice(end + 1);
        if (Buffer.byteLength(line) > MAX_LINE_BYTES) return tooLong(socket);
        // `stop`: the reply is flushed first, then the shutdown runs
        let afterReply: (() => void) | undefined;
        const reply = answer(line, controls, () => void (afterReply = () => void stop().catch((error) => log.error('stop failed', error))));
        send(socket, reply, afterReply);
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
