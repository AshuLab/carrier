import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { loadProviders, offeredNames } from './providers.ts';

const errorsOf = (providers: unknown) => {
  const result = loadProviders({ providers });
  if (result.ok) throw new Error('expected invalid providers');
  return result.errors;
};
const pathsOf = (providers: unknown) => errorsOf(providers).map((e) => e.path);

describe('providers.json', () => {
  test('no file is one account per harness, named after it, with no folder and not enabled', () => {
    expect(loadProviders({})).toEqual({ ok: true, providers: { claude: { harness: 'claude', enabled: false }, codex: { harness: 'codex', enabled: false }, agy: { harness: 'agy', enabled: false } } });
    expect(loadProviders({ providers: {} })).toEqual({ ok: true, providers: {} });
  });

  test('enabled is a boolean, and an account without it is offered', () => {
    expect(pathsOf({ claude: { harness: 'claude', enabled: 'no' } })).toEqual(['providers.claude.enabled']);
    const result = loadProviders({ providers: { a: { harness: 'claude' }, b: { harness: 'codex', enabled: true }, c: { harness: 'codex', enabled: false } } });
    expect(result.ok && offeredNames(result.providers)).toEqual(['a', 'b']);
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

  test('the runtime keys load as written, `command` expanded from ~', () => {
    const result = loadProviders({ providers: { a: { harness: 'claude', command: '~/bin/claude', autoCompact: 'auto', idleCompaction: false, launchArgs: ['--chrome'] }, b: { harness: 'codex', autoCompact: 1500000, launchArgs: ['-c', 'model_reasoning_effort=high'] } } });
    expect(result).toEqual({ ok: true, providers: { a: { harness: 'claude', command: join(homedir(), 'bin/claude'), autoCompact: 'auto', idleCompaction: false, launchArgs: ['--chrome'] }, b: { harness: 'codex', autoCompact: 1500000, launchArgs: ['-c', 'model_reasoning_effort=high'] } } });
  });

  test('a wrong runtime key is refused naming it', () => {
    // A union that fails reports its key once per branch.
    const claude = (extra: object) => [...new Set(pathsOf({ a: { harness: 'claude', ...extra } }))];
    for (const autoCompact of ['300000', 0, -1, 1.5, 99999, 1000001]) expect(claude({ autoCompact })).toEqual(['providers.a.autoCompact']);
    expect(pathsOf({ a: { harness: 'codex', autoCompact: 'auto' } })).toEqual(['providers.a.autoCompact']);
    expect(claude({ launchArgs: '--chrome' })).toEqual(['providers.a.launchArgs']);
    expect(claude({ launchArgs: ['--chrome', ''] })).toEqual(['providers.a.launchArgs.1']);
    expect(claude({ command: '' })).toEqual(['providers.a.command']);
    expect(claude({ command: 'claude' })).toEqual(['providers.a.command']);
    expect(claude({ idleCompaction: 'false' })).toEqual(['providers.a.idleCompaction']);
    expect(pathsOf({ a: { harness: 'codex', idleCompaction: false } })).toEqual(['providers.a.idleCompaction']);
    expect(pathsOf({ a: { harness: 'agy', idleCompaction: false } })).toEqual(['providers.a.idleCompaction']);
    expect(pathsOf({ a: { harness: 'agy', autoCompact: 'auto' } })).toEqual(['providers.a.autoCompact']);
  });

  test('every form of a flag Carrier sets is refused, one that is not on the list passes', () => {
    const refused = (harness: string, launchArgs: string[]) => errorsOf({ a: { harness, launchArgs } }).map((e) => e.path);
    for (const args of [['--model=x'], ['--model', 'x'], ['-p'], ['--settings={}'], ['--autocompact', '200000'], ['--chrome', '--add-dir', '/tmp']]) expect(refused('claude', args)).toEqual([expect.stringMatching(/^providers\.a\.launchArgs\.\d$/)]);
    for (const args of [['--model=x'], ['--model', 'x'], ['--json'], ['--sandbox', 'read-only'], ['--dangerously-bypass-approvals-and-sandbox'], ['-c', 'model_provider=x'], ['-cmodel_provider=x'], ['--config', 'model_provider=x'], ['--config=model_provider=x'], ['-c', 'carrier_marker="x"'], ['-c', 'model_auto_compact_token_limit=1']]) {
      expect(refused('codex', args)).toEqual([expect.stringMatching(/^providers\.a\.launchArgs\.\d$/)]);
    }
    expect(loadProviders({ providers: { a: { harness: 'claude', launchArgs: ['--chrome', '--model-x'] }, b: { harness: 'codex', launchArgs: ['-c', 'model_reasoning_effort=high', '-cshell_environment_policy.inherit=all', '--config=sandbox_mode=x'] } } }).ok).toBe(true);
    expect(loadProviders({ providers: { a: { harness: 'codex', launchArgs: ['-p', '--settings'] } } }).ok).toBe(true);
  });

  test('a refusal names the flag and never the value of an argument', () => {
    expect(errorsOf({ a: { harness: 'claude', launchArgs: ['--model=secret-value'] } })[0]!.message).not.toContain('secret-value');
    expect(errorsOf({ a: { harness: 'codex', launchArgs: ['-c', 'model_provider=secret-value'] } })[0]!.message).not.toContain('secret-value');
  });
});
