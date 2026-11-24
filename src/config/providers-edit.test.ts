import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { ChatRefused } from '../chat/runner.ts';
import { chatConfigPathOf, engineConfigPathOf, providersPathOf } from './places.ts';
import { addAccount, editAccount, normalizedConfigDir, removeAccount, setAccounts, setTextGenerator } from './providers-edit.ts';

let folder: string;
beforeEach(() => void (folder = mkdtempSync(join(tmpdir(), 'pe-'))));
afterEach(() => rmSync(folder, { recursive: true, force: true }));

const file = () => providersPathOf(folder);
const seed = (value: unknown) => writeFileSync(file(), typeof value === 'string' ? value : JSON.stringify(value));
const written = () => JSON.parse(readFileSync(file(), 'utf8'));
const refusal = (run: () => unknown) => {
  try {
    run();
  } catch (error) {
    if (error instanceof ChatRefused) return error;
    throw error;
  }
  throw new Error('expected a refusal');
};

// what the person wrote by hand, which no request may drop: a model, launch arguments and a text generator entry of their own
const base = {
  providers: { claude: { harness: 'claude', model: 'm', launchArgs: ['--chrome'] }, codex: { harness: 'codex' } },
  textGenerators: { mine: { kind: 'ollama', model: 'x' } },
};

test('setAccounts makes a file that is not there, with its folder, and adds each account as { harness }', () => {
  const folderThatIsNotThere = join(folder, 'new');
  expect(setAccounts([{ name: 'claude', harness: 'claude' }, { name: 'agy', harness: 'agy' }], folderThatIsNotThere)).toEqual({ saved: { providers: { claude: { harness: 'claude' }, agy: { harness: 'agy' } } } });
  expect(JSON.parse(readFileSync(providersPathOf(folderThatIsNotThere), 'utf8'))).toEqual({ providers: { claude: { harness: 'claude' }, agy: { harness: 'agy' } } });
});

test('setAccounts keeps every other key and account, and refuses a taken name without writing', () => {
  seed(base);
  setAccounts([{ name: 'agy', harness: 'agy' }], folder);
  expect(written()).toEqual({ ...base, providers: { ...base.providers, agy: { harness: 'agy' } } });
  const before = readFileSync(file(), 'utf8');
  expect(refusal(() => setAccounts([{ name: 'new', harness: 'claude' }, { name: 'codex', harness: 'codex' }], folder))).toMatchObject({ code: 'account.taken', params: { name: 'codex' }, message: 'There is already an account named codex.' });
  expect(readFileSync(file(), 'utf8')).toBe(before);
});

test.each([['[1]', 'notAnObject'], ['"text"', 'notAnObject'], ['{ not json', 'notJson']])('a providers.json that holds %s is refused and left as it was', (text, problem) => {
  seed(text);
  expect(refusal(() => setAccounts([{ name: 'agy', harness: 'agy' }], folder))).toMatchObject({ code: 'config.problem', params: { path: '(file)', problem } });
  expect(readFileSync(file(), 'utf8')).toBe(text);
});

test('a providers key that is not a map is refused and left as it was', () => {
  seed('{"providers":[]}');
  expect(refusal(() => addAccount({ name: 'work', harness: 'claude' }, folder))).toMatchObject({ code: 'config.problem', params: { path: 'providers', problem: 'notAnObject' } });
  expect(readFileSync(file(), 'utf8')).toBe('{"providers":[]}');
});

test('addAccount writes the name, the harness and the config folder taken from the home folder when it is not absolute', () => {
  seed(base);
  expect(addAccount({ name: 'claude-work', harness: 'claude', configDir: ' work ' }, folder)).toEqual({ saved: { providers: { 'claude-work': { harness: 'claude', configDir: '~/work' } } } });
  addAccount({ name: 'codex-two', harness: 'codex', configDir: '' }, folder);
  expect(written()).toEqual({ ...base, providers: { ...base.providers, 'claude-work': { harness: 'claude', configDir: '~/work' }, 'codex-two': { harness: 'codex' } } });
  expect([normalizedConfigDir('./work'), normalizedConfigDir('/srv/c'), normalizedConfigDir('~/x'), normalizedConfigDir('~'), normalizedConfigDir('')]).toEqual(['~/work', '/srv/c', '~/x', '~', '']);
});

