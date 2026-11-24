import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, chatPlacesOf, engineConfigPathOf, enginePlacesOf, projectsPathOf, providersPathOf } from '../../../config/places.ts';
import { validEngineFile } from '../../../config/testing.ts';
import { startControlServer, type Controls } from '../../../control/server.ts';
import { fakeEngine } from '../../../chat/fake-engine.ts';
import { startChatServer, type ChatControls } from '../../../chat/server.ts';
import { ChatRefused } from '../../../chat/runner.ts';
import { ConfigRefused } from '../../../config/engine-edit.ts';
import { configCommand } from './config.ts';

let folder: string;
let written: string[];
let closers: (() => void)[];
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'cc-')); // short: a socket path holds 103 bytes on macOS
  written = [];
  closers = [];
  vi.spyOn(process.stdout, 'write').mockImplementation((text) => (written.push(String(text)), true));
});
afterEach(() => {
  for (const close of closers) close();
  rmSync(folder, { recursive: true, force: true });
  vi.restoreAllMocks();
});

const file = () => chatConfigPathOf(folder);
const run = (stdin: string) => configCommand(folder, Readable.from([stdin]));
const printed = () => {
  expect(written).toHaveLength(1);
  expect(written[0]!.endsWith('\n') && written[0]!.indexOf('\n') === written[0]!.length - 1).toBe(true); // one line
  return JSON.parse(written[0]!);
};
const request = (changes: object) => JSON.stringify({ cmd: 'editChatSettings', changes });

test('with no host, a request on standard input writes the file and prints the reply as one line, exit 0', async () => {
  mkdirSync(folder, { recursive: true });
  writeFileSync(file(), '{ "projectsFolder": "/mine", "deleteAfterDays": 60 }');
  expect(await run(request({ archiveAfterDays: 7, deleteAfterDays: null }))).toBe(0);
  expect(printed()).toEqual({ ok: true, data: { saved: { archiveAfterDays: 7 } } });
  expect(JSON.parse(readFileSync(file(), 'utf8'))).toEqual({ projectsFolder: '/mine', archiveAfterDays: 7 });
});

test('a refused change prints the refusal, leaves the file as it was and exits 1', async () => {
  const text = '{"archiveAfterDays":20}';
  writeFileSync(file(), text);
  expect(await run(request({ idleCloseMinutes: 15 }))).toBe(1);
  expect(printed()).toMatchObject({ ok: false, code: 'config.problem', params: { path: 'idleCloseMinutes', problem: 'invalid_union' } });
  expect(readFileSync(file(), 'utf8')).toBe(text);
});

test.each([['not json'], [''], ['{"cmd":"editChatSettings"}'], ['{"cmd":"nope","changes":{}}'], ['{"id":1,"cmd":"editChatSettings","changes":{}}']])('standard input %j exits 2 and writes nothing', async (stdin) => {
  expect(await run(stdin)).toBe(2);
  expect(printed()).toMatchObject({ ok: false, code: expect.stringMatching(/^request\./) });
  expect(() => readFileSync(file())).toThrow();
});

async function owner(controls: Partial<ChatControls>) {
  const stateDir = chatPlacesOf(folder).state;
  mkdirSync(stateDir, { recursive: true });
  const server = await startChatServer({ stateDir, startedAt: 1, controls: controls as ChatControls, stop: async () => {}, clients: { joined() {}, left() {} } });
  closers.push(server.close);
}

test('with an owner answering on the socket, it forwards the request, prints the owner\'s reply and writes nothing', async () => {
  const seen: unknown[] = [];
  await owner({ editChatSettings: ({ changes }) => (seen.push(changes), { saved: { archiveAfterDays: 7, by: 'owner' } }) });
  expect(await run(request({ archiveAfterDays: 7 }))).toBe(0);
  expect(seen).toEqual([{ archiveAfterDays: 7 }]);
  expect(printed()).toEqual({ ok: true, data: { saved: { archiveAfterDays: 7, by: 'owner' } } });
  expect(() => readFileSync(file())).toThrow();
});

test('the owner\'s refusal is printed with its code and params, exit 1', async () => {
  await owner({ editChatSettings: () => { throw new ChatRefused('config.problem', 'deleteAfterDays: must be greater than archiveAfterDays', { path: 'deleteAfterDays', problem: 'custom' }); } });
  expect(await run(request({ deleteAfterDays: 3 }))).toBe(1);
  expect(printed()).toEqual({ ok: false, error: 'deleteAfterDays: must be greater than archiveAfterDays', code: 'config.problem', params: { path: 'deleteAfterDays', problem: 'custom' } });
});

