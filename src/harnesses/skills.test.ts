import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { createSkills, type SkillsDeps } from './skills.ts';

let root: string;
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'carrier-skills-'));
});
afterEach(() => rmSync(root, { recursive: true, force: true }));

const touch = (path: string) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, '');
};

const home = () => join(root, 'home');
const account = () => join(root, 'account');
const repo = () => join(root, 'repo');
const folder = () => join(repo(), 'packages', 'app');
const plugin = (name: string, install = join(root, 'plugins', name)) => ({ id: `${name}@market`, installPath: install, enabled: true });

const system = () => join(root, 'etc-codex-skills');
const fakeDeps = (over: Partial<SkillsDeps> = {}): SkillsDeps => ({ home: home(), pluginList: async () => '[]', agyPluginList: async () => '[]', codexSystemSkills: system(), ...over });

/** The Claude reader over the temporary folders and a plugin list that answers `list`, or fails. */
function reader(list: unknown[] | Error = []) {
  const calls: (string | undefined)[] = [];
  const skills = createSkills(
    fakeDeps({
      pluginList: async (configDir) => {
        calls.push(configDir);
        if (list instanceof Error) throw list;
        return JSON.stringify(list);
      },
    }),
  );
  mkdirSync(join(repo(), '.git'), { recursive: true });
  mkdirSync(folder(), { recursive: true });
  return { calls, has: (name: string, ...configDir: [string | undefined] | []) => skills.has('claude', configDir.length === 0 ? account() : configDir[0], folder(), name) };
}

test('a skill in the skills folder of the account is present', async () => {
  touch(join(account(), 'skills', 'ship', 'SKILL.md'));
  expect(await reader().has('ship')).toBe('present');
});

test('a command in the commands folder of the account is present', async () => {
  touch(join(account(), 'commands', 'ship.md'));
  expect(await reader().has('ship')).toBe('present');
});

test('an account with no configDir reads ~/.claude, and the other account is not read', async () => {
  touch(join(home(), '.claude', 'skills', 'ship', 'SKILL.md'));
  expect(await reader().has('ship', undefined)).toBe('present');
  expect(await reader().has('ship')).toBe('absent');
});

test('a skill in the repo folder or in a parent up to the repo root is present', async () => {
  touch(join(folder(), '.claude', 'skills', 'ship', 'SKILL.md'));
  touch(join(repo(), '.claude', 'skills', 'review', 'SKILL.md'));
  const { has } = reader();
  expect(await has('ship')).toBe('present');
  expect(await has('review')).toBe('present');
});

test('a skill above the repo root is not read', async () => {
  touch(join(root, '.claude', 'skills', 'ship', 'SKILL.md'));
  expect(await reader().has('ship')).toBe('absent');
});

test('a skill of a plugin the list reports is present, listed with the account of the role', async () => {
  const solve = plugin('solve');
  touch(join(solve.installPath, 'skills', 'ship', 'SKILL.md'));
  const { has, calls } = reader([plugin('other'), solve]);
  expect(await has('ship')).toBe('present');
  expect(calls).toEqual([account()]);
});

test('a skill that none of the places has is absent', async () => {
  const { has } = reader([plugin('solve')]);
  expect(await has('ship')).toBe('absent');
});

test('a plugin the person disabled does not count, unless the repo enables it', async () => {
  const off = { ...plugin('solve'), enabled: false };
  touch(join(off.installPath, 'skills', 'ship', 'SKILL.md'));
  expect(await reader([off]).has('ship')).toBe('absent');
  expect(await reader([{ ...off, projectEnabled: true }]).has('ship')).toBe('present');
});

test.each([[new Error('claude is not installed')], [[{ nope: true }]]])('a plugin list that fails or cannot be read is cannot-tell when no folder had the skill', async (list) => {
  const { has } = reader(list instanceof Error ? list : (list as unknown[]));
  expect(await has('ship')).toBe('cannot-tell');
});

test('a plugin list that is not JSON is cannot-tell', async () => {
  const skills = createSkills(fakeDeps({ pluginList: async () => 'not json' }));
  expect(await skills.has('claude', account(), folder(), 'ship')).toBe('cannot-tell');
});

