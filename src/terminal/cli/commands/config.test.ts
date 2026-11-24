import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, chatPlacesOf, engineConfigPathOf, enginePlacesOf } from '../../../config/places.ts';
import { validEngineFile } from '../../../config/testing.ts';
import { startControlServer, type Controls } from '../../../control/server.ts';
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
