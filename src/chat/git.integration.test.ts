import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import { realGit } from './git.ts';
import { fetchFolder, inspectFolder } from './workspace.ts';

// What the host's `workspace` request finds in real repositories made in temporary folders, with the `git` on this
// machine: a repository with and without a remote, a detached HEAD, a bare repository, a linked worktree as the
// folder, an untracked file and a modified file counted in `dirty`. Nothing leaves the machine: the "remote" is a
// bare repository in a temporary folder, and only its URL is then changed to a GitHub one. It only runs when this is
// set explicitly:
//   CARRIER_IT_GIT=1
const enabled = process.env.CARRIER_IT_GIT === '1';

let dir: string;
const git = (cwd: string, ...args: string[]) =>
  execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t', GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' } });
const repoAt = (name: string) => {
  const path = join(dir, name);
  mkdirSync(path);
  git(path, 'init', '-q', '-b', 'main');
  writeFileSync(join(path, 'a.txt'), 'a\n');
  git(path, 'add', '.');
  git(path, 'commit', '-q', '-m', 'one');
  return realpathSync(path);
};

describe.skipIf(!enabled)('the workspace of a folder, with the real git', () => {
  beforeAll(() => void (dir = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-git-')))));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  test('a folder that is not a repository is a plain one', async () => {
    const plain = join(dir, 'plain');
    mkdirSync(plain);
    expect(await inspectFolder(realGit, plain)).toEqual({ folder: plain, git: false, bare: false, linkedWorktree: false, repo: null, branch: null, defaultBranch: null, dirty: 0, branches: [], fetchedAt: null });
  });

  test('a repository without a remote: its branch, main as the default, a clean tree and no fetch', async () => {
    const repo = repoAt('local');
    git(repo, 'branch', 'dev');
    expect(await inspectFolder(realGit, repo)).toEqual({ folder: repo, git: true, bare: false, linkedWorktree: false, repo: null, branch: 'main', defaultBranch: 'main', dirty: 0, branches: [{ name: 'dev', remote: false }, { name: 'main', remote: false }], fetchedAt: null });
  });

  test('a repository with no commit yet still has its branch', async () => {
    const path = join(dir, 'empty');
    mkdirSync(path);
    git(path, 'init', '-q', '-b', 'trunk');
    expect(await inspectFolder(realGit, path)).toMatchObject({ git: true, branch: 'trunk', defaultBranch: null, branches: [] });
  });

  test('a repository with a remote: origin/HEAD is the default, remote branches follow the local ones, a fetch leaves a time and a GitHub URL gives the repo', async () => {
    const origin = repoAt('origin-src');
    git(origin, 'branch', 'release');
    git(origin, 'checkout', '-q', 'release');
    const bare = join(dir, 'origin.git');
    git(dir, 'clone', '-q', '--bare', origin, bare);
    const clone = join(dir, 'clone');
    git(dir, 'clone', '-q', bare, clone);
    git(clone, 'checkout', '-q', '-b', 'mine');
    git(clone, 'fetch', '-q', 'origin');
    git(clone, 'remote', 'set-url', 'origin', 'git@github.com:acme/app.git');
    const info = await inspectFolder(realGit, realpathSync(clone));
    expect(info).toMatchObject({ git: true, repo: { owner: 'acme', name: 'app' }, branch: 'mine', defaultBranch: 'release' });
    expect(info.branches).toEqual([{ name: 'mine', remote: false }, { name: 'release', remote: false }, { name: 'origin/main', remote: true }, { name: 'origin/release', remote: true }]);
    expect(info.fetchedAt).toBeGreaterThan(Date.now() - 60_000);
    git(clone, 'remote', 'set-url', 'origin', 'https://gitlab.com/acme/app.git');
    expect((await inspectFolder(realGit, realpathSync(clone))).repo).toBeNull();
  });

  test('a fetch brings a branch pushed to a local origin into branches and moves fetchedAt', async () => {
    const bare = join(dir, 'fetch-origin.git');
    git(dir, 'clone', '-q', '--bare', repoAt('fetch-src'), bare);
    const clone = join(dir, 'fetch-clone');
    git(dir, 'clone', '-q', bare, clone);
    const folder = realpathSync(clone);
    const before = await inspectFolder(realGit, folder);
    expect(before.branches.map((branch) => branch.name)).not.toContain('origin/pushed');
    const other = join(dir, 'fetch-other');
    git(dir, 'clone', '-q', bare, other);
    git(other, 'push', '-q', 'origin', 'main:pushed');
    await new Promise((done) => setTimeout(done, 20)); // FETCH_HEAD is stamped in ms
    const after = await fetchFolder(realGit, folder);
    expect(after.branches).toContainEqual({ name: 'origin/pushed', remote: true });
    expect(after.fetchedAt).toBeGreaterThan(before.fetchedAt ?? 0);
    git(other, 'push', '-q', 'origin', '--delete', 'pushed');
    expect((await fetchFolder(realGit, folder)).branches).not.toContainEqual({ name: 'origin/pushed', remote: true }); // --prune
  });

  test('a fetch refuses a folder that is not a repository and a repository with no origin', async () => {
    const plain = join(dir, 'fetch-plain');
    mkdirSync(plain);
    await expect(fetchFolder(realGit, plain)).rejects.toThrow('not a git repository');
    await expect(fetchFolder(realGit, repoAt('fetch-local'))).rejects.toThrow('no origin');
  });

  test('a detached HEAD has no branch', async () => {
    const repo = repoAt('detached');
    git(repo, 'checkout', '-q', '--detach');
    expect(await inspectFolder(realGit, repo)).toMatchObject({ git: true, branch: null, branches: [{ name: 'main', remote: false }] });
  });

  test('a bare repository is bare, has no work tree to be dirty and is not a linked worktree', async () => {
    const bare = join(dir, 'just-bare.git');
    git(dir, 'clone', '-q', '--bare', repoAt('bare-src'), bare);
    expect(await inspectFolder(realGit, realpathSync(bare))).toMatchObject({ git: true, bare: true, linkedWorktree: false, branch: 'main', dirty: 0, branches: [{ name: 'main', remote: false }] });
  });

  test('a linked worktree as the folder says so, on its own branch', async () => {
    const repo = repoAt('main-checkout');
    const linked = join(dir, 'linked');
    git(repo, 'worktree', 'add', '-q', '-b', 'side', linked);
    expect(await inspectFolder(realGit, realpathSync(linked))).toMatchObject({ git: true, linkedWorktree: true, branch: 'side' });
    expect((await inspectFolder(realGit, repo)).linkedWorktree).toBe(false);
  });

  test('an untracked file and a modified file are two in dirty, and a folder inside the repository is still the repository', async () => {
    const repo = repoAt('dirty');
    writeFileSync(join(repo, 'a.txt'), 'changed\n');
    writeFileSync(join(repo, 'new.txt'), 'new\n');
    expect((await inspectFolder(realGit, repo)).dirty).toBe(2);
    mkdirSync(join(repo, 'sub'));
    expect(await inspectFolder(realGit, join(repo, 'sub'))).toMatchObject({ git: true, dirty: 2 });
  });

  test('a folder name with spaces and a dash goes to git as one argument', async () => {
    const path = join(dir, '-odd name; echo hi');
    mkdirSync(path);
    git(path, 'init', '-q', '-b', 'main');
    expect(await inspectFolder(realGit, realpathSync(path))).toMatchObject({ git: true, branch: 'main' });
  });
});
