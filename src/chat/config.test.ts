import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { chatConfigPathOf, chatConfigProblem, chatDirOf, chatSocketOf, loadChatConfig, readChatConfig } from './config.ts';

let folder: string;
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 'cfg-'));
  vi.stubEnv('CARRIER_HOME', folder);
});
afterEach(() => {
  rmSync(folder, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

const errorsOf = (user: unknown) => {
  const result = loadChatConfig(user, folder);
  if (result.ok) throw new Error('expected errors');
  return result.errors;
};
const write = (text: string) => {
  mkdirSync(chatDirOf(), { recursive: true });
  writeFileSync(chatConfigPathOf(), text);
};

test('the chat lives in <folder>/chat, and the socket in its state folder', () => {
  expect(chatDirOf()).toBe(join(folder, 'chat'));
  expect(chatSocketOf()).toBe(join(folder, 'chat', 'state', 'chat.sock'));
  expect(chatConfigPathOf()).toBe(join(folder, 'chat', 'chat.json'));
});

test('without the file, or with an empty one, every setting has its default', () => {
  const defaults = {
    agents: [{ name: 'claude', account: 'claude' }, { name: 'codex', account: 'codex' }],
    projectsFolder: join(folder, 'chat', 'projects'),
    githubCallTimeoutSeconds: 30,
    logLevel: 'info',
    archiveAfterDays: 15,
    deleteAfterDays: 30,
  };
  expect(readChatConfig()).toEqual({ ok: true, settings: defaults });
  write('{}');
  expect(readChatConfig()).toEqual({ ok: true, settings: defaults });
});

test('a key that is set replaces its default, agents in the order written and `~/` expanded', () => {
  const agents = { zed: { account: 'codex' }, work: { account: 'claude-work', model: 'opus', options: { permissionMode: 'plan' } } };
  write(JSON.stringify({ agents, projectsFolder: '~/Projects', githubCallTimeoutSeconds: 5, logLevel: 'debug', archiveAfterDays: 7, deleteAfterDays: 'never' }));
  expect(readChatConfig()).toEqual({
    ok: true,
    settings: { agents: [{ name: 'zed', account: 'codex' }, { name: 'work', ...agents.work }], projectsFolder: join(homedir(), 'Projects'), githubCallTimeoutSeconds: 5, logLevel: 'debug', archiveAfterDays: 7, deleteAfterDays: 'never' },
  });
  expect(loadChatConfig({ agents: {} }, folder)).toMatchObject({ ok: true, settings: { agents: [] } }); // none, not the defaults
});

test('an unknown key, a wrong type or a bad value is an error naming the key', () => {
  expect(errorsOf({ root: '/x' }).map((e) => e.path)).toEqual(['(root)']);
  expect(errorsOf({ githubCallTimeoutSeconds: '30' }).map((e) => e.path)).toEqual(['githubCallTimeoutSeconds']);
  for (const githubCallTimeoutSeconds of [0, -1, 1.5]) expect(errorsOf({ githubCallTimeoutSeconds }).map((e) => e.path)).toEqual(['githubCallTimeoutSeconds']);
  expect(errorsOf({ logLevel: 'loud' }).map((e) => e.path)).toEqual(['logLevel']);
  for (const projectsFolder of ['', 'relative/dir', './x', '~other/dir', 5]) expect(errorsOf({ projectsFolder }).map((e) => e.path)).toEqual(['projectsFolder']);
  expect(errorsOf({ projectsFolder: 'x' })[0]!.message).toContain('absolute');
  const one = (agent: object, name = 'a') => errorsOf({ agents: { [name]: agent } });
  expect(one({ account: 'claude', extra: 1 }).map((e) => e.path)).toEqual(['agents.a']);
  expect(one({ account: '' }).map((e) => e.path)).toEqual(['agents.a.account']);
  expect(one({}).map((e) => e.path)).toEqual(['agents.a.account']);
  for (const name of ['Work', 'my agent', '1st', '-x']) expect(one({ account: 'claude' }, name).map((e) => e.path.startsWith('agents'))).toEqual([true]);
});

test('an agent that still has harness or command is refused naming the key and the account that replaces it', () => {
  const errors = errorsOf({ agents: { a: { account: 'claude', harness: 'claude', command: '/opt/claude' } } });
  expect(errors.map((e) => e.path)).toEqual(['agents.a.harness', 'agents.a.command']);
  for (const e of errors) expect(e.message).toContain('providers.json');
  expect(loadChatConfig({ agents: { work: { account: 'claude-work', model: 'opus' } } }, folder)).toEqual({ ok: true, settings: expect.objectContaining({ agents: [{ name: 'work', account: 'claude-work', model: 'opus' }] }) });
});

test('the session ages default to 15 and 30, and one key alone takes the other\'s default', () => {
  expect(loadChatConfig({ archiveAfterDays: 5 }, folder)).toMatchObject({ ok: true, settings: { archiveAfterDays: 5, deleteAfterDays: 30 } });
  expect(loadChatConfig({ deleteAfterDays: 60 }, folder)).toMatchObject({ ok: true, settings: { archiveAfterDays: 15, deleteAfterDays: 60 } });
  expect(loadChatConfig({ archiveAfterDays: 'never', deleteAfterDays: 'never' }, folder)).toMatchObject({ ok: true, settings: { archiveAfterDays: 'never', deleteAfterDays: 'never' } });
});

test('a session age that is not a whole number of days or "never" is an error naming its key', () => {
  for (const key of ['archiveAfterDays', 'deleteAfterDays']) {
    for (const value of [0, -1, 1.5, '15', null, '', 'Never']) expect(errorsOf({ [key]: value }).map((e) => e.path)).toEqual([key]);
  }
});

test('the delete age must be greater than the archive age when both are numbers, reported on deleteAfterDays', () => {
  expect(errorsOf({ archiveAfterDays: 30, deleteAfterDays: 30 }).map((e) => e.path)).toEqual(['deleteAfterDays']);
  expect(errorsOf({ archiveAfterDays: 15, deleteAfterDays: 10 }).map((e) => e.path)).toEqual(['deleteAfterDays']);
  expect(errorsOf({ archiveAfterDays: 40 }).map((e) => e.path)).toEqual(['deleteAfterDays']); // against the default 30
  expect(loadChatConfig({ archiveAfterDays: 'never', deleteAfterDays: 5 }, folder)).toMatchObject({ ok: true });
  expect(loadChatConfig({ archiveAfterDays: 5, deleteAfterDays: 'never' }, folder)).toMatchObject({ ok: true });
});

test('a file that is not JSON is an error that says so, and the message names the file and the key', () => {
  write('{ nope');
  const result = readChatConfig();
  expect(result).toMatchObject({ ok: false, errors: [{ path: '(file)', message: expect.stringContaining('not valid JSON') }] });
  write('{"githubCallTimeoutSeconds": 0}');
  const bad = readChatConfig();
  if (bad.ok) throw new Error('expected errors');
  expect(chatConfigProblem(folder, bad.errors)).toContain(`${join(folder, 'chat', 'chat.json')}:\n  githubCallTimeoutSeconds:`);
});
