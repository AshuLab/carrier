import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase } from '../storage/db.ts';
import { executionEvents } from '../storage/events.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';

const script = join(import.meta.dirname, 'replay-events.ts');
const fixture = join(import.meta.dirname, 'claude-events.fixture.jsonl');
const replay = (...args: string[]) => spawnSync('node', [script, ...args], { encoding: 'utf8' });

let dir: string;
beforeEach(() => void (dir = mkdtempSync(join(tmpdir(), 'carrier-replay-'))));
afterEach(() => rmSync(dir, { recursive: true, force: true }));

test('prints the events of a log as JSON lines and exits zero', () => {
  const { status, stdout, stderr } = replay(fixture);
  expect(status).toBe(0);
  expect(stderr).toBe('');
  const events = stdout.trimEnd().split('\n').map((line) => JSON.parse(line));
  expect(events).toHaveLength(14);
  expect(events[0]).toMatchObject({ kind: 'say' });
  expect(events.at(-1)).toMatchObject({ kind: 'error', text: 'API Error: upstream failed' });
});

test('a missing file fails with a clear error and prints no event', () => {
  const { status, stdout, stderr } = replay(join(dir, 'nope.log'));
  expect(status).toBe(1);
  expect(stdout).toBe('');
  expect(stderr).toContain('replay-events: cannot read');
  expect(stderr).toContain('no such file');
});

test('no argument, or one option without the other, is a usage error', () => {
  expect(replay().status).toBe(2);
  expect(replay(fixture, '--db', join(dir, 'x.db')).status).toBe(2);
  expect(replay(fixture, '--db', join(dir, 'x.db')).stderr).toContain('usage');
});

test('with --db and --execution it fills the events of an execution once, and refuses a second time', () => {
  const file = join(dir, 'carrier.db');
  const db = openDatabase(file);
  const epic = db.insert(epics).values({ repo: 'AshuLab/a', issue: 1 }).returning().get();
  db.insert(executions).values({ executionId: 'old', epicId: epic.id, stage: 'ship', resultPath: 'r', startedAt: 0 }).run();
  db.$client.close();

  const first = replay(fixture, '--db', file, '--execution', 'old');
  expect(first.status).toBe(0);
  expect(first.stdout).toContain('stored 14 events for old');
  const again = openDatabase(file);
  expect(again.select().from(executionEvents).all()).toHaveLength(14);
  again.$client.close();

  expect(replay(fixture, '--db', file, '--execution', 'old').stderr).toContain('already has events');
  expect(replay(fixture, '--db', file, '--execution', 'ghost').stderr).toContain('no execution ghost');
  expect(replay(fixture, '--db', join(dir, 'missing.db'), '--execution', 'old').stderr).toContain('no such file');
  writeFileSync(join(dir, 'empty.log'), '');
  expect(replay(join(dir, 'empty.log')).stdout).toBe('');
});
