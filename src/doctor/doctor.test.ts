import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventEmitter } from 'node:events';
import { PassThrough } from 'node:stream';
import { afterEach, expect, test, vi } from 'vitest';
import { defaults, loadConfig } from '../config/load.ts';
import type { Config } from '../config/schema.ts';
import { doctorCommand } from '../terminal/cli/commands/doctor.ts';
import { cliLoggedIn, runDoctor, type Check, type DoctorDeps } from './doctor.ts';

const folder = '/tmp/carrier-doctor';
const doctor = (cfg: Config, ...rest: Parameters<typeof runDoctor> extends [unknown, unknown, ...infer Rest] ? Rest : never) => runDoctor(cfg, folder, ...rest);

const base = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'forge', agent: 'tassadar-agent' } },
  orchestratorProfile: 'a',
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  agents: {
    author: { profile: 'a', provider: 'claude', model: 'm' },
    reviewer: { profile: 'b', provider: 'codex', model: 'm' },
  },
};

const config = (overrides: Record<string, unknown> = {}): Config => {
  const result = loadConfig(defaults, { ...base, ...overrides });
  if (!result.ok) throw new Error(JSON.stringify(result.errors));
  return result.config;
};

// A stand-in for the agy process: prints what it is told and ends only when `end` says so.
function fakeAgy({ stdout = '', stderr = '', end = false }: { stdout?: string; stderr?: string; end?: boolean }) {
  const process = Object.assign(new EventEmitter(), { stdout: new PassThrough(), stderr: new PassThrough(), kill: vi.fn(() => { process.emit('close'); }) });
  setImmediate(() => {
    if (stdout) process.stdout.write(stdout);
    if (stderr) process.stderr.write(stderr);
    if (end) process.emit('close');
  });
  return process;
}

const deps = (overrides: Partial<DoctorDeps> = {}): DoctorDeps => ({
  which: () => true,
  mint: async () => 'secret-token',
  listLabels: async () => [],
  localModels: async () => [],
  loggedIn: async () => true,
  startAgy: () => fakeAgy({ stdout: '{"status":"SUCCESS"}', end: true }),
  ...overrides,
});

const failed = (checks: Check[]) => checks.filter((check) => check.status === 'fail');

test('everything in place: all checks pass and no token reaches the report', async () => {
  const checks = await doctor(config(), deps());
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).toEqual([
    'git installed',
    'gh installed',
    'claude installed',
    'codex installed',
    'agent-forge installed',
    'claude provider claude is logged in',
    'codex provider codex is logged in',
    'author and reviewer are different identities',
    'forge agent artanis-agent can mint a token for AshuLab/carrier',
    'forge agent tassadar-agent can mint a token for AshuLab/carrier',
    'forge agent artanis-agent can read AshuLab/carrier',
  ]);
  expect(JSON.stringify(checks)).not.toContain('secret-token');
});

test('a Carrier folder whose socket path does not fit is a warning with a shorter folder as the remedy', async () => {
  const root = `/tmp/${'é'.repeat(40)}`; // 45 characters, 85 bytes: 111 with /engine/state/control.sock
  const checks = await runDoctor(config(), root, deps());
  expect(failed(checks)).toEqual([]);
  expect(checks.filter((check) => check.status === 'warn')).toMatchObject([
    { name: 'control socket path fits', detail: expect.stringContaining(`${root}/engine/state/control.sock is 111 bytes`), fix: expect.stringContaining('shorter') },
  ]);
});

test('a Carrier folder whose socket path fits, up to 103 bytes, reports nothing about it', async () => {
  const root = `/tmp/${'r'.repeat(103 - '/engine/state/control.sock'.length - 5)}`;
  const checks = await runDoctor(config(), root, deps());
  expect(checks.map((check) => check.name)).not.toContain('control socket path fits');
});

