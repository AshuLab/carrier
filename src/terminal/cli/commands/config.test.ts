import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, chatPlacesOf, projectsPathOf } from '../../../config/places.ts';
import { startChatServer, type ChatControls } from '../../../chat/server.ts';
import { ChatRefused } from '../../../chat/runner.ts';
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