test('the plugin list is not needed when a folder has the skill', async () => {
  touch(join(account(), 'skills', 'ship', 'SKILL.md'));
  expect(await reader(new Error('down')).has('ship')).toBe('present');
});

test('a bare name matches a plugin skill, and a namespaced name matches only that plugin', async () => {
  const solve = plugin('solve');
  touch(join(solve.installPath, 'skills', 'ship', 'SKILL.md'));
  const { has } = reader([solve, plugin('other')]);
  expect(await has('ship')).toBe('present');
  expect(await has('solve:ship')).toBe('present');
  expect(await has('other:ship')).toBe('absent');
});

test('a folder skill named with a colon is found by that name', async () => {
  touch(join(account(), 'skills', 'solve:ship', 'SKILL.md'));
  expect(await reader().has('solve:ship')).toBe('present');
});

const codex = (over: Partial<SkillsDeps> = {}) => {
  mkdirSync(join(repo(), '.git'), { recursive: true });
  mkdirSync(folder(), { recursive: true });
  const skills = createSkills(fakeDeps(over));
  return (name: string, ...configDir: [string | undefined] | []) => skills.has('codex', configDir.length === 0 ? account() : configDir[0], folder(), name);
};
const skill = (dir: string, name = 'ship') => touch(join(dir, name, 'SKILL.md'));

test.each([
  ['the skills folder of the account', () => join(account(), 'skills')],
  ['its .system folder', () => join(account(), 'skills', '.system')],
  ['~/.agents/skills', () => join(home(), '.agents', 'skills')],
  ['the .agents/skills of the folder', () => join(folder(), '.agents', 'skills')],
  ['the .agents/skills of the repo root', () => join(repo(), '.agents', 'skills')],
  ['the skills folder of the machine', system],
])('a Codex skill in %s is present', async (_where, dir) => {
  skill(dir());
  expect(await codex()('ship')).toBe('present');
});

test('a Codex skill of a plugin in the cache of the account is present, by bare or namespaced name', async () => {
  skill(join(account(), 'plugins', 'cache', 'market', 'solve', '1.0', 'skills'));
  const has = codex();
  expect(await has('ship')).toBe('present');
  expect(await has('solve:ship')).toBe('present');
  expect(await has('other:ship')).toBe('absent');
});

test('an account with no configDir reads ~/.codex, and the other account is not read', async () => {
  skill(join(home(), '.codex', 'skills'));
  const has = codex();
  expect(await has('ship', undefined)).toBe('present');
  expect(await has('ship')).toBe('absent');
});

test('a Codex skill that none of the places has is absent, with a plugin cache that has other skills or files', async () => {
  skill(join(account(), 'plugins', 'cache', 'market', 'solve', '1.0', 'skills'), 'review');
  touch(join(account(), 'plugins', 'cache', '.DS_Store'));
  expect(await codex()('ship')).toBe('absent');
});

test('a Codex skills folder with no SKILL.md in it does not count', async () => {
  mkdirSync(join(account(), 'skills', 'ship'), { recursive: true });
  expect(await codex()('ship')).toBe('absent');
});

test('a plugin cache that cannot be read makes Codex cannot-tell', async () => {
  touch(join(account(), 'plugins', 'cache', 'market', 'solve', '1.0', 'skills', 'review', 'SKILL.md'));
  const cache = join(account(), 'plugins', 'cache');
  chmodSync(cache, 0o000);
  try {
    expect(await codex()('ship')).toBe('cannot-tell');
  } finally {
    chmodSync(cache, 0o755);
  }
});

const agyFolder = () => folder();
const gemini = () => join(home(), '.gemini');
const agy = (list: unknown[] | string | Error = []) => {
  mkdirSync(join(repo(), '.git'), { recursive: true });
  mkdirSync(folder(), { recursive: true });
  const asked: string[] = [];
  const skills = createSkills(
    fakeDeps({
      agyPluginList: async (where) => {
        asked.push(where);
        if (list instanceof Error) throw list;
        return typeof list === 'string' ? list : JSON.stringify(list);
      },
    }),
  );
  return { asked, has: (name: string) => skills.has('agy', undefined, folder(), name) };
};
const json = (path: string, value: unknown) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, typeof value === 'string' ? value : JSON.stringify(value));
};

