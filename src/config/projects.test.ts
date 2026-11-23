import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { projectsPathOf } from './places.ts';
import { loadProjects, readProjectsFile, updateProjectsFile, type ProjectEntry } from './projects.ts';

const full = {
  path: '~/work/carrier',
  name: 'Carrier',
  origin: 'cloned',
  pinned: true,
  hidden: false,
  tags: ['work', 'swift'],
  icon: { color: 'teal', mark: 'bolt', image: 'carrier.png' },
  defaults: { agent: 'claude', workIn: 'worktree', baseBranch: 'main' },
  actions: [{ name: 'Install', command: 'pnpm install', when: 'newWorktree', on: true, onFail: 'stop' }, { name: 'Setup', command: 'make', when: 'afterClone' }],
};
const minimal = { path: '/Users/ana/notes', origin: 'added' };

// The table the Swift side repeats: `macos/Tests/Fixtures/projects.json` is written from it (UPDATE_FIXTURES=1) and read by ContractTests.swift.
const valid: { name: string; file: unknown }[] = [
  { name: 'no projects', file: {} },
  { name: 'an empty list', file: { projects: [] } },
  { name: 'an entry with every optional field absent', file: { projects: [minimal] } },
  { name: 'an entry with every field', file: { projects: [full] } },
  { name: 'two entries and an action with no optional field', file: { projects: [minimal, { path: '/b', origin: 'created', actions: [{ name: 'a', command: 'b', when: 'afterClone' }] }] } },
];
const invalid: { name: string; file: unknown; fields: string[] }[] = [
  { name: 'a repeated path', file: { projects: [minimal, { path: '/x', origin: 'added' }, { ...minimal, name: 'Again' }] }, fields: ['projects.2.path'] },
  { name: 'an empty path', file: { projects: [{ path: '', origin: 'added' }] }, fields: ['projects.0.path'] },
  { name: 'a relative path', file: { projects: [{ path: 'work/x', origin: 'added' }] }, fields: ['projects.0.path'] },
  { name: 'an empty name', file: { projects: [{ ...minimal, name: '' }] }, fields: ['projects.0.name'] },
  { name: 'a blank name', file: { projects: [{ ...minimal, name: '  \t' }] }, fields: ['projects.0.name'] },
  { name: 'an empty command', file: { projects: [{ ...minimal, actions: [{ name: 'a', command: '', when: 'newWorktree' }] }] }, fields: ['projects.0.actions.0.command'] },
  { name: 'a blank command', file: { projects: [{ ...minimal, actions: [{ name: 'a', command: ' ', when: 'newWorktree' }] }] }, fields: ['projects.0.actions.0.command'] },
  { name: 'a blank action name', file: { projects: [{ ...minimal, actions: [{ name: ' ', command: 'x', when: 'newWorktree' }] }] }, fields: ['projects.0.actions.0.name'] },
  { name: 'an unknown key of an entry', file: { projects: [{ ...minimal, color: 'red' }] }, fields: ['projects.0.color'] },
  { name: 'an unknown key of the icon', file: { projects: [{ ...minimal, icon: { colour: 'red' } }] }, fields: ['projects.0.icon.colour'] },
  { name: 'an unknown key of an action', file: { projects: [{ ...minimal, actions: [{ name: 'a', command: 'b', when: 'afterClone', timeout: 3 }] }] }, fields: ['projects.0.actions.0.timeout'] },
  { name: 'an unknown key of the file', file: { projects: [], version: 1 }, fields: ['version'] },
  { name: 'a file that is not an object', file: [], fields: ['(root)'] },
  { name: 'projects that is not a list', file: { projects: {} }, fields: ['projects'] },
  { name: 'a name that is not a string', file: { projects: [{ ...minimal, name: 3 }] }, fields: ['projects.0.name'] },
  { name: 'a pinned that is not a boolean', file: { projects: [{ ...minimal, pinned: 'yes' }] }, fields: ['projects.0.pinned'] },
  { name: 'a null field', file: { projects: [{ ...minimal, hidden: null }] }, fields: ['projects.0.hidden'] },
  { name: 'tags that are not a list', file: { projects: [{ ...minimal, tags: 'work' }] }, fields: ['projects.0.tags'] },
  { name: 'a tag with capitals', file: { projects: [{ ...minimal, tags: ['Work'] }] }, fields: ['projects.0.tags.0'] },
  { name: 'a repeated tag', file: { projects: [{ ...minimal, tags: ['a', 'a'] }] }, fields: ['projects.0.tags'] },
  { name: 'a missing origin', file: { projects: [{ path: '/x' }] }, fields: ['projects.0.origin'] },
  { name: 'an unknown origin', file: { projects: [{ ...minimal, origin: 'bought' }] }, fields: ['projects.0.origin'] },
  { name: 'an unknown workIn', file: { projects: [{ ...minimal, defaults: { workIn: 'folder' } }] }, fields: ['projects.0.defaults.workIn'] },
  { name: 'an action with no when', file: { projects: [{ ...minimal, actions: [{ name: 'a', command: 'b' }] }] }, fields: ['projects.0.actions.0.when'] },
  { name: 'an unknown onFail', file: { projects: [{ ...minimal, actions: [{ name: 'a', command: 'b', when: 'afterClone', onFail: 'ignore' }] }] }, fields: ['projects.0.actions.0.onFail'] },
  { name: 'an icon that is not an object', file: { projects: [{ ...minimal, icon: 'bolt' }] }, fields: ['projects.0.icon'] },
];