// `engine.json`: the same command, the engine as the owner.
const engineFile = () => engineConfigPathOf(folder);
const engineRequest = (cmd: string, fields: object) => JSON.stringify({ cmd, ...fields });
const engineOwner = async (controls: Partial<Controls>) => {
  const stateDir = enginePlacesOf(folder).state;
  mkdirSync(stateDir, { recursive: true });
  closers.push((await startControlServer({ stateDir, snapshot: () => ({}), startedAt: 1, controls: controls as Controls, stop: async () => {} })).close);
};

test('with no engine, setWatchedRepos writes engine.json with the same code, prints one line with engine notRunning and exits 0', async () => {
  writeFileSync(engineFile(), JSON.stringify(validEngineFile));
  expect(await run(engineRequest('setWatchedRepos', { repos: ['acme/web', 'new/one'] }))).toBe(0);
  expect(printed()).toEqual({ ok: true, data: { saved: { repos: [validEngineFile.repos[1], { name: 'new/one' }] }, engine: 'notRunning' } });
  expect(JSON.parse(readFileSync(engineFile(), 'utf8'))).toEqual({ ...validEngineFile, repos: [validEngineFile.repos[1], { name: 'new/one' }] });
});

test('with no engine, editBehavior writes the values, a default one taken out, and says notRunning', async () => {
  writeFileSync(engineFile(), JSON.stringify(validEngineFile));
  expect(await run(engineRequest('editBehavior', { changes: { logLevel: 'debug', limits: { maxReviews: 5 } } }))).toBe(0);
  expect(printed()).toEqual({ ok: true, data: { saved: { logLevel: 'debug' }, engine: 'notRunning' } });
  expect(JSON.parse(readFileSync(engineFile(), 'utf8'))).toEqual({ ...validEngineFile, logLevel: 'debug', limits: { maxLeadRounds: 2 } });
});

test.each([
  [{ cmd: 'editRole', role: 'author', changes: { model: 'm2' } }, (file: any) => file.agents.author.model, 'm2'],
  [{ cmd: 'editRepoRole', repo: 'acme/web', role: 'reviewer', fields: { model: 'a' } }, (file: any) => file.repos[1].agents.reviewer, { model: 'a' }],
  [{ cmd: 'editPersona', role: 'author', name: 'Ada', prompt: null }, (file: any) => file.agents.author.persona, { name: 'Ada' }],
  [{ cmd: 'editFailover', role: 'author', first: { provider: 'codex' }, second: null }, (file: any) => file.failover.roles.author, [{ provider: 'codex' }]],
  [{ cmd: 'setLeadReviewer', draft: null }, (file: any) => file.agents.leadReviewer, undefined],
  [{ cmd: 'setOrchestratorProfile', name: null }, (file: any) => file.orchestratorProfile, undefined],
])('with no engine, %o writes engine.json with the same code and says notRunning', async (request, read, expected) => {
  writeFileSync(engineFile(), JSON.stringify(validEngineFile));
  expect(await run(JSON.stringify(request))).toBe(0);
  expect(printed()).toMatchObject({ ok: true, data: { engine: 'notRunning' } });
  expect(read(JSON.parse(readFileSync(engineFile(), 'utf8')))).toEqual(expected);
});

test('a refused role change prints the refusal with its code and params and leaves the file as it was', async () => {
  const text = JSON.stringify(validEngineFile);
  writeFileSync(engineFile(), text);
  expect(await run(engineRequest('editRole', { role: 'author', changes: { provider: 'nope' } }))).toBe(1);
  expect(printed()).toEqual({ ok: false, error: 'Provider “nope” is not an account of providers.json. Pick another one.', code: 'config.problem', params: { path: 'agents.author.provider', problem: 'notAnAccount' } });
  expect(readFileSync(engineFile(), 'utf8')).toBe(text);
});

test('with the engine answering, a role request is forwarded and nothing is written here', async () => {
  const seen: unknown[] = [];
  await engineOwner({ editEngineFile: (command) => (seen.push(command.cmd), { saved: {}, engine: 'applied' }) });
  expect(await run(engineRequest('setOrchestratorProfile', { name: 'x' }))).toBe(0);
  expect(seen).toEqual(['setOrchestratorProfile']);
  expect(printed()).toEqual({ ok: true, data: { saved: {}, engine: 'applied' } });
  expect(() => readFileSync(engineFile())).toThrow();
});

