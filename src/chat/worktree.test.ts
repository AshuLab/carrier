import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeGit } from './fake.ts';
import { ChatRefused } from './runner.ts';
import { countPorcelain } from './workspace.ts';
import { createWorktree, parseCount, parseWorktreeList } from './worktree.ts';

test('parseCount reads the number rev-list --count printed, and 0 for anything else', () => {
  expect(parseCount('3\n')).toBe(3);
  expect(parseCount('0\n')).toBe(0);
  expect(parseCount('')).toBe(0);
  expect(parseCount('fatal')).toBe(0);
});

test('parseWorktreeList reads the main tree first, then each linked one, with its branch or none when detached', () => {
  const out = 'worktree /a/app\nHEAD 111\nbranch refs/heads/main\n\nworktree /h/worktrees/acme/app/kerrigan\nHEAD 222\nbranch refs/heads/carrier/kerrigan\n\nworktree /h/worktrees/acme/app/zerg\nHEAD 333\ndetached\n\nworktree /h/gone\nHEAD 444\nbranch refs/heads/x\nprunable gitdir file points to non-existent location\n';
  expect(parseWorktreeList(out)).toEqual([{ path: '/a/app', branch: 'main' }, { path: '/h/worktrees/acme/app/kerrigan', branch: 'carrier/kerrigan' }, { path: '/h/worktrees/acme/app/zerg', branch: null }, { path: '/h/gone', branch: 'x' }]);
  expect(parseWorktreeList('')).toEqual([]);
});

test('dirty is the number of lines git status --porcelain prints', () => {
  expect(countPorcelain('')).toBe(0);
  expect(countPorcelain(' M a.ts\n?? b.ts\nA  c.ts\n')).toBe(3);
});

test('a worktree the person cancels is refused as cancelled and not logged as a failure of git', async () => {
  const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
  const folder = mkdtempSync(join(tmpdir(), 'wt-'));
  try {
    const git = new FakeGit();
    git.repos.set(folder, { head: 'main', branches: ['main'] });
    git.worktreePending = new Promise(() => {});
    const abort = new AbortController();
    const making = createWorktree(git, folder, { from: 'main', name: 'my-fix' }, abort.signal);
    await vi.waitFor(() => expect(git.calls.some((call) => call.args[0] === 'worktree' && call.args[1] === 'add')).toBe(true));
    abort.abort();
    await expect(making).rejects.toThrow(new ChatRefused('Creating the worktree was cancelled'));
    expect(errors.mock.calls.flat().join('\n')).not.toContain('git worktree add failed');
  } finally {
    errors.mockRestore();
    rmSync(folder, { recursive: true, force: true });
  }
});

// A worktree is made under the Carrier folder: a scratch one, never the person's.
let home: string;
beforeEach(() => {
  home = mkdtempSync(join(tmpdir(), 'wt-home-'));
  vi.stubEnv('CARRIER_HOME', home);
});
afterEach(() => {
  vi.unstubAllEnvs();
  rmSync(home, { recursive: true, force: true });
});

/** A repository with a local `main` and `local-only`, and `main` and `dev` on origin. */
const startRepo = () => {
  const folder = mkdtempSync(join(tmpdir(), 'wt-'));
  const git = new FakeGit();
  git.repos.set(folder, { head: 'main', branches: ['main', 'local-only'], remoteBranches: ['main', 'dev'], origin: 'git@github.com:acme/app.git' });
  const startOf = () => git.calls.find((call) => call.args[0] === 'worktree' && call.args[1] === 'add')!.args.at(-1);
  return { folder, git, startOf };
};

test.each([
  ['remote', 'main', 'refs/remotes/origin/main', 'origin/main'],
  ['local', 'main', 'refs/heads/main', 'main'],
  ['remote', 'local-only', 'refs/heads/local-only', 'local-only'], // never pushed: nothing else to start from
  ['remote', 'origin/dev', 'refs/remotes/origin/dev', 'origin/dev'],
  ['local', 'origin/dev', 'refs/remotes/origin/dev', 'origin/dev'], // a name that already carries origin/ wins over startFrom
  [undefined, 'main', 'refs/heads/main', 'main'], // the open request: `from` is the exact ref
] as const)('startFrom %s on %s is cut from %s and recorded as %s', async (startFrom, from, ref, recorded) => {
  const { folder, git, startOf } = startRepo();
  try {
    const made = await createWorktree(git, folder, { from, name: 'my-fix', ...(startFrom && { startFrom }) });
    expect(startOf()).toBe(ref);
    expect(git.calls.find((call) => call.args[1] === 'add')!.args.slice(0, 5)).toEqual(['worktree', 'add', '--no-track', '-b', 'carrier/my-fix']);
    expect(made.from).toBe(recorded);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});

test('a local start of a branch the repository has only on origin is refused as an unlisted branch', async () => {
  const { folder, git } = startRepo();
  try {
    await expect(createWorktree(git, folder, { from: 'dev', name: 'my-fix', startFrom: 'local' })).rejects.toThrow(new ChatRefused('The branch to start from is not one this repository lists'));
    expect(git.calls.some((call) => call.args[1] === 'add')).toBe(false);
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});
