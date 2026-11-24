import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, chatPlacesOf, providersPathOf } from '../../../config/places.ts';
import { fakeEngine } from '../../../chat/fake-engine.ts';
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