const entriesOf = (file: unknown) => {
  const result = loadProjects(file);
  if (!result.ok) throw new Error(`expected valid projects: ${JSON.stringify(result.errors)}`);
  return result.projects;
};

describe('the schema of projects.json', () => {
  test.each(valid)('accepts $name', ({ file }) => {
    expect(entriesOf(file)).toEqual((file as { projects?: unknown[] }).projects ?? []);
  });

  test('an entry with every optional field absent is read as it is, with no key added', () => {
    expect(Object.keys(entriesOf({ projects: [minimal] })[0]!)).toEqual(['path', 'origin']);
  });

  test.each(invalid)('refuses $name, naming the field', ({ file, fields }) => {
    const result = loadProjects(file);
    expect(result.ok).toBe(false);
    expect(result.ok ? [] : result.errors.map((e) => e.path)).toEqual(fields);
  });

  test('the fixture of the Swift contract equals this table', () => {
    const fixture = fileURLToPath(new URL('../../macos/Tests/Fixtures/projects.json', import.meta.url));
    const json = `${JSON.stringify({ valid: valid.map(({ name, file }) => ({ name, file, entries: entriesOf(file) })), invalid }, null, 2)}\n`;
    if (process.env.UPDATE_FIXTURES === '1') writeFileSync(fixture, json);
    expect(json).toBe(readFileSync(fixture, 'utf8'));
  });
});

describe('reading and writing the file', () => {
  let folder: string;
  beforeEach(() => { folder = mkdtempSync(join(tmpdir(), 'projects-')); });
  afterEach(() => rmSync(folder, { recursive: true, force: true }));
  const add = (entry: ProjectEntry) => (current: ProjectEntry[]) => [...current, entry];

  test('an absent file is an empty list, and a first write makes it', () => {
    expect(readProjectsFile(folder)).toEqual({ ok: true, projects: [] });
    expect(updateProjectsFile(add(minimal as ProjectEntry), folder)).toEqual({ ok: true, projects: [minimal] });
    expect(JSON.parse(readFileSync(projectsPathOf(folder), 'utf8'))).toEqual({ projects: [minimal] });
    expect(readdirSync(folder)).toEqual(['projects.json']);
  });

  test('two writers that interleave keep each other\'s entry, since each one reads the file again just before it writes', () => {
    const a = { path: '/a', origin: 'added' } as ProjectEntry;
    const b = { path: '/b', origin: 'cloned' } as ProjectEntry;
    expect(readProjectsFile(folder)).toEqual({ ok: true, projects: [] }); // what both writers saw when they started
    // B writes first, then A, whose change was made from the empty list it saw: it is applied to what is on disk now
    expect(updateProjectsFile(add(b), folder).ok).toBe(true);
    expect(updateProjectsFile(add(a), folder)).toEqual({ ok: true, projects: [b, a] });
    expect(readProjectsFile(folder)).toEqual({ ok: true, projects: [b, a] });
    // an edit of one entry keeps the other
    expect(updateProjectsFile((current) => current.map((entry) => (entry.path === '/a' ? { ...entry, pinned: true } : entry)), folder)).toEqual({ ok: true, projects: [b, { ...a, pinned: true }] });
  });

  test('a file that does not match is reported with the field and is never written over', () => {
    const bad = JSON.stringify({ projects: [{ path: '/a', origin: 'added', colour: 'red' }] });
    writeFileSync(projectsPathOf(folder), bad);
    expect(readProjectsFile(folder)).toMatchObject({ ok: false, errors: [{ path: 'projects.0.colour' }] });
    expect(updateProjectsFile(add(minimal as ProjectEntry), folder)).toMatchObject({ ok: false, errors: [{ path: 'projects.0.colour' }] });
    expect(readFileSync(projectsPathOf(folder), 'utf8')).toBe(bad);
    writeFileSync(projectsPathOf(folder), 'not json');
    expect(readProjectsFile(folder)).toMatchObject({ ok: false, errors: [{ path: '(file)' }] });
    expect(updateProjectsFile(add(minimal as ProjectEntry), folder).ok).toBe(false);
    expect(readFileSync(projectsPathOf(folder), 'utf8')).toBe('not json');
  });

  test('a change that would make the file invalid is refused and the file stays as it was', () => {
    updateProjectsFile(add(minimal as ProjectEntry), folder);
    const before = readFileSync(projectsPathOf(folder), 'utf8');
    expect(updateProjectsFile(add(minimal as ProjectEntry), folder)).toMatchObject({ ok: false, errors: [{ path: 'projects.1.path' }] });
    expect(readFileSync(projectsPathOf(folder), 'utf8')).toBe(before);
    expect(readdirSync(folder)).toEqual(['projects.json']);
  });
});
