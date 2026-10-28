import { readFileSync, rmSync } from 'node:fs';
import { createServer, type Socket } from 'node:net';
import { join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { z } from 'zod';
import type { ChatCapability } from '../chat/server.ts';
import type { AvailableRepo } from '../integrations/available-repos.ts';
import { ResumeRefused } from '../orchestration/resume-refused.ts';
import type { EpicReply, EventsReply, FileDiffReply, FilesReply, SessionsReply } from './replies.ts';

const log = createScopedLogger('control');

const MAX_LINE_BYTES = 16 * 1024;
const MAX_SOCKET_PATH_BYTES = 103; // macOS: sun_path holds 104 with its terminator

/** Measured in bytes, never left to Node: 22.22.0 truncates a longer path and binds a mangled name, 24 to 26 throw EINVAL. */
export function socketPathFits(path: string): { fits: boolean; bytes: number } {
  const bytes = Buffer.byteLength(path);
  return { fits: bytes <= MAX_SOCKET_PATH_BYTES, bytes };
}

const id = z.number().int().positive();
const repo = z
  .string()
  .max(200)
  .regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/)
  .refine((value) => value.split('/').every((part) => part !== '.' && part !== '..'));
const issue = z.number().int().positive();
// An allowlist: any other command, field or type is rejected before anything acts on it.
export const request = z.union([
  z.strictObject({ id, cmd: z.enum(['snapshot', 'pause', 'resume', 'checkNow', 'stop']) }),
  z.strictObject({ id, cmd: z.literal('tail'), executionId: z.uuid(), lines: z.number().int().min(1).max(500) }),
  z.strictObject({ id, cmd: z.literal('sessions'), repo, issue }),
  z.strictObject({ id, cmd: z.literal('events'), executionId: z.uuid(), after: z.number().int().min(0).optional(), limit: z.number().int().min(1).max(200) }),
  z.strictObject({ id, cmd: z.literal('epic'), repo, issue }),
  z.strictObject({ id, cmd: z.literal('files'), repo, issue, executionId: z.uuid().optional() }),
  z.strictObject({ id, cmd: z.literal('fileDiff'), repo, issue, section: z.string().min(1).max(100), path: z.string().min(1).max(500) }),
  z.strictObject({ id, cmd: z.literal('availableRepos'), page: z.int().min(1).max(100).optional() }),
  z.strictObject({ id, cmd: z.literal('resumeEpic'), repo, issue }),
]);

