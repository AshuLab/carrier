import { expect, test, vi } from 'vitest';
import { defaults, loadConfig } from '../config/load.ts';
import type { Config } from '../config/schema.ts';
import { runDoctor, type Check, type DoctorDeps } from './doctor.ts';

const base = {
  root: '/tmp/carrier-doctor',
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'forge', agent: 'tassadar-agent' } },
  orchestratorProfile: 'a',
  agentOptions: { claude: { harness: 'claude', model: 'm' }, codex: { harness: 'codex', model: 'm' } },
  agents: {
    author: { profile: 'a', option: 'claude' },
    reviewer: { profile: 'b', option: 'codex' },
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

test('a root whose socket path does not fit is a warning with a shorter root as the remedy', async () => {
  const root = `/tmp/${'é'.repeat(40)}`; // 45 characters, 85 bytes: 111 with /orchestrator/control.sock
  const checks = await runDoctor(config({ root }), deps());
  expect(failed(checks)).toEqual([]);
  expect(checks.filter((check) => check.status === 'warn')).toMatchObject([
    { name: 'control socket path fits', detail: expect.stringContaining(`${root}/orchestrator/control.sock is 111 bytes`), fix: expect.stringContaining('shorter') },
  ]);
});

test('a root whose socket path fits, up to 103 bytes, reports nothing about it', async () => {
  const root = `/tmp/${'r'.repeat(103 - '/orchestrator/control.sock'.length - 5)}`;
  const checks = await runDoctor(config({ root }), deps());
  expect(checks.map((check) => check.name)).not.toContain('control socket path fits');
});

test('a missing harness CLI fails once, by name', async () => {
  const checks = await runDoctor(config(), deps({ which: (command) => command !== 'claude' }));
  expect(failed(checks)).toMatchObject([{ name: 'claude installed', status: 'fail', detail: 'not found on PATH' }]);
});

test('only the harnesses in use are required', async () => {
  const which = vi.fn(() => true);
  await runDoctor(config({ agents: { author: { profile: 'a', option: 'claude' }, reviewer: { profile: 'b', option: 'claude' } } }), deps({ which }));
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
  expect(failed(checks)).toMatchObject([
    { name: 'author and reviewer are different identities', status: 'fail', detail: 'AshuLab/carrier: author and reviewer both use forge agent bot' },
  ]);
});

test('two gh profiles are one identity', async () => {
  const checks = await runDoctor(config({ profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } } }), deps({ which: (command) => command !== 'agent-forge' }));
  expect(failed(checks).map((c) => c.name)).toEqual(['author and reviewer are different identities']);
});

const sharedGh = { identities: 'shared', profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } } };
const noForge = (command: string) => command !== 'agent-forge';

test('a shared identity with the same login for both roles has no failed check and no clash check', async () => {
  const checks = await runDoctor(config(sharedGh), deps({ which: noForge }));
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).not.toContain('author and reviewer are different identities');
});

test('the same config under separate identities fails the clash check', async () => {
  const checks = await runDoctor(config({ ...sharedGh, identities: 'separate' }), deps({ which: noForge }));
  expect(failed(checks).map((c) => c.name)).toEqual(['author and reviewer are different identities']);
});

test('a shared login that cannot get a token or read a repo still fails', async () => {
  const noToken = await runDoctor(config(sharedGh), deps({ which: noForge, mint: async () => { throw new Error('no login'); } }));
  expect(failed(noToken).map((c) => c.name)).toEqual(['your gh login can mint a token for AshuLab/carrier']);
  const noRead = await runDoctor(config(sharedGh), deps({ which: noForge, listLabels: async () => { throw new Error('404'); } }));
  expect(failed(noRead).map((c) => c.name)).toEqual(['your gh login can read AshuLab/carrier']);
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
  expect(failed(checks)).toMatchObject([{ name: 'forge agent tassadar-agent can mint a token for AshuLab/two', status: 'fail', detail: 'Agent not found: tassadar-agent' }]);
});

