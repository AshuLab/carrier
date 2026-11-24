import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, chatPlacesOf } from '../../../config/places.ts';
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
