import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { FakeGit } from './fake.ts';
import { generateName, invalidReason, suggestName } from './names.ts';
import { adjectives, places, units } from './words.ts';

describe.each([
  ['adjectives', adjectives],
  ['units', units],
  ['places', places],
])('the %s list', (_, words) => {
  test('has at least thirty lowercase single words and no duplicates', () => {
    expect(words.length).toBeGreaterThanOrEqual(30);
    for (const word of words) expect(word).toMatch(/^[a-z]+$/);
    expect(new Set(words).size).toBe(words.length);
  });
});

describe('generateName', () => {
  test('is <adjective>-<unit>-<place> from the random source it is given', () => {
    expect(generateName(() => 0)).toBe(`${adjectives[0]}-${units[0]}-${places[0]}`);
    expect(generateName(() => 0.999999)).toBe(`${adjectives.at(-1)}-${units.at(-1)}-${places.at(-1)}`);
    const rolls = [0, 0.5, 0.25];
    expect(generateName(() => rolls.shift()!)).toBe(`${adjectives[0]}-${units[Math.floor(units.length / 2)]}-${places[Math.floor(places.length / 4)]}`);
  });
  test('every generated name is valid', () => {
    for (let i = 0; i < 200; i++) expect(invalidReason(generateName())).toBeNull();
  });
});

describe('invalidReason', () => {
  test.each(['marine', 'a', '0day', 'a-b_c.d', 'x'.repeat(60), 'v1.2'])('%s is valid', (name) => expect(invalidReason(name)).toBeNull());
  test.each([
    ['', 'empty'],
    ['x'.repeat(61), 'longer than 60'],
    ['-a', 'start with'],
    ['.a', 'start with'],
    ['_a', 'start with'],
    ['A', 'start with'],
    ['a b', 'only have'],
    ['a/b', 'only have'],
    ['aB', 'only have'],
    ['ñ', 'start with'],
    ['a..b', 'two dots'],
    ['a.', 'end with a dot'],
    ['a.lock', '.lock'],
  ])('%j is not: %s', (name, why) => expect(invalidReason(name)).toContain(why));
});

describe('suggestName with the fake git', () => {
  const folder = '/work/app';
  const first = `${adjectives[0]}-${units[0]}-${places[0]}`;
  const second = `${adjectives[0]}-${units[0]}-${places[1]}`;
  let home: string;
  beforeEach(() => {
    home = mkdtempSync(join(tmpdir(), 'nm-'));
    vi.stubEnv('CARRIER_HOME', home);
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(home, { recursive: true, force: true });
  });
  const rolls = (...places: number[]) => {
    const queue = places.flatMap((place) => [0, 0, place / 1000]); // adjective 0, unit 0, then a place
    return () => queue.shift() ?? 0;
  };
  const git = (repo: Parameters<FakeGit['repos']['set']>[1]) => {
    const fake = new FakeGit();
    fake.repos.set(folder, repo);
    return fake;
  };

  test('a free name is answered as it rolled', async () => {
    expect(await suggestName(git({ head: 'main', branches: ['main'] }), folder, rolls(0))).toEqual({ name: first });
  });
  test('a name taken by a local branch, a remote branch or a folder is rolled again, never numbered', async () => {
    const place = (index: number) => Math.ceil((index * 1000) / places.length); // a roll that lands on places[index]
    const taken = [`carrier/${first}`];
    const remote = [`carrier/${second}`];
    mkdirSync(join(home, 'chat', 'worktrees', 'local', 'app', `${adjectives[0]}-${units[0]}-${places[2]}`), { recursive: true });
    const found = await suggestName(git({ head: 'main', branches: ['main', ...taken], remoteBranches: remote }), folder, rolls(place(0), place(1), place(2), place(3)));
    expect(found).toEqual({ name: `${adjectives[0]}-${units[0]}-${places[3]}` });
  });
  test('after fifty rolls it refuses in words', async () => {
    const all = adjectives.flatMap((adjective) => units.flatMap((unit) => places.map((place) => `carrier/${adjective}-${unit}-${place}`)));
    await expect(suggestName(git({ head: 'main', branches: all }), folder, () => 0)).rejects.toThrow('already taken');
  });
});
