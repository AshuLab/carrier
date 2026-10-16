import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { acquireLock } from '../storage/lock.ts';

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
