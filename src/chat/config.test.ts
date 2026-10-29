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
    agents: [{ name: 'claude', harness: 'claude' }, { name: 'codex', harness: 'codex' }],
    projectsFolder: join(folder, 'chat', 'projects'),
    githubCallTimeoutSeconds: 30,
    logLevel: 'info',
  };
  expect(readChatConfig()).toEqual({ ok: true, settings: defaults });
  write('{}');
  expect(readChatConfig()).toEqual({ ok: true, settings: defaults });
});

test('a key that is set replaces its default, agents in the order written and `~/` expanded', () => {
  const agents = { zed: { harness: 'codex' }, work: { harness: 'claude', command: '/opt/claude', model: 'opus', options: { permissionMode: 'plan' } } };
  write(JSON.stringify({ agents, projectsFolder: '~/Projects', githubCallTimeoutSeconds: 5, logLevel: 'debug' }));
  expect(readChatConfig()).toEqual({
    ok: true,
    settings: { agents: [{ name: 'zed', harness: 'codex' }, { name: 'work', ...agents.work }], projectsFolder: join(homedir(), 'Projects'), githubCallTimeoutSeconds: 5, logLevel: 'debug' },
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
  expect(one({ harness: 'claude', extra: 1 }).map((e) => e.path)).toEqual(['agents.a']);
  expect(one({ harness: 'agy' }).map((e) => e.path)).toEqual(['agents.a.harness']);
  expect(one({ harness: 'claude', command: '' }).map((e) => e.path)).toEqual(['agents.a.command']);
  for (const name of ['Work', 'my agent', '1st', '-x']) expect(one({ harness: 'claude' }, name).map((e) => e.path.startsWith('agents'))).toEqual([true]);
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
