import { mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { chatConfigPathOf, projectsPathOf } from '../config/places.ts';
import { projectEdits } from './project-edits.ts';
import { ChatRefused } from './runner.ts';

// Each change to `projects.json` over a scratch Carrier folder: the file after it, the keys the person wrote kept, a value the schema refuses refused with its key path and kind and the file left as it was.

let home: string;
beforeEach(() => void (home = mkdtempSync(join(tmpdir(), 'pe-'))));
afterEach(() => rmSync(home, { recursive: true, force: true }));

const alpha = { path: '/w/alpha', name: 'Alpha', origin: 'cloned', pinned: true, tags: ['a', 'b'], icon: { color: 'teal', mark: 'bolt', image: 'a.png' }, defaults: { agent: 'claude', model: 'opus', access: { mode: 'plan' } }, actions: [{ name: 'Install', command: 'pnpm i', when: 'newWorktree' }] };
const beta = { path: '/w/beta', origin: 'added' };
const file = () => projectsPathOf(home);
const seed = (projects: unknown[]) => writeFileSync(file(), JSON.stringify({ projects }, null, 2) + '\n');
const projects = () => JSON.parse(readFileSync(file(), 'utf8')).projects;
const refusalOf = (run: () => unknown) => {
  try {
    run();
  } catch (error) {
    if (error instanceof ChatRefused) return error;
    throw error;
  }
  throw new Error('was not refused');
};
/** Runs `run`, expects its refusal and the file byte for byte as before. */
const refused = (run: () => unknown) => {
  const before = readFileSync(file(), 'utf8');
  const error = refusalOf(run);
  expect(readFileSync(file(), 'utf8')).toBe(before);
  expect(readdirSync(home).filter((name) => name.endsWith('.tmp'))).toEqual([]);
  return error;
};
const edits = [
  ['removeProject', { path: '/w/none' }],
  ['editProject', { path: '/w/none', key: 'name', value: 'x' }],
  ['moveProject', { path: '/w/none', folder: '/w/else' }],
  ['editProjectIcon', { path: '/w/none', changes: { color: 'red' } }],
  ['editProjectDefaults', { path: '/w/none', changes: { agent: 'codex' } }],
  ['editProjectTags', { path: '/w/none', add: ['x'], remove: [] }],
  ['setProjectActions', { path: '/w/none', actions: [] }],
] as const;

test.each(edits)('%s refuses a project that is not there with its code and path, and leaves the file as it was', (cmd, args) => {
  seed([alpha]);
  const error = refused(() => (projectEdits[cmd] as (args: unknown, home: string) => unknown)(args, home));
  expect(error).toMatchObject({ code: 'project.missing', params: { path: '/w/none' } });
});

test.each([
  ['removeProject', { path: '/w/alpha' }],
  ['editProject', { path: '/w/alpha', key: 'name', value: 'x' }],
  ['editProjectTags', { path: '/w/alpha', add: ['x'], remove: [] }],
])('%s refuses a file that does not match its schema, naming the field, and leaves it as it was', (cmd, args) => {
  seed([{ ...alpha, colour: 'red' }]);
  expect(refused(() => (projectEdits[cmd as 'removeProject'] as (args: unknown, home: string) => unknown)(args, home))).toMatchObject({ code: 'config.problem', params: { path: 'projects.0.colour', problem: 'unrecognized_keys' } });
});

test('a projects.json that is not JSON is refused as the file, and left as it was', () => {
  writeFileSync(file(), '{ not json');
  expect(refused(() => projectEdits.removeProject({ path: '/w/alpha' }, home))).toMatchObject({ code: 'config.problem', params: { path: '(file)', problem: 'notJson' } });
});

describe('addProject', () => {
  test('adds the folder as a project of origin added named after it, and keeps every entry and key', () => {
    seed([alpha, beta]);
    expect(projectEdits.addProject({ folder: '/w/gamma' }, home)).toEqual({ added: true, saved: { path: '/w/gamma', name: 'gamma', origin: 'added' } });
    expect(projects()).toEqual([alpha, beta, { path: '/w/gamma', name: 'gamma', origin: 'added' }]);
  });

  test('makes a projects.json that is not there', () => {
    expect(projectEdits.addProject({ folder: '/w/gamma' }, home).added).toBe(true);
    expect(projects()).toEqual([{ path: '/w/gamma', name: 'gamma', origin: 'added' }]);
  });

  test('says a folder that already is a project is one, however it is written, and writes nothing', () => {
    seed([alpha]);
    const before = readFileSync(file(), 'utf8');
    expect(projectEdits.addProject({ folder: '/w/alpha/' }, home)).toEqual({ added: false, saved: alpha });
    expect(readFileSync(file(), 'utf8')).toBe(before);
  });

  test.each([['work/x'], ['']])('refuses the folder %j that is not an absolute path', (folder) => {
    seed([alpha]);
    expect(refused(() => projectEdits.addProject({ folder }, home))).toMatchObject({ code: 'config.problem', params: { path: 'projects.1.path' } });
  });
});

describe('removeProject', () => {
  test('takes the entry out and keeps the others as they are', () => {
    seed([alpha, beta]);
    expect(projectEdits.removeProject({ path: '/w/alpha' }, home)).toEqual({ removed: '/w/alpha' });
    expect(projects()).toEqual([beta]);
  });
});

describe('editProject', () => {
  test('sets a key, keeps every other key of the entry, and a null takes it out', () => {
    seed([alpha, beta]);
    expect(projectEdits.editProject({ path: '/w/alpha', key: 'name', value: 'Renamed' }, home).saved).toEqual({ ...alpha, name: 'Renamed' });
    projectEdits.editProject({ path: '/w/alpha', key: 'hidden', value: true }, home);
    projectEdits.editProject({ path: '/w/alpha', key: 'pinned', value: null }, home);
    const { pinned, ...rest } = alpha;
    expect(projects()).toEqual([{ ...rest, name: 'Renamed', hidden: true }, beta]);
  });

  test.each([
    ['name', true, 'projects.0.name', 'invalid_type'],
    ['name', '  ', 'projects.0.name', 'invalid_format'],
    ['pinned', 'yes', 'projects.0.pinned', 'invalid_type'],
  ] as const)('refuses %s = %j with its key path and kind', (key, value, path, problem) => {
    seed([alpha]);
    const error = refused(() => projectEdits.editProject({ path: '/w/alpha', key, value }, home));
    expect(error).toMatchObject({ code: 'config.problem', params: { path, problem } });
    expect(error.message).toContain(path);
  });
});

describe('moveProject', () => {
  test('points the entry at the folder and keeps every other key', () => {
    seed([alpha, beta]);
    expect(projectEdits.moveProject({ path: '/w/alpha', folder: '/w/moved' }, home).saved).toEqual({ ...alpha, path: '/w/moved' });
    expect(projects()).toEqual([{ ...alpha, path: '/w/moved' }, beta]);
  });

  test('refuses a folder that is another project, written with a slash, with ~, or through a link', () => {
    const real = mkdtempSync(join(tmpdir(), 'pe-real-'));
    const link = `${real}-link`;
    symlinkSync(real, link);
    try {
      seed([alpha, { path: real, origin: 'added' }]);
      for (const folder of [`${real}/`, link, `${real}/../${real.split('/').pop()}`]) {
        expect(refused(() => projectEdits.moveProject({ path: '/w/alpha', folder }, home))).toMatchObject({ code: 'config.problem', params: { path: 'projects.1.path', problem: 'custom' }, message: "projects.json: projects.1.path is already another project's folder" });
      }
    } finally {
      rmSync(real, { recursive: true, force: true });
      rmSync(link, { force: true });
    }
  });

  test('moving a project to its own folder written another way is not a clash', () => {
    seed([alpha]);
    expect(projectEdits.moveProject({ path: '/w/alpha', folder: '/w/alpha/' }, home).saved.path).toBe('/w/alpha/');
  });

  test('refuses a folder that is not an absolute path', () => {
    seed([alpha]);
    expect(refused(() => projectEdits.moveProject({ path: '/w/alpha', folder: 'rel' }, home))).toMatchObject({ code: 'config.problem', params: { path: 'projects.0.path' } });
  });
});

describe('editProjectIcon and editProjectDefaults', () => {
  test('set the keys given, remove those that are null, and keep every other key of the object and of the entry', () => {
    seed([alpha, beta]);
    projectEdits.editProjectIcon({ path: '/w/alpha', changes: { color: 'red', image: null } }, home);
    projectEdits.editProjectDefaults({ path: '/w/alpha', changes: { model: null, workIn: 'worktree', access: null } }, home);
    expect(projects()[0]).toEqual({ ...alpha, icon: { color: 'red', mark: 'bolt' }, defaults: { agent: 'claude', workIn: 'worktree' } });
    expect(projects()[1]).toEqual(beta);
  });

  test('remove the object when its last key goes, and make it when the first one comes', () => {
    seed([alpha, beta]);
    projectEdits.editProjectIcon({ path: '/w/alpha', changes: { color: null, mark: null, image: null } }, home);
    projectEdits.editProjectDefaults({ path: '/w/alpha', changes: { agent: null, model: null, access: null } }, home);
    const { icon, defaults, ...rest } = alpha;
    expect(projects()[0]).toEqual(rest);
    projectEdits.editProjectDefaults({ path: '/w/beta', changes: { baseBranch: 'main' } }, home);
    expect(projects()[1]).toEqual({ ...beta, defaults: { baseBranch: 'main' } });
  });

  test.each([
    ['editProjectIcon', { color: '' }, 'projects.0.icon.color', 'too_small'],
    ['editProjectDefaults', { workIn: 'folder' }, 'projects.0.defaults.workIn', 'invalid_value'],
    ['editProjectDefaults', { access: { mode: '' } }, 'projects.0.defaults.access.mode', 'too_small'],
  ] as const)('%s refuses %j with its key path and kind', (cmd, changes, path, problem) => {
    seed([alpha]);
    expect(refused(() => (projectEdits[cmd] as (args: unknown, home: string) => unknown)({ path: '/w/alpha', changes }, home))).toMatchObject({ code: 'config.problem', params: { path, problem } });
  });
});

describe('editProjectTags', () => {
  test('removes, then adds, normalized and without repeats, keeping the order', () => {
    seed([alpha]);
    expect(projectEdits.editProjectTags({ path: '/w/alpha', add: ['  C ', 'b', 'D', 'c', '   '], remove: ['a'] }, home).saved.tags).toEqual(['b', 'c', 'd']);
    expect(projects()[0]).toEqual({ ...alpha, tags: ['b', 'c', 'd'] });
  });

  test('takes the key out when no tag remains', () => {
    seed([alpha]);
    projectEdits.editProjectTags({ path: '/w/alpha', add: [], remove: ['A', ' b '] }, home);
    const { tags, ...rest } = alpha;
    expect(projects()[0]).toEqual(rest);
  });
});

describe('setProjectActions', () => {
  test('replaces the actions, leaving out the defaults, and takes the key out when none is given', () => {
    seed([alpha]);
    const actions = [
      { name: 'Setup', command: 'make', when: 'afterClone', on: true, onFail: 'warn' },
      { name: 'Test', command: 'pnpm test', when: 'newWorktree', on: false, onFail: 'stop' },
    ];
    expect(projectEdits.setProjectActions({ path: '/w/alpha', actions }, home).saved.actions).toEqual([{ name: 'Setup', command: 'make', when: 'afterClone' }, { name: 'Test', command: 'pnpm test', when: 'newWorktree', on: false, onFail: 'stop' }]);
    projectEdits.setProjectActions({ path: '/w/alpha', actions: [] }, home);
    const { actions: gone, ...rest } = alpha;
    expect(projects()[0]).toEqual(rest);
  });

  test.each([
    [{ name: ' ', command: 'x', when: 'newWorktree' }, 'projects.0.actions.1.name'],
    [{ name: 'x', command: '', when: 'newWorktree' }, 'projects.0.actions.1.command'],
    [{ name: 'x', command: ' \t', when: 'afterClone' }, 'projects.0.actions.1.command'],
  ])('refuses the action %j with a blank name or command, and writes none of them', (action, path) => {
    seed([alpha]);
    expect(refused(() => projectEdits.setProjectActions({ path: '/w/alpha', actions: [alpha.actions[0]!, action] }, home))).toMatchObject({ code: 'config.problem', params: { path, problem: 'invalid_format' } });
  });
});

describe('setProjectsFolder', () => {
  const chat = () => chatConfigPathOf(home);

  test('writes projectsFolder to chat.json, keeping every other key, and answers it', () => {
    writeFileSync(chat(), '{ "agents": {}, "archiveAfterDays": 20 }');
    expect(projectEdits.setProjectsFolder({ folder: '/w/all' }, home)).toEqual({ saved: { projectsFolder: '/w/all' } });
    expect(JSON.parse(readFileSync(chat(), 'utf8'))).toEqual({ agents: {}, archiveAfterDays: 20, projectsFolder: '/w/all' });
  });

  test('makes a chat.json that is not there', () => {
    projectEdits.setProjectsFolder({ folder: '/w/all' }, home);
    expect(JSON.parse(readFileSync(chat(), 'utf8'))).toEqual({ projectsFolder: '/w/all' });
  });

  test.each([
    ['rel/folder', 'folder.projectsNotAbsolute'],
    ['<home>/engine', 'folder.insideCarrier'],
    ['<home>/engine/repos/x', 'folder.insideCarrier'],
    ['<home>/chat/worktrees', 'folder.insideCarrier'],
  ])('refuses %s with %s and leaves chat.json as it was', (folder, code) => {
    const text = '{ "archiveAfterDays": 20 }';
    writeFileSync(chat(), text);
    mkdirSync(join(home, 'engine'), { recursive: true });
    expect(refusalOf(() => projectEdits.setProjectsFolder({ folder: folder.replace('<home>', home) }, home))).toMatchObject({ code });
    expect(readFileSync(chat(), 'utf8')).toBe(text);
  });
});
