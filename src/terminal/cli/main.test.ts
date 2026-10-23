import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, expect, test, vi } from 'vitest';
import { acquireLock } from '../../storage/lock.ts';
import { connectControl } from './control-client.ts';

const main = join(import.meta.dirname, 'main.ts');
const dir = mkdtempSync(join(tmpdir(), 'carrier-cli-'));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const valid = {
  root: dir,
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: { kind: 'gh' }, b: { kind: 'gh' } },
  orchestratorProfile: 'a',
  agents: {
    author: { profile: 'a', harness: 'claude', model: 'm' },
    reviewer: { profile: 'b', harness: 'codex', model: 'm' },
  },
};

// Runs from another working directory on purpose: nothing may depend on cwd.
// CARRIER_HOME keeps the tests away from the real ~/.carrier.
const home = join(dir, 'carrier-home');
const run = (...args: string[]) => spawnSync(process.execPath, [main, ...args], { cwd: dir, encoding: 'utf8', env: { ...process.env, CARRIER_HOME: home } });
const write = (name: string, content: unknown) => {
  const file = join(dir, name);
  writeFileSync(file, JSON.stringify(content));
  return file;
};

// A stand-in for `agent-forge` that answers every GitHub call with an empty 200, so the real process runs the
// real startup (lock, logging, engine, Forge adapter, panel) without GitHub, Forge or any agent.
const bin = join(dir, 'bin');
mkdirSync(bin);
const calls = join(dir, 'forge-calls.log');
writeFileSync(
  join(bin, 'agent-forge'),
  `#!/usr/bin/env node\nrequire('node:fs').appendFileSync(${JSON.stringify(calls)}, JSON.stringify({ args: process.argv.slice(2), cwd: process.cwd() }) + '\\n');\nprocess.stdout.write('HTTP/2.0 200 OK\\ncontent-type: application/json\\n\\n[]');\n`,
  { mode: 0o755 },
);

test('a valid config starts the engine over Forge, shows the panel as plain lines, and Ctrl+C stops it cleanly', async () => {
  const root = join(dir, 'run');
  const config = write('ok.json', { ...valid, root, pollIntervalMinutes: 0.001, logLevel: 'debug', profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'gh' } } });
  const child = spawn(process.execPath, [main, '--config', config], { cwd: dir, env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, stdio: ['ignore', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  child.stdout.on('data', (chunk) => (stdout += chunk));
  child.stderr.on('data', (chunk) => (stderr += chunk));
  const closed = once(child, 'close');
  try {
    // The engine reached GitHub as the orchestrator's profile, from a repo-shaped folder under the root.
    await vi.waitFor(() => expect(readFileSync(calls, 'utf8')).toContain('/issues?'), { timeout: 15_000 });
    const [first] = readFileSync(calls, 'utf8').trim().split('\n').map((line) => JSON.parse(line));
    expect(first.args.slice(0, 4)).toEqual(['gh', 'artanis-agent', 'api', '-i']);
    expect(realpathSync(first.cwd)).toBe(realpathSync(join(root, 'orchestrator', 'forge-cwd', 'AshuLab', 'carrier')));
    expect(stdout).toContain('slots 0/3');
    expect(stdout).not.toContain('\x1b['); // not a terminal: plain lines
  } finally {
    child.kill('SIGINT');
  }
  const [code] = await closed;
  expect([code, stderr]).toEqual([0, '']);
  expect(readFileSync(join(root, 'orchestrator', 'logs', 'orchestrator.log'), 'utf8')).toContain('[info] {"message":"[cli] carrier started"');
  const lock = acquireLock(join(root, 'orchestrator'));
  expect(lock.ok).toBe(true);
  if (lock.ok) lock.release();
});

test('a relative --config path resolves against the working directory', () => {
  write('rel-bad.json', { ...valid, orchestratorProfile: 'x' });
  expect(run('--config', 'rel-bad.json').stderr).toMatch(/Invalid config \/.*carrier-cli-.*\/rel-bad\.json/); // resolved to an absolute path
});

test('missing --config exits non-zero with usage', () => {
  const result = run();
  expect(result.status).not.toBe(0);
  expect(result.stderr).toContain('Usage: carrier --config');
});

test('invalid config lists every error and exits non-zero', () => {
  const result = run('--config', write('bad.json', { ...valid, limits: { maxConcurrentEpics: 0 }, orchestratorProfile: 'x' }));
  expect(result.status).not.toBe(0);
  expect(result.stdout).toBe('');
  expect(result.stderr).toContain('limits.maxConcurrentEpics');
  expect(result.stderr).toContain('orchestratorProfile');
});

test('a second carrier on the same root reports it and exits non-zero without printing config', async () => {
  const config = write('busy.json', valid);
  const holder = spawn(process.execPath, [join(import.meta.dirname, '../../storage/lock-holder.fixture.ts'), join(dir, 'orchestrator')]);
  try {
    await once(holder.stdout, 'data');
    const result = run('--config', config);
    expect(result.status).not.toBe(0);
    expect(result.stderr).toContain('already running');
    expect(result.stdout).toBe('');
  } finally {
    holder.kill();
  }
});

test('missing file exits non-zero', () => {
  expect(run('--config', join(dir, 'nope.json')).status).not.toBe(0);
});

test('schema prints the JSON Schema of the config as the user writes it', () => {
  const result = run('schema');
  expect(result.status).toBe(0);
  const schema = JSON.parse(result.stdout);
  expect(schema.properties.repos.minItems).toBe(1);
  expect(schema.required).toEqual(expect.arrayContaining(['repos', 'profiles', 'agents']));
  expect(schema.required).not.toContain('root'); // has a default
  expect(schema.properties.limits.required ?? []).toEqual([]);
});

test('an unknown command or flag exits 2 with the usage', () => {
  for (const args of [['frobnicate'], ['--nope']]) {
    const result = run(...args);
    expect([result.status, result.stderr]).toEqual([2, expect.stringContaining('carrier init [flags]')]);
  }
});

test('init without a terminal names the question a flag has to answer', () => {
  const result = run('init', '--yes', '--out', join(dir, 'never.json')); // cwd is not a git repo: no repo to suggest
  expect(result.status).toBe(1);
  expect(result.stderr).toContain('Repos to watch');
  expect(result.stderr).toContain('pass it as a flag');
});

test('doctor refuses an invalid config like the run command does', () => {
  const result = run('doctor', '--config', write('doctor-bad.json', { ...valid, orchestratorProfile: 'x' }));
  expect(result.status).toBe(1);
  expect(result.stderr).toContain('orchestratorProfile');
  expect(run('doctor').stderr).toContain('Usage: carrier doctor --config');
});

test('without --config the global file is used when it exists, and init is suggested when it does not', () => {
  const missing = run('doctor');
  expect([missing.status, missing.stderr]).toEqual([2, expect.stringContaining(`No config at ${join(home, 'config.json')}: run "carrier init"`)]);
  mkdirSync(home);
  writeFileSync(join(home, 'config.json'), JSON.stringify({ ...valid, orchestratorProfile: 'x' }));
  const found = run('doctor');
  expect([found.status, found.stderr]).toEqual([1, expect.stringContaining(`Invalid config ${join(home, 'config.json')}`)]);
});

// `start` leaves a Carrier behind on purpose, so each test registers what it started and the afterAll below stops it.
const started: number[] = [];
const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};
afterAll(() => {
  for (const pid of started) if (alive(pid)) process.kill(pid, 'SIGINT');
});
const start = (config: string) => spawnSync(process.execPath, [main, 'start', '--config', config], { cwd: dir, encoding: 'utf8', env: { ...process.env, CARRIER_HOME: home, PATH: `${bin}:${process.env.PATH}` } });
const pidOf = (stdout: string) => Number(/pid (\d+)/.exec(stdout)?.[1]);

