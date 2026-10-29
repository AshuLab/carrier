import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { acquireLock } from '../../storage/lock.ts';
import { createShutdown } from './interrupt.ts';

const holder = join(import.meta.dirname, 'interrupt-holder.fixture.ts');
let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-sigint-'));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

const startHolder = async (...args: string[]) => {
  const child = spawn(process.execPath, [holder, dir, ...args], { stdio: ['ignore', 'pipe', 'inherit'] });
  const closed = once(child, 'close');
  expect(String((await once(child.stdout, 'data'))[0]).trim()).toBe('ready');
  return { child, closed };
};

test.each(['SIGINT', 'SIGTERM', 'SIGHUP'] as const)('%s in the middle of two runs stops them fast, keeps epics running and sessions saved, frees the lock and writes nothing to GitHub', async (sent) => {
  const { child, closed } = await startHolder();

  const sentAt = Date.now();
  child.kill(sent);
  const [code, signal] = await closed;
  expect(Date.now() - sentAt).toBeLessThan(10_000);
  expect([code, signal]).toEqual([0, null]);

  // Reopen the database the process left.
  const db = new Database(join(dir, 'engine', 'state', 'carrier.db'), { readonly: true });
  expect(db.prepare('select status from epics order by id').all()).toEqual([{ status: 'running' }, { status: 'running' }, { status: 'queued' }]);
  expect(db.prepare('select status, sessionId, finishedAt is not null as finished from executions order by rowid').all()).toEqual([
    { status: 'interrupted', sessionId: 's-1', finished: 1 },
    { status: 'interrupted', sessionId: 's-2', finished: 1 },
  ]);
  db.close();

  const lock = acquireLock(join(dir, 'engine', 'state'));
  expect(lock.ok).toBe(true);
  if (lock.ok) lock.release();

  const writes = readFileSync(join(dir, 'writes.log'), 'utf8').trim().split('\n');
  expect(writes).toContain(sent);
  expect(writes.slice(writes.indexOf(sent) + 1).filter((line) => line !== 'shutdown')).toEqual([]);
});

test('a runner whose stop never finishes: the shutdown gives up after its time limit, frees the lock and exits with 1, leaving the epics running', async () => {
  const { child, closed } = await startHolder('hang', '300');

  child.kill('SIGTERM');
  expect((await closed)[0]).toBe(1);

  const db = new Database(join(dir, 'engine', 'state', 'carrier.db'), { readonly: true });
  expect(db.prepare('select status from epics order by id').pluck().all()).toEqual(['running', 'running', 'queued']);
  expect(db.prepare('select status from executions order by rowid').pluck().all()).toEqual(['running', 'running']); // the next start recovers them
  db.close();

  const lock = acquireLock(join(dir, 'engine', 'state'));
  expect(lock.ok).toBe(true);
  if (lock.ok) lock.release();
});

test('a second signal while it is shutting down exits at once with 130', async () => {
  const { child, closed } = await startHolder('hang', '60000');

  child.kill('SIGTERM');
  const writes = () => readFileSync(join(dir, 'writes.log'), 'utf8');
  await vi.waitFor(() => expect(writes()).toContain('SIGTERM')); // the shutdown has started and cannot end
  child.kill('SIGINT');
  expect((await closed)[0]).toBe(130);
});

test('the shutdown can be called without a signal, and calling it twice stops once', async () => {
  const engine = { shutdown: vi.fn(async () => {}) };
  const close = vi.fn();
  const exit = vi.fn();
  const shutdown = createShutdown({ engine, close }, { exit });

  expect(shutdown.running).toBe(false);
  const first = shutdown();
  expect(shutdown.running).toBe(true);
  await Promise.all([first, shutdown()]);

  expect(engine.shutdown).toHaveBeenCalledTimes(1);
  expect(close).toHaveBeenCalledTimes(1);
  expect(exit).toHaveBeenCalledExactlyOnceWith(0);
});