test('a missing harness CLI fails once, by name', async () => {
  const checks = await doctor(config(), deps({ which: (command) => command !== 'claude' }));
  expect(failed(checks)).toMatchObject([{ name: 'claude installed', status: 'fail', detail: 'not found on PATH' }]);
});

test('only the harnesses in use are required', async () => {
  const which = vi.fn(() => true);
  await doctor(config({ agents: { author: { profile: 'a', provider: 'claude', model: 'm' }, reviewer: { profile: 'b', provider: 'claude', model: 'm' } } }), deps({ which }));
  expect(which).not.toHaveBeenCalledWith('codex');
});

test('without agent-forge the forge profiles are not minted or read, only reported once', async () => {
  const mint = vi.fn(async () => 't');
  const listLabels = vi.fn(async () => []);
  const checks = await doctor(config(), deps({ which: (command) => command !== 'agent-forge', mint, listLabels }));
  expect(failed(checks).map((c) => c.name)).toEqual(['agent-forge installed']);
  expect(mint).not.toHaveBeenCalled();
  expect(listLabels).not.toHaveBeenCalled();
});

test('without gh nothing that needs it runs', async () => {
  const mint = vi.fn(async () => 't');
  const checks = await doctor(config(), deps({ which: (command) => command !== 'gh', mint }));
  expect(failed(checks).map((c) => c.name)).toEqual(['gh installed']);
  expect(mint).not.toHaveBeenCalled();
});

test('two profile names for the same forge agent are one identity', async () => {
  const checks = await doctor(config({ profiles: { a: { kind: 'forge', agent: 'bot' }, b: { kind: 'forge', agent: 'bot' } } }), deps());
  expect(failed(checks)).toMatchObject([
    { name: 'author and reviewer are different identities', status: 'fail', detail: 'AshuLab/carrier: author and reviewer both use forge agent bot' },
  ]);
});

test('two gh profiles are one identity', async () => {
  const checks = await doctor(config({ profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } } }), deps({ which: (command) => command !== 'agent-forge' }));
  expect(failed(checks).map((c) => c.name)).toEqual(['author and reviewer are different identities']);
});

test('lead reviewer sharing account with author fails the clash check under separate identities', async () => {
  const cfg = config({
    profiles: { a: { kind: 'gh' }, b: { kind: 'forge', agent: 'rev' }, c: { kind: 'gh' } },
    agents: {
      author: { profile: 'a', provider: 'claude', model: 'sonnet' },
      reviewer: { profile: 'b', provider: 'codex', model: 'm' },
      leadReviewer: { profile: 'c', provider: 'claude', model: 'sonnet' },
    },
  });
  const checks = await doctor(cfg, deps());
  expect(failed(checks)).toMatchObject([
    { name: 'author and reviewer are different identities', status: 'fail', detail: expect.stringContaining('author and lead reviewer both use your gh login') },
  ]);
});

const sharedGh = { identities: 'shared', profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } } };
const noForge = (command: string) => command !== 'agent-forge';

test('a shared identity with the same login for both roles has no failed check and no clash check', async () => {
  const checks = await doctor(config(sharedGh), deps({ which: noForge }));
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).not.toContain('author and reviewer are different identities');
});

test('the same config under separate identities fails the clash check', async () => {
  const checks = await doctor(config({ ...sharedGh, identities: 'separate' }), deps({ which: noForge }));
  expect(failed(checks).map((c) => c.name)).toEqual(['author and reviewer are different identities']);
});

test('a shared login that cannot get a token or read a repo still fails', async () => {
  const noToken = await doctor(config(sharedGh), deps({ which: noForge, mint: async () => { throw new Error('no login'); } }));
  expect(failed(noToken).map((c) => c.name)).toEqual(['your gh login can mint a token for AshuLab/carrier']);
  const noRead = await doctor(config(sharedGh), deps({ which: noForge, listLabels: async () => { throw new Error('404'); } }));
  expect(failed(noRead).map((c) => c.name)).toEqual(['your gh login can read AshuLab/carrier']);
});

