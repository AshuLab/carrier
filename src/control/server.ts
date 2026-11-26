import { readFileSync, rmSync } from 'node:fs';
import { createServer, type Socket } from 'node:net';
import { createScopedLogger } from '@ashulab/universal-logger';
import { z } from 'zod';
import type { ChatCapability } from '../chat/server.ts';
import type { AvailableRepo } from '../integrations/available-repos.ts';
import { controlSocketIn } from '../config/places.ts';
import { ConfigRefused } from '../config/engine-edit.ts';
import { optionNamePattern } from '../config/providers.ts';
import type { TextParams } from '../orchestration/text-params.ts';
import { RecoverRefused } from '../orchestration/recover-refused.ts';
import { ReloadRefused } from '../orchestration/reload-refused.ts';
import { ResumeRefused } from '../orchestration/resume-refused.ts';
import type { ConfigReply } from './config.ts';
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
const optionName = z.string().regex(optionNamePattern);
const extraRounds = z.int().min(1);
// The `config` capability: the requests that change `engine.json` (ADR 0053). A value the file's schema refuses is refused with its key path and kind.
const whole = z.number().finite();
export const setWatchedReposRequest = z.strictObject({ id, cmd: z.literal('setWatchedRepos'), repos: z.array(z.string().max(200)).max(500) });
export const editBehaviorRequest = z.strictObject({
  id,
  cmd: z.literal('editBehavior'),
  changes: z.strictObject({
    pollIntervalMinutes: whole.optional(),
    logLevel: z.string().max(20).optional(),
    finishedWindowDays: whole.optional(),
    limits: z.strictObject({ maxConcurrentEpics: whole.optional(), maxReviews: whole.optional(), maxLeadRounds: whole.optional(), maxExecutionRetries: whole.optional(), maxExecutionHours: z.union([z.literal('unlimited'), whole]).optional(), githubCallTimeoutSeconds: whole.optional() }).optional(),
  }),
});
// The requests that change the roles of `engine.json`: what the Roles page, a repo's role screens and the Engine page send. The words of a field the file refuses are the handler's, so a limit here is only a bound on the line.
const roleName = z.enum(['author', 'reviewer', 'leadReviewer']);
const field = z.string().max(200);
const identity = z.union([z.strictObject({ kind: z.literal('forge'), agent: field }), z.strictObject({ kind: z.literal('gh') })]);
const roleChanges = z.strictObject({ identity: identity.optional(), provider: field.optional(), model: field.optional(), effort: field.nullable().optional() });
const personaName = field;
const personaPrompt = z.string().max(10_000);
const failoverStep = z.strictObject({ provider: field, model: field.optional(), effort: field.optional() }).nullable();
export const engineFileRequests = [
  z.strictObject({ id, cmd: z.literal('editRole'), role: roleName, changes: roleChanges }),
  z.strictObject({
    id,
    cmd: z.literal('editRepoRole'),
    repo,
    role: roleName,
    fields: z.strictObject({ profile: field.optional(), provider: field.optional(), model: field.optional(), effort: field.optional(), persona: z.strictObject({ name: personaName.optional(), prompt: personaPrompt.optional() }).optional() }).nullable(),
  }),
  z.strictObject({ id, cmd: z.literal('editPersona'), role: roleName, name: personaName.nullable(), prompt: personaPrompt.nullable() }),
  z.strictObject({ id, cmd: z.literal('editFailover'), role: roleName, first: failoverStep, second: failoverStep }),
  z.strictObject({ id, cmd: z.literal('setLeadReviewer'), draft: roleChanges.nullable() }),
  z.strictObject({ id, cmd: z.literal('setOrchestratorProfile'), name: field.nullable() }),
] as const;
type EngineFileCmd = (typeof engineFileRequests)[number]['shape']['cmd']['value'];
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
  z.strictObject({ id, cmd: z.literal('reload') }),
  z.strictObject({ id, cmd: z.literal('resumeEpic'), repo, issue, author: optionName.optional(), reviewer: optionName.optional(), reviewer2: optionName.optional(), reviewer3: optionName.optional(), reviewer4: optionName.optional(), lead: optionName.optional(), from: z.enum(['ship', 'review', 'fix']).optional(), extraRounds: extraRounds.optional() }),
  z.strictObject({ id, cmd: z.literal('recoverEpic'), repo, issue }),
  setWatchedReposRequest,
  editBehaviorRequest,
  ...engineFileRequests,
]);