test.each([
  [{ name: 'claude', harness: 'claude' }, 'account.taken', { name: 'claude' }],
  [{ name: 'a', harness: 'agy' }, 'account.harnessTakesOne', { harness: 'agy' }],
  [{ name: 'Bad Name', harness: 'claude' }, 'config.problem', { path: 'providers.Bad Name', problem: 'custom' }],
  [{ name: 'x', harness: 'claude', configDir: '/a\nb' }, 'config.problem', { path: 'providers.x.configDir', problem: 'invalid_format' }],
] as const)('addAccount refuses %o with code %s and writes nothing', (account, code, params) => {
  seed(base);
  const before = readFileSync(file(), 'utf8');
  expect(refusal(() => addAccount({ ...account }, folder))).toMatchObject({ code, params });
  expect(readFileSync(file(), 'utf8')).toBe(before);
});

test('editAccount sets a filled key, removes an emptied or null one, trims, and keeps every key it was not given', () => {
  seed({ ...base, providers: { ...base.providers, claude: { ...base.providers.claude, displayName: 'Old', icon: 'bolt' } } });
  const reply = editAccount('claude', { displayName: '  Work ', icon: null, label: 'w', command: '', configDir: 'cw', autoCompact: 250000, idleCompaction: false, launchArgs: ['--a'] }, folder);
  const account = { harness: 'claude', model: 'm', launchArgs: ['--a'], displayName: 'Work', label: 'w', configDir: '~/cw', autoCompact: 250000, idleCompaction: false };
  expect(reply).toEqual({ saved: { providers: { claude: account } } });
  expect(written()).toEqual({ ...base, providers: { ...base.providers, claude: account } });
  expect(readdirSync(folder).filter((name) => name.endsWith('.tmp'))).toEqual([]);
});

test.each([
  ['claude', { autoCompact: 10 }, 'providers.claude.autoCompact', 'custom'],
  ['claude', { icon: 'nope' }, 'providers.claude.icon', 'invalid_value'],
  ['codex', { idleCompaction: true }, 'providers.codex.idleCompaction', 'custom'],
  ['claude', { launchArgs: ['--model'] }, 'providers.claude.launchArgs.0', 'custom'],
  ['claude', { command: 'relative/bin' }, 'providers.claude.command', 'custom'],
] as const)('editAccount refuses %s %o with the key path and kind and writes nothing', (name, changes, path, problem) => {
  seed(base);
  const before = readFileSync(file(), 'utf8');
  const refused = refusal(() => editAccount(name, { ...changes }, folder));
  expect(refused).toMatchObject({ code: 'config.problem', params: { path, problem } });
  expect(refused.message).toContain(path);
  expect(readFileSync(file(), 'utf8')).toBe(before);
});

test('editAccount refuses an account the file does not have', () => {
  seed(base);
  expect(refusal(() => editAccount('ghost', { label: 'x' }, folder))).toMatchObject({ code: 'account.missing', params: { name: 'ghost' } });
});

test('removeAccount removes a free account and keeps everything else', () => {
  seed(base);
  mkdirSync(folder, { recursive: true });
  writeFileSync(chatConfigPathOf(folder), JSON.stringify({ agents: { me: { account: 'codex' } } }));
  expect(removeAccount('claude', folder)).toEqual({ saved: { providers: {} } });
  expect(written()).toEqual({ ...base, providers: { codex: base.providers.codex } });
});

test('removeAccount is refused with who uses the account: a role, a repo override, a failover list (also one that is off) and a chat agent', () => {
  seed({ providers: { a: { harness: 'claude' }, b: { harness: 'claude' }, c: { harness: 'claude' }, d: { harness: 'claude' }, e: { harness: 'claude' }, f: { harness: 'claude' } } });
  writeFileSync(engineConfigPathOf(folder), JSON.stringify({
    agents: { author: { provider: 'a' }, leadReviewer: { provider: 'e' } },
    repos: [{ name: 'acme/web', agents: { reviewer: { provider: 'b' } } }],
    failover: { enabled: false, roles: { author: [{ provider: 'c' }] } },
  }));
  writeFileSync(chatConfigPathOf(folder), JSON.stringify({ agents: { helper: { account: 'd' } } }));
  const before = readFileSync(file(), 'utf8');
  const uses = { a: 'Author', b: 'Reviewer in acme/web', c: 'Failover of Author', d: 'Chat agent helper', e: 'Lead reviewer' };
  for (const [name, who] of Object.entries(uses)) {
    expect(refusal(() => removeAccount(name, folder))).toMatchObject({ code: 'account.inUse', params: { name, uses: who }, message: `${name} is used by ${who}, so it stays. Point those at another account first.` });
  }
  expect(readFileSync(file(), 'utf8')).toBe(before);
  expect(removeAccount('f', folder)).toEqual({ saved: { providers: {} } });
});

