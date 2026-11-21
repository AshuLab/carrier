import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { checkFolder, checkProjectFolder, checkProjectsFolder } from './folder.ts';

let base: string;
let home: string;
let work: string;
beforeEach(() => {
  base = mkdtempSync(join(tmpdir(), 'fo-'));
  home = join(base, 'home');
  work = join(base, 'work');
  for (const dir of ['engine/repos/acme/app', 'chat/state', 'chat/logs', 'chat/worktrees/acme']) mkdirSync(join(home, dir), { recursive: true });
  mkdirSync(work);
});
afterEach(() => rmSync(base, { recursive: true, force: true }));

test('an existing folder is accepted and comes back as its real path', () => {
  expect(checkFolder(work, home)).toBe(realpathSync(work));
  // the chat's own folders are the chat's to work in (its worktrees are session folders), and so is the Carrier folder itself
  for (const inside of ['', 'chat', 'chat/worktrees/acme']) expect(checkFolder(join(home, inside), home)).toBe(realpathSync(join(home, inside)));
});

test('a folder that does not exist, a file and a relative path are refused with a reason', () => {
  writeFileSync(join(work, 'file.txt'), '');
  expect(() => checkFolder(join(work, 'missing'), home)).toThrow('does not exist');
  expect(() => checkFolder(join(work, 'file.txt'), home)).toThrow('not a folder');
  expect(() => checkFolder('work', home)).toThrow('absolute');
});

test.each(['engine', 'engine/repos/acme/app'])('%s of the Carrier folder is refused', (inside) => {
  expect(() => checkFolder(join(home, inside), home)).toThrow(/inside Carrier's own engine folder/);
});

test('a symlink into the engine folder is refused too', () => {
  symlinkSync(join(home, 'engine', 'repos', 'acme', 'app'), join(work, 'link'));
  expect(() => checkFolder(join(work, 'link'), home)).toThrow(/inside Carrier's own engine folder/);
});

test('a Carrier folder that is itself reached through a symlink is still protected', () => {
  symlinkSync(home, join(base, 'alias'));
  expect(() => checkFolder(join(home, 'engine'), join(base, 'alias'))).toThrow(/engine/);
  expect(() => checkFolder(join(base, 'alias', 'engine'), home)).toThrow(/engine/);
});

test('a folder that only starts with the name of the engine folder is fine', () => {
  mkdirSync(join(home, 'engine-old'));
  expect(checkFolder(join(home, 'engine-old'), home)).toBe(realpathSync(join(home, 'engine-old')));
});

test("a projects folder may not exist yet, but not be relative nor lie in the engine's folder or the chat's own state, logs and worktrees, even through a symlink", () => {
  expect(checkProjectsFolder(join(home, 'chat', 'projects'), home)).toBe(join(home, 'chat', 'projects'));
  expect(checkProjectsFolder(home, home)).toBe(home); // the Carrier folder itself is checked again below, per project
  expect(checkProjectsFolder(join(work, 'a', 'b'), home)).toBe(join(work, 'a', 'b'));
  expect(() => checkProjectsFolder('projects', home)).toThrow('absolute');
  for (const name of ['engine', join('chat', 'state'), join('chat', 'logs'), join('chat', 'worktrees'), join('chat', 'pending'), join('chat', 'sessions')]) {
    expect(() => checkProjectsFolder(join(home, name), home)).toThrow(`inside Carrier's own ${name} folder`);
    expect(() => checkProjectsFolder(join(home, name, 'new', 'deeper'), home)).toThrow(`inside Carrier's own ${name} folder`);
  }
  symlinkSync(join(home, 'engine'), join(work, 'link'));
  expect(() => checkProjectsFolder(join(work, 'link', 'x'), home)).toThrow("inside Carrier's own engine folder");
  symlinkSync(join(home, 'chat', 'state'), join(work, 'state-link'));
  expect(() => checkProjectsFolder(join(work, 'state-link', 'x'), home)).toThrow(/chat.state folder/);
});

type ProjectFolderFixture = {
  carrier: string;
  layout: {
    dirs: string[];
    files: Record<string, string>;
    symlinks: Record<string, string>;
    unreadable: string[];
  };
  cases: {
    name: string;
    path: string;
    carrier?: string;
    relative?: boolean;
    refusal: string | null;
  }[];
};

const projectFolderFixture = JSON.parse(readFileSync(fileURLToPath(new URL('../../macos/Tests/Fixtures/project-folder.json', import.meta.url)), 'utf8')) as ProjectFolderFixture;

test.each(projectFolderFixture.cases)('checkProjectFolder: $name', (entry) => {
  const root = mkdtempSync(join(tmpdir(), 'pf-'));
  try {
    for (const dir of projectFolderFixture.layout.dirs) mkdirSync(join(root, dir), { recursive: true });
    for (const [file, body] of Object.entries(projectFolderFixture.layout.files)) {
      mkdirSync(dirname(join(root, file)), { recursive: true });
      writeFileSync(join(root, file), body);
    }
    for (const [link, target] of Object.entries(projectFolderFixture.layout.symlinks)) {
      symlinkSync(join(root, target), join(root, link));
    }
    for (const dir of projectFolderFixture.layout.unreadable) chmodSync(join(root, dir), 0o000);

    const carrier = join(root, entry.carrier ?? projectFolderFixture.carrier);
    const target = entry.relative === true ? entry.path : join(root, entry.path);
    if (entry.refusal === null) {
      expect(checkProjectFolder(target, carrier)).toBe(realpathSync(target));
    } else {
      expect(() => checkProjectFolder(target, carrier)).toThrow(entry.refusal);
    }
  } finally {
    for (const dir of projectFolderFixture.layout.unreadable) chmodSync(join(root, dir), 0o755);
    rmSync(root, { recursive: true, force: true });
  }
});
