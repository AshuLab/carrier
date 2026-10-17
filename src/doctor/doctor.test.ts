import { expect, test, vi } from 'vitest';
import { defaults, loadConfig } from '../config/load.ts';
import type { Config } from '../config/schema.ts';
import { runDoctor, type Check, type DoctorDeps } from './doctor.ts';

const base = {
  root: '/tmp/carrier-doctor',
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'forge', agent: 'tassadar-agent' } },
  orchestratorProfile: 'a',
  agents: {
    author: { profile: 'a', harness: 'claude', model: 'm' },
    reviewer: { profile: 'b', harness: 'codex', model: 'm' },
  },
};

const config = (overrides: Record<string, unknown> = {}): Config => {
  const result = loadConfig(defaults, { ...base, ...overrides });
  if (!result.ok) throw new Error(JSON.stringify(result.errors));
  return result.config;
};

const deps = (overrides: Partial<DoctorDeps> = {}): DoctorDeps => ({
  which: () => true,
  mint: async () => 'secret-token',
  listLabels: async () => [],
  localModels: async () => [],
  ...overrides,
});

const failed = (checks: Check[]) => checks.filter((check) => check.status === 'fail');

test('everything in place: all checks pass and no token reaches the report', async () => {
  const checks = await runDoctor(config(), deps());
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).toEqual([
    'git installed',
    'gh installed',
    'claude installed',
    'codex installed',
    'agent-forge installed',
    'author and reviewer are different identities',
    'forge agent artanis-agent can mint a token for AshuLab/carrier',
    'forge agent tassadar-agent can mint a token for AshuLab/carrier',
    'forge agent artanis-agent can read AshuLab/carrier',
  ]);
  expect(JSON.stringify(checks)).not.toContain('secret-token');
});

test('a missing harness CLI fails once, by name', async () => {
  const checks = await runDoctor(config(), deps({ which: (command) => command !== 'claude' }));
  expect(failed(checks)).toEqual([{ name: 'claude installed', status: 'fail', detail: 'not found on PATH' }]);
});

test('only the harnesses in use are required', async () => {
  const which = vi.fn(() => true);
  await runDoctor(config({ agents: { author: { profile: 'a', harness: 'claude', model: 'm' }, reviewer: { profile: 'b', harness: 'claude', model: 'm' } } }), deps({ which }));
  expect(which).not.toHaveBeenCalledWith('codex');
});

test('without agent-forge the forge profiles are not minted or read, only reported once', async () => {
  const mint = vi.fn(async () => 't');
  const listLabels = vi.fn(async () => []);
  const checks = await runDoctor(config(), deps({ which: (command) => command !== 'agent-forge', mint, listLabels }));
  expect(failed(checks).map((c) => c.name)).toEqual(['agent-forge installed']);
  expect(mint).not.toHaveBeenCalled();
  expect(listLabels).not.toHaveBeenCalled();
});

test('without gh nothing that needs it runs', async () => {
  const mint = vi.fn(async () => 't');
  const checks = await runDoctor(config(), deps({ which: (command) => command !== 'gh', mint }));
  expect(failed(checks).map((c) => c.name)).toEqual(['gh installed']);
  expect(mint).not.toHaveBeenCalled();
});

test('two profile names for the same forge agent are one identity', async () => {
  const checks = await runDoctor(config({ profiles: { a: { kind: 'forge', agent: 'bot' }, b: { kind: 'forge', agent: 'bot' } } }), deps());
  expect(failed(checks)).toEqual([
    { name: 'author and reviewer are different identities', status: 'fail', detail: 'AshuLab/carrier: author and reviewer both use forge agent bot' },
  ]);
});

test('two gh profiles are one identity', async () => {
  const checks = await runDoctor(config({ profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } } }), deps({ which: (command) => command !== 'agent-forge' }));
  expect(failed(checks).map((c) => c.name)).toEqual(['author and reviewer are different identities']);
});

test('a per-repo override can make the roles clash even when the globals differ', async () => {
  const clash = config({
    profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'forge', agent: 'tassadar-agent' }, c: { kind: 'forge', agent: 'artanis-agent' } },
    repos: [{ name: 'AshuLab/one' }, { name: 'AshuLab/two', agents: { reviewer: { profile: 'c' } } }],
  });
  expect(failed(await runDoctor(clash, deps())).map((c) => c.detail)).toEqual(['AshuLab/two: author and reviewer both use forge agent artanis-agent']);
});

test('a token that cannot be minted fails for that repo only', async () => {
  const mint = async (profile: { kind: string; agent?: string }, repo: string) => {
    if (repo === 'AshuLab/two' && profile.agent === 'tassadar-agent') throw new Error('Agent not found: tassadar-agent');
    return 't';
  };
  const checks = await runDoctor(config({ repos: [{ name: 'AshuLab/one' }, { name: 'AshuLab/two' }] }), deps({ mint }));
  expect(failed(checks)).toEqual([{ name: 'forge agent tassadar-agent can mint a token for AshuLab/two', status: 'fail', detail: 'Agent not found: tassadar-agent' }]);
});

test('a repo GitHub answers 404 for fails with the error', async () => {
  const listLabels = async () => {
    throw new Error('GitHub answered HTTP 404: Not Found');
  };
  const checks = await runDoctor(config(), deps({ listLabels }));
  expect(failed(checks)).toEqual([{ name: 'forge agent artanis-agent can read AshuLab/carrier', status: 'fail', detail: 'GitHub answered HTTP 404: Not Found' }]);
});

test('each identity is minted once per repo, however many roles it has', async () => {
  const mint = vi.fn(async (_profile: unknown, _repo: string) => 't');
  await runDoctor(config({ repos: [{ name: 'AshuLab/one' }, { name: 'AshuLab/two' }] }), deps({ mint }));
  expect(mint.mock.calls.map(([profile, repo]) => `${(profile as { agent: string }).agent}@${repo}`)).toEqual([
    'artanis-agent@AshuLab/one',
    'tassadar-agent@AshuLab/one',
    'artanis-agent@AshuLab/two',
    'tassadar-agent@AshuLab/two',
  ]);
});

test('onCheck sees every check as it finishes, in the order of the result', async () => {
  const seen: Check[] = [];
  const checks = await runDoctor(config(), deps(), (check) => seen.push(check));
  expect(seen).toEqual(checks);
});

const local = (over: Record<string, unknown> = {}) => config({ agents: { ...base.agents, reviewer: { ...base.agents.reviewer, model: 'google/gemma-4-12b', provider: 'lmstudio', ...over } } });

test('a local model passes when its server has it', async () => {
  const checks = await runDoctor(local(), deps({ localModels: async () => ['google/gemma-4-12b'] }));
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).toContain('LM Studio has google/gemma-4-12b');
});

test('a local model fails with what the server does have, or when the server is down', async () => {
  const missing = failed(await runDoctor(local(), deps({ localModels: async () => ['other'] })));
  expect(missing).toEqual([{ name: 'LM Studio has google/gemma-4-12b', status: 'fail', detail: 'not downloaded there (it has: other)' }]);
  const down = failed(await runDoctor(local(), deps({ localModels: async () => Promise.reject(new Error('ECONNREFUSED')) })));
  expect(down[0]?.detail).toBe('LM Studio is not answering at http://localhost:1234; start its server');
});