// src/control and dist/control both sit two folders under the package root.
export const version = (JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8')) as { version: string }).version;

/** The optional requests an engine can answer; each one's slice adds its name to `capabilities`. */
export type Capability = 'sessions' | 'events' | 'epic' | 'files' | 'fileDiff' | 'availableRepos' | 'availableReposPaged' | 'resumeEpic';
export type Hello = { event: 'hello'; protocol: 1; pid: number; startedAt: number; version: string; capabilities: (Capability | ChatCapability)[] };
export type Reply = { id: number; ok: true; data?: unknown } | { id: number | null; ok: false; error: string };

/** What the socket does for the client: the same controls the interactive panel's keys use. */
export type Controls = {
  poll(): unknown;
  setPaused(paused: boolean): unknown;
  logs(executionId: string, count: number): string[];
  /** null for an epic the engine does not know. */
  sessions(repo: string, issue: number): SessionsReply | null;
  /** null for an execution the engine does not know. */
  events(executionId: string, after: number, limit: number): EventsReply | null;
  /** null for an epic the engine does not know. */
  epic(repo: string, issue: number): EpicReply | null;
  /** null for an epic the engine does not know. */
  files(repo: string, issue: number, executionId?: string): FilesReply | null;
  /** null for an unknown epic or card, or a path that is not in the card's own file list. */
  fileDiff(repo: string, issue: number, section: string, path: string): FileDiffReply | null;
  /** One page of the repos the gh login can push to, and whether there is a next one; rejects when GitHub cannot be read. */
  availableRepos(page: number): Promise<{ repos: AvailableRepo[]; hasMore: boolean }>;
  /** Puts a stopped epic back in motion and resolves once it started; rejects with ResumeRefused when it could not. */
  resumeEpic(repo: string, issue: number): Promise<void>;
};

/** pause, resume, checkNow and tail. Like the panel's keys, a check is started and not waited for: its failure is the engine's to report. */
function control(command: Exclude<z.infer<typeof request>, { cmd: 'snapshot' | 'stop' | Capability }>, controls: Controls): Reply {
  try {
    if (command.cmd === 'tail') return { id: command.id, ok: true, data: controls.logs(command.executionId, command.lines) };
    if (command.cmd === 'checkNow') void Promise.resolve(controls.poll()).catch((error) => log.error('check now failed', error));
    else void Promise.resolve(controls.setPaused(command.cmd === 'pause')).catch((error) => log.error(`${command.cmd} failed`, error));
    return { id: command.id, ok: true };
  } catch (error) {
    log.error(`${command.cmd} failed`, error);
    return { id: command.id, ok: false, error: 'internal error' };
  }
}

/** The reply to one line; a promise for the requests that wait on GitHub. */
function answer(line: string, snapshot: () => unknown, controls: Controls, stopAfterReply: () => void): Reply | Promise<Reply> {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return { id: null, ok: false, error: 'invalid JSON' };
  }
  const parsed = request.safeParse(value);
  if (parsed.success === false) {
    // the id is echoed only when it is a valid one, so the client can match the error
    const given = typeof value === 'object' && value !== null ? id.safeParse((value as { id?: unknown }).id) : null;
    return { id: given?.success ? given.data : null, ok: false, error: 'invalid request' };
  }
  if (parsed.data.cmd === 'snapshot') {
    try {
      return { id: parsed.data.id, ok: true, data: snapshot() };
    } catch (error) {
      log.error('snapshot failed', error);
      return { id: parsed.data.id, ok: false, error: 'internal error' };
    }
  }
  if (parsed.data.cmd === 'sessions' || parsed.data.cmd === 'epic') {
    const { id: replyId, cmd, repo, issue } = parsed.data;
    try {
      const reply = controls[cmd](repo, issue);
      return reply === null ? { id: replyId, ok: false, error: 'unknown epic' } : { id: replyId, ok: true, data: reply };
    } catch (error) {
      log.error(`${cmd} failed`, error);
      return { id: replyId, ok: false, error: 'internal error' };
    }
  }
  if (parsed.data.cmd === 'files') {
    const { id: replyId, repo, issue, executionId } = parsed.data;
    try {
      const reply = controls.files(repo, issue, executionId);
      return reply === null ? { id: replyId, ok: false, error: 'unknown epic' } : { id: replyId, ok: true, data: reply };
    } catch (error) {
      log.error('files failed', error);
      return { id: replyId, ok: false, error: 'internal error' };
    }
  }
  if (parsed.data.cmd === 'fileDiff') {
    const { id: replyId, repo, issue, section, path } = parsed.data;
    try {
      const reply = controls.fileDiff(repo, issue, section, path);
      // never git's own message: it can name more of the machine than the client should see
      return reply === null ? { id: replyId, ok: false, error: 'unknown file' } : { id: replyId, ok: true, data: reply };
    } catch (error) {
      log.error('fileDiff failed', error);
      return { id: replyId, ok: false, error: 'internal error' };
    }
  }
  if (parsed.data.cmd === 'availableRepos') {
    const { id: replyId, page } = parsed.data;
    // never the reason in the reply: gh's own message can carry more than the client should see
    return Promise.resolve()
      .then(() => controls.availableRepos(page ?? 1))
      .then(
        (data): Reply => ({ id: replyId, ok: true, data }),
        (error): Reply => {
          log.error('availableRepos failed', error);
          return { id: replyId, ok: false, error: 'github unavailable' };
        },
      );
  }
  if (parsed.data.cmd === 'resumeEpic') {
    const { id: replyId, repo, issue } = parsed.data;
    return Promise.resolve()
      .then(() => controls.resumeEpic(repo, issue))
      .then(
        (): Reply => ({ id: replyId, ok: true }),
        (error): Reply => {
          if (error instanceof ResumeRefused) return { id: replyId, ok: false, error: error.reason };
          log.error('resumeEpic failed', error);
          return { id: replyId, ok: false, error: 'internal error' };
        },
      );
  }
  if (parsed.data.cmd === 'events') {
    const { id: replyId, executionId, after, limit } = parsed.data;
    try {
      const reply = controls.events(executionId, after ?? 0, limit);
      return reply === null ? { id: replyId, ok: false, error: 'unknown execution' } : { id: replyId, ok: true, data: reply };
    } catch (error) {
      log.error('events failed', error);
      return { id: replyId, ok: false, error: 'internal error' };
    }
  }
  if (parsed.data.cmd !== 'stop') return control(parsed.data, controls);
  stopAfterReply();
  return { id: parsed.data.id, ok: true };
}

