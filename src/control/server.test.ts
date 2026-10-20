import { chmodSync, existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { connect, type Socket } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { acquireLock } from '../storage/lock.ts';
import { socketPathFits, startControlServer } from './server.ts';

let dir: string;
let sockets: Socket[];
let closers: (() => void)[];
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cs-')) // short: a socket path holds 103 bytes on macOS;
  sockets = [];
  closers = [];
});
afterEach(() => {
  for (const socket of sockets) socket.destroy();
  for (const close of closers) close();
  rmSync(dir, { recursive: true, force: true });
});

const snapshotData = { now: 1, epics: [{ repo: 'AshuLab/a', issue: 5 }] };
const path = () => join(dir, 'control.sock');

// Fake controls: a pause flag the snapshot reads, a counter of checks, and one execution with output.
const executionId = '3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c';
function fakeControls() {
  const state = { paused: false, polls: 0 };
  const logs = vi.fn((id: string, count: number) => (id === executionId ? ['one', 'two', 'three'].slice(-count) : []));
  return { state, logs, controls: { poll: () => void state.polls++, setPaused: (paused: boolean) => void (state.paused = paused), logs } };
}

const stop = async () => {};

async function open(snapshot: () => unknown = () => snapshotData, controls = fakeControls().controls) {
  const server = await startControlServer({ orchestratorDir: dir, snapshot, startedAt: 1234, controls, stop });
  closers.push(server.close);
  return server;
}

// A plain client: the lines it sends are the ones the app sends, and `next()` resolves with the next line received.
async function client() {
  const socket = connect(path());
  sockets.push(socket);
  socket.setEncoding('utf8');
  const lines: string[] = [];
  const waiting: ((line: string) => void)[] = [];
  let buffer = '';
  let closed = false;
  socket.on('data', (chunk: string) => {
    buffer += chunk;
    for (let end = buffer.indexOf('\n'); end >= 0; end = buffer.indexOf('\n')) {
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 1);
      (waiting.shift() ?? ((l) => lines.push(l)))(line);
    }
  });
  socket.on('close', () => (closed = true));
  socket.on('error', () => {});
  const next = () => new Promise<any>((resolve) => (lines.length > 0 ? resolve(JSON.parse(lines.shift()!)) : waiting.push((line) => resolve(JSON.parse(line)))));
  const hello = await next();
  return {
    hello,
    socket,
    next,
    ask: async (line: string) => (socket.write(`${line}\n`), next()),
    isClosed: () => closed,
    closedEvent: () => new Promise<void>((resolve) => (closed ? resolve() : socket.once('close', () => resolve()))),
  };
}

test('a client gets a hello, and the snapshot as JSON when it asks', async () => {
  await open();
  const c = await client();
  expect(c.hello).toEqual({ event: 'hello', protocol: 1, pid: process.pid, startedAt: 1234 });
  expect(await c.ask('{"id":1,"cmd":"snapshot"}')).toEqual({ id: 1, ok: true, data: snapshotData });
  expect(await c.ask('{"id":7,"cmd":"snapshot"}')).toMatchObject({ id: 7, ok: true });
});

test('several requests in one write get one reply each, in order, and a request split across writes is one request', async () => {
  await open();
  const c = await client();
  c.socket.write('{"id":1,"cmd":"snapshot"}\n{"id":2,"cmd":"snap');
  expect((await c.next()).id).toBe(1);
  c.socket.write('shot"}\n');
  expect((await c.next()).id).toBe(2);
});

test('every command in the schema gets a real reply, none is "not supported"', async () => {
  const stopped = vi.fn(async () => {});
  const server = await startControlServer({ orchestratorDir: dir, snapshot: () => snapshotData, startedAt: 1234, controls: fakeControls().controls, stop: stopped });
  closers.push(server.close);
  const c = await client();
  const commands = [
    '{"id":1,"cmd":"snapshot"}',
    '{"id":2,"cmd":"pause"}',
    '{"id":3,"cmd":"resume"}',
    '{"id":4,"cmd":"checkNow"}',
    `{"id":5,"cmd":"tail","executionId":"${executionId}","lines":1}`,
    '{"id":6,"cmd":"stop"}',
  ];
  for (const [index, line] of commands.entries()) expect(await c.ask(line)).toMatchObject({ id: index + 1, ok: true });
  await vi.waitFor(() => expect(stopped).toHaveBeenCalledTimes(1));
});

test('pause and resume reply ok and the next snapshot shows it', async () => {
  const fake = fakeControls();
  await open(() => ({ paused: fake.state.paused }), fake.controls);
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"pause"}')).toEqual({ id: 1, ok: true });
  expect((await c.ask('{"id":2,"cmd":"snapshot"}')).data).toEqual({ paused: true });
  expect(await c.ask('{"id":3,"cmd":"resume"}')).toEqual({ id: 3, ok: true });
  expect((await c.ask('{"id":4,"cmd":"snapshot"}')).data).toEqual({ paused: false });
});