test('a per-repo override can make the roles clash even when the globals differ', async () => {
  const clash = config({
    profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'forge', agent: 'tassadar-agent' }, c: { kind: 'forge', agent: 'artanis-agent' } },
    repos: [{ name: 'AshuLab/one' }, { name: 'AshuLab/two', agents: { reviewer: { profile: 'c' } } }],
  });
  expect(failed(await doctor(clash, deps())).map((c) => c.detail)).toEqual(['AshuLab/two: author and reviewer both use forge agent artanis-agent']);
});

test('a token that cannot be minted fails for that repo only', async () => {
  const mint = async (profile: { kind: string; agent?: string }, repo: string) => {
    if (repo === 'AshuLab/two' && profile.agent === 'tassadar-agent') throw new Error('Agent not found: tassadar-agent');
    return 't';
  };
  const checks = await doctor(config({ repos: [{ name: 'AshuLab/one' }, { name: 'AshuLab/two' }] }), deps({ mint }));
  expect(failed(checks)).toMatchObject([{ name: 'forge agent tassadar-agent can mint a token for AshuLab/two', status: 'fail', detail: 'Agent not found: tassadar-agent' }]);
});

test('a repo GitHub answers 404 for fails with the error', async () => {
  const listLabels = async () => {
    throw new Error('GitHub answered HTTP 404: Not Found');
  };
  const checks = await doctor(config(), deps({ listLabels }));
  expect(failed(checks)).toMatchObject([{ name: 'forge agent artanis-agent can read AshuLab/carrier', status: 'fail', detail: 'GitHub answered HTTP 404: Not Found' }]);
});

test('each identity is minted once per repo, however many roles it has', async () => {
  const mint = vi.fn(async (_profile: unknown, _repo: string) => 't');
  await doctor(config({ repos: [{ name: 'AshuLab/one' }, { name: 'AshuLab/two' }] }), deps({ mint }));
  expect(mint.mock.calls.map(([profile, repo]) => `${(profile as { agent: string }).agent}@${repo}`)).toEqual([
    'artanis-agent@AshuLab/one',
    'tassadar-agent@AshuLab/one',
    'artanis-agent@AshuLab/two',
    'tassadar-agent@AshuLab/two',
  ]);
});

test('onCheck sees every check as it finishes, in the order of the result', async () => {
  const seen: Check[] = [];
  const checks = await doctor(config(), deps(), (check) => seen.push(check));
  expect(seen).toEqual(checks);
});

const local = (over: Record<string, unknown> = {}) => config({ providers: { ...base.providers, local: { harness: 'codex', provider: 'lmstudio', ...over } }, agents: { ...base.agents, reviewer: { ...base.agents.reviewer, provider: 'local', model: 'google/gemma-4-12b' } } });

test('a local model passes when its server has it', async () => {
  const checks = await doctor(local(), deps({ localModels: async () => ['google/gemma-4-12b'] }));
  expect(failed(checks)).toEqual([]);
  expect(checks.map((c) => c.name)).toContain('LM Studio has google/gemma-4-12b');
});

test('a local model fails with what the server does have, or when the server is down', async () => {
  const missing = failed(await doctor(local(), deps({ localModels: async () => ['other'] })));
  expect(missing).toMatchObject([{ name: 'LM Studio has google/gemma-4-12b', status: 'fail', detail: 'not downloaded there (it has: other)' }]);
  const down = failed(await doctor(local(), deps({ localModels: async () => Promise.reject(new Error('ECONNREFUSED')) })));
  expect(down[0]?.detail).toBe('LM Studio is not answering at http://localhost:1234; start its server');
});

// The remedy of each family of failures; it only names what the check already knew.
const gh = { a: { kind: 'gh' }, b: { kind: 'forge', agent: 'bot' } };
const fixOf = async (cfg: Config, d: Partial<DoctorDeps>) => failed(await doctor(cfg, deps(d)))[0]?.fix;