test('start returns once Carrier answers on its socket and leaves it running without the terminal', async () => {
  const root = join(dir, 's1');
  const config = write('start.json', { ...valid, root, pollIntervalMinutes: 0.001, profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'gh' } } });
  const began = Date.now();
  const first = start(config);
  const pid = pidOf(first.stdout);
  started.push(pid);
  const log = join(root, 'orchestrator', 'logs', 'start.log');
  expect([first.status, first.stderr]).toEqual([0, '']);
  expect(Date.now() - began).toBeLessThan(15_000);
  expect(first.stdout).toContain(log);
  expect(alive(pid)).toBe(true); // `start` has returned and its own process is gone
  const client = await connectControl(join(root, 'orchestrator', 'control.sock'));
  expect(client.hello.pid).toBe(pid);
  client.close();
  await vi.waitFor(() => expect(readFileSync(log, 'utf8')).toContain('slots 0/3'), { timeout: 15_000 }); // what the engine wrote

  const second = start(config);
  expect([second.status, second.stderr, second.stdout]).toEqual([0, '', expect.stringContaining(`already running (pid ${pid})`)]);
  expect(readFileSync(log, 'utf8')).toContain('slots 0/3'); // the second start did not replace the log

  process.kill(pid, 'SIGINT');
  await vi.waitFor(() => expect(alive(pid)).toBe(false), { timeout: 15_000 });
});

test('a start that cannot come up prints the end of the log and exits 1 as soon as the child is gone', () => {
  const root = join(dir, 's2');
  mkdirSync(join(root, 'orchestrator', 'carrier.db'), { recursive: true }); // the engine cannot open a database that is a folder
  const began = Date.now();
  const result = start(write('start-bad.json', { ...valid, root }));
  expect(result.status).toBe(1);
  expect(Date.now() - began).toBeLessThan(10_000);
  expect(result.stderr).toContain('Carrier exited before it was ready');
  expect(result.stderr).toContain('carrier failed to start');
  expect(result.stderr).toContain(join(root, 'orchestrator', 'logs', 'start.log'));
});
