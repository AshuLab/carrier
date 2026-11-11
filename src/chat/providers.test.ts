import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Machine } from '../doctor/detect.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { createProviders } from './providers.ts';

let home: string;
beforeEach(() => {
  home = mkdtempSync(join(tmpdir(), 'pv-'));
  vi.stubEnv('CARRIER_HOME', home);
});
afterEach(() => {
  rmSync(home, { recursive: true, force: true });
  vi.unstubAllEnvs();
});
const writeFile = (contents: string) => writeFileSync(join(home, 'providers.json'), contents);
const writeProviders = (providers: object) => writeFile(JSON.stringify({ providers }));

/** A Mac with claude and codex on the PATH, no agy, and Ollama serving one model. */
const machine = (over: Partial<Machine> = {}): Machine => ({
  resolveBinary: (name) => {
    if (name === 'agy') throw new Error('not on the PATH');
    return `/opt/bin/${name}`;
  },
  version: async (command) => `${command} 1.0`,
  login: async () => 'in',
  localModels: async (local) => (local === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))),
  ...over,
});
const providers = (over?: Partial<Machine>, clock = new FakeClock(), binaryFound = (command: string) => command !== '/opt/gone') => createProviders({ clock, machine: machine(over), binaryFound });

test('each account has its state, found by its own binary and judged by its own login folder', async () => {
  writeProviders({ claude: { harness: 'claude' }, 'claude-work': { harness: 'claude', configDir: '/logins/work', displayName: 'Work' }, mine: { harness: 'codex', command: '/opt/mine/codex' }, gone: { harness: 'codex', command: '/opt/gone' } });
  const asked: unknown[] = [];
  const reply = await providers({ login: async (harness, configDir) => (asked.push([harness, configDir]), configDir === '/logins/work' ? 'out' : 'in') })();
  expect(reply.accounts).toEqual([
    { name: 'claude', harness: 'claude', found: true, path: '/opt/bin/claude', version: '/opt/bin/claude 1.0', state: 'ready' },
    { name: 'claude-work', harness: 'claude', displayName: 'Work', configDir: '/logins/work', found: true, path: '/opt/bin/claude', version: '/opt/bin/claude 1.0', state: 'signedOut' },
    { name: 'mine', harness: 'codex', command: '/opt/mine/codex', found: true, path: '/opt/mine/codex', version: '/opt/mine/codex 1.0', state: 'ready' },
    { name: 'gone', harness: 'codex', command: '/opt/gone', found: false, state: 'missing' },
  ]);
  expect(asked).toContainEqual(['claude', '/logins/work']);
  expect(asked).toContainEqual(['claude', undefined]);
});

test('a harness found with no account is unadded, and the servers say what answers', async () => {
  writeProviders({ claude: { harness: 'claude' } });
  const reply = await providers()();
  expect(reply.unadded).toEqual([{ harness: 'codex', path: '/opt/bin/codex', version: '/opt/bin/codex 1.0' }]); // agy is not found, claude has an account
  expect(reply.servers).toEqual([{ kind: 'lmstudio', running: false, models: [] }, { kind: 'ollama', running: true, models: ['qwen3:8b'] }]);
  expect(reply.problem).toBeUndefined();
});

test('without a providers.json the accounts are the default ones', async () => {
  const reply = await providers()();
  expect(reply.accounts.map(({ name }) => name)).toEqual(['claude', 'codex', 'agy']);
  expect(reply.accounts.find((account) => account.name === 'agy')).toMatchObject({ found: false, state: 'missing' });
  expect(reply.unadded).toEqual([]);
});

test('a version that cannot be read is absent, not empty', async () => {
  writeProviders({ claude: { harness: 'claude' }, mine: { harness: 'codex', command: '/opt/mine/codex' } });
  for (const version of [async () => undefined, async () => '  ', async () => Promise.reject(new Error('no'))]) {
    const reply = await providers({ version })();
    for (const account of reply.accounts) expect(account).not.toHaveProperty('version');
    expect(reply.accounts.map((account) => account.state)).toEqual(['ready', 'ready']);
  }
});

test('a login that does not answer in five seconds is unknown, and so is one that cannot tell', async () => {
  writeProviders({ claude: { harness: 'claude' }, codex: { harness: 'codex' } });
  const clock = new FakeClock();
  const answer = providers({ login: (harness) => (harness === 'claude' ? new Promise(() => {}) : Promise.reject(new Error('cannot tell'))) }, clock)();
  await new Promise((resolve) => setImmediate(resolve)); // the probes have started and their limits are set
  await clock.advance(5_000);
  expect((await answer).accounts.map(({ name, state }) => [name, state])).toEqual([['claude', 'unknown'], ['codex', 'unknown']]);
});

test('a providers.json that does not match answers the problem with the key and no accounts', async () => {
  writeFile(JSON.stringify({ providers: { claude: { harness: 'claude', autoCompact: '300000' } } }));
  const reply = await providers()();
  expect(reply).toMatchObject({ accounts: [], unadded: [], servers: [], problem: { path: 'providers.claude.autoCompact' } });
  expect(reply.problem?.message).toBeTruthy();
  writeFile('{ not json');
  expect((await providers()()).problem).toMatchObject({ path: '(file)' });
});
