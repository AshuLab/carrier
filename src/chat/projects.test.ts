import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { connectControl } from '../terminal/cli/control-client.ts';
import { FakeChatRunner, FakeGit } from './fake.ts';
import { startChatHost } from './host.ts';
import { ChatRefused } from './runner.ts';

// The host's cloneRepo request through its socket, with a fake git and a fake `gh` token.
let root: string;
let configPath: string;
let stops: (() => Promise<void>)[];
let git: FakeGit;
let token: () => Promise<string>;
const valid = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { bot: { kind: 'gh' } },
  orchestratorProfile: 'bot',
  providers: { claude: { harness: 'claude', model: 'm' } },
  agents: { author: { profile: 'bot', provider: 'claude', model: 'm' }, reviewer: { profile: 'bot', provider: 'claude', model: 'm' } },
  identities: 'shared',
};
const writeConfig = (chat?: object) => writeFileSync(configPath, JSON.stringify({ ...valid, root, ...(chat === undefined ? {} : { chat }) }));
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'pr-')); // short: a socket path holds 103 bytes on macOS
  configPath = join(root, 'config.json');
  stops = [];
  hosted = false;
  git = new FakeGit();
  token = async () => 'ghp_secrettoken';
  writeConfig();
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
});

let hosted = false;
async function connect() {
  if (hosted === false) await start();
  return connectControl(join(root, 'chat', 'chat.sock'));
}
async function start() {
  hosted = true;
  const started = await startChatHost({ root, logLevel: 'info' } as Config, { installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: new FakeChatRunner() }, git, token: () => token(), configPath, binaryFound: () => true });
  stops.push(started.stop);
}
const projects = () => join(root, 'chat', 'projects');
const clones = () => git.calls.filter((call) => call.args[0] === 'clone');

test('the host lists cloneRepo, and a repository that is not there is cloned to <projects>/<owner>/<repo>', async () => {
  const client = await connect();
  expect(client.hello.capabilities).toContain('cloneRepo');
  expect(await client.request('cloneRepo', { repo: 'acme/app' })).toEqual({ folder: join(projects(), 'acme', 'app'), repo: 'acme/app', fetched: false });
  expect(clones()).toHaveLength(1);
  expect(clones()[0]).toMatchObject({ folder: join(projects(), 'acme'), args: ['clone', '--', 'https://github.com/acme/app.git', join(projects(), 'acme', 'app')], timeoutMs: 10 * 60_000 });
  client.close();
});

