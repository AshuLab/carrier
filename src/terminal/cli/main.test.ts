import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
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
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  agents: {
    author: { profile: 'a', provider: 'claude', model: 'm' },
    reviewer: { profile: 'b', provider: 'codex', model: 'm' },
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

test('init with --lead-reviewer flags forwards them and configures the lead reviewer', () => {
  const out = join(dir, 'init-lead.json');
  const result = run(
    'init',
    '--repo', 'AshuLab/carrier',
    '--author-profile', 'forge:artanis-agent',
    '--reviewer-profile', 'gh',
    '--author', 'claude:sonnet',
    '--reviewer', 'codex:gpt-test',
    '--lead-reviewer', 'claude:opus',
    '--lead-reviewer-profile', 'gh',
    '--lead-reviewer-persona-name', 'Architect',
    '--lead-reviewer-persona-prompt', 'Be rigorous.',
    '--out', out,
    '--yes',
  );
  expect(result.status).toBe(0);
  const config = JSON.parse(readFileSync(out, 'utf8'));
  expect(config.agents.leadReviewer).toEqual({
    profile: 'gh',
    provider: 'claude',
    model: 'opus',
    persona: { name: 'Architect', prompt: 'Be rigorous.' },
  });
}, 15_000);

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

test('status prints the panel of the running carrier, plain when piped, and exits 0; with none running it says so and exits 1', async () => {
  const root = join(dir, 'st');
  const config = write('status.json', { ...valid, root, pollIntervalMinutes: 0.001, profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'gh' } } });
  const none = run('status', '--config', config);
  expect([none.status, none.stdout, none.stderr]).toEqual([1, '', expect.stringMatching(/not running.*carrier start/)]);

  const child = spawn(process.execPath, [main, '--config', config], { cwd: dir, env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, stdio: 'ignore' });
  const closed = once(child, 'close');
  try {
    await vi.waitFor(() => expect(run('status', '--config', config).status).toBe(0), { timeout: 15_000 });
    const shown = run('status', '--config', config);
    expect(shown.stdout).toContain('CARRIER');
    expect(shown.stdout).toContain('Slots');
    expect(shown.stdout).not.toContain('\x1b[');
  } finally {
    child.kill('SIGINT');
  }
  await closed;
});

test('watch prints plain lines when piped and leaves on Ctrl+C with Carrier still running; with none running it says so and exits 1; when the Carrier stops it says so and exits 1', async () => {
  const root = join(dir, 'w');
  const config = write('watch.json', { ...valid, root, pollIntervalMinutes: 0.001, profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'gh' } } });
  const began = Date.now();
  const none = run('watch', '--config', config);
  expect([none.status, none.stdout, none.stderr]).toEqual([1, '', expect.stringMatching(/not running.*carrier start/)]);
  expect(Date.now() - began).toBeLessThan(5000);

  const carrier = spawn(process.execPath, [main, '--config', config], { cwd: dir, env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, stdio: 'ignore' });
  const carrierClosed = once(carrier, 'close');
  const watch = () => {
    const child = spawn(process.execPath, [main, 'watch', '--config', config], { cwd: dir, env: { ...process.env, CARRIER_HOME: home }, stdio: ['ignore', 'pipe', 'pipe'] });
    const seen = { stdout: '', stderr: '' };
    child.stdout.on('data', (chunk) => (seen.stdout += chunk));
    child.stderr.on('data', (chunk) => (seen.stderr += chunk));
    return { child, seen, closed: once(child, 'close') };
  };
  try {
    await vi.waitFor(() => expect(run('status', '--config', config).status).toBe(0), { timeout: 15_000 });

    const leaving = watch();
    await vi.waitFor(() => expect(leaving.seen.stdout).toContain('slots 0/3'), { timeout: 15_000 });
    expect(leaving.seen.stdout).not.toContain('\x1b[');
    leaving.child.kill('SIGINT');
    expect((await leaving.closed)[0]).toBe(0);
    expect(run('status', '--config', config).status).toBe(0); // leaving did not stop it

    const watching = watch();
    await vi.waitFor(() => expect(watching.seen.stdout).toContain('slots 0/3'), { timeout: 15_000 });
    carrier.kill('SIGINT');
    expect((await watching.closed)[0]).toBe(1);
    expect(watching.seen.stderr).toBe('Carrier stopped.\n');
  } finally {
    carrier.kill('SIGINT');
  }
  await carrierClosed;
});