/**
 * Opens `orchestrator/control.sock`: newline-delimited JSON, a hello on connect and one reply per request. The caller
 * must hold the instance lock: that is what makes any socket file already there a leftover of a crash, safe to replace.
 * A path that does not fit, or a socket that cannot open, is logged and Carrier goes on without it. `close()` is synchronous and removes the file.
 */
export async function startControlServer({ orchestratorDir, snapshot, startedAt, controls, stop }: { orchestratorDir: string; snapshot: () => unknown; startedAt: number; controls: Controls; stop: () => Promise<void> }): Promise<{ close: () => void }> {
  const path = join(orchestratorDir, 'control.sock');
  const { fits, bytes } = socketPathFits(path);
  if (fits === false) {
    log.warn(`control socket not opened: ${path} is ${bytes} bytes, the limit is ${MAX_SOCKET_PATH_BYTES}; use a shorter shared root`);
    return { close: () => {} };
  }
  const sockets = new Set<Socket>();
  const hello: Hello = { event: 'hello', protocol: 1, pid: process.pid, startedAt, version, capabilities: ['sessions', 'events', 'epic', 'files', 'fileDiff', 'availableRepos', 'availableReposPaged', 'resumeEpic'] };
  const send = (socket: Socket, message: Hello | Reply, written?: () => void) => void socket.write(`${JSON.stringify(message)}\n`, written);

  const server = createServer((socket) => {
    sockets.add(socket);
    socket.setEncoding('utf8');
    // a client that goes away mid-write is routine, not a failure
    socket.on('error', (error) => log.debug('control connection error', error));
    socket.on('close', () => sockets.delete(socket));
    send(socket, hello);
    let pending = '';
    // replies leave in the order the requests came, also when one of them waits on GitHub
    let replies: Promise<void> = Promise.resolve();
    socket.on('data', (chunk: string) => {
      pending += chunk;
      for (let end = pending.indexOf('\n'); end >= 0; end = pending.indexOf('\n')) {
        const line = pending.slice(0, end);
        pending = pending.slice(end + 1);
        if (Buffer.byteLength(line) > MAX_LINE_BYTES) return tooLong(socket);
        // `stop`: the reply is flushed first, then the shared shutdown runs and ends with the connection closing
        let afterReply: (() => void) | undefined;
        const stopAfterReply = () => void (afterReply = () => void stop().catch((error) => log.error('stop failed', error)));
        const reply = answer(line, snapshot, controls, stopAfterReply);
        replies = replies.then(async () => {
          const message = await reply;
          if (socket.destroyed === false) send(socket, message, afterReply);
        });
      }
      if (Buffer.byteLength(pending) > MAX_LINE_BYTES) tooLong(socket);
    });
  });
  const tooLong = (socket: Socket) => {
    socket.removeAllListeners('data'); // nothing more is read from this client
    socket.end(`${JSON.stringify({ id: null, ok: false, error: 'line too long' })}\n`);
  };
  server.on('error', (error) => log.error('control socket error', error));

  const close = () => {
    server.close();
    for (const socket of sockets) socket.destroy();
    rmSync(path, { force: true });
  };
  try {
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
  } catch (error) {
    log.error('control socket not opened', error);
    return { close: () => {} };
  }
  return { close };
}
