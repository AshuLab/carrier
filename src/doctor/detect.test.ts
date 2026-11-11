import { expect, test } from 'vitest';
import { resolveBinary } from '../harnesses/common.ts';
import { detect, type Machine } from './detect.ts';

/** A Mac with `claude` and `codex` installed, no `agy`, and nothing serving models. */
const machine = (over: Partial<Machine> = {}): Machine => ({
  resolveBinary: (name) => {
    if (name === 'agy') throw new Error('cannot find the real "agy" binary on PATH');
    return `/opt/bin/${name}`;
  },
  version: async (command) => (command.endsWith('claude') ? '2.1.3 (Claude Code)' : 'codex-cli 0.5.0'),
  login: async (harness) => (harness === 'claude' ? 'in' : 'out'),
  localModels: async () => Promise.reject(new Error('connection refused')),
  ...over,
});
const accounts = { claude: { harness: 'claude' as const }, codex: { harness: 'codex' as const }, agy: { harness: 'agy' as const } };

test('a Mac with claude and codex but not agy: the two with path and version, a signed-out account as such, agy as not found', async () => {
  const found = await detect(machine(), accounts);
  expect(found.harnesses).toEqual({
    claude: { found: true, path: '/opt/bin/claude', version: '2.1.3 (Claude Code)' },
    codex: { found: true, path: '/opt/bin/codex', version: 'codex-cli 0.5.0' },
    agy: { found: false },
  });
  expect(found.accounts).toEqual({ claude: 'in', codex: 'out', agy: 'unknown' }); // agy is not asked: its CLI is not there
});

test('a login check asks with the account\'s own folder and binary, and one that cannot tell is unknown', async () => {
  const asked: unknown[] = [];
  const found = await detect(
    machine({
      login: async (harness, configDir, command) => {
        asked.push([harness, configDir, command]);
        if (configDir === '/h/.claude-broken') throw new Error('no cli');
        return 'in';
      },
    }),
    { 'claude-work': { harness: 'claude', configDir: '/h/.claude-work' }, 'claude-broken': { harness: 'claude', configDir: '/h/.claude-broken' }, mine: { harness: 'codex', command: '/h/bin/codex' } },
  );
  expect(asked).toEqual(expect.arrayContaining([['claude', '/h/.claude-work', '/opt/bin/claude'], ['codex', undefined, '/h/bin/codex']]));
  expect(found.accounts).toEqual({ 'claude-work': 'in', 'claude-broken': 'unknown', mine: 'in' });
});

test('a wrapper directory first on the PATH is skipped by the lookup', async () => {
  const path = '/Users/d/.paradev/bin:/Users/d/.superset/bin:/opt/bin';
  const executable = (file: string) => !file.startsWith('/opt/bin/agy');
  const found = await detect(machine({ resolveBinary: (name) => resolveBinary(name, path, executable) }), accounts);
  expect(found.harnesses.claude).toMatchObject({ found: true, path: '/opt/bin/claude' });
  expect(found.harnesses.agy).toEqual({ found: false }); // only the wrappers had it
});

test('a local server that does not answer is not running, and one that does lists its models; no account is made for either', async () => {
  const found = await detect(machine({ localModels: async (local) => (local === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))) }), accounts);
  expect(found.servers).toEqual({ lmstudio: { running: false }, ollama: { running: true, models: ['qwen3:8b'] } });
  expect(Object.keys(found.accounts)).toEqual(['claude', 'codex', 'agy']);
});