test('restarting after Ctrl+C resumes the interrupted runs with their saved sessions, verifying the real state first, and launches no second author', async () => {
  const start = async () => {
    const { child, closed } = await startHolder();
    return { stop: async () => (child.kill('SIGINT'), (await closed)[0]) };
  };
  const tasks = () => readFileSync(join(dir, 'tasks.log'), 'utf8').trim().split('\n');

  expect(await (await start()).stop()).toBe(0);
  expect(tasks()).toEqual(['1:-:-', '2:-:-']);

  const second = await start();
  await vi.waitFor(() => expect(tasks()).toHaveLength(4));
  expect(tasks()).toEqual(['1:-:-', '2:-:-', '1:s-1:true', '2:s-2:true']); // the third epic stays queued: still two slots
  expect(await second.stop()).toBe(0);

  const db = new Database(join(dir, 'engine', 'state', 'carrier.db'), { readonly: true });
  expect(db.prepare('select status from epics order by id').pluck().all()).toEqual(['running', 'running', 'queued']);
  expect(db.prepare('select status from executions order by rowid').pluck().all()).toEqual(['interrupted', 'interrupted', 'interrupted', 'interrupted']);
  db.close();
});

// A socket client of the real process: `ask` sends a line and resolves with the next reply (the hello is skipped).
async function socketClient() {
  const socket = connect(join(dir, 'engine', 'state', 'control.sock'));
  socket.setEncoding('utf8');
  let buffer = '';
  const lines: string[] = [];
  socket.on('data', (chunk: string) => lines.push(...(buffer += chunk).split('\n').slice(0, -1)) && (buffer = buffer.slice(buffer.lastIndexOf('\n') + 1)));
  socket.on('error', () => {});
  const closed = once(socket, 'close');
  await vi.waitFor(() => expect(lines.shift()).toContain('hello'));
  const ask = async (line: string) => (socket.write(`${line}\n`), await vi.waitFor(() => (expect(lines.length).toBeGreaterThan(0), JSON.parse(lines.shift()!))));
  return { ask, closed };
}

test('stop through the socket: the reply arrives every time, then the same shutdown runs and the connection closes', async () => {
  for (let round = 0; round < 5; round++) {
    const { closed } = await startHolder();
    const client = await socketClient();

    expect(await client.ask('{"id":7,"cmd":"stop"}')).toEqual({ id: 7, ok: true });
    await client.closed;
    expect((await closed)[0]).toBe(0);

    const db = new Database(join(dir, 'engine', 'state', 'carrier.db'), { readonly: true });
    expect(db.prepare('select status from epics order by id').pluck().all()).toEqual(['running', 'running', 'queued']);
    expect(db.prepare('select status, sessionId from executions order by rowid').all()).toEqual([
      { status: 'interrupted', sessionId: 's-1' },
      { status: 'interrupted', sessionId: 's-2' },
    ]);
    db.close();
    expect(existsSync(join(dir, 'engine', 'state', 'control.sock'))).toBe(false);
    const lock = acquireLock(join(dir, 'engine', 'state'));
    expect(lock.ok).toBe(true);
    if (lock.ok) lock.release();
    const writes = readFileSync(join(dir, 'writes.log'), 'utf8').trim().split('\n');
    expect(writes.filter((line) => line === 'shutdown')).toHaveLength(1);
    expect(writes.slice(writes.indexOf('shutdown') + 1)).toEqual([]); // nothing to GitHub after the stop
    rmSync(dir, { recursive: true, force: true });
    dir = mkdtempSync(join(tmpdir(), 'carrier-sigint-'));
  }
});

test('a second stop, or a snapshot, while it is shutting down is answered and starts no second shutdown', async () => {
  const { child, closed } = await startHolder('hang', '60000');
  const client = await socketClient();

  expect(await client.ask('{"id":1,"cmd":"stop"}')).toEqual({ id: 1, ok: true });
  expect(await client.ask('{"id":2,"cmd":"stop"}')).toEqual({ id: 2, ok: true });
  expect(await client.ask('{"id":3,"cmd":"snapshot"}')).toMatchObject({ id: 3, ok: true });
  expect(readFileSync(join(dir, 'writes.log'), 'utf8').match(/^shutdown$/gm)).toHaveLength(1);

  child.kill('SIGINT'); // the shutdown is under way and cannot end: the signal handler sees it running and exits at once
  expect((await closed)[0]).toBe(130);
});