test('checkNow replies ok and starts one GitHub check', async () => {
  const fake = fakeControls();
  await open(undefined, fake.controls);
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"checkNow"}')).toEqual({ id: 1, ok: true });
  expect(fake.state.polls).toBe(1);
});

test('tail replies the lines the panel shows, and an empty array for an execution with no output', async () => {
  const fake = fakeControls();
  await open(undefined, fake.controls);
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"tail","executionId":"${executionId}","lines":2}`)).toEqual({ id: 1, ok: true, data: ['two', 'three'] });
  expect(fake.logs).toHaveBeenCalledWith(executionId, 2);
  expect(await c.ask('{"id":2,"cmd":"tail","executionId":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","lines":500}')).toEqual({ id: 2, ok: true, data: [] });
});

test.each([
  ['a path', '"../../etc/passwd"', 5],
  ['an empty id', '""', 5],
  ['a UUID with a suffix', `"${executionId}/.."`, 5],
  ['no id', 'null', 5],
  ['zero lines', `"${executionId}"`, 0],
  ['501 lines', `"${executionId}"`, 501],
  ['a fractional count', `"${executionId}"`, 1.5],
  ['a string count', `"${executionId}"`, '"5"'],
  ['no count', `"${executionId}"`, undefined],
])('a tail with %s is a validation error and reads nothing', async (_name, id, lines) => {
  const fake = fakeControls();
  await open(undefined, fake.controls);
  const c = await client();
  const count = lines === undefined ? '' : `,"lines":${lines}`;
  expect(await c.ask(`{"id":3,"cmd":"tail","executionId":${id}${count}}`)).toEqual({ id: 3, ok: false, error: 'invalid request' });
  expect(fake.logs).not.toHaveBeenCalled();
});

test('a control that throws is an error reply, not a dead server', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  const fake = fakeControls();
  fake.logs.mockImplementationOnce(() => {
    throw new Error('disk is gone');
  });
  await open(undefined, fake.controls);
  const c = await client();
  expect(await c.ask(`{"id":1,"cmd":"tail","executionId":"${executionId}","lines":5}`)).toEqual({ id: 1, ok: false, error: 'internal error' });
  expect(await c.ask('{"id":2,"cmd":"snapshot"}')).toMatchObject({ id: 2, ok: true });
});

test.each([
  ['not JSON', 'hello', null],
  ['an empty line', '', null],
  ['{}', '{}', null],
  ['null', 'null', null],
  ['an array', '[{"id":1,"cmd":"snapshot"}]', null],
  ['a number', '5', null],
  ['a missing id', '{"cmd":"snapshot"}', null],
  ['a zero id', '{"id":0,"cmd":"snapshot"}', null],
  ['a negative id', '{"id":-1,"cmd":"snapshot"}', null],
  ['a fractional id', '{"id":1.5,"cmd":"snapshot"}', null],
  ['a string id', '{"id":"1","cmd":"snapshot"}', null],
  ['a huge id', '{"id":1e400,"cmd":"snapshot"}', null],
  ['an unsafe integer id', '{"id":99999999999999999999,"cmd":"snapshot"}', null],
  ['a null id', '{"id":null,"cmd":"snapshot"}', null],
  ['a missing command', '{"id":3}', 3],
  ['an unknown command', '{"id":3,"cmd":"reboot"}', 3],
  ['an inherited name', '{"id":3,"cmd":"toString"}', 3],
  ['another inherited name', '{"id":3,"cmd":"constructor"}', 3],
  ['a command that is not a string', '{"id":3,"cmd":["snapshot"]}', 3],
  ['an extra field', '{"id":3,"cmd":"snapshot","extra":1}', 3],
  ['a __proto__ key', '{"id":3,"cmd":"snapshot","__proto__":{"cmd":"stop"}}', 3],
  ['a tail without its fields', '{"id":3,"cmd":"tail"}', 3],
  ['a tail with an id that is not a UUID', '{"id":3,"cmd":"tail","executionId":"../../etc/passwd","lines":5}', 3],
  ['a tail with too many lines', '{"id":3,"cmd":"tail","executionId":"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c","lines":501}', 3],
  ['a snapshot with tail fields', '{"id":3,"cmd":"snapshot","executionId":"3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c","lines":5}', 3],
])('%s gets an error reply, the connection stays open and the snapshot is never taken', async (_name, line, id) => {
  const snapshot = vi.fn(() => snapshotData);
  await open(snapshot);
  const c = await client();
  const reply = await c.ask(line);
  expect(reply).toMatchObject({ id, ok: false });
  expect(typeof reply.error).toBe('string');
  expect(snapshot).not.toHaveBeenCalled();
  // still usable
  expect(await c.ask('{"id":9,"cmd":"snapshot"}')).toMatchObject({ id: 9, ok: true });
});

test('a line over 16 KiB gets the error reply and the connection is closed', async () => {
  const snapshot = vi.fn(() => snapshotData);
  await open(snapshot);
  const c = await client();
  c.socket.write(`{"id":1,"cmd":"snapshot","pad":"${'x'.repeat(16 * 1024)}"}\n`);
  expect(await c.next()).toEqual({ id: null, ok: false, error: 'line too long' });
  await c.closedEvent();
  expect(snapshot).not.toHaveBeenCalled();
});

test('a client that never sends a newline cannot grow the buffer past 16 KiB either', async () => {
  await open();
  const c = await client();
  c.socket.write('x'.repeat(16 * 1024 + 1));
  expect(await c.next()).toMatchObject({ ok: false, error: 'line too long' });
  await c.closedEvent();
});

test('a failing snapshot is an error reply, not a dead server', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  let fail = true;
  await open(() => {
    if (fail) throw new Error('db is gone');
    return snapshotData;
  });
  const c = await client();
  expect(await c.ask('{"id":1,"cmd":"snapshot"}')).toEqual({ id: 1, ok: false, error: 'internal error' });
  fail = false;
  expect(await c.ask('{"id":2,"cmd":"snapshot"}')).toMatchObject({ id: 2, ok: true });
});

test('the socket is 0600 and orchestrator/ is 0700, also when the folder existed with a looser mode', async () => {
  const folder = join(dir, 'orchestrator');
  mkdirSync(folder);
  chmodSync(folder, 0o755);
  const lock = acquireLock(folder);
  expect(lock.ok).toBe(true);
  const server = await startControlServer({ orchestratorDir: folder, snapshot: () => snapshotData, startedAt: 1, controls: fakeControls().controls, stop });
  expect(statSync(folder).mode & 0o777).toBe(0o700);
  expect(statSync(join(folder, 'control.sock')).mode & 0o777).toBe(0o600);
  server.close();
  if (lock.ok) lock.release();
});

test('the umask is back as it was once the socket is open', async () => {
  const before = process.umask();
  await open();
  expect(process.umask()).toBe(before);
});

test('closing removes the socket file at once and drops the connections', async () => {
  const server = await open();
  const c = await client();
  expect(existsSync(path())).toBe(true);
  server.close();
  // synchronous: it is gone before the next line of the caller, which is where the lock is released
  expect(existsSync(path())).toBe(false);
  await c.closedEvent();
});

test('a leftover socket file is replaced by a new one that works', async () => {
  writeFileSync(path(), 'leftover of a crash');
  await open();
  expect((await client()).hello.event).toBe('hello');
});

test('a socket that cannot open is logged and leaves a server that closes without failing', async () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  const server = await startControlServer({ orchestratorDir: join(dir, 'missing', 'folder'), snapshot: () => snapshotData, startedAt: 1, controls: fakeControls().controls, stop });
  expect(() => server.close()).not.toThrow();
});

// A root under `dir` whose socket path is `socketBytes` long, padded with `fill`; the folder exists, so a truncated name would be created in it.
const rootOf = (socketBytes: number, fill: string) => {
  const suffix = '/orchestrator/control.sock'.length;
  const pad = Math.ceil((socketBytes - suffix - dir.length - 1) / Buffer.byteLength(fill));
  return join(dir, fill.repeat(pad));
};

test('the path fits up to 103 bytes, counted in bytes and not in characters', () => {
  expect(socketPathFits('a'.repeat(103))).toEqual({ fits: true, bytes: 103 });
  expect(socketPathFits('a'.repeat(104))).toEqual({ fits: false, bytes: 104 });
  expect(socketPathFits('é'.repeat(52))).toEqual({ fits: false, bytes: 104 }); // 52 characters
});

test.each([
  ['a long root', 'x', 120],
  ['a root of multi-byte characters under 103 characters but over 103 bytes', 'é', 110],
])('%s: no socket file anywhere and a warning with the path and its length', async (_name, fill, bytes) => {
  const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
  const orchestratorDir = join(rootOf(bytes, fill), 'orchestrator');
  mkdirSync(orchestratorDir, { recursive: true });
  const before = readdirSync(dir, { recursive: true }).sort();
  const full = join(orchestratorDir, 'control.sock');
  expect(Buffer.byteLength(full)).toBeGreaterThan(103);
  if (fill === 'é') expect(full.length).toBeLessThan(103);

  const server = await startControlServer({ orchestratorDir, snapshot: () => snapshotData, startedAt: 1, controls: fakeControls().controls, stop });

  expect(readdirSync(dir, { recursive: true }).sort()).toEqual(before);
  const logged = warn.mock.calls.flat().join(' ');
  expect(logged).toContain(full);
  expect(logged).toContain(`${Buffer.byteLength(full)} bytes`);
  expect(() => server.close()).not.toThrow();
});
