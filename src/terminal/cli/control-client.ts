import { connect } from 'node:net';
import { socketPathFits, type Hello } from '../../control/server.ts';

/** Why there is no usable Carrier behind a socket path: nothing listens, it does not answer, or it speaks another protocol. */
export type Unreachable = 'not-running' | 'no-answer' | 'incompatible';

export class ControlUnreachable extends Error {
  readonly reason: Unreachable;
  /** For 'incompatible': the protocol the hello announced, when it announced one. */
  readonly protocol: unknown;

  // No parameter properties: Node strips types at runtime and cannot run that syntax.
  constructor(reason: Unreachable, protocol?: unknown) {
    super(reason);
    this.reason = reason;
    this.protocol = protocol;
  }
}

export type CarrierClient = {
  /** Read when connecting: protocol, version, capabilities. */
  hello: Hello;
  /** The `data` of the reply that carries this request's id; an `ok: false` reply rejects with its error text. */
  request(cmd: string, fields?: Record<string, unknown>): Promise<unknown>;
  close(): void;
};

// Errors that mean no Carrier is listening there; any other one (a permission, say) is a socket that did not answer.
const nobodyListening = new Set(['ENOENT', 'ECONNREFUSED', 'ENOTSOCK', 'ENAMETOOLONG']);

/**
 * Connects to a running Carrier's control socket and reads its hello. `timeoutMs` bounds the hello and each request.
 * Rejects with a `ControlUnreachable`; the path is never tried when it does not fit the socket limit.
 */
export function connectControl(path: string, { timeoutMs = 5000 }: { timeoutMs?: number } = {}): Promise<CarrierClient> {
  if (socketPathFits(path).fits === false) return Promise.reject(new ControlUnreachable('not-running'));
  return new Promise((resolve, reject) => {
    const socket = connect(path);
    socket.setEncoding('utf8');
    const pending = new Map<number, { resolve: (data: unknown) => void; reject: (error: Error) => void; timer: NodeJS.Timeout }>();
    let hello: Hello | undefined;
    let nextId = 1;
    let buffer = '';

    const helloTimer = setTimeout(() => fail('no-answer'), timeoutMs);
    const fail = (reason: Unreachable, protocol?: unknown) => {
      clearTimeout(helloTimer);
      socket.destroy();
      reject(new ControlUnreachable(reason, protocol));
    };
    const settle = (id: number, finish: (entry: NonNullable<ReturnType<typeof pending.get>>) => void) => {
      const entry = pending.get(id);
      if (entry === undefined) return;
      clearTimeout(entry.timer);
      pending.delete(id);
      finish(entry);
    };

    const onLine = (line: string) => {
      let message: any;
      try {
        message = JSON.parse(line);
      } catch {
        return hello === undefined ? fail('incompatible') : undefined;
      }
      if (hello === undefined) {
        if (message?.event !== 'hello' || message.protocol !== 1) return fail('incompatible', message?.event === 'hello' ? message.protocol : undefined);
        clearTimeout(helloTimer);
        hello = message as Hello;
        return resolve({ hello, request, close: () => socket.destroy() });
      }
      // the server answers in order, so a reply without an id (a request it could not read) belongs to the oldest one
      const id: number | undefined = message.id ?? pending.keys().next().value;
      if (id === undefined) return;
      settle(id, (entry) => (message.ok === true ? entry.resolve(message.data) : entry.reject(new Error(String(message.error)))));
    };

    socket.on('data', (chunk: string) => {
      buffer += chunk;
      for (let end = buffer.indexOf('\n'); end >= 0; end = buffer.indexOf('\n')) {
        const line = buffer.slice(0, end);
        buffer = buffer.slice(end + 1);
        onLine(line);
      }
    });
    socket.on('error', (error: NodeJS.ErrnoException) => {
      if (hello === undefined) fail(nobodyListening.has(error.code ?? '') ? 'not-running' : 'no-answer');
    });
    socket.on('close', () => {
      if (hello === undefined) return fail('no-answer');
      for (const id of [...pending.keys()]) settle(id, (entry) => entry.reject(new ControlUnreachable('no-answer')));
    });

    function request(cmd: string, fields: Record<string, unknown> = {}): Promise<unknown> {
      if (socket.destroyed) return Promise.reject(new ControlUnreachable('no-answer'));
      return new Promise((resolveRequest, rejectRequest) => {
        const id = nextId++;
        const timer = setTimeout(() => settle(id, (entry) => entry.reject(new ControlUnreachable('no-answer'))), timeoutMs);
        pending.set(id, { resolve: resolveRequest, reject: rejectRequest, timer });
        socket.write(`${JSON.stringify({ ...fields, id, cmd })}\n`);
      });
    }
  });
}
