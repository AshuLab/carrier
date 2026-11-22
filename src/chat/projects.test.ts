import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeClock } from '../orchestration/fake.ts';
import { connectControl } from '../terminal/cli/control-client.ts';
import { FakeChatRunner, FakeGit, fakeProjects } from './fake.ts';
import { startChatHost } from './host.ts';
import { ChatRefused } from './runner.ts';

// The host's cloneRepo request through its socket, with a fake git and a fake `gh` token.
let root: string;
let stops: (() => Promise<void>)[];
let git: FakeGit;
let token: () => Promise<string>;
const chatJson = () => join(root, 'chat.json');
const writeConfig = (chat: object = {}) => writeFileSync(chatJson(), JSON.stringify(chat));
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'pr-')); // short: a socket path holds 103 bytes on macOS
  vi.stubEnv('CARRIER_HOME', root);
  stops = [];
  hosted = false;
  git = new FakeGit();
  token = async () => 'ghp_secrettoken';
  writeConfig();
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

let hosted = false;
async function connect() {
  if (hosted === false) await start();
  return connectControl(join(root, 'chat', 'state', 'chat.sock'));
}
async function start() {
  hosted = true;
  const started = await startChatHost({ installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: new FakeChatRunner() }, git, token: () => token(), binaryFound: () => true });
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

