import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { acquireLock } from './lock.ts';

const holder = join(import.meta.dirname, 'lock-holder.fixture.ts');
let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-lock-'));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
});

// Starts a child that tries to take the lock; resolves once it reports 'locked' or 'busy'.
async function start(folder: string) {
  const child = spawn(process.execPath, [holder, folder]);
  const closed = once(child, 'close');
  const [chunk] = await once(child.stdout, 'data');
  return { child, closed, outcome: String(chunk).trim() };
}

test('a second acquire on the same folder is refused, and works again after release', () => {
  const first = acquireLock(dir);
  expect(first.ok).toBe(true);
  expect(acquireLock(dir).ok).toBe(false);
  if (first.ok) first.release();
  const again = acquireLock(dir);
  expect(again.ok).toBe(true);
  if (again.ok) again.release();
});

test('different folders each get their own lock', () => {
  const a = acquireLock(join(dir, 'a'));
  const b = acquireLock(join(dir, 'b'));
  expect([a.ok, b.ok]).toEqual([true, true]);
  for (const lock of [a, b]) if (lock.ok) lock.release();
});

test('after kill -9 of the holder a new start gets the lock', async () => {
  const first = await start(dir);
  expect(first.outcome).toBe('locked');
  expect((await start(dir)).outcome).toBe('busy');
  first.child.kill('SIGKILL');
  await first.closed;
  const next = await start(dir);
  expect(next.outcome).toBe('locked');
  next.child.stdin.end();
  await next.closed;
});

test('with 20 simultaneous starts exactly one gets the lock', async () => {
  const runs = await Promise.all(Array.from({ length: 20 }, () => start(dir)));
  expect(runs.filter((r) => r.outcome === 'locked')).toHaveLength(1);
  for (const r of runs) r.child.stdin.end();
  await Promise.all(runs.map((r) => r.closed));
});