test.each([
  ['a missing tool', () => fixOf(config(), { which: (c) => c !== 'gh' }), 'install the GitHub CLI (https://cli.github.com) and run: gh auth login'],
  ['agent-forge missing', () => fixOf(config(), { which: (c) => c !== 'agent-forge' }), 'install it: pnpm add -g @ashulab/agent-forge (https://github.com/AshuLab/agent-forge)'],
  ['an unknown Forge agent', () => fixOf(config(), { mint: async () => Promise.reject(new Error('could not mint a token for artanis-agent: Agent not found: artanis-agent')) }), 'agent-forge --list shows your agents; add one with: agent-forge add'],
  ['no installation', () => fixOf(config(), { mint: async () => Promise.reject(new Error('could not mint a token for artanis-agent: has no installations')) }), 'install the GitHub App of that agent on AshuLab'],
  ['an unreadable key', () => fixOf(config(), { mint: async () => Promise.reject(new Error('could not mint a token for artanis-agent: Private key for x not found or unreadable')) }), 'check privateKeyPath of that agent in your Forge registry'],
  ['any other mint error', () => fixOf(config(), { mint: async () => Promise.reject(new Error('boom')) }), 'run: agent-forge token --agent artanis-agent from a clone of the repo to see the full error'],
  ['a gh login that cannot mint', () => fixOf(config({ profiles: gh, orchestratorProfile: 'b', agents: { author: { profile: 'a', provider: 'claude', model: 'm' }, reviewer: { profile: 'b', provider: 'codex', model: 'm' } } }), { mint: async (p) => (p.kind === 'gh' ? Promise.reject(new Error('x')) : 't') }), 'run: gh auth login'],
  ['a 404 on the repo', () => fixOf(config(), { listLabels: async () => Promise.reject(new Error('GitHub answered HTTP 404: Not Found')) }), 'the repo does not exist or this identity cannot see it: install the App on AshuLab and give it access to AshuLab/carrier'],
  ['a 401 on the repo', () => fixOf(config(), { listLabels: async () => Promise.reject(new Error('GitHub answered HTTP 401: Bad credentials')) }), "the identity's credentials were rejected: for gh run gh auth login, for a bot check its App in Forge"],
  ['the same identity twice', () => fixOf(config({ profiles: { a: { kind: 'forge', agent: 'bot' }, b: { kind: 'forge', agent: 'bot' } } }), {}), 'use two different bots (agent-forge add) or one bot and your gh login, or set identities to "shared" to use one account for both'],
  ['a local server that is down', () => fixOf(local(), { localModels: async () => Promise.reject(new Error('ECONNREFUSED')) }), 'start the server (LM Studio: lms server start, Ollama: ollama serve) and download the model'],
  ['a missing local model', () => fixOf(local(), { localModels: async () => ['other'] }), 'download it in LM Studio / ollama pull google/gemma-4-12b'],
])('fix: %s', async (_, run, expected) => {
  expect(await run()).toBe(expected);
});

test('an unlisted read failure has no fix, and passing checks never do', async () => {
  const checks = await doctor(config(), deps({ listLabels: async () => Promise.reject(new Error('GitHub answered HTTP 422: x')) }));
  expect(failed(checks)[0]).not.toHaveProperty('fix');
  expect((await doctor(config(), deps())).filter((c) => 'fix' in c)).toEqual([]);
});

test('onStart announces each check, in the order and with the name of the check that follows', async () => {
  const events: string[] = [];
  const checks = await doctor(config(), deps({ mint: async () => 'secret-token' }), (c) => events.push(`done:${c.name}`), (name) => events.push(`start:${name}`));
  expect(events).toEqual(checks.flatMap((c) => [`start:${c.name}`, `done:${c.name}`]));
  expect(JSON.stringify(checks)).not.toContain('secret-token');
});

