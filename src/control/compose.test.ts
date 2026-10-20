import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { connect } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { defaults, loadConfig } from '../config/load.ts';
import { FakeAgentRunner, FakeWorkspaces } from '../execution/fake.ts';
import { FakeClock, FakeGitHub } from '../orchestration/fake.ts';
import { InstanceBusy, startCarrier, type CarrierDeps } from '../terminal/cli/compose.ts';

// What happens to the socket file when the lock is released: the removal order, seen from the lock's side.
const atRelease: boolean[] = [];
vi.mock('../storage/lock.ts', async (importOriginal) => {
  const { acquireLock } = await importOriginal<typeof import('../storage/lock.ts')>();
  return {
    acquireLock: (dir: string) => {
      const lock = acquireLock(dir);
      return lock.ok ? { ok: true, release: () => (atRelease.push(existsSync(join(dir, 'control.sock'))), lock.release()) } : lock;
    },
  };
});

let root: string;
let closers: (() => void)[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'cc-')) // short: a socket path holds 103 bytes on macOS;
  closers = [];
  atRelease.length = 0;
});
afterEach(() => {
  for (const close of closers) close();
  rmSync(root, { recursive: true, force: true });
});

const sock = () => join(root, 'orchestrator', 'control.sock');
const deps = (): Partial<CarrierDeps> => ({
  installLogging: () => {},
  clock: new FakeClock(),
  makeGitHub: () => new FakeGitHub(),
  makeWorkspaces: () => new FakeWorkspaces(),
  makeRunner: () => new FakeAgentRunner(),
  mint: async () => 'ghs_fake',
  botId: async () => 99,
  sessionDirs: { claude: join(root, 'claude'), codex: join(root, 'codex') },
  panelOut: { write: () => {}, isTTY: false },
  panelIntervalMs: 1000,
  onSigint: () => {},
});
const config = () => {
  const result = loadConfig(defaults, {
    root,
    repos: [{ name: 'AshuLab/a' }],
    profiles: { orchestrator: { kind: 'gh' }, author: { kind: 'forge', agent: 'artanis-agent' }, reviewer: { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'orchestrator',
    agents: { author: { profile: 'author', harness: 'claude', model: 'm' }, reviewer: { profile: 'reviewer', harness: 'codex', model: 'm' } },
  });
  if (!result.ok) throw new Error(JSON.stringify(result.errors));
  return result.config;
};

// The first two lines the socket sends: the hello, and the reply to a snapshot request.
const ask = () =>
  new Promise<string[]>((resolve, reject) => {
    const socket = connect(sock());
    let text = '';
    socket.on('error', reject);
    socket.on('connect', () => socket.write('{"id":1,"cmd":"snapshot"}\n'));
    socket.on('data', (chunk) => {
      text += chunk;
      if (text.split('\n').length > 2) (socket.destroy(), resolve(text.trim().split('\n')));
    });
  });

test('startCarrier opens the socket once the engine is up, serves the panel\'s snapshot, and close removes it before the lock is released', async () => {
  const app = await startCarrier(config(), deps());
  closers.push(() => app.close());

  const [hello, reply] = (await ask()).map((line) => JSON.parse(line));
  expect(hello).toMatchObject({ event: 'hello', protocol: 1, pid: process.pid });
  expect(reply).toMatchObject({ id: 1, ok: true, data: { repos: 1, slots: { busy: 0, total: 3 }, queue: [], epics: [], paused: false } });

  await app.engine.shutdown();
  app.close();
  expect(existsSync(sock())).toBe(false);
  expect(atRelease).toEqual([false]);
});

test('a second carrier on the same folder fails as already running and leaves the live socket alone', async () => {
  const app = await startCarrier(config(), deps());
  closers.push(() => app.close());

  await expect(startCarrier(config(), deps())).rejects.toBeInstanceOf(InstanceBusy);
  expect((await ask())[0]).toContain('"event":"hello"');
});

test('a socket file left by a crash is replaced once the lock is held', async () => {
  const app0 = await startCarrier(config(), deps());
  await app0.engine.shutdown();
  app0.close();
  writeFileSync(sock(), 'leftover of a crash');

  const app = await startCarrier(config(), deps());
  closers.push(() => app.close());
  expect((await ask())[0]).toContain('"event":"hello"');
});

test('the socket pauses and resumes the engine the panel pauses', async () => {
  const app = await startCarrier(config(), deps());
  closers.push(() => app.close());

  const lines = await new Promise<string[]>((resolve, reject) => {
    const socket = connect(sock());
    let text = '';
    socket.on('error', reject);
    socket.on('connect', () => socket.write('{"id":1,"cmd":"pause"}\n{"id":2,"cmd":"snapshot"}\n'));
    socket.on('data', (chunk) => {
      text += chunk;
      if (text.split('\n').length > 3) (socket.destroy(), resolve(text.trim().split('\n')));
    });
  });
  const [, pause, snapshot] = lines.map((line) => JSON.parse(line));
  expect(pause).toEqual({ id: 1, ok: true });
  expect(snapshot.data.paused).toBe(true);
  expect(app.engine.paused).toBe(true);
});