test('a refused engine.json change prints the refusal with its code and params, leaves the file as it was and exits 1', async () => {
  const text = JSON.stringify(validEngineFile);
  writeFileSync(engineFile(), text);
  expect(await run(engineRequest('setWatchedRepos', { repos: ['a/b', 'nope'] }))).toBe(1);
  expect(printed()).toEqual({ ok: false, error: 'nope must be owner/name', code: 'config.problem', params: { path: 'repos[1]', problem: 'notARepo' } });
  expect(readFileSync(engineFile(), 'utf8')).toBe(text);
});

test.each([['{"cmd":"setWatchedRepos"}'], ['{"cmd":"editBehavior","changes":{"nope":1}}'], ['{"id":1,"cmd":"setWatchedRepos","repos":[]}']])('standard input %j exits 2 and writes nothing', async (stdin) => {
  writeFileSync(engineFile(), JSON.stringify(validEngineFile));
  expect(await run(stdin)).toBe(2);
  expect(printed()).toMatchObject({ ok: false, code: 'request.invalid' });
  expect(JSON.parse(readFileSync(engineFile(), 'utf8'))).toEqual(validEngineFile);
});

test('with the engine answering on its socket, it forwards the request, prints the engine\'s reply (with what the engine did) and writes nothing', async () => {
  const seen: unknown[] = [];
  await engineOwner({ setWatchedRepos: (repos) => (seen.push(repos), { saved: { repos: [{ name: 'a/b' }] }, engine: 'applied' }) });
  expect(await run(engineRequest('setWatchedRepos', { repos: ['a/b'] }))).toBe(0);
  expect(seen).toEqual([['a/b']]);
  expect(printed()).toEqual({ ok: true, data: { saved: { repos: [{ name: 'a/b' }] }, engine: 'applied' } });
  expect(() => readFileSync(engineFile())).toThrow();
});

test("the engine's refusal of a value is printed with its code and params, exit 1", async () => {
  await engineOwner({ editBehavior: () => { throw new ConfigRefused('config.problem', 'Must be 1 or more', { path: 'limits.maxReviews', problem: 'tooSmall' }); } });
  expect(await run(engineRequest('editBehavior', { changes: { limits: { maxReviews: 0 } } }))).toBe(1);
  expect(printed()).toEqual({ ok: false, error: 'Must be 1 or more', code: 'config.problem', params: { path: 'limits.maxReviews', problem: 'tooSmall' } });
});

// providers.json: the five requests, with no host answering, write the file with the same codes (the table of src/chat/server.test.ts, through standard input)
const accountsFile = () => providersPathOf(folder);
const seedAccounts = (value: unknown) => (mkdirSync(folder, { recursive: true }), writeFileSync(accountsFile(), JSON.stringify(value)));
const handWritten = { providers: { claude: { harness: 'claude', model: 'mine' }, codex: { harness: 'codex' } }, textGenerators: { hand: { kind: 'ollama', model: 'x' } } };

test.each([
  [{ cmd: 'setAccounts', accounts: [{ name: 'agy', harness: 'agy' }] }, { providers: { ...handWritten.providers, agy: { harness: 'agy' } }, textGenerators: handWritten.textGenerators }],
  [{ cmd: 'addAccount', account: { name: 'work', harness: 'claude', configDir: 'w' } }, { providers: { ...handWritten.providers, work: { harness: 'claude', configDir: '~/w' } }, textGenerators: handWritten.textGenerators }],
  [{ cmd: 'editAccount', name: 'claude', changes: { displayName: 'Mine' } }, { providers: { ...handWritten.providers, claude: { harness: 'claude', model: 'mine', displayName: 'Mine' } }, textGenerators: handWritten.textGenerators }],
  [{ cmd: 'removeAccount', name: 'claude' }, { providers: { codex: handWritten.providers.codex }, textGenerators: handWritten.textGenerators }],
  [{ cmd: 'setTextGenerator', choice: { server: 'lmstudio', model: 'gemma' } }, { ...handWritten, textGenerators: { hand: handWritten.textGenerators.hand, lmstudio: { kind: 'lmstudio', model: 'gemma' } }, textGenerator: 'lmstudio' }],
])('with no host and no engine, %o writes providers.json and prints the saved part with engine notRunning, exit 0', async (request, after) => {
  seedAccounts(handWritten);
  writeFileSync(chatConfigPathOf(folder), '{"agents":{}}');
  expect(await run(JSON.stringify(request))).toBe(0);
  expect(printed()).toMatchObject({ ok: true, data: { engine: 'notRunning' } });
  expect(JSON.parse(readFileSync(accountsFile(), 'utf8'))).toEqual(after);
});

