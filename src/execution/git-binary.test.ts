import { expect, test } from 'vitest';
import { execFileSync } from 'node:child_process';
import { findGit, gitRunner, type Machine, withGit } from './git-binary.ts';

const XCODE = '/Applications/Xcode.app/Contents/Developer';
const mac = (over: Partial<Machine> = {}): Machine => ({
  platform: 'darwin',
  path: '/usr/local/bin:/usr/bin:/bin',
  executable: (file) => ['/usr/bin/git', `${XCODE}/usr/bin/git`].includes(file),
  exists: (file) => file === `${XCODE}/usr/bin/git`,
  developerDir: async () => XCODE,
  ...over,
});

test('the shim of a Mac is skipped for the real git; everything else keeps the git the PATH reaches', async () => {
  expect(await findGit(mac())).toBe(`${XCODE}/usr/bin/git`);
  // another git first on the PATH (Homebrew's, the person's own): theirs
  expect(await findGit(mac({ path: '/opt/homebrew/bin:/usr/bin', executable: (f) => ['/opt/homebrew/bin/git', '/usr/bin/git', `${XCODE}/usr/bin/git`].includes(f) }))).toBe('git');
  // not a Mac
  expect(await findGit(mac({ platform: 'linux' }))).toBe('git');
  // no git on the PATH at all
  expect(await findGit(mac({ path: '/bin', executable: () => false }))).toBe('git');
  // the developer folder cannot be asked, or has no git
  expect(await findGit(mac({ developerDir: async () => Promise.reject(new Error('no developer tools')) }))).toBe('git');
  expect(await findGit(mac({ executable: (file) => file === '/usr/bin/git' }))).toBe('git');
});

test('the binary is asked once, and one that went away is replaced by plain git for good', async () => {
  let asked = 0;
  const run = gitRunner(mac({ developerDir: async () => (asked++, XCODE) }));
  const used: string[] = [];
  const ok = async (binary: string) => (used.push(binary), 'out');
  expect([await run(ok), await run(ok)]).toEqual(['out', 'out']);
  expect(asked).toBe(1);

  const gone = (binary: string) => (used.push(binary), binary === 'git' ? Promise.resolve('out') : Promise.reject(Object.assign(new Error('spawn ENOENT'), { code: 'ENOENT' })));
  used.length = 0;
  const away = gitRunner(mac({ exists: () => false }));
  expect(await away(gone)).toBe('out');
  expect(used).toEqual([`${XCODE}/usr/bin/git`, 'git']);
  used.length = 0;
  expect(await away(gone)).toBe('out');
  expect(used).toEqual(['git']);
});

test('a folder that is gone, another error and plain git failing are the caller\'s, not a reason to give up the binary', async () => {
  const run = gitRunner(mac()); // the binary exists
  const enoent = Object.assign(new Error('spawn git ENOENT'), { code: 'ENOENT' });
  const tried: string[] = [];
  await expect(run(async (binary) => (tried.push(binary), Promise.reject(enoent)))).rejects.toBe(enoent);
  await expect(run(async (binary) => (tried.push(binary), Promise.reject(new Error('boom'))))).rejects.toThrow('boom');
  expect(tried).toEqual([`${XCODE}/usr/bin/git`, `${XCODE}/usr/bin/git`]); // still the real one, no retry

  const plain = gitRunner(mac({ platform: 'linux' }));
  const used: string[] = [];
  await expect(plain(async (binary) => (used.push(binary), Promise.reject(enoent)))).rejects.toBe(enoent);
  expect(used).toEqual(['git']);
});

test("this machine's git runs", async () => {
  const version = await withGit(async (binary) => execFileSync(binary, ['--version'], { encoding: 'utf8' }));
  expect(version).toMatch(/^git version /);
});
