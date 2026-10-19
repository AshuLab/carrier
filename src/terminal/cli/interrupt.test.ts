import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { acquireLock } from '../../storage/lock.ts';

const holder = join(import.meta.dirname, 'interrupt-holder.fixture.ts');
let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-sigint-'));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

test('SIGINT in the middle of two runs stops them fast, keeps epics running and sessions saved, frees the lock and writes nothing to GitHub', async () => {
  const child = spawn(process.execPath, [holder, dir], { stdio: ['ignore', 'pipe', 'inherit'] });
  const closed = once(child, 'close');
  const [chunk] = await once(child.stdout, 'data');
  expect(String(chunk).trim()).toBe('ready');

  const sentAt = Date.now();
  child.kill('SIGINT');
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
  expect(writes).toContain('SIGINT');
  expect(writes.slice(writes.indexOf('SIGINT') + 1)).toEqual([]);
});

test('restarting after Ctrl+C resumes the interrupted runs with their saved sessions, verifying the real state first, and launches no second author', async () => {
  const start = async () => {
    const child = spawn(process.execPath, [holder, dir], { stdio: ['ignore', 'pipe', 'inherit'] });
    const closed = once(child, 'close');
    expect(String((await once(child.stdout, 'data'))[0]).trim()).toBe('ready');
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