test('status against a carrier that speaks another protocol exits 2 naming both', async () => {
  const root = join(dir, 'sp');
  mkdirSync(join(root, 'orchestrator'), { recursive: true });
  const server = createServer((socket) => socket.end(`${JSON.stringify({ event: 'hello', protocol: 2, pid: 1, startedAt: 1, version: '9.0.0', capabilities: [] })}\n`));
  await new Promise<void>((resolve) => server.listen(join(root, 'orchestrator', 'control.sock'), resolve));
  try {
    const result = await new Promise<{ status: number | null; stderr: string }>((resolve) => {
      const child = spawn(process.execPath, [main, 'status', '--config', write('proto.json', { ...valid, root })], { cwd: dir, env: { ...process.env, CARRIER_HOME: home }, stdio: ['ignore', 'ignore', 'pipe'] });
      let stderr = '';
      child.stderr.on('data', (chunk) => (stderr += chunk));
      child.on('close', (status) => resolve({ status, stderr }));
    });
    expect(result.status).toBe(2);
    expect(result.stderr).toMatch(/protocol 1.*protocol 2/);
  } finally {
    server.close();
  }
});

test('pause, resume, check and stop act on a running Carrier; a second stop and the others without one say so', async () => {
  const root = join(dir, 's'); // short: a socket path holds 103 bytes on macOS
  const config = write('control.json', { ...valid, root, profiles: { a: { kind: 'forge', agent: 'artanis-agent' }, b: { kind: 'gh' } } });
  const socket = join(root, 'orchestrator', 'control.sock');
  const control = (command: string) => run(command, '--config', config);

  // none running yet
  for (const command of ['pause', 'resume', 'check']) {
    const result = control(command);
    expect([result.status, result.stdout, result.stderr]).toEqual([1, '', 'Carrier is not running\n']);
  }

  const child = spawn(process.execPath, [main, '--config', config], { cwd: dir, env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, stdio: 'ignore' });
  const closed = once(child, 'close');
  try {
    await vi.waitFor(() => expect(existsSync(socket)).toBe(true), { timeout: 15_000 });
    const paused = async () => {
      const client = await connectControl(socket);
      try {
        return ((await client.request('snapshot')) as { paused: boolean }).paused;
      } finally {
        client.close();
      }
    };
    expect(await paused()).toBe(false);
    expect(control('pause')).toMatchObject({ status: 0, stdout: 'Intake paused\n', stderr: '' });
    await vi.waitFor(async () => expect(await paused()).toBe(true));
    expect(control('resume')).toMatchObject({ status: 0, stdout: 'Intake resumed\n', stderr: '' });
    await vi.waitFor(async () => expect(await paused()).toBe(false));
    expect(control('check')).toMatchObject({ status: 0, stdout: 'Checking GitHub now\n', stderr: '' });

    expect(control('stop')).toMatchObject({ status: 0, stdout: 'Carrier stopped\n', stderr: '' });
    expect(existsSync(socket)).toBe(false);
    expect(child.exitCode === null ? (await closed)[0] : child.exitCode).toBe(0);
  } finally {
    child.kill('SIGINT');
  }
  expect(control('stop')).toMatchObject({ status: 0, stdout: 'Carrier is not running\n', stderr: '' });
});

test('a Carrier that speaks another protocol makes the commands exit 2', async () => {
  const root = join(dir, 'p');
  mkdirSync(join(root, 'orchestrator'), { recursive: true });
  const server = createServer((connection) => connection.write(`${JSON.stringify({ event: 'hello', protocol: 2 })}\n`));
  await new Promise<void>((resolve) => server.listen(join(root, 'orchestrator', 'control.sock'), resolve));
  try {
    const config = write('protocol.json', { ...valid, root });
    const result = await new Promise<{ status: number | null; stderr: string }>((resolve) => {
      const child = spawn(process.execPath, [main, 'pause', '--config', config], { cwd: dir, env: { ...process.env, CARRIER_HOME: home }, stdio: ['ignore', 'ignore', 'pipe'] });
      let stderr = '';
      child.stderr.on('data', (chunk) => (stderr += chunk));
      child.on('close', (status) => resolve({ status, stderr }));
    });
    expect(result.status).toBe(2);
    expect(result.stderr).toContain('protocol');
  } finally {
    server.close();
  }
});