test('the projects folder is read from chat.json at each request, ~ expanded, with no restart', async () => {
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

test.each(['engine', join('chat', 'state'), join('chat', 'logs'), join('chat', 'worktrees')])('a projects folder inside the Carrier folder\'s %s is refused with a reason and git is not run', async (name) => {
  const client = await connect();
  writeConfig({ projectsFolder: join(root, name, 'mine') });
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow(`inside Carrier's own ${name} folder`);
  expect(git.calls).toHaveLength(0);
  client.close();
});

test("a projects folder that is the Carrier folder cannot reach the engine's folder", async () => {
  const client = await connect();
  writeConfig({ projectsFolder: root });
  await expect(client.request('cloneRepo', { repo: 'engine/x' })).rejects.toThrow("inside Carrier's own engine folder");
  expect(git.calls).toHaveLength(0);
  expect(existsSync(join(root, 'engine'))).toBe(false);
  client.close();
});

test('a chat.json that cannot be read or is not valid is a refusal in words', async () => {
  const client = await connect();
  writeFileSync(chatJson(), '{ nope');
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('chat.json is not valid: (file): is not valid JSON');
  writeConfig({ projectsFolder: 'relative/dir' });
  await expect(client.request('cloneRepo', { repo: 'acme/app' })).rejects.toThrow('chat.json is not valid: projectsFolder: must be an absolute path');
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

test('createProject follows the projects folder of chat.json and refuses one inside the engine folder', async () => {
  const client = await connect();
  const elsewhere = join(root, 'elsewhere');
  writeConfig({ projectsFolder: elsewhere });
  expect(await client.request('createProject', { name: 'x' })).toEqual({ folder: join(elsewhere, 'local', 'x') });
  writeConfig({ projectsFolder: join(root, 'engine', 'mine') });
  await expect(client.request('createProject', { name: 'y' })).rejects.toThrow("inside Carrier's own engine folder");
  expect(existsSync(join(root, 'engine'))).toBe(false);
  client.close();
});

// The progress of a clone: git's stderr, of which only its progress lines leave projects.ts, one a second at most.
test('only git\'s progress lines reach the waiter, and a line with a URL or anything else does not', async () => {
  let release!: () => void;
  git.clonePending = new Promise((resolve) => (release = resolve));
  const clock = new FakeClock();
  const lines: string[] = [];
  const cloning = fakeProjects(git, clock).cloneRepo({ repo: 'acme/app' }, new AbortController().signal, (line) => lines.push(line));
  await vi.waitFor(() => expect(clones()).toHaveLength(1));
  const said = [
    "Cloning into '/x/acme/app'...",
    'fatal: unable to access https://x:ghp_secrettoken@github.com/acme/app.git/',
    'Receiving objects: 45% (45/100), https://x:tok@github.com/ 1.2 MiB',
    'remote: Counting objects: 100% (5/5), done.',
    'Enumerating objects: 5, done.',
    'warning: Receiving objects: 10%',
    'https://github.com/acme/app Receiving objects: 10%',
  ];
  for (const line of said) {
    git.emitProgress(line);
    clock.time += 1500;
  }
  release();
  await cloning;
  expect(lines).toEqual(['Receiving objects: 45%', 'Counting objects: 100%']);
});

test('every kind of git progress passes, and at most one line a second', async () => {
  let release!: () => void;
  git.clonePending = new Promise((resolve) => (release = resolve));
  const clock = new FakeClock();
  const lines: string[] = [];
  const cloning = fakeProjects(git, clock).cloneRepo({ repo: 'acme/app' }, new AbortController().signal, (line) => lines.push(line));
  await vi.waitFor(() => expect(clones()).toHaveLength(1));
  for (const line of ['Counting objects:   1%', 'Compressing objects:   2%', 'Receiving objects:   3%', 'Resolving deltas:   4%', 'Updating files:   5%']) {
    git.emitProgress(line, 'Receiving objects: 99%'); // the second is within the same second
    clock.time += 1000;
  }
  release();
  await cloning;
  expect(lines).toEqual(['Counting objects: 1%', 'Compressing objects: 2%', 'Receiving objects: 3%', 'Resolving deltas: 4%', 'Updating files: 5%']);
});

test('a waiter that joins a clone in progress hears the latest line at once, and one that left hears nothing more', async () => {
  let release!: () => void;
  git.clonePending = new Promise((resolve) => (release = resolve));
  const clock = new FakeClock();
  const projects = fakeProjects(git, clock);
  const first = new AbortController();
  const heardFirst: string[] = [];
  const one = projects.cloneRepo({ repo: 'acme/app' }, first.signal, (line) => heardFirst.push(line));
  await vi.waitFor(() => expect(clones()).toHaveLength(1));
  git.emitProgress('Receiving objects: 10%');
  const heardSecond: string[] = [];
  const two = projects.cloneRepo({ repo: 'acme/app' }, new AbortController().signal, (line) => heardSecond.push(line));
  expect(heardSecond).toEqual(['Receiving objects: 10%']);
  first.abort();
  await expect(one).rejects.toThrow('The clone was cancelled');
  clock.time += 2000;
  git.emitProgress('Receiving objects: 50%');
  release();
  await two;
  expect(heardFirst).toEqual(['Receiving objects: 10%']);
  expect(heardSecond).toEqual(['Receiving objects: 10%', 'Receiving objects: 50%']);
  expect(clones()).toHaveLength(1);
});

test('the last waiter to leave stops the clone and hears of it only once the half clone is gone', async () => {
  git.clonePending = new Promise(() => {});
  const abort = new AbortController();
  const dest = join(projects(), 'acme', 'app');
  const cloning = fakeProjects(git).cloneRepo({ repo: 'acme/app' }, abort.signal);
  await vi.waitFor(() => expect(existsSync(dest)).toBe(true));
  abort.abort();
  await expect(cloning).rejects.toThrow('The clone was cancelled');
  expect(existsSync(dest)).toBe(false);
});

test('no progress callback is asked of git for a fetch', async () => {
  const dest = join(projects(), 'acme', 'app');
  mkdirSync(join(dest, '.git'), { recursive: true });
  git.repos.set(dest, { head: 'main', branches: ['main'], origin: 'https://github.com/acme/app.git' });
  expect(await fakeProjects(git).cloneRepo({ repo: 'acme/app' }, new AbortController().signal)).toMatchObject({ fetched: true });
});

test('the owner folder a failed or cancelled clone made goes with it, and one that holds another repository stays', async () => {
  const owner = join(projects(), 'acme');
  git.clonePending = new Promise(() => {});
  const abort = new AbortController();
  const cloning = fakeProjects(git).cloneRepo({ repo: 'acme/app' }, abort.signal);
  await vi.waitFor(() => expect(existsSync(join(owner, 'app'))).toBe(true));
  abort.abort();
  await expect(cloning).rejects.toThrow('The clone was cancelled');
  expect(existsSync(owner)).toBe(false);

  git.clonePending = undefined;
  mkdirSync(join(owner, 'other'), { recursive: true });
  git.failures.set(`clone -- https://github.com/acme/app.git ${join(owner, 'app')}`, { ok: false, code: 128, stderr: 'remote: Repository not found.' });
  await expect(fakeProjects(git).cloneRepo({ repo: 'acme/app' }, new AbortController().signal)).rejects.toThrow(ChatRefused);
  expect(existsSync(join(owner, 'other'))).toBe(true);
});

test('a clone the person cancels is not logged as a failure of git', async () => {
  const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
  git.clonePending = new Promise(() => {});
  const abort = new AbortController();
  const cloning = fakeProjects(git).cloneRepo({ repo: 'acme/app' }, abort.signal);
  await vi.waitFor(() => expect(existsSync(join(projects(), 'acme', 'app'))).toBe(true));
  abort.abort();
  await expect(cloning).rejects.toThrow('The clone was cancelled');
  expect(errors.mock.calls.flat().join('\n')).not.toContain('git clone failed');
  errors.mockRestore();
});

test('a folder that cannot be made is not reported as one that is already there', async () => {
  const owner = join(projects(), 'acme');
  mkdirSync(owner, { recursive: true });
  chmodSync(owner, 0o555); // the destination cannot be made inside it
  try {
    const error = await fakeProjects(git).cloneRepo({ repo: 'acme/app' }, new AbortController().signal).catch((e: Error) => e.message);
    expect(error).toContain('could not be made');
    expect(error).not.toContain('already there');
    expect(clones()).toHaveLength(0);
  } finally {
    chmodSync(owner, 0o755);
  }
});

// A new project from Settings (the `projects` capability): the host makes the folder, runs git init and registers the entry with origin created.
const projectsFile = () => join(root, 'projects.json');

test('newProject makes <projects>/local/<name> with git init and registers it with origin created', async () => {
  const client = await connect();
  const reply = await client.request('newProject', { name: 'my-app' });
  expect(reply).toEqual({ folder: localProject('my-app') });
  // the app's golden reply has the same shape (macos/Tests/Fixtures/chat-new-project.json)
  const golden = JSON.parse(readFileSync(join(import.meta.dirname, '..', '..', 'macos', 'Tests', 'Fixtures', 'chat-new-project.json'), 'utf8'));
  expect(Object.keys(golden)).toEqual(Object.keys(reply as object));
  expect(git.calls).toEqual([{ folder: localProject('my-app'), args: ['init', '-b', 'main'], timeoutMs: undefined, env: undefined }]);
  expect(JSON.parse(readFileSync(projectsFile(), 'utf8')).projects).toEqual([{ path: localProject('my-app'), origin: 'created' }]);
  client.close();
});

test('newProject with a parent makes <parent>/local/<name>, and a parent inside Carrier\'s own folder is refused with nothing written', async () => {
  const client = await connect();
  const parent = join(root, 'elsewhere');
  expect(await client.request('newProject', { name: 'x', parent })).toEqual({ folder: join(parent, 'local', 'x') });
  await expect(client.request('newProject', { name: 'y', parent: join(root, 'chat', 'worktrees') })).rejects.toThrow("Carrier's own");
  await expect(client.request('newProject', { name: 'z', parent: 'relative' })).rejects.toThrow('absolute');
  expect(JSON.parse(readFileSync(projectsFile(), 'utf8')).projects).toEqual([{ path: join(parent, 'local', 'x'), origin: 'created' }]);
  expect(git.calls).toHaveLength(1);
  client.close();
});

test('newProject refuses a name whose folder exists, or that is already a project, and writes nothing', async () => {
  mkdirSync(localProject('mine'), { recursive: true });
  writeFileSync(join(localProject('mine'), 'mine.txt'), 'mine');
  writeFileSync(projectsFile(), JSON.stringify({ projects: [{ path: localProject('gone'), origin: 'added' }] }));
  const before = readFileSync(projectsFile(), 'utf8');
  const client = await connect();
  await expect(client.request('newProject', { name: 'mine' })).rejects.toThrow('mine is already a project; choose another name');
  await expect(client.request('newProject', { name: 'gone' })).rejects.toThrow('gone is already a project; choose another name');
  expect(readFileSync(projectsFile(), 'utf8')).toBe(before);
  expect(existsSync(join(localProject('mine'), '.git'))).toBe(false);
  expect(git.calls).toHaveLength(0);
  client.close();
});

test('newProject with a projects.json that does not match its schema makes nothing and leaves the file alone', async () => {
  writeFileSync(projectsFile(), '{"projects": 7}');
  const client = await connect();
  await expect(client.request('newProject', { name: 'fine' })).rejects.toThrow(/^projects\.json .*fix the file and try again$/);
  expect(existsSync(localProject('fine'))).toBe(false);
  expect(readFileSync(projectsFile(), 'utf8')).toBe('{"projects": 7}');
  client.close();
});

test('a newProject whose git init fails leaves nothing behind and no entry', async () => {
  git.failures.set('init -b main', { ok: false, code: 1, stderr: 'fatal: x' });
  const client = await connect();
  await expect(client.request('newProject', { name: 'broken' })).rejects.toThrow(/^git could not start the project broken$/);
  expect(existsSync(localProject('broken'))).toBe(false);
  expect(existsSync(projectsFile())).toBe(false);
  client.close();
});

// A clone started from Settings (the `projects` capability): it runs in the background and the folder is registered in projects.json when it ends.
const registered = () => JSON.parse(readFileSync(join(root, 'projects.json'), 'utf8')).projects;
const held = () => {
  let release!: () => void;
  git.clonePending = new Promise<void>((resolve) => (release = resolve));
  return release;
};

test('cloneProject answers at once, lists the clone with git\'s progress, and registers a project with origin cloned when it ends', async () => {
  const release = held();
  const clock = new FakeClock();
  const host = fakeProjects(git, clock);
  const dest = join(projects(), 'acme', 'app');
  expect(host.cloneProject({ repo: 'acme/app' })).toEqual({ repo: 'acme/app', folder: dest, state: 'cloning' });
  await vi.waitFor(() => expect(clones()).toHaveLength(1));
  git.emitProgress('Receiving objects: 45% (45/100)');
  expect(host.projectClones()).toEqual({ clones: [{ repo: 'acme/app', folder: dest, state: 'cloning', progress: 'Receiving objects: 45%' }] });
  expect(existsSync(join(root, 'projects.json'))).toBe(false);
  release();
  await vi.waitFor(() => expect(host.projectClones()).toEqual({ clones: [] }));
  expect(registered()).toEqual([{ path: dest, origin: 'cloned' }]);
});

test('a second clone of the same repository while one runs is shared, even for another folder', async () => {
  const release = held();
  const host = fakeProjects(git);
  const first = host.cloneProject({ repo: 'acme/app' });
  const second = host.cloneProject({ repo: 'Acme/App', parent: join(root, 'elsewhere') });
  expect(second).toEqual(first);
  await vi.waitFor(() => expect(clones()).toHaveLength(1));
  release();
  await vi.waitFor(() => expect(host.projectClones().clones).toHaveLength(0));
  expect(clones()).toHaveLength(1);
  expect(registered()).toHaveLength(1);
});

test('a clone for this once goes to <parent>/<owner>/<repo> and leaves chat.json as it was', async () => {
  const host = fakeProjects(git);
  const parent = join(root, 'work');
  expect(host.cloneProject({ repo: 'acme/app', parent }).folder).toBe(join(parent, 'acme', 'app'));
  await vi.waitFor(() => expect(host.projectClones().clones).toHaveLength(0));
  expect(clones()[0]!.args.at(-1)).toBe(join(parent, 'acme', 'app'));
  expect(registered()).toEqual([{ path: join(parent, 'acme', 'app'), origin: 'cloned' }]);
  expect(JSON.parse(readFileSync(chatJson(), 'utf8'))).toEqual({});
});

test('a clone and an add never touch engine.json: the repositories Carrier watches stay as they were', async () => {
  const engine = join(root, 'engine.json');
  const before = JSON.stringify({ repos: [{ repo: 'acme/watched' }] });
  writeFileSync(engine, before);
  const host = fakeProjects(git);
  host.cloneProject({ repo: 'acme/app' });
  const there = join(projects(), 'acme', 'existing');
  mkdirSync(join(there, '.git'), { recursive: true });
  git.repos.set(there, { head: 'main', branches: ['main'], origin: 'https://github.com/acme/existing.git' });
  host.cloneProject({ repo: 'acme/existing' });
  await vi.waitFor(() => expect(registered()).toHaveLength(2));
  expect(readFileSync(engine, 'utf8')).toBe(before);
});

test('a failed clone stays listed with its reason, never what git said, until it is dismissed, and a new one can start', async () => {
  const dest = join(projects(), 'acme', 'app');
  git.failures.set(`clone -- https://github.com/acme/app.git ${dest}`, { ok: false, code: 128, stderr: 'fatal: something with https://x:ghp_secrettoken@github.com/acme/app.git/' });
  const host = fakeProjects(git);
  host.cloneProject({ repo: 'acme/app' });
  await vi.waitFor(() => expect(host.projectClones().clones[0]?.state).toBe('failed'));
  expect(host.projectClones()).toEqual({ clones: [{ repo: 'acme/app', folder: dest, state: 'failed', error: 'git could not clone acme/app' }] });
  expect(existsSync(join(root, 'projects.json'))).toBe(false);
  expect(host.dismissClone({ repo: 'acme/app' })).toEqual({ clones: [] });
  git.failures.clear();
  host.cloneProject({ repo: 'acme/app' });
  await vi.waitFor(() => expect(registered()).toHaveLength(1));
});

test('dismissClone leaves a clone that is running', async () => {
  const release = held();
  const host = fakeProjects(git);
  host.cloneProject({ repo: 'acme/app' });
  expect(host.dismissClone({ repo: 'acme/app' }).clones).toHaveLength(1);
  release();
  await vi.waitFor(() => expect(host.projectClones().clones).toHaveLength(0));
});

test('a repository already there is fetched and registered as added, not cloned', async () => {
  const dest = join(projects(), 'acme', 'app');
  mkdirSync(join(dest, '.git'), { recursive: true });
  git.repos.set(dest, { head: 'main', branches: ['main'], origin: 'https://github.com/acme/app.git' });
  const host = fakeProjects(git);
  host.cloneProject({ repo: 'acme/app' });
  await vi.waitFor(() => expect(registered()).toEqual([{ path: dest, origin: 'added' }]));
  expect(clones()).toHaveLength(0);
});

test('a repository that is already a project is refused at once, and the entries already there are kept', async () => {
  const dest = join(projects(), 'acme', 'app');
  writeFileSync(join(root, 'projects.json'), JSON.stringify({ projects: [{ path: dest, origin: 'added', name: 'Mine' }] }));
  const host = fakeProjects(git);
  expect(() => host.cloneProject({ repo: 'acme/app' })).toThrow('acme/app is already a project');
  expect(clones()).toHaveLength(0);
  host.cloneProject({ repo: 'acme/other' });
  await vi.waitFor(() => expect(registered()).toHaveLength(2));
  expect(registered()[0]).toEqual({ path: dest, origin: 'added', name: 'Mine' });
});

test('a parent inside Carrier\'s own folders and a name that is not owner/name never reach git', () => {
  const host = fakeProjects(git);
  expect(() => host.cloneProject({ repo: 'acme/app', parent: join(root, 'chat', 'worktrees') })).toThrow("Carrier's own");
  expect(() => host.cloneProject({ repo: 'acme/app', parent: 'relative' })).toThrow('absolute');
  expect(() => host.cloneProject({ repo: '../x' })).toThrow('not a repository');
  expect(git.calls).toHaveLength(0);
  expect(host.projectClones()).toEqual({ clones: [] });
});

test('a projects.json that does not match is not written over: the clone stays and the failure says to fix the file', async () => {
  writeFileSync(join(root, 'projects.json'), '{"projects":[{"path":"/x"}]}');
  const host = fakeProjects(git);
  host.cloneProject({ repo: 'acme/app' });
  await vi.waitFor(() => expect(host.projectClones().clones[0]?.state).toBe('failed'));
  expect(host.projectClones().clones[0]!.error).toContain('fix the file');
  expect(readFileSync(join(root, 'projects.json'), 'utf8')).toBe('{"projects":[{"path":"/x"}]}');
});

test('stop aborts the running clones and removes what they made', async () => {
  held();
  const host = fakeProjects(git);
  host.cloneProject({ repo: 'acme/app' });
  await vi.waitFor(() => expect(existsSync(join(projects(), 'acme', 'app'))).toBe(true));
  expect(host.cloningCount()).toBe(1);
  await host.stop();
  expect(existsSync(join(projects(), 'acme', 'app'))).toBe(false);
  expect(host.cloningCount()).toBe(0);
});