test('without a chat.json the default chat agents use the accounts claude and codex; with agents of its own they do not', () => {
  seed({ providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' }, other: { harness: 'codex' } } });
  expect(refusal(() => removeAccount('claude', folder))).toMatchObject({ code: 'account.inUse', params: { uses: 'Chat agent claude' } });
  expect(refusal(() => removeAccount('codex', folder))).toMatchObject({ code: 'account.inUse', params: { uses: 'Chat agent codex' } });
  writeFileSync(chatConfigPathOf(folder), '{"agents":{"me":{"account":"other"}}}');
  expect(removeAccount('claude', folder)).toBeTruthy();
});

test.each([['{ not json'], ['[1]']])('a chat.json that is there and cannot be read (%s) stops the removal, and so does an engine.json', (text) => {
  seed({ providers: { a: { harness: 'claude' } } });
  const before = readFileSync(file(), 'utf8');
  writeFileSync(chatConfigPathOf(folder), text);
  expect(refusal(() => removeAccount('a', folder))).toMatchObject({ code: 'config.problem', params: { path: 'chat.json' } });
  rmSync(chatConfigPathOf(folder));
  writeFileSync(engineConfigPathOf(folder), text);
  writeFileSync(chatConfigPathOf(folder), '{"agents":{}}');
  expect(refusal(() => removeAccount('a', folder))).toMatchObject({ code: 'config.problem', params: { path: 'engine.json' } });
  expect(readFileSync(file(), 'utf8')).toBe(before);
});

test('removeAccount refuses an account the file does not have', () => {
  seed(base);
  expect(refusal(() => removeAccount('ghost', folder))).toMatchObject({ code: 'account.missing' });
});

test('setTextGenerator writes one entry named after its server, replaces what it wrote before, and keeps an entry written by hand', () => {
  seed(base);
  expect(setTextGenerator({ server: 'ollama', model: ' qwen3:8b ' }, folder)).toEqual({ saved: { textGenerators: { mine: base.textGenerators.mine, ollama: { kind: 'ollama', model: 'qwen3:8b' } }, textGenerator: 'ollama' } });
  setTextGenerator({ server: 'lmstudio', model: 'gemma' }, folder);
  expect(written()).toEqual({ ...base, textGenerators: { mine: base.textGenerators.mine, lmstudio: { kind: 'lmstudio', model: 'gemma' } }, textGenerator: 'lmstudio' });
  expect(setTextGenerator(null, folder)).toEqual({ saved: { textGenerators: base.textGenerators } });
  expect(written()).toEqual(base);
});

test('clearing the generator of a file that has none leaves no key, and a file with no providers key stays without it', () => {
  expect(setTextGenerator({ server: 'ollama', model: 'm' }, folder)).toMatchObject({ saved: { textGenerator: 'ollama' } });
  expect(written().providers).toBeUndefined();
  expect(setTextGenerator(null, folder)).toEqual({ saved: {} });
  expect(written()).toEqual({});
});

test.each([[{ server: 'openai', model: 'm' }, 'textGenerators.openai'], [{ server: 'ollama', model: '  ' }, 'textGenerators.ollama']])('setTextGenerator refuses %o and writes nothing', (choice, path) => {
  seed(base);
  const before = readFileSync(file(), 'utf8');
  expect(refusal(() => setTextGenerator(choice, folder))).toMatchObject({ code: 'config.problem', params: { path, problem: 'invalid_value' } });
  expect(readFileSync(file(), 'utf8')).toBe(before);
});

test('setTextGenerator refuses a textGenerators that is not a map', () => {
  seed('{"textGenerators":"x"}');
  expect(refusal(() => setTextGenerator(null, folder))).toMatchObject({ code: 'config.problem', params: { path: 'textGenerators', problem: 'notAnObject' } });
});
