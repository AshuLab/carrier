import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { openDatabase, type Db } from '../storage/db.ts';
import { createEngine } from './engine.ts';
import { FakeClock, FakeGitHub } from './fake.ts';
import { GitHubUnavailable } from './github.ts';

const MIN = 60_000;
const repos = ['AshuLab/a', 'AshuLab/b'];

let dir: string;
let dbs: Db[];
let github: FakeGitHub;
let clock: FakeClock;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-'));
  dbs = [];
  github = new FakeGitHub();
  clock = new FakeClock();
});
afterEach(() => {
  for (const db of dbs) db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

function start() {
  const db = openDatabase(join(dir, 'carrier.db'));
  dbs.push(db);
  const engine = createEngine({ db, github, clock, repos, pollIntervalMs: 5 * MIN });
  engine.start();
  return engine;
}
const ids = (engine: ReturnType<typeof start>) => engine.queue().map((e) => `${e.repo}#${e.issue}`);

test('registers ready epics of every repo once, and the same issue number in two repos is two epics', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 7, title: 'x' }], 'AshuLab/b': [{ issue: 7, title: 'y' }, { issue: 8, title: 'z' }] };
  const engine = start();

  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#7', 'AshuLab/b#7', 'AshuLab/b#8']);
  expect(engine.queue()[0]).toMatchObject({ status: 'queued', queuedAt: 5 * MIN });

  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#7', 'AshuLab/b#7', 'AshuLab/b#8']);
  expect(github.calls).toBe(4);
});

test('first poll waits one full interval, then repeats every interval', async () => {
  const engine = start();
  await clock.advance(5 * MIN - 1);
  expect(github.calls).toBe(0);
  await clock.advance(1);
  expect(github.calls).toBe(2);
  await clock.advance(5 * MIN);
  expect(github.calls).toBe(4);
  engine.stop();
  await clock.advance(5 * MIN);
  expect(github.calls).toBe(4);
});

test('FIFO order survives a restart on the same SQLite file, and later epics go after', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 9, title: '' }], 'AshuLab/b': [{ issue: 2, title: '' }] };
  const first = start();
  await clock.advance(5 * MIN);
  first.stop();
  dbs.pop()!.$client.close();

  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }, { issue: 9, title: '' }], 'AshuLab/b': [{ issue: 2, title: '' }] };
  const second = start();
  expect(ids(second)).toEqual(['AshuLab/a#9', 'AshuLab/b#2']);
  await clock.advance(5 * MIN);
  expect(ids(second)).toEqual(['AshuLab/a#9', 'AshuLab/b#2', 'AshuLab/a#1']);
});

test('GitHubUnavailable keeps queue and state, exposes the error and backs off to max(interval, retryAfter)', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }], 'AshuLab/b': [] };
  const engine = start();
  await clock.advance(5 * MIN);
  expect(ids(engine)).toEqual(['AshuLab/a#1']);

  github.ready = { 'AshuLab/a': [], 'AshuLab/b': [{ issue: 2, title: '' }] };
  github.unavailable = new GitHubUnavailable(12 * MIN);
  const calls = github.calls;
  await clock.advance(5 * MIN);
  expect(engine.error).toBe(github.unavailable);
  expect(ids(engine)).toEqual(['AshuLab/a#1']);
  expect(engine.queue()[0]?.status).toBe('queued');

  await clock.advance(12 * MIN - 1);
  expect(github.calls).toBe(calls + 1);
  github.unavailable = new GitHubUnavailable(); // no retryAfter: falls back to the interval
  await clock.advance(1);
  expect(github.calls).toBe(calls + 2);

  await clock.advance(5 * MIN);
  expect(github.calls).toBe(calls + 3);

  github.unavailable = null;
  await clock.advance(5 * MIN);
  expect(engine.error).toBeNull();
  expect(ids(engine)).toEqual(['AshuLab/a#1', 'AshuLab/b#2']);
});

test('a failure in one repo registers nothing from the other repos in that poll', async () => {
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  const fail = new GitHubUnavailable();
  github.listReadyEpics = async (repo) => {
    if (repo === 'AshuLab/b') throw fail;
    return [{ issue: 1, title: '' }];
  };
  const engine = start();
  await clock.advance(5 * MIN);
  expect(engine.queue()).toEqual([]);
  expect(engine.error).toBe(fail);
});