test('checks skipped because a prerequisite failed announce nothing', async () => {
  const started: string[] = [];
  const checks = await doctor(config(), deps({ which: (c) => c !== 'gh' }), () => {}, (name) => started.push(name));
  expect(started).toEqual(checks.map((c) => c.name)); // no start for the mints and reads that were skipped
});

// The login of each Claude and Codex provider; the answer is faked, no test starts a real CLI.
const withDirs = { providers: { claude: { harness: 'claude', configDir: '/home/me/.claude-work' }, codex: { harness: 'codex', configDir: '/home/me/.codex-alt' }, spare: { harness: 'claude', configDir: '/home/me/.claude-spare' }, agy: { harness: 'agy' } } };

test('every Claude and Codex provider is asked with its folder, role or not, and agy is left out', async () => {
  const loggedIn = vi.fn(async (_harness: string, _dir: string | undefined) => true);
  const checks = await doctor(config(withDirs), deps({ loggedIn }));
  expect(loggedIn.mock.calls).toEqual([['claude', '/home/me/.claude-work'], ['codex', '/home/me/.codex-alt'], ['claude', '/home/me/.claude-spare']]);
  expect(failed(checks)).toEqual([]);
});

test('a provider without a folder is checked in the process environment', async () => {
  const loggedIn = vi.fn(async (_harness: string, _dir: string | undefined) => true);
  await doctor(config(), deps({ loggedIn }));
  expect(loggedIn.mock.calls).toEqual([['claude', undefined], ['codex', undefined]]);
});

test('a role provider that is not logged in fails, a spare one only warns, both name the provider and folder and carry the login remedy', async () => {
  const checks = await doctor(config(withDirs), deps({ loggedIn: async (_harness, dir) => dir !== '/home/me/.claude-work' && dir !== '/home/me/.claude-spare' }));
  const logins = checks.filter((c) => c.name.endsWith('is logged in'));
  expect(logins.filter((c) => c.status !== 'ok')).toMatchObject([
    { name: 'claude provider claude is logged in', status: 'fail', detail: 'not logged in at /home/me/.claude-work', fix: 'log in with: CLAUDE_CONFIG_DIR=/home/me/.claude-work claude /login' },
    { name: 'claude provider spare is logged in', status: 'warn', detail: 'not logged in at /home/me/.claude-spare', fix: 'log in with: CLAUDE_CONFIG_DIR=/home/me/.claude-spare claude /login' },
  ]);
});

test('a Codex provider that is not logged in has the Codex remedy, and one without a folder says so', async () => {
  const checks = await doctor(config(withDirs), deps({ loggedIn: async (harness) => harness !== 'codex' }));
  expect(failed(checks)).toMatchObject([{ name: 'codex provider codex is logged in', detail: 'not logged in at /home/me/.codex-alt', fix: 'log in with: CODEX_HOME=/home/me/.codex-alt codex login' }]);
  const inherited = failed(await doctor(config(), deps({ loggedIn: async () => false })));
  expect(inherited.map((c) => c.detail)).toEqual(['not logged in in the environment Carrier runs in', 'not logged in in the environment Carrier runs in']);
  expect(inherited.map((c) => c.fix)).toEqual(['log in with: claude /login', 'log in with: codex login']);
});

test('a login check that cannot run is reported by provider, and an email never reaches the report', async () => {
  const loggedIn = async () => {
    throw new Error('spawnSync claude ENOENT me@example.com');
  };
  const checks = await doctor(config(), deps({ loggedIn }));
  expect(failed(checks)).toMatchObject([{ name: 'claude provider claude is logged in' }, { name: 'codex provider codex is logged in' }]);
  expect(JSON.stringify(checks)).not.toContain('me@example.com');
});

test('a provider whose CLI is not installed is not asked for its login', async () => {
  const loggedIn = vi.fn(async () => true);
  await doctor(config(), deps({ which: (command) => command !== 'claude', loggedIn }));
  expect(loggedIn).toHaveBeenCalledTimes(1);
});