test.each([
  ['the .agents/skills of the folder', () => join(agyFolder(), '.agents', 'skills')],
  ['the legacy .agent/skills of the folder', () => join(agyFolder(), '.agent', 'skills')],
  ['~/.gemini/config/skills', () => join(gemini(), 'config', 'skills')],
  ['~/.gemini/antigravity-cli/skills', () => join(gemini(), 'antigravity-cli', 'skills')],
  ['~/.gemini/skills', () => join(gemini(), 'skills')],
  ['the built-in skills folder', () => join(gemini(), 'antigravity', 'builtin', 'skills')],
])('an agy skill in %s is present', async (_where, dir) => {
  skill(dir());
  expect(await agy().has('ship')).toBe('present');
});

test('an agy skill in an entry of the manifest of the folder is present when the entry is inside the folder', async () => {
  skill(join(folder(), 'tools', 'skills'));
  skill(join(root, 'outside', 'skills'), 'review');
  json(join(folder(), '.agents', 'skills.json'), { entries: [{ path: 'tools/skills' }, { path: join(root, 'outside', 'skills') }, { path: '../../outside/skills' }] });
  const { has } = agy();
  expect(await has('ship')).toBe('present');
  expect(await has('review')).toBe('absent');
});

test('an agy skill in an entry of the manifest of the user is present, wherever it points', async () => {
  skill(join(root, 'elsewhere', 'skills'));
  json(join(gemini(), 'config', 'skills.json'), { entries: [{ path: join(root, 'elsewhere', 'skills') }] });
  expect(await agy().has('ship')).toBe('present');
});

test('an agy skill of a plugin the list reports is present, listed in the folder, unless the plugin is disabled', async () => {
  skill(join(root, 'plug', 'skills'));
  const plug = { name: 'solve', path: join(root, 'plug'), enabled: true };
  const { has, asked } = agy([plug]);
  expect(await has('ship')).toBe('present');
  expect(await has('solve:ship')).toBe('present');
  expect(await has('other:ship')).toBe('absent');
  expect(asked[0]).toBe(folder());
  expect(await agy([{ ...plug, enabled: false }]).has('ship')).toBe('absent');
});

test('an agy skill that none of the places has is absent', async () => {
  expect(await agy().has('ship')).toBe('absent');
});

test.each([
  ['a manifest with include_only', () => json(join(gemini(), 'config', 'skills.json'), { entries: [], include_only: ['x'] })],
  ['a manifest of the folder with exclude', () => json(join(folder(), '.agents', 'skills.json'), { entries: [], exclude: ['x'] })],
  ['an entry with exclude', () => json(join(gemini(), 'config', 'skills.json'), { entries: [{ path: join(root, 'p'), exclude: ['x'] }] })],
  ['a manifest that cannot be parsed', () => json(join(gemini(), 'config', 'skills.json'), 'not json')],
  ['a manifest with an entry that has no path', () => json(join(folder(), '.agents', 'skills.json'), { entries: [{}] })],
])('%s makes agy cannot-tell when no place had the skill', async (_what, set) => {
  set();
  expect(await agy().has('ship')).toBe('cannot-tell');
});

test.each([
  ['include_only', (path: string) => ({ entries: [{ path }], include_only: ['x'] })],
  ['exclude', (path: string) => ({ entries: [{ path, exclude: ['ship'] }] })],
])('an agy skill in a folder a manifest with %s points at is cannot-tell, since the filter may hide it', async (_what, manifest) => {
  skill(join(root, 'p'));
  json(join(gemini(), 'config', 'skills.json'), manifest(join(root, 'p')));
  expect(await agy().has('ship')).toBe('cannot-tell');
});

test.each([[new Error('agy is not installed')], ['not json'], [[{ nope: true }]]])('a plugin list that fails or cannot be read makes agy cannot-tell', async (list) => {
  expect(await agy(list).has('ship')).toBe('cannot-tell');
});

test('an agy skill found in a place is present even when another place could not be read', async () => {
  json(join(gemini(), 'config', 'skills.json'), 'not json');
  skill(join(gemini(), 'skills'));
  expect(await agy(new Error('down')).has('ship')).toBe('present');
});
