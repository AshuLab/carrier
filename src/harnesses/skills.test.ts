import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { createSkills } from './skills.ts';

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

/** The Claude reader over the temporary folders and a plugin list that answers `list`, or fails. */
function reader(list: unknown[] | Error = []) {
  const calls: (string | undefined)[] = [];
  const skills = createSkills({
    home: home(),
    pluginList: async (configDir) => {
      calls.push(configDir);
      if (list instanceof Error) throw list;
      return JSON.stringify(list);
    },
  });
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
  const skills = createSkills({ home: home(), pluginList: async () => 'not json' });
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

test.each(['codex', 'agy'] as const)('%s has no reader yet: it cannot tell', async (harness) => {
  const skills = createSkills({ home: home(), pluginList: async () => '[]' });
  expect(await skills.has(harness, undefined, folder(), 'ship')).toBe('cannot-tell');
});