// A stand-in for a running Carrier on `root`: says hello, records every request and answers `reply(request)`; `ok` is the answer, an Error refuses it.
async function fakeCarrier(root: string, { capabilities = ['agentOptions', 'resumeEpic'], reply = (): unknown => undefined }: { capabilities?: string[]; reply?: (request: any) => unknown } = {}) {
  mkdirSync(join(root, 'orchestrator'), { recursive: true });
  const requests: any[] = [];
  const server = createServer((connection) => {
    connection.write(`${JSON.stringify({ event: 'hello', protocol: 1, pid: 1, startedAt: 0, version: 'x', capabilities })}\n`);
    connection.on('data', (chunk) => {
      for (const line of String(chunk).split('\n').filter(Boolean)) {
        const request = JSON.parse(line);
        requests.push(request);
        const answer = reply(request);
        connection.write(`${JSON.stringify(answer instanceof Error ? { id: request.id, ok: false, error: answer.message } : { id: request.id, ok: true, data: answer })}\n`);
      }
    });
  });
  await new Promise<void>((resolve) => server.listen(join(root, 'orchestrator', 'control.sock'), resolve));
  return { requests, close: () => server.close() };
}
// Not spawnSync: the fake Carrier answers from this process.
const runAsync = (...args: string[]) =>
  new Promise<{ status: number | null; stdout: string; stderr: string }>((resolve) => {
    const child = spawn(process.execPath, [main, ...args], { cwd: dir, env: { ...process.env, CARRIER_HOME: home }, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.on('close', (status) => resolve({ status, stdout, stderr }));
  });

test('restart asks a running Carrier to resume the epic on the options named, prints one line and exits 0', async () => {
  const root = join(dir, 'r1');
  const carrier = await fakeCarrier(root);
  try {
    const config = write('restart.json', { ...valid, root });
    expect(await runAsync('restart', 'AshuLab/carrier#5', '--author', 'codex', '--config', config)).toEqual({ status: 0, stdout: 'Restarting AshuLab/carrier#5…\nRestarted AshuLab/carrier#5\n', stderr: '' });
    expect(await runAsync('restart', 'AshuLab/carrier#6', '--reviewer', 'claude', '--author', 'claude', '--config', config)).toMatchObject({ status: 0, stdout: 'Restarting AshuLab/carrier#6…\nRestarted AshuLab/carrier#6\n' });
    // without flags and without a terminal each role keeps its option: neither is sent
    expect(await runAsync('restart', 'AshuLab/carrier#7', '--config', config)).toMatchObject({ status: 0, stdout: 'Restarting AshuLab/carrier#7…\nRestarted AshuLab/carrier#7\n' });
    expect(carrier.requests.map(({ id, ...request }) => request)).toEqual([
      { cmd: 'resumeEpic', repo: 'AshuLab/carrier', issue: 5, author: 'codex' },
      { cmd: 'resumeEpic', repo: 'AshuLab/carrier', issue: 6, author: 'claude', reviewer: 'claude' },
      { cmd: 'resumeEpic', repo: 'AshuLab/carrier', issue: 7 },
    ]);
  } finally {
    carrier.close();
  }
});

test.each([
  ['unknown epic', 'Carrier does not know AshuLab/carrier#5. Use the owner/repo#issue that carrier status shows.'],
  ['not stopped', 'AshuLab/carrier#5 is not stopped, so there is nothing to restart.'],
  ['github unavailable', 'GitHub did not answer, so nothing changed. Try again in a moment.'],
  ['did not restart', 'The ready label is back on the issue, but the epic did not start within 30 seconds. The next check will take it.'],
  ['unknown option', 'That option is not in agentOptions of the configuration. Use a name declared there.'],
  ['internal error', 'Carrier refused: internal error'],
])('restart refused as "%s" says what it means and exits 1', async (reason, words) => {
  const root = join(dir, 'r2');
  const carrier = await fakeCarrier(root, { reply: () => new Error(reason) });
  try {
    const result = await runAsync('restart', 'AshuLab/carrier#5', '--config', write('refused.json', { ...valid, root }));
    expect([result.status, result.stdout, result.stderr]).toEqual([1, 'Restarting AshuLab/carrier#5…\n', `${words}\n`]);
  } finally {
    carrier.close();
  }
});

test('restart against an engine without the agentOptions capability says so and sends nothing', async () => {
  const root = join(dir, 'r3');
  const carrier = await fakeCarrier(root, { capabilities: ['resumeEpic'] });
  try {
    const result = await runAsync('restart', 'AshuLab/carrier#5', '--config', write('old.json', { ...valid, root }));
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('agentOptions');
    expect(carrier.requests).toEqual([]);
  } finally {
    carrier.close();
  }
});

test('restart without a Carrier running says so and exits 1; against another protocol it exits 2', async () => {
  const none = write('restart-none.json', { ...valid, root: join(dir, 'r4') });
  expect(await runAsync('restart', 'AshuLab/carrier#5', '--config', none)).toEqual({ status: 1, stdout: '', stderr: 'Carrier is not running\n' });

  const root = join(dir, 'r5');
  mkdirSync(join(root, 'orchestrator'), { recursive: true });
  const server = createServer((connection) => connection.write(`${JSON.stringify({ event: 'hello', protocol: 2 })}\n`));
  await new Promise<void>((resolve) => server.listen(join(root, 'orchestrator', 'control.sock'), resolve));
  try {
    const result = await runAsync('restart', 'AshuLab/carrier#5', '--config', write('restart-protocol.json', { ...valid, root }));
    expect(result.status).toBe(2);
    expect(result.stderr).toContain('protocol');
  } finally {
    server.close();
  }
});

test('restart with an argument that is not owner/name#N is a usage error and sends nothing to Carrier', async () => {
  const root = join(dir, 'r6');
  const carrier = await fakeCarrier(root);
  try {
    const config = write('restart-usage.json', { ...valid, root });
    for (const args of [['restart', '--config', config], ['restart', 'AshuLab/carrier', '--config', config], ['restart', 'AshuLab/carrier#0', '--config', config], ['restart', 'carrier#5', '--config', config]]) {
      const result = await runAsync(...args);
      expect([result.status, result.stdout, result.stderr]).toEqual([2, '', expect.stringContaining('owner/name#N')]);
    }
    expect(carrier.requests).toEqual([]);
  } finally {
    carrier.close();
  }
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

test('--help lists chat and chat-host', () => {
  const out = run('--help').stdout;
  expect(out).toContain('carrier chat ');
  expect(out).toContain('carrier chat-host');
});

test('chat --list starts a real detached host, a second one starts no other, an engine on the same root keeps running, and chat --stop ends only the host', () => {
  const root = join(dir, 'chat-run');
  const config = write('chat.json', { ...valid, root });
  const engine = acquireLock(join(root, 'orchestrator')); // an engine holding its lock on the same root
  expect(engine.ok).toBe(true);
  try {
    const first = run('chat', '--list', '--config', config);
    expect(first.stdout).toBe('No chat sessions.\n');
    expect(run('chat', '--list', '--config', config).stdout).toBe('No chat sessions.\n');
    expect(run('stop', '--config', config).stdout).toBe('Carrier is not running\n'); // the engine's stop does not reach the host
    expect(existsSync(join(root, 'chat', 'chat.sock'))).toBe(true);
    expect(run('chat', '--stop', '--config', config).stdout).toBe('Chat host stopped\n');
    expect(existsSync(join(root, 'chat', 'chat.sock'))).toBe(false);
    expect(run('chat', '--stop', '--config', config).stdout).toBe('No chat host is running\n');
  } finally {
    run('chat', '--stop', '--config', config);
    if (engine.ok) engine.release();
  }
}, 30_000);
