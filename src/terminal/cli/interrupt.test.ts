import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
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
  const db = new Database(join(dir, 'orchestrator', 'carrier.db'), { readonly: true });
  expect(db.prepare('select status from epics order by id').all()).toEqual([{ status: 'running' }, { status: 'running' }, { status: 'queued' }]);
  expect(db.prepare('select status, sessionId, finishedAt is not null as finished from executions order by rowid').all()).toEqual([
    { status: 'interrupted', sessionId: 's-1', finished: 1 },
    { status: 'interrupted', sessionId: 's-2', finished: 1 },
  ]);
  db.close();

  const lock = acquireLock(join(dir, 'orchestrator'));
  expect(lock.ok).toBe(true);
  if (lock.ok) lock.release();

  const writes = readFileSync(join(dir, 'writes.log'), 'utf8').trim().split('\n');
  expect(writes).toContain(sent);
  expect(writes.slice(writes.indexOf(sent) + 1)).toEqual([]);
});

test('a runner whose stop never finishes: the shutdown gives up after its time limit, frees the lock and exits with 1, leaving the epics running', async () => {
  const { child, closed } = await startHolder('hang', '300');

  child.kill('SIGTERM');
  expect((await closed)[0]).toBe(1);

  const db = new Database(join(dir, 'orchestrator', 'carrier.db'), { readonly: true });
  expect(db.prepare('select status from epics order by id').pluck().all()).toEqual(['running', 'running', 'queued']);
  expect(db.prepare('select status from executions order by rowid').pluck().all()).toEqual(['running', 'running']); // the next start recovers them
  db.close();

  const lock = acquireLock(join(dir, 'orchestrator'));
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

  const db = new Database(join(dir, 'orchestrator', 'carrier.db'), { readonly: true });
  expect(db.prepare('select status from epics order by id').pluck().all()).toEqual(['running', 'running', 'queued']);
  expect(db.prepare('select status from executions order by rowid').pluck().all()).toEqual(['interrupted', 'interrupted', 'interrupted', 'interrupted']);
  db.close();
});