// The Antigravity login: agy has no status command, so the check reads the first stderr line of `agy -p /usage`.
afterEach(() => vi.useRealTimers());
const agyChecks = (checks: Check[]) => checks.filter((c) => c.name.startsWith('agy provider'));
const onlyAgy = { providers: { agy: { harness: 'agy' } }, agents: { author: { profile: 'a', provider: 'agy', model: 'm' }, reviewer: { profile: 'b', provider: 'agy', model: 'm' } } };

test('an Antigravity provider whose /usage answers SUCCESS is logged in', async () => {
  const startAgy = vi.fn(() => fakeAgy({ stdout: '{"status":"SUCCESS"}', end: true }));
  const checks = await doctor(config(onlyAgy), deps({ startAgy }));
  expect(startAgy).toHaveBeenCalledTimes(1);
  expect(agyChecks(checks)).toEqual([{ name: 'agy provider agy is logged in', status: 'ok' }]);
});

test('Authentication required on the first stderr line is logged out at once: the process is killed, not waited for, and the login URL stays out', async () => {
  const process = fakeAgy({ stderr: 'Authentication required. Open https://accounts.example/login?code=SECRET\n' }); // never ends by itself
  const checks = await doctor(config(onlyAgy), deps({ startAgy: () => process }));
  expect(process.kill).toHaveBeenCalledTimes(1);
  expect(agyChecks(checks)).toEqual([{ name: 'agy provider agy is logged in', status: 'fail', detail: 'not logged in', fix: 'log in with: agy' }]);
  expect(JSON.stringify(checks)).not.toContain('SECRET');
});

test('an Antigravity provider that is not a role provider only warns when logged out', async () => {
  const spare = { providers: { ...base.providers, agy: { harness: 'agy' } } };
  const checks = await doctor(config(spare), deps({ startAgy: () => fakeAgy({ stderr: 'Authentication required\n' }) }));
  expect(failed(checks)).toEqual([]);
  expect(agyChecks(checks)).toMatchObject([{ status: 'warn', detail: 'not logged in', fix: 'log in with: agy' }]);
});

test('an agy that neither succeeds nor asks for login within the time limit is killed and only a warning, even for a role option', async () => {
  vi.useFakeTimers();
  const process = fakeAgy({});
  const done = doctor(config(onlyAgy), deps({ startAgy: () => process }));
  await vi.advanceTimersByTimeAsync(60_000);
  const checks = await done;
  expect(process.kill).toHaveBeenCalled();
  expect(failed(checks)).toEqual([]);
  expect(agyChecks(checks)).toMatchObject([{ status: 'warn', detail: expect.stringContaining('could not tell') }]);
});

test('an agy that ends without SUCCESS or the login line could not be told, and one that cannot start is reported too', async () => {
  const ended = await doctor(config(onlyAgy), deps({ startAgy: () => fakeAgy({ stdout: 'garbage', end: true }) }));
  expect(agyChecks(ended)).toMatchObject([{ status: 'warn', detail: expect.stringContaining('could not tell') }]);
  const broken = await doctor(config(onlyAgy), deps({ startAgy: () => { throw new Error('spawn agy EACCES'); } }));
  expect(agyChecks(broken)).toMatchObject([{ status: 'warn', detail: expect.stringContaining('could not run agy') }]);
});

test('an Antigravity option whose CLI is not installed is not started', async () => {
  const startAgy = vi.fn(() => fakeAgy({ end: true }));
  await doctor(config(onlyAgy), deps({ which: (command) => command !== 'agy', startAgy }));
  expect(startAgy).not.toHaveBeenCalled();
});

