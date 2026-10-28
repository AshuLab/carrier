import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { checkFolder } from './folder.ts';

let base: string;
let root: string;
let work: string;
beforeEach(() => {
  base = mkdtempSync(join(tmpdir(), 'fo-'));
  root = join(base, 'root');
  work = join(base, 'work');
  for (const dir of ['repos/acme/app', 'worktrees/acme', 'orchestrator', 'chat']) mkdirSync(join(root, dir), { recursive: true });
  mkdirSync(work);
});
afterEach(() => rmSync(base, { recursive: true, force: true }));

test('an existing folder is accepted and comes back as its real path', () => {
  expect(checkFolder(work, root)).toBe(realpathSync(work));
  expect(checkFolder(join(root, 'chat'), root)).toBe(realpathSync(join(root, 'chat'))); // the root itself is not forbidden
});

test('a folder that does not exist, a file and a relative path are refused with a reason', () => {
  writeFileSync(join(work, 'file.txt'), '');
  expect(() => checkFolder(join(work, 'missing'), root)).toThrow('does not exist');
  expect(() => checkFolder(join(work, 'file.txt'), root)).toThrow('not a folder');
  expect(() => checkFolder('work', root)).toThrow('absolute');
});

test.each(['repos', 'repos/acme/app', 'worktrees/acme', 'orchestrator'])('%s of the root is refused', (inside) => {
  expect(() => checkFolder(join(root, inside), root)).toThrow(/inside Carrier's own/);
});

test('a symlink into the engine folders is refused too', () => {
  symlinkSync(join(root, 'repos', 'acme', 'app'), join(work, 'link'));
  expect(() => checkFolder(join(work, 'link'), root)).toThrow(/inside Carrier's own repos folder/);
});

test('a root that is itself reached through a symlink is still protected', () => {
  symlinkSync(root, join(base, 'alias'));
  expect(() => checkFolder(join(root, 'worktrees'), join(base, 'alias'))).toThrow(/worktrees/);
  expect(() => checkFolder(join(base, 'alias', 'repos'), root)).toThrow(/repos/);
});

test('a folder that only starts with the name of an engine folder is fine', () => {
  mkdirSync(join(root, 'repos-old'));
  expect(checkFolder(join(root, 'repos-old'), root)).toBe(realpathSync(join(root, 'repos-old')));
});