test.each([
  [{ cmd: 'setAccounts', accounts: [{ name: 'codex', harness: 'codex' }] }, 'account.taken'],
  [{ cmd: 'addAccount', account: { name: 'x', harness: 'agy' } }, 'account.harnessTakesOne'],
  [{ cmd: 'editAccount', name: 'ghost', changes: {} }, 'account.missing'],
  [{ cmd: 'editAccount', name: 'claude', changes: { autoCompact: 3 } }, 'config.problem'],
  [{ cmd: 'removeAccount', name: 'ghost' }, 'account.missing'],
  [{ cmd: 'removeAccount', name: 'codex' }, 'account.inUse'],
  [{ cmd: 'setTextGenerator', choice: { server: 'x', model: 'm' } }, 'config.problem'],
])('with no host, %o is refused with %s, exit 1, and the file is left as it was', async (request, code) => {
  seedAccounts(handWritten);
  const text = readFileSync(accountsFile(), 'utf8');
  expect(await run(JSON.stringify(request))).toBe(1);
  expect(printed()).toMatchObject({ ok: false, code });
  expect(readFileSync(accountsFile(), 'utf8')).toBe(text);
});

test.each([['{"cmd":"setAccounts"}'], ['{"cmd":"addAccount","account":{"name":"a"}}'], ['{"cmd":"removeAccount","name":"a","id":3}'], ['{"cmd":"toString"}'], ['{"cmd":"__proto__"}']])('standard input %j exits 2', async (stdin) => {
  expect(await run(stdin)).toBe(2);
  expect(printed()).toMatchObject({ ok: false, code: 'request.invalid' });
});

test('when this process writes providers.json it asks the engine, and says applied or refused with the engine\'s reason', async () => {
  seedAccounts(handWritten);
  const applied = await fakeEngine(folder, 'applied');
  closers.push(applied.close);
  expect(await run(JSON.stringify({ cmd: 'addAccount', account: { name: 'one', harness: 'codex' } }))).toBe(0);
  expect(printed()).toMatchObject({ ok: true, data: { engine: 'applied' } });
  expect(applied.reloads).toBe(1);
  applied.close();
  rmSync(join(folder, 'engine'), { recursive: true });
  written.length = 0;
  const reason = { error: 'agents.author.provider: bad', code: 'config.problem', params: { path: 'agents.author.provider', problem: 'providerNotDeclared' } };
  closers.push((await fakeEngine(folder, reason)).close);
  expect(await run(JSON.stringify({ cmd: 'removeAccount', name: 'one' }))).toBe(0);
  expect(printed()).toEqual({ ok: true, data: { saved: { providers: {} }, engine: 'refused', engineReason: reason } });
});

test('with an owner answering, a providers request is forwarded as it is and this process writes nothing', async () => {
  const seen: unknown[] = [];
  await owner({ addAccount: (args) => (seen.push(args), Promise.resolve({ saved: { providers: {} }, engine: 'applied' })) });
  expect(await run(JSON.stringify({ cmd: 'addAccount', account: { name: 'one', harness: 'codex' } }))).toBe(0);
  expect(seen).toEqual([{ account: { name: 'one', harness: 'codex' } }]);
  expect(printed()).toEqual({ ok: true, data: { saved: { providers: {} }, engine: 'applied' } });
  expect(() => readFileSync(accountsFile())).toThrow();
});

// Every request of the `config` capability for a project, with no host answering: the file after it, from a scratch Carrier folder.
const projectsFile = () => projectsPathOf(folder);
const alpha = { path: '/w/alpha', name: 'alpha', origin: 'cloned', tags: ['a'], icon: { color: 'blue', image: 'a.png' }, defaults: { agent: 'claude', model: 'opus' }, actions: [{ name: 'Setup', command: 'make', when: 'afterClone' }] };
const beta = { path: '/w/beta', origin: 'added' };
const seedProjects = () => (mkdirSync(folder, { recursive: true }), writeFileSync(projectsFile(), JSON.stringify({ projects: [alpha, beta] })));
const after = (change: (entries: Record<string, unknown>[]) => unknown) => change(JSON.parse(readFileSync(projectsFile(), 'utf8')).projects);