// The login probe runs the real CLI: a stand-in on the PATH answers, and the event loop is free while it does.
test('cliLoggedIn reads the verdict of the CLI with the option\'s folder, without blocking, and a CLI that does not answer in time rejects', async () => {
  const bin = mkdtempSync(join(tmpdir(), 'carrier-login-'));
  const script = (name: string, body: string) => {
    writeFileSync(join(bin, name), `#!/bin/sh\n${body}\n`);
    chmodSync(join(bin, name), 0o755);
  };
  const path = process.env.PATH;
  process.env.PATH = `${bin}:${path}`;
  try {
    script('claude', '[ "$CLAUDE_CONFIG_DIR" = /cfg ] && echo \'{"loggedIn":true}\' || echo \'{"loggedIn":false}\'');
    script('codex', '[ "$CODEX_HOME" = /cfg ]');
    const answers = await Promise.all([cliLoggedIn('claude', '/cfg'), cliLoggedIn('claude', undefined), cliLoggedIn('codex', '/cfg'), cliLoggedIn('codex', undefined)]);
    expect(answers).toEqual([true, false, true, false]);
    script('claude', 'echo not json');
    await expect(cliLoggedIn('claude', undefined)).rejects.toThrow('could not read');
    process.env.PATH = '/nonexistent';
    await expect(cliLoggedIn('codex', undefined)).rejects.toThrow();
  } finally {
    process.env.PATH = path;
    rmSync(bin, { recursive: true, force: true });
  }
});

test('cliLoggedIn gives up on time on a CLI that ignores SIGTERM and one whose child holds the pipe, and kills them', async () => {
  const bin = mkdtempSync(join(tmpdir(), 'carrier-login-hang-'));
  const path = process.env.PATH;
  process.env.PATH = `${bin}:${path}`;
  const stub = (name: string, body: string) => {
    writeFileSync(join(bin, name), `#!/bin/sh\n${body}\n`);
    chmodSync(join(bin, name), 0o755);
  };
  try {
    stub('codex', "trap '' TERM; sleep 8");
    stub('claude', 'sleep 8; true');
    for (const harness of ['codex', 'claude'] as const) {
      const started = Date.now();
      await expect(cliLoggedIn(harness, undefined, 200)).rejects.toThrow('did not answer');
      expect(Date.now() - started).toBeLessThan(3000);
    }
  } finally {
    process.env.PATH = path;
    rmSync(bin, { recursive: true, force: true });
  }
});

// doctorCommand writes to process.stdout; capture it whole.
async function printed(run: () => Promise<number>) {
  let out = '';
  const write = vi.spyOn(process.stdout, 'write').mockImplementation((chunk) => ((out += String(chunk)), true));
  try {
    return { code: await run(), out };
  } finally {
    write.mockRestore();
  }
}

test('--json prints the checks as one JSON array and nothing else, with the exit code the terminal report has', async () => {
  for (const which of [() => true, (command: string) => command !== 'gh']) {
    const overrides = deps({ which });
    const terminal = await printed(() => doctorCommand(config(), folder, false, overrides));
    const json = await printed(() => doctorCommand(config(), folder, true, overrides));
    const checks = JSON.parse(json.out) as Check[]; // the whole of stdout parses: no summary line, no progress
    expect(json.out.trimEnd().split('\n')).toHaveLength(1);
    expect(checks).toEqual(await doctor(config(), overrides));
    expect(json.code).toBe(terminal.code);
    expect(json.code).toBe(checks.some((c) => c.status === 'fail') ? 1 : 0);
    for (const check of checks) expect(Object.keys(check).every((key) => ['name', 'status', 'detail', 'fix'].includes(key))).toBe(true);
  }
});

test('--json carries no token and no email', async () => {
  const { out } = await printed(() => doctorCommand(config(), folder, true, deps({ mint: async () => 'secret-token' })));
  expect(out).not.toContain('secret-token');
});

test('without --json the report is the summary line, not an array', async () => {
  const { code, out } = await printed(() => doctorCommand(config(), folder, false, deps()));
  expect([code, out]).toEqual([0, expect.stringMatching(/All \d+ checks passed\n$/)]);
  expect(out.trimStart().startsWith('[')).toBe(false);
});