// src/control and dist/control both sit two folders under the package root.
export const version = (JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8')) as { version: string }).version;

/** The optional requests an engine can answer; each one's slice adds its name to `capabilities`. */
export type Capability = 'sessions' | 'events' | 'epic' | 'files' | 'fileDiff' | 'availableRepos' | 'availableReposPaged' | 'resumeEpic' | 'resumeFromStage' | 'resumeReviewerOptions' | 'recoverEpic' | 'reload' | 'config';
/** What the hello announces. */
export const capabilities: Capability[] = ['sessions', 'events', 'epic', 'files', 'fileDiff', 'availableRepos', 'availableReposPaged', 'resumeEpic', 'resumeFromStage', 'resumeReviewerOptions', 'recoverEpic', 'reload', 'config'];
export type Hello = { event: 'hello'; protocol: 1; pid: number; startedAt: number; version: string; capabilities: (Capability | ChatCapability)[] };
export type Reply = { id: number; ok: true; data?: unknown } | { id: number | null; ok: false; error: string; code?: string; params?: TextParams };

/** A refused reply: the words in `error` as always, the code and its parameters beside them ([ADR 0055](../../docs/adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). Also what the chat socket answers for its fixed errors. */
export const refused = (id: number | null, code: string, error: string, params: TextParams = {}): Reply => ({ id, ok: false, error, code, params });

/** What the socket does for the client: the same controls the interactive panel's keys use. */
export type Controls = {
  poll(): unknown;
  setPaused(paused: boolean): unknown;
  logs(executionId: string, count: number): string[];
  /** null for an epic the engine does not know. */
  sessions(repo: string, issue: number): SessionsReply | null;
  /** null for an execution the engine does not know. */
  events(executionId: string, after: number, limit: number): EventsReply | null;
  /** null for an epic the engine does not know. Waits on git, so it may answer later; a rejection is `internal error`. */
  epic(repo: string, issue: number): EpicReply | null | Promise<EpicReply | null>;
  /** null for an epic the engine does not know. */
  files(repo: string, issue: number, executionId?: string): FilesReply | null | Promise<FilesReply | null>;
  /** null for an unknown epic or card, or a path that is not in the card's own file list. */
  fileDiff(repo: string, issue: number, section: string, path: string): FileDiffReply | null | Promise<FileDiffReply | null>;
  /** One page of the repos the gh login can push to, and whether there is a next one; rejects when GitHub cannot be read. */
  availableRepos(page: number): Promise<{ repos: AvailableRepo[]; hasMore: boolean }>;
  /** Puts a stopped epic back in motion and resolves once it started; rejects with ResumeRefused when it could not. */
  resumeEpic(repo: string, issue: number, chosen: { author?: string; reviewer?: string; reviewer2?: string; reviewer3?: string; reviewer4?: string; lead?: string; from?: 'ship' | 'review' | 'fix'; extraRounds?: number }): Promise<void>;
  /** Continues one running epic whose agent is not alive and resolves once it was; rejects with RecoverRefused when it could not. It takes no state: the engine reads the epic's own. */
  recoverEpic(repo: string, issue: number): Promise<void>;
  /** Reads the settings again and runs on them; throws ReloadRefused, with the settings as they were, when they are not valid. */
  reload(): void;
  /** Writes the watched repos of `engine.json` and makes the engine run on the file; throws a `ConfigRefused`, the file left as it was, for a list the engine would refuse. */
  setWatchedRepos(repos: string[]): ConfigReply;
  /** Writes the Behavior values of `engine.json` and makes the engine run on the file; throws a `ConfigRefused`, the file left as it was, for a value the engine would refuse. */
  editBehavior(changes: z.infer<typeof editBehaviorRequest>['changes']): ConfigReply;
  /** Writes one of the role requests of `engine.json` (roles, a repo's role, persona, failover, lead reviewer, orchestrator profile) and makes the engine run on the file; throws a `ConfigRefused`, the file left as it was, for what the engine would refuse. */
  editEngineFile(command: EngineFileRequest): ConfigReply;
};

export type EngineFileRequest = z.infer<(typeof engineFileRequests)[number]>;
const isEngineFile = (command: z.infer<typeof request>): command is EngineFileRequest => engineFileRequests.some((schema) => schema.shape.cmd.value === command.cmd);

/** pause, resume, checkNow and tail. Like the panel's keys, a check is started and not waited for: its failure is the engine's to report. */
function control(command: Exclude<z.infer<typeof request>, { cmd: 'snapshot' | 'stop' | 'setWatchedRepos' | 'editBehavior' | EngineFileCmd | Capability }>, controls: Controls): Reply {
  try {
    if (command.cmd === 'tail') return { id: command.id, ok: true, data: controls.logs(command.executionId, command.lines) };
    if (command.cmd === 'checkNow') void Promise.resolve(controls.poll()).catch((error) => log.error('check now failed', error));
    else void Promise.resolve(controls.setPaused(command.cmd === 'pause')).catch((error) => log.error(`${command.cmd} failed`, error));
    return { id: command.id, ok: true };
  } catch (error) {
    log.error(`${command.cmd} failed`, error);
    return refused(command.id, 'request.internal', 'internal error');
  }
}

/** The reply to one line; a promise for the requests that wait on GitHub. */
function answer(line: string, snapshot: () => unknown, controls: Controls, stopAfterReply: () => void): Reply | Promise<Reply> {
  let value: unknown;
  try {
    value = JSON.parse(line);
  } catch {
    return refused(null, 'request.invalidJson', 'invalid JSON');
  }
  const parsed = request.safeParse(value);
  if (parsed.success === false) {
    // the id is echoed only when it is a valid one, so the client can match the error
    const given = typeof value === 'object' && value !== null ? id.safeParse((value as { id?: unknown }).id) : null;
    // a refused extraRounds names its field, so `restart --extra-rounds` can say what to fix; other fields stay the generic refusal
    const asked = typeof value === 'object' && value !== null ? (value as { cmd?: unknown; extraRounds?: unknown }) : {};
    const at = given?.success ? given.data : null;
    if (asked.cmd === 'resumeEpic' && 'extraRounds' in asked && extraRounds.safeParse(asked.extraRounds).success === false) return refused(at, 'request.extraRounds', 'invalid request: extraRounds takes a positive whole number');
    return refused(at, 'request.invalid', 'invalid request');
  }
  if (parsed.data.cmd === 'snapshot') {
    try {
      return { id: parsed.data.id, ok: true, data: snapshot() };
    } catch (error) {
      log.error('snapshot failed', error);
      return refused(parsed.data.id, 'request.internal', 'internal error');
    }
  }
  if (parsed.data.cmd === 'sessions') {
    const { id: replyId, repo, issue } = parsed.data;
    try {
      const reply = controls.sessions(repo, issue);
      return reply === null ? refused(replyId, 'epic.unknown', 'unknown epic') : { id: replyId, ok: true, data: reply };
    } catch (error) {
      log.error('sessions failed', error);
      return refused(replyId, 'request.internal', 'internal error');
    }
  }
  // what waits on git answers later: the engine keeps running meanwhile, and this connection's replies keep their order
  if (parsed.data.cmd === 'epic') {
    const { id: replyId, repo, issue } = parsed.data;
    return Promise.resolve()
      .then(() => controls.epic(repo, issue))
      .then(
        (reply): Reply => (reply === null ? refused(replyId, 'epic.unknown', 'unknown epic') : { id: replyId, ok: true, data: reply }),
        (error): Reply => {
          log.error('epic failed', error);
          return refused(replyId, 'request.internal', 'internal error');
        },
      );
  }
  if (parsed.data.cmd === 'files') {
    const { id: replyId, repo, issue, executionId } = parsed.data;
    return Promise.resolve()
      .then(() => controls.files(repo, issue, executionId))
      .then(
        (reply): Reply => (reply === null ? refused(replyId, 'epic.unknown', 'unknown epic') : { id: replyId, ok: true, data: reply }),
        (error): Reply => {
          log.error('files failed', error);
          return refused(replyId, 'request.internal', 'internal error');
        },
      );
  }
  if (parsed.data.cmd === 'fileDiff') {
    const { id: replyId, repo, issue, section, path } = parsed.data;
    return Promise.resolve()
      .then(() => controls.fileDiff(repo, issue, section, path))
      .then(
        // never git's own message: it can name more of the machine than the client should see
        (reply): Reply => (reply === null ? refused(replyId, 'file.unknown', 'unknown file') : { id: replyId, ok: true, data: reply }),
        (error): Reply => {
          log.error('fileDiff failed', error);
          return refused(replyId, 'request.internal', 'internal error');
        },
      );
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
          return refused(replyId, 'github.unavailable', 'github unavailable');
        },
      );
  }
  if (parsed.data.cmd === 'resumeEpic') {
    const { id: replyId, repo, issue, author, reviewer, reviewer2, reviewer3, reviewer4, lead, from, extraRounds } = parsed.data;
    return Promise.resolve()
      .then(() => controls.resumeEpic(repo, issue, { author, reviewer, reviewer2, reviewer3, reviewer4, lead, from, extraRounds }))
      .then(
        (): Reply => ({ id: replyId, ok: true }),
        (error): Reply => {
          if (error instanceof ResumeRefused) return refused(replyId, error.code, error.reason, error.params);
          log.error('resumeEpic failed', error);
          return refused(replyId, 'request.internal', 'internal error');
        },
      );
  }
  if (parsed.data.cmd === 'recoverEpic') {
    const { id: replyId, repo, issue } = parsed.data;
    return Promise.resolve()
      .then(() => controls.recoverEpic(repo, issue))
      .then(
        (): Reply => ({ id: replyId, ok: true }),
        (error): Reply => {
          if (error instanceof RecoverRefused) return refused(replyId, error.code, error.reason, error.params);
          log.error('recoverEpic failed', error);
          return refused(replyId, 'request.internal', 'internal error');
        },
      );
  }
  if (parsed.data.cmd === 'reload') {
    try {
      controls.reload();
      return { id: parsed.data.id, ok: true };
    } catch (error) {
      if (error instanceof ReloadRefused) return refused(parsed.data.id, error.code, error.problem, error.params);
      log.error('reload failed', error);
      return refused(parsed.data.id, 'request.internal', 'internal error');
    }
  }
  if (parsed.data.cmd === 'setWatchedRepos' || parsed.data.cmd === 'editBehavior') {
    const command = parsed.data;
    try {
      return { id: command.id, ok: true, data: command.cmd === 'setWatchedRepos' ? controls.setWatchedRepos(command.repos) : controls.editBehavior(command.changes) };
    } catch (error) {
      if (error instanceof ConfigRefused) return refused(command.id, error.code, error.message, error.params);
      log.error(`${command.cmd} failed`, error);
      return refused(command.id, 'request.internal', 'internal error');
    }
  }
  if (isEngineFile(parsed.data)) {
    const command = parsed.data;
    try {
      return { id: command.id, ok: true, data: controls.editEngineFile(command) };
    } catch (error) {
      if (error instanceof ConfigRefused) return refused(command.id, error.code, error.message, error.params);
      log.error(`${command.cmd} failed`, error);
      return refused(command.id, 'request.internal', 'internal error');
    }
  }
  if (parsed.data.cmd === 'events') {
    const { id: replyId, executionId, after, limit } = parsed.data;
    try {
      const reply = controls.events(executionId, after ?? 0, limit);
      return reply === null ? refused(replyId, 'execution.unknown', 'unknown execution') : { id: replyId, ok: true, data: reply };
    } catch (error) {
      log.error('events failed', error);
      return refused(replyId, 'request.internal', 'internal error');
    }
  }
  if (parsed.data.cmd !== 'stop') return control(parsed.data, controls);
  stopAfterReply();
  return { id: parsed.data.id, ok: true };
}

/**
 * Opens `control.sock` in the engine's state folder: newline-delimited JSON, a hello on connect and one reply per request. The caller
 * must hold the instance lock: that is what makes any socket file already there a leftover of a crash, safe to replace.
 * A path that does not fit, or a socket that cannot open, is logged and Carrier goes on without it. `close()` is synchronous and removes the file.
 */
export async function startControlServer({ stateDir, snapshot, startedAt, controls, stop }: { stateDir: string; snapshot: () => unknown; startedAt: number; controls: Controls; stop: () => Promise<void> }): Promise<{ close: () => void }> {
  const path = controlSocketIn(stateDir);
  const { fits, bytes } = socketPathFits(path);
  if (fits === false) {
    log.warn(`control socket not opened: ${path} is ${bytes} bytes, the limit is ${MAX_SOCKET_PATH_BYTES}; use a shorter Carrier folder`);
    return { close: () => {} };
  }
  const sockets = new Set<Socket>();
  const hello: Hello = { event: 'hello', protocol: 1, pid: process.pid, startedAt, version, capabilities };
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
    socket.end(`${JSON.stringify(refused(null, 'request.tooLong', 'line too long'))}\n`);
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