type Entries = Record<string, unknown>[];
test.each([
  ['addProject', { folder: '/w/gamma' }, { added: true, saved: { path: '/w/gamma', name: 'gamma', origin: 'added' } }, (p: Entries) => p[2]],
  ['removeProject', { path: '/w/beta' }, { removed: '/w/beta' }, (p: Entries) => p.map((entry) => entry.path)],
  ['editProject', { path: '/w/alpha', key: 'name', value: 'Alpha' }, { saved: { ...alpha, name: 'Alpha' } }, (p: Entries) => p[0]],
  ['moveProject', { path: '/w/alpha', folder: '/w/moved' }, { saved: { ...alpha, path: '/w/moved' } }, (p: Entries) => p[0]],
  ['editProjectIcon', { path: '/w/alpha', changes: { color: null } }, { saved: { ...alpha, icon: { image: 'a.png' } } }, (p: Entries) => p[0]],
  ['editProjectDefaults', { path: '/w/alpha', changes: { model: null, workIn: 'worktree' } }, { saved: { ...alpha, defaults: { agent: 'claude', workIn: 'worktree' } } }, (p: Entries) => p[0]],
  ['editProjectTags', { path: '/w/alpha', add: ['B'], remove: ['a'] }, { saved: { ...alpha, tags: ['b'] } }, (p: Entries) => p[0]],
  ['setProjectActions', { path: '/w/alpha', actions: [{ name: 'Test', command: 'pnpm test', when: 'newWorktree', onFail: 'stop' }] }, { saved: { ...alpha, actions: [{ name: 'Test', command: 'pnpm test', when: 'newWorktree', onFail: 'stop' }] } }, (p: Entries) => p[0]],
])('with no host, %s writes projects.json and prints the reply the socket would give, exit 0', async (cmd, fields, data, seen) => {
  seedProjects();
  expect(await run(JSON.stringify({ cmd, ...fields }))).toBe(0);
  expect(printed()).toEqual({ ok: true, data });
  // what the file holds after it: the entry the reply names, or the paths left after a removal
  expect(after(seen)).toEqual('saved' in data ? data.saved : ['/w/alpha']);
});

test('with no host, setProjectsFolder writes chat.json and a refused folder leaves it as it was', async () => {
  mkdirSync(folder, { recursive: true });
  writeFileSync(file(), '{ "archiveAfterDays": 20 }');
  expect(await run(JSON.stringify({ cmd: 'setProjectsFolder', folder: '/w/all' }))).toBe(0);
  expect(printed()).toEqual({ ok: true, data: { saved: { projectsFolder: '/w/all' } } });
  expect(JSON.parse(readFileSync(file(), 'utf8'))).toEqual({ archiveAfterDays: 20, projectsFolder: '/w/all' });
  written.length = 0;
  expect(await run(JSON.stringify({ cmd: 'setProjectsFolder', folder: join(folder, 'engine', 'x') }))).toBe(1);
  expect(printed()).toMatchObject({ ok: false, code: 'folder.insideCarrier', params: { folder: 'engine' } });
  expect(JSON.parse(readFileSync(file(), 'utf8')).projectsFolder).toBe('/w/all');
});

test('a refused change of a project prints its code and the key path and kind, exit 1, and leaves projects.json as it was', async () => {
  seedProjects();
  const text = readFileSync(projectsFile(), 'utf8');
  expect(await run(JSON.stringify({ cmd: 'editProject', path: '/w/alpha', key: 'name', value: true }))).toBe(1);
  expect(printed()).toMatchObject({ ok: false, code: 'config.problem', params: { path: 'projects.0.name', problem: 'invalid_type' } });
  written.length = 0;
  expect(await run(JSON.stringify({ cmd: 'removeProject', path: '/w/none' }))).toBe(1);
  expect(printed()).toMatchObject({ ok: false, code: 'project.missing', params: { path: '/w/none' } });
  expect(readFileSync(projectsFile(), 'utf8')).toBe(text);
});

test('a project request the schema refuses exits 2 and writes nothing', async () => {
  seedProjects();
  const text = readFileSync(projectsFile(), 'utf8');
  expect(await run(JSON.stringify({ cmd: 'editProject', path: '/w/alpha', key: 'origin', value: 'created' }))).toBe(2);
  expect(printed()).toMatchObject({ ok: false, code: 'request.invalid' });
  expect(readFileSync(projectsFile(), 'utf8')).toBe(text);
});

test('with an owner answering, a project request is forwarded as it is and nothing is written here', async () => {
  seedProjects();
  const text = readFileSync(projectsFile(), 'utf8');
  const seen: unknown[] = [];
  await owner({ moveProject: (args) => (seen.push(args), { saved: { by: 'owner' } }) });
  expect(await run(JSON.stringify({ cmd: 'moveProject', path: '/w/alpha', folder: '/w/moved' }))).toBe(0);
  expect(seen).toEqual([{ path: '/w/alpha', folder: '/w/moved' }]);
  expect(printed()).toEqual({ ok: true, data: { saved: { by: 'owner' } } });
  expect(readFileSync(projectsFile(), 'utf8')).toBe(text);
});