test('the token reaches git in the environment and in no argument, and a failure never tells what git said', async () => {
  const client = await connect();
  git.failures.set(`clone -- https://github.com/acme/app.git ${join(projects(), 'acme', 'app')}`, { ok: false, code: 128, stderr: 'fatal: unable to access https://x:ghp_secrettoken@github.com/acme/app.git/' });
  const error = await client.request('cloneRepo', { repo: 'acme/app' }).catch((e: Error) => e.message);
  expect(error).not.toContain('ghp_secrettoken');
  expect(error).toBe('GitHub could not be reached; check the network connection');
  const [call] = clones();
  expect(JSON.stringify(call!.args)).not.toContain('secrettoken');
  expect(call!.env).toMatchObject({ GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraHeader' });
  expect(call!.env!.GIT_CONFIG_VALUE_0).toBe(`Authorization: Basic ${Buffer.from('x-access-token:ghp_secrettoken').toString('base64')}`);
  client.close();
});

test('a repository already there (a .git whose origin is it) is fetched, with the token and the limit, and the reply says so', async () => {
  const dest = join(projects(), 'acme', 'app');
  mkdirSync(join(dest, '.git'), { recursive: true });
  git.repos.set(dest, { head: 'main', branches: ['main'], origin: 'git@github.com:Acme/App.git' });
  const client = await connect();
  expect(await client.request('cloneRepo', { repo: 'acme/app' })).toEqual({ folder: dest, repo: 'acme/app', fetched: true });
  expect(clones()).toHaveLength(0);
  const fetch = git.calls.find((call) => call.args[0] === 'fetch')!;
  expect(fetch).toMatchObject({ folder: dest, args: ['fetch', 'origin', '--prune'], timeoutMs: 600_000 });
  expect(fetch.env!.GIT_CONFIG_COUNT).toBe('1');
  client.close();
});

test('anything else at the path stops the request with a reason and is left untouched', async () => {
  const dest = join(projects(), 'acme', 'app');
  mkdirSync(dest, { recursive: true });
  writeFileSync(join(dest, 'mine.txt'), 'mine');
  const client = await connect();
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('not a clone of acme/app');
  mkdirSync(join(dest, '.git'));
  git.repos.set(dest, { head: 'main', branches: ['main'], origin: 'https://github.com/acme/other.git' });
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('not a clone of acme/app');
  git.repos.set(dest, { head: 'main', branches: ['main'] }); // no origin
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('not a clone of acme/app');
  expect(existsSync(join(dest, 'mine.txt'))).toBe(true);
  expect(git.calls.filter((call) => ['clone', 'fetch'].includes(call.args[0]!))).toHaveLength(0);
  client.close();
});

test('a repo that is empty, has a .. part, has more or fewer than two parts or is not a string never reaches git', async () => {
  const client = await connect();
  for (const repo of ['', '../x', 'a/..', 'a/b/c', 'solo', '/a', 'a//b', 7, null]) await expect(client.request('cloneRepo', { repo } as never)).rejects.toThrow('invalid request');
  expect(git.calls).toHaveLength(0);
  client.close();
});

test.each([
  ['a repository that is not found or not visible', { ok: false, code: 128, stderr: 'remote: Repository not found.' }, 'acme/app was not found, or your GitHub login cannot see it'],
  ['no network', { ok: false, code: 128, stderr: 'fatal: Could not resolve host: github.com' }, 'GitHub could not be reached; check the network connection'],
  ['a command that took too long', { ok: false, code: null, timedOut: true, stderr: 'git took too long' }, 'The clone took more than ten minutes and was stopped'],
  ['anything else', { ok: false, code: 1, stderr: 'fatal: something with a https://x:tok@github.com url' }, 'git could not clone acme/app'],
] as const)('%s comes back as its own sentence and leaves nothing behind', async (_name, failure, sentence) => {
  const client = await connect();
  git.failures.set(`clone -- https://github.com/acme/app.git ${join(projects(), 'acme', 'app')}`, failure);
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow(new RegExp(`^${sentence}$`));
  expect(existsSync(join(projects(), 'acme', 'app'))).toBe(false);
  client.close();
});

test('a failed fetch keeps the clone and says so in words', async () => {
  const dest = join(projects(), 'acme', 'app');
  mkdirSync(join(dest, '.git'), { recursive: true });
  git.repos.set(dest, { head: 'main', branches: ['main'], origin: 'https://github.com/acme/app.git' });
  git.failures.set('fetch origin --prune', { ok: false, code: null, timedOut: true, stderr: 'git took too long' });
  const client = await connect();
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('The fetch took more than ten minutes and was stopped');
  expect(existsSync(join(dest, '.git'))).toBe(true);
  client.close();
});

test('gh missing or signed out is a refusal with its own sentence, before git runs', async () => {
  const client = await connect();
  token = async () => {
    throw new ChatRefused('gh is not signed in to GitHub; run "gh auth login"');
  };
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('gh is not signed in');
  expect(clones()).toHaveLength(0);
  expect(existsSync(join(projects(), 'acme', 'app'))).toBe(false);
  client.close();
});

test('when the client closes the connection the clone is aborted and the destination this request made is removed', async () => {
  let release!: () => void;
  git.clonePending = new Promise((resolve) => (release = resolve));
  const client = await connect();
  const dest = join(projects(), 'acme', 'app');
  void client.request('cloneRepo', { repo: 'acme/app' }).catch(() => {});
  await vi.waitFor(() => expect(existsSync(dest)).toBe(true)); // the half-made clone
  client.close();
  await vi.waitFor(() => expect(existsSync(dest)).toBe(false));
  release();
  const again = await connect();
  git.clonePending = undefined;
  expect(await again.request('cloneRepo', { repo: 'acme/app' })).toMatchObject({ fetched: false }); // nothing of the aborted one is in the way
  again.close();
});

test('an abort during a fetch leaves the clone that was already there', async () => {
  const dest = join(projects(), 'acme', 'app');
  mkdirSync(join(dest, '.git'), { recursive: true });
  git.repos.set(dest, { head: 'main', branches: ['main'], origin: 'https://github.com/acme/app.git' });
  token = () => new Promise(() => {}); // never answers: the request is still waiting when the client leaves
  const client = await connect();
  void client.request('cloneRepo', { repo: 'acme/app' }).catch(() => {});
  await new Promise((resolve) => setTimeout(resolve, 50));
  client.close();
  await new Promise((resolve) => setTimeout(resolve, 50));
  expect(existsSync(join(dest, '.git'))).toBe(true);
});

test('two requests for the same repository at the same time share one clone, and it goes on while one of them is still waiting', async () => {
  let release!: () => void;
  git.clonePending = new Promise((resolve) => (release = resolve));
  const first = await connect();
  const second = await connect();
  const one = first.request('cloneRepo', { repo: 'acme/app' });
  await vi.waitFor(() => expect(clones()).toHaveLength(1));
  const two = second.request('cloneRepo', { repo: 'ACME/app' }); // same repository, other spelling
  await new Promise((resolve) => setTimeout(resolve, 50));
  first.close();
  one.catch(() => {});
  await new Promise((resolve) => setTimeout(resolve, 50));
  expect(existsSync(join(projects(), 'acme', 'app'))).toBe(true); // the second client still wants it
  release();
  expect(await two).toMatchObject({ repo: 'acme/app', fetched: false });
  expect(clones()).toHaveLength(1);
  second.close();
});

test('the projects folder is read from the config file at each request, ~ expanded, with no restart', async () => {
  const client = await connect();
  const elsewhere = join(root, 'elsewhere');
  writeConfig({ projectsFolder: elsewhere });
  expect(await client.request('cloneRepo', { repo: 'acme/app' })).toMatchObject({ folder: join(elsewhere, 'acme', 'app') });
  writeConfig({ projectsFolder: '~/carrier-projects-test' });
  git.failures.set(`clone -- https://github.com/acme/app.git ${join(process.env.HOME!, 'carrier-projects-test', 'acme', 'app')}`, { ok: false, code: 1, stderr: '' });
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('git could not clone'); // it went to the new folder
  rmSync(join(process.env.HOME!, 'carrier-projects-test'), { recursive: true, force: true });
  writeConfig();
  expect(await client.request('cloneRepo', { repo: 'acme/other' })).toMatchObject({ folder: join(projects(), 'acme', 'other') });
  client.close();
});

test.each(['repos', 'worktrees', 'orchestrator'])('a projects folder inside the shared root\'s %s is refused with a reason and git is not run', async (name) => {
  const client = await connect();
  writeConfig({ projectsFolder: join(root, name, 'mine') });
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow(`inside Carrier's own ${name} folder`);
  expect(git.calls).toHaveLength(0);
  client.close();
});

test("a projects folder that is the shared root cannot reach the engine's own clones", async () => {
  const client = await connect();
  writeConfig({ projectsFolder: root });
  await expect(client.request('cloneRepo', { repo: 'repos/x' })).rejects.toThrow("inside Carrier's own repos folder");
  expect(git.calls).toHaveLength(0);
  expect(existsSync(join(root, 'repos'))).toBe(false);
  client.close();
});

test('a config file that cannot be read or is not valid is a refusal in words', async () => {
  const client = await connect();
  writeFileSync(configPath, '{ nope');
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('The config file cannot be read');
  writeConfig({ projectsFolder: 'relative/dir' });
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('chat.projectsFolder: must be an absolute path');
  client.close();
});

const localProject = (name: string) => join(projects(), 'local', name);

test('the host lists createProject, and a free name makes <projects>/local/<name> with git init -b main', async () => {
  const client = await connect();
  expect(client.hello.capabilities).toContain('createProject');
  expect(await client.request('createProject', { name: 'my-app' })).toEqual({ folder: localProject('my-app') });
  expect(existsSync(localProject('my-app'))).toBe(true);
  expect(git.calls).toEqual([{ folder: localProject('my-app'), args: ['init', '-b', 'main'], timeoutMs: undefined, env: undefined }]);
  expect(git.repos.get(localProject('my-app'))).toMatchObject({ head: 'main' });
  client.close();
});

test('a name that is taken, by a folder or a file, is refused with a reason and nothing is changed', async () => {
  mkdirSync(localProject('mine'), { recursive: true });
  writeFileSync(join(localProject('mine'), 'mine.txt'), 'mine');
  writeFileSync(localProject('file'), 'a file');
  const client = await connect();
  await expect(client.request('createProject', { name: 'mine' })).rejects.toThrow('mine is already a project');
  await expect(client.request('createProject', { name: 'file' })).rejects.toThrow('file is already a project');
  expect(existsSync(join(localProject('mine'), 'mine.txt'))).toBe(true);
  expect(existsSync(join(localProject('mine'), '.git'))).toBe(false);
  expect(git.calls).toHaveLength(0);
  client.close();
});

test('a git init that fails removes what the request made and says so without git\'s words', async () => {
  git.failures.set('init -b main', { ok: false, code: 1, stderr: 'fatal: something with a https://x:tok@github.com url' });
  const client = await connect();
  await expect(client.request('createProject', { name: 'broken' })).rejects.toThrow(/^git could not start the project broken$/);
  expect(existsSync(localProject('broken'))).toBe(false);
  git.failures.clear();
  expect(await client.request('createProject', { name: 'broken' })).toEqual({ folder: localProject('broken') }); // the name is free again
  client.close();
});

test('a name that is empty, dotted or has a slash never makes a folder', async () => {
  const client = await connect();
  for (const name of ['', '.', '..', '.hidden', 'a/b', '../escape', '/abs', 'a'.repeat(101), 7, null]) await expect(client.request('createProject', { name } as never)).rejects.toThrow('invalid request');
  expect(git.calls).toHaveLength(0);
  expect(existsSync(join(projects(), 'local'))).toBe(false);
  expect(existsSync(join(root, 'escape'))).toBe(false);
  client.close();
});

test('createProject follows the projects folder of the config file and refuses one inside the engine folders', async () => {
  const client = await connect();
  const elsewhere = join(root, 'elsewhere');
  writeConfig({ projectsFolder: elsewhere });
  expect(await client.request('createProject', { name: 'x' })).toEqual({ folder: join(elsewhere, 'local', 'x') });
  writeConfig({ projectsFolder: join(root, 'repos', 'mine') });
  await expect(client.request('createProject', { name: 'y' })).rejects.toThrow("inside Carrier's own repos folder");
  expect(existsSync(join(root, 'repos'))).toBe(false);
  client.close();
});