test('a repo GitHub answers 404 for fails with the error', async () => {
  const listLabels = async () => {
    throw new Error('GitHub answered HTTP 404: Not Found');
  };
  const checks = await runDoctor(config(), deps({ listLabels }));
  expect(failed(checks)).toMatchObject([{ name: 'forge agent artanis-agent can read AshuLab/carrier', status: 'fail', detail: 'GitHub answered HTTP 404: Not Found' }]);
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

const local = (over: Record<string, unknown> = {}) => config({ agentOptions: { ...base.agentOptions, local: { harness: 'codex', model: 'google/gemma-4-12b', provider: 'lmstudio', ...over } }, agents: { ...base.agents, reviewer: { ...base.agents.reviewer, option: 'local' } } });

test('a local model passes when its server has it', async () => {
  const checks = await runDoctor(local(), deps({ localModels: async () => ['google/gemma-4-12b'] }));
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).toContain('LM Studio has google/gemma-4-12b');
});

test('a local model fails with what the server does have, or when the server is down', async () => {
  const missing = failed(await runDoctor(local(), deps({ localModels: async () => ['other'] })));
  expect(missing).toMatchObject([{ name: 'LM Studio has google/gemma-4-12b', status: 'fail', detail: 'not downloaded there (it has: other)' }]);
  const down = failed(await runDoctor(local(), deps({ localModels: async () => Promise.reject(new Error('ECONNREFUSED')) })));
  expect(down[0]?.detail).toBe('LM Studio is not answering at http://localhost:1234; start its server');
});

// The remedy of each family of failures; it only names what the check already knew.
const gh = { a: { kind: 'gh' }, b: { kind: 'forge', agent: 'bot' } };
const fixOf = async (cfg: Config, d: Partial<DoctorDeps>) => failed(await runDoctor(cfg, deps(d)))[0]?.fix;

test.each([
  ['a missing tool', () => fixOf(config(), { which: (c) => c !== 'gh' }), 'install the GitHub CLI (https://cli.github.com) and run: gh auth login'],
  ['agent-forge missing', () => fixOf(config(), { which: (c) => c !== 'agent-forge' }), 'install it: pnpm add -g @ashulab/agent-forge (https://github.com/AshuLab/agent-forge)'],
  ['an unknown Forge agent', () => fixOf(config(), { mint: async () => Promise.reject(new Error('could not mint a token for artanis-agent: Agent not found: artanis-agent')) }), 'agent-forge --list shows your agents; add one with: agent-forge add'],
  ['no installation', () => fixOf(config(), { mint: async () => Promise.reject(new Error('could not mint a token for artanis-agent: has no installations')) }), 'install the GitHub App of that agent on AshuLab'],
  ['an unreadable key', () => fixOf(config(), { mint: async () => Promise.reject(new Error('could not mint a token for artanis-agent: Private key for x not found or unreadable')) }), 'check privateKeyPath of that agent in your Forge registry'],
  ['any other mint error', () => fixOf(config(), { mint: async () => Promise.reject(new Error('boom')) }), 'run: agent-forge token --agent artanis-agent from a clone of the repo to see the full error'],
  ['a gh login that cannot mint', () => fixOf(config({ profiles: gh, orchestratorProfile: 'b', agents: { author: { profile: 'a', option: 'claude' }, reviewer: { profile: 'b', option: 'codex' } } }), { mint: async (p) => (p.kind === 'gh' ? Promise.reject(new Error('x')) : 't') }), 'run: gh auth login'],
  ['a 404 on the repo', () => fixOf(config(), { listLabels: async () => Promise.reject(new Error('GitHub answered HTTP 404: Not Found')) }), 'the repo does not exist or this identity cannot see it: install the App on AshuLab and give it access to AshuLab/carrier'],
  ['a 401 on the repo', () => fixOf(config(), { listLabels: async () => Promise.reject(new Error('GitHub answered HTTP 401: Bad credentials')) }), "the identity's credentials were rejected: for gh run gh auth login, for a bot check its App in Forge"],
  ['the same identity twice', () => fixOf(config({ profiles: { a: { kind: 'forge', agent: 'bot' }, b: { kind: 'forge', agent: 'bot' } } }), {}), 'use two different bots (agent-forge add) or one bot and your gh login, or set identities to "shared" to use one account for both'],
  ['a local server that is down', () => fixOf(local(), { localModels: async () => Promise.reject(new Error('ECONNREFUSED')) }), 'start the server (LM Studio: lms server start, Ollama: ollama serve) and download the model'],
  ['a missing local model', () => fixOf(local(), { localModels: async () => ['other'] }), 'download it in LM Studio / ollama pull google/gemma-4-12b'],
])('fix: %s', async (_, run, expected) => {
  expect(await run()).toBe(expected);
});

test('an unlisted read failure has no fix, and passing checks never do', async () => {
  const checks = await runDoctor(config(), deps({ listLabels: async () => Promise.reject(new Error('GitHub answered HTTP 422: x')) }));
  expect(failed(checks)[0]).not.toHaveProperty('fix');
  expect((await runDoctor(config(), deps())).filter((c) => 'fix' in c)).toEqual([]);
});

test('onStart announces each check, in the order and with the name of the check that follows', async () => {
  const events: string[] = [];
  const checks = await runDoctor(config(), deps({ mint: async () => 'secret-token' }), (c) => events.push(`done:${c.name}`), (name) => events.push(`start:${name}`));
  expect(events).toEqual(checks.flatMap((c) => [`start:${c.name}`, `done:${c.name}`]));
  expect(JSON.stringify(checks)).not.toContain('secret-token');
});

test('checks skipped because a prerequisite failed announce nothing', async () => {
  const started: string[] = [];
  const checks = await runDoctor(config(), deps({ which: (c) => c !== 'gh' }), () => {}, (name) => started.push(name));
  expect(started).toEqual(checks.map((c) => c.name)); // no start for the mints and reads that were skipped
});
