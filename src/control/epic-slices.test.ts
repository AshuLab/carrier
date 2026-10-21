import { mkdtempSync, rmSync } from 'node:fs';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import { FakeAgentRunner, FakeWorkspaces } from '../execution/fake.ts';
import { createEngine } from '../orchestration/engine.ts';
import { FakeClock, FakeGitHub } from '../orchestration/fake.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { epicOf } from './epic.ts';
import { startControlServer } from './server.ts';

// The slices a poll cached, served by the epic request over a real socket from a real (temp) SQLite, with the engine and a fake GitHub.
const MIN = 60_000;
const agent = { profile: 'p', harness: 'claude' as const, model: 'm' };
const repos: EffectiveRepoConfig[] = [{ name: 'AshuLab/a', agents: { author: agent, reviewer: agent } }];

let dir: string;
let db: Db;
let close: () => void;
beforeEach(async () => {
  dir = mkdtempSync(join(tmpdir(), 'cs-')); // short: a socket path holds 103 bytes on macOS
  db = openDatabase(join(dir, 'carrier.db'));
  const controls = { poll: () => {}, setPaused: () => {}, logs: () => [], sessions: () => null, epic: (repo: string, issue: number) => epicOf(db, repo, issue) };
  close = (await startControlServer({ orchestratorDir: dir, snapshot: () => ({}), startedAt: 1, controls, stop: async () => {} })).close;
});
afterEach(() => {
  close();
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

async function askEpic() {
  const socket = connect(join(dir, 'control.sock'));
  socket.setEncoding('utf8');
  const lines: string[] = [];
  const waiting: ((line: string) => void)[] = [];
  let buffer = '';
  socket.on('data', (chunk: string) => {
    buffer += chunk;
    for (let end = buffer.indexOf('\n'); end >= 0; end = buffer.indexOf('\n')) {
      const line = buffer.slice(0, end);
      buffer = buffer.slice(end + 1);
      (waiting.shift() ?? ((l) => lines.push(l)))(line);
    }
  });
  const next = () => new Promise<string>((resolve) => (lines.length ? resolve(lines.shift()!) : waiting.push(resolve)));
  await next(); // hello
  socket.write(`${JSON.stringify({ id: 1, cmd: 'epic', repo: 'AshuLab/a', issue: 1 })}\n`);
  const reply = JSON.parse(await next());
  socket.destroy();
  return reply;
}

test('the epic reply carries the cached slices with their read time and says when the list is partial', async () => {
  const github = new FakeGitHub();
  const clock = new FakeClock();
  const runner = new FakeAgentRunner();
  runner.behavior = () => ({ exit: 'stopped' }); // the epic stays running
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  github.slices['AshuLab/a#1'] = {
    truncated: true,
    slices: [
      { number: 12, title: 'Second', state: 'waiting', blockedBy: [10, 11], assignee: null, prNumber: null, closedAt: null },
      { number: 10, title: 'First', state: 'closed', blockedBy: [], assignee: 'someone', prNumber: 30, closedAt: 1_000 },
    ],
  };
  const engine = createEngine({ db, github, clock, repos, pollIntervalMs: 5 * MIN, maxConcurrentEpics: 1, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, runner, workspaces: new FakeWorkspaces(), root: dir });
  await engine.start();
  await clock.advance(5 * MIN); // reserved
  await clock.advance(5 * MIN); // read while running
  engine.stop();

  const { ok, data } = await askEpic();
  expect(ok).toBe(true);
  expect(data.slices).toEqual([
    { number: 10, title: 'First', state: 'closed', blockedBy: [], prNumber: 30, closedAt: 1_000, readAt: 10 * MIN },
    { number: 12, title: 'Second', state: 'waiting', blockedBy: [10, 11], prNumber: null, closedAt: null, readAt: 10 * MIN },
  ]);
  expect(data.slicesTruncated).toBe(true);
});

test('an epic whose slices were never read answers an empty list that is not partial', async () => {
  const github = new FakeGitHub();
  const clock = new FakeClock();
  github.ready = { 'AshuLab/a': [{ issue: 1, title: '' }] };
  const engine = createEngine({ db, github, clock, repos, pollIntervalMs: 5 * MIN, maxConcurrentEpics: 0, maxExecutionHours: 4, maxExecutionRetries: 3, maxReviews: 5, runner: new FakeAgentRunner(), workspaces: new FakeWorkspaces(), root: dir });
  await engine.start();
  await clock.advance(5 * MIN);
  engine.stop();
  expect((await askEpic()).data).toMatchObject({ slices: [], slicesTruncated: false });
});
