import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { loadProviders } from './providers.ts';

const errorsOf = (providers: unknown) => {
  const result = loadProviders({ providers });
  if (result.ok) throw new Error('expected invalid providers');
  return result.errors;
};
const pathsOf = (providers: unknown) => errorsOf(providers).map((e) => e.path);

describe('providers.json', () => {
  test('no file is no accounts', () => {
    expect(loadProviders({})).toEqual({ ok: true, providers: {} });
  });

  test('two accounts load with every key of this slice', () => {
    const result = loadProviders({ providers: { claude: { harness: 'claude' }, work: { harness: 'claude', configDir: '~/.claude-work', model: 'opus', displayName: '  Work  ' }, local: { harness: 'codex', provider: 'lmstudio' } } });
    expect(result).toEqual({ ok: true, providers: { claude: { harness: 'claude' }, work: { harness: 'claude', configDir: join(homedir(), '.claude-work'), model: 'opus', displayName: 'Work' }, local: { harness: 'codex', provider: 'lmstudio' } } });
  });

  test('a key outside the file is refused, and so is a key the account does not have', () => {
    expect(loadProviders({ accounts: {} })).toMatchObject({ ok: false, errors: [{ path: '(root)', message: expect.stringContaining('accounts') }] });
    expect(errorsOf({ claude: { harness: 'claude', token: 'x' } })).toEqual([{ path: 'providers.claude', message: expect.stringContaining('token') }]);
  });

  test('a wrong type names its key', () => {
    expect(pathsOf({ claude: { harness: 'claude', model: 3 } })).toEqual(['providers.claude.model']);
    expect(pathsOf({ claude: { harness: 'gpt' } })).toEqual(['providers.claude.harness']);
    expect(pathsOf({ claude: 'claude' })).toEqual(['providers.claude']);
  });

  test('a name is a lowercase word of up to 40 characters', () => {
    for (const name of ['a', 'claude-ashu', 'x1-2', 'a'.repeat(40)]) expect(loadProviders({ providers: { [name]: { harness: 'codex' } } }).ok).toBe(true);
    for (const name of ['Claude', '1claude', '-claude', 'claude_work', 'claude work', '', 'a'.repeat(41)]) {
      const errors = errorsOf({ [name]: { harness: 'codex' } });
      expect(errors.map((e) => e.path)).toEqual([`providers.${name}`]);
      expect(errors[0]!.message).toContain('lowercase word');
    }
  });

  test('displayName is one trimmed line of 1 to 60 characters', () => {
    expect(loadProviders({ providers: { a: { harness: 'claude', displayName: 'b'.repeat(60) } } }).ok).toBe(true);
    for (const displayName of ['', '   ', 'two\nlines', 'two\r\nlines', 'b'.repeat(61), 7]) expect(pathsOf({ a: { harness: 'claude', displayName } })).toEqual(['providers.a.displayName']);
  });

  test('`provider` is optional and only lmstudio or ollama, and agy cannot use one', () => {
    expect(pathsOf({ a: { harness: 'codex', provider: 'vllm' } })).toEqual(['providers.a.provider']);
    expect(errorsOf({ a: { harness: 'agy', provider: 'ollama' } })).toEqual([{ path: 'providers.a.provider', message: 'providers.a: agy cannot use the provider "ollama"' }]);
  });

  test('`configDir` is expanded from ~ and must then be absolute; an empty one is refused', () => {
    expect(loadProviders({ providers: { a: { harness: 'codex', configDir: '/srv/codex' } } })).toMatchObject({ ok: true, providers: { a: { configDir: '/srv/codex' } } });
    for (const configDir of ['', 'relative/dir', '.claude', '~other/dir']) expect(pathsOf({ a: { harness: 'claude', configDir } })).toEqual(['providers.a.configDir']);
  });

  test('an agy account cannot have a `configDir`', () => {
    expect(errorsOf({ a: { harness: 'agy', configDir: '/srv/agy' } })).toEqual([{ path: 'providers.a.configDir', message: expect.stringContaining('agy') }]);
  });
});
