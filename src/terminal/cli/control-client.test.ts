import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createServer, type Server, type Socket } from 'node:net';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import type { EpicReply, EventsReply, FilesReply } from '../../control/replies.ts';
import { startControlServer } from '../../control/server.ts';
import { connectControl, ControlUnreachable } from './control-client.ts';

let dir: string;
let closers: (() => void)[];
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cc-')); // short: a socket path holds 103 bytes on macOS
  closers = [];
});
afterEach(() => {
  for (const close of closers) close();
  rmSync(dir, { recursive: true, force: true });
});

const path = () => join(dir, 'control.sock');
const snapshotData = { now: 1, epics: [{ repo: 'AshuLab/a', issue: 5 }] };
const controls = {
  poll: () => {},
  setPaused: () => {},
  logs: () => [],
  sessions: () => ({ sessions: [] }),
  events: (): EventsReply | null => ({ events: [], next: 0, running: false, structured: true }),
  epic: (): EpicReply | null => null,
  files: (): FilesReply | null => null,
  availableRepos: () => Promise.resolve([]), resumeEpic: () => Promise.resolve(),
};

async function realServer() {
  const server = await startControlServer({ orchestratorDir: dir, snapshot: () => snapshotData, startedAt: 1234, controls, stop: async () => {} });
  closers.push(server.close);
}

// A hand-made server for what the real one never does: answer late, or say something else.
async function fakeServer(onConnect: (socket: Socket) => void): Promise<Server> {
  const server = createServer(onConnect);
  await new Promise<void>((resolve) => server.listen(path(), resolve));
  closers.push(() => server.close());
  return server;
}
const hello = (protocol: number) => `${JSON.stringify({ event: 'hello', protocol, pid: 1, startedAt: 1, version: '0.0.0', capabilities: [] })}\n`;

async function reason(promise: Promise<unknown>) {
  const error = await promise.then(
    () => null,
    (caught) => caught,
  );
  expect(error).toBeInstanceOf(ControlUnreachable);
  return (error as ControlUnreachable).reason;
}

test('connect returns the hello and a request resolves with the data of its reply', async () => {
  await realServer();
  const client = await connectControl(path());
  closers.push(client.close);
  expect(client.hello).toMatchObject({ event: 'hello', protocol: 1, pid: process.pid, capabilities: ['sessions', 'events', 'epic', 'files', 'availableRepos', 'resumeEpic'] });
  expect(typeof client.hello.version).toBe('string');
  expect(await client.request('snapshot')).toEqual(snapshotData);
  expect(await client.request('pause')).toBeUndefined();
});

test('two requests in flight resolve each with its own reply', async () => {
  const socks: Socket[] = [];
  await fakeServer((socket) => {
    socks.push(socket);
    socket.setEncoding('utf8');
    socket.write(hello(1));
    let seen = '';
    socket.on('data', (chunk: string) => {
      seen += chunk;
      const ids = seen.split('\n').filter(Boolean).map((line) => JSON.parse(line).id as number);
      if (ids.length < 2) return;
      // answered in the opposite order
      for (const id of ids.reverse()) socket.write(`${JSON.stringify({ id, ok: true, data: `reply ${id}` })}\n`);
    });
  });
  const client = await connectControl(path());
  closers.push(client.close);
  const first = client.request('snapshot');
  const second = client.request('snapshot', { extra: true });
  expect(await first).toBe('reply 1');
  expect(await second).toBe('reply 2');
});

test('the fields of a request go to the server next to the id and the cmd', async () => {
  await realServer();
  const client = await connectControl(path());
  closers.push(client.close);
  expect(await client.request('sessions', { repo: 'AshuLab/a', issue: 5 })).toEqual({ sessions: [] });
});

test('a socket file that is not there is not-running', async () => {
  expect(await reason(connectControl(path()))).toBe('not-running');
});

test('a stale socket file nobody listens on is not-running', async () => {
  const server = await fakeServer(() => {});
  server.close();
  await new Promise((resolve) => setTimeout(resolve, 20));
  // closing a net server removes the file, so leave a plain file where the socket was: nothing listens there
  writeFileSync(path(), '');
  expect(await reason(connectControl(path()))).toBe('not-running');
});

test('a path that does not fit the socket limit is not-running, without trying to connect', async () => {
  expect(await reason(connectControl(join(dir, 'x'.repeat(120), 'control.sock')))).toBe('not-running');
});

test('a server that does not say hello within the timeout is no-answer', async () => {
  await fakeServer(() => {});
  expect(await reason(connectControl(path(), { timeoutMs: 50 }))).toBe('no-answer');
});

test('a server that answers a request late is no-answer, and the client stays usable for the next one', async () => {
  let held = true;
  await fakeServer((socket) => {
    socket.setEncoding('utf8');
    socket.write(hello(1));
    socket.on('data', (chunk: string) => {
      const { id } = JSON.parse(chunk.split('\n')[0]!);
      if (held) return void (held = false);
      socket.write(`${JSON.stringify({ id, ok: true, data: 'late but here' })}\n`);
    });
  });
  const client = await connectControl(path(), { timeoutMs: 50 });
  closers.push(client.close);
  expect(await reason(client.request('snapshot'))).toBe('no-answer');
  expect(await client.request('snapshot')).toBe('late but here');
});

test('a hello whose protocol is not 1 is incompatible', async () => {
  await fakeServer((socket) => socket.write(hello(2)));
  expect(await reason(connectControl(path()))).toBe('incompatible');
  expect(await connectControl(path()).catch((error) => error.protocol)).toBe(2);
});

test('something that is not a hello is incompatible', async () => {
  await fakeServer((socket) => socket.write('not json\n'));
  expect(await reason(connectControl(path()))).toBe('incompatible');
});

test('an ok:false reply rejects with its error text', async () => {
  await realServer();
  const client = await connectControl(path());
  closers.push(client.close);
  await expect(client.request('epic', { repo: 'AshuLab/a', issue: 5 })).rejects.toThrow('unknown epic');
  await expect(client.request('nonsense')).rejects.toThrow('invalid request');
});

test('close ends the connection, and a request after it is no-answer', async () => {
  let onGone = () => {};
  const gone = new Promise<void>((resolve) => (onGone = resolve));
  await fakeServer((socket) => {
    socket.write(hello(1));
    socket.on('close', () => onGone());
  });
  const client = await connectControl(path());
  client.close();
  await gone;
  expect(await reason(client.request('snapshot'))).toBe('no-answer');
});

test('a connection that drops while a request waits rejects that request as no-answer', async () => {
  await fakeServer((socket) => {
    socket.write(hello(1));
    socket.on('data', () => socket.destroy());
  });
  const client = await connectControl(path());
  expect(await reason(client.request('snapshot'))).toBe('no-answer');
});

test('after close nothing keeps the process alive', async () => {
  await fakeServer((socket) => socket.write(hello(1)));
  const script = `import { connectControl } from ${JSON.stringify(new URL('./control-client.ts', import.meta.url).href)}; const client = await connectControl(${JSON.stringify(path())}); client.close();`;
  // the child must end by itself: execFile kills it at the timeout, which fails the test
  await promisify(execFile)(process.execPath, ['--input-type=module', '-e', script], { timeout: 5000, killSignal: 'SIGKILL' });
}, 10_000);
