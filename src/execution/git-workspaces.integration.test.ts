import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test } from 'vitest';
import { GitWorkspaces, profileToken } from './git-workspaces.ts';
import { enginePlacesOf } from '../config/places.ts';

const git = (cwd: string, ...args: string[]) =>
  execFileSync('git', args, {
    cwd,
    encoding: 'utf8',
    env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' },
  }).trim();

const repo = 'AshuLab/demo';
let tmp: string;
let root: string;
let bare: string;
let work: string;

// A local bare remote stands in for GitHub: `refs/pull/<n>/head` is how GitHub exposes a PR's head.
const commit = (name: string) => {
  writeFileSync(join(work, name), name);
  git(work, 'add', '.');
  git(work, 'commit', '-qm', name);
  return git(work, 'rev-parse', 'HEAD');
};
const openPr = (pr: number, sha: string) => git(work, 'push', '-qf', 'origin', `${sha}:refs/pull/${pr}/head`);

beforeEach(() => {
  tmp = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-ws-')));
  root = join(tmp, 'root');
  bare = join(tmp, 'remote.git');
  work = join(tmp, 'work');
  git(tmp, 'init', '-q', '--bare', '-b', 'main', bare);
  git(tmp, 'clone', '-q', bare, work);
  commit('one');
  git(work, 'push', '-q', 'origin', 'HEAD:main');
});
afterEach(() => rmSync(tmp, { recursive: true, force: true }));

const workspaces = (token?: () => Promise<string>) => new GitWorkspaces({ places: enginePlacesOf(root), remoteUrl: () => bare, token });

describe('GitWorkspaces against a local bare remote', () => {
  test('prepareAuthor clones, then only fetches, and is idempotent', async () => {
    const ws = workspaces();
    const path = await ws.prepareAuthor(repo, 3);
    expect(path).toBe(join(root, 'engine', 'repos', 'AshuLab', 'demo'));
    expect(git(path, 'rev-parse', 'origin/main')).toBe(git(work, 'rev-parse', 'HEAD'));

    const next = commit('two');
    git(work, 'push', '-q', 'origin', 'HEAD:main');
    expect(await ws.prepareAuthor(repo, 3)).toBe(path);
    expect(git(path, 'rev-parse', 'origin/main')).toBe(next);
    // The checked-out branch is not touched: only refs are updated.
    expect(existsSync(join(path, 'two'))).toBe(false);
  });

  test('prepareReviewer checks out the PR head detached, reuses the path and re-points it', async () => {
    const ws = workspaces();
    const first = commit('feature');
    git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/feat/x/epic');
    openPr(7, first);

    const path = await ws.prepareReviewer(repo, 3, 7);
    expect(path).toBe(join(root, 'engine', 'reviews', 'demo', '3'));
    expect(git(path, 'rev-parse', 'HEAD')).toBe(first);
    expect(git(path, 'branch', '--show-current')).toBe('');

    expect(await ws.prepareReviewer(repo, 3, 7)).toBe(path);

    const second = commit('fix');
    openPr(7, second);
    expect(await ws.prepareReviewer(repo, 3, 7)).toBe(path);
    expect(git(path, 'rev-parse', 'HEAD')).toBe(second);
    expect(existsSync(join(path, 'fix'))).toBe(true);

    // Lives outside the author's clone and outside worktrees/, but the clone knows it.
    const clone = await ws.prepareAuthor(repo, 3);
    expect(path.startsWith(clone)).toBe(false);
    expect(git(clone, 'worktree', 'list')).toContain(path);
    expect(git(clone, 'status', '--porcelain')).toBe('');
  });

  test('a reviewer checkout deleted by hand is recreated', async () => {
    const ws = workspaces();
    openPr(7, git(work, 'rev-parse', 'HEAD'));
    const path = await ws.prepareReviewer(repo, 3, 7);
    rmSync(path, { recursive: true });
    expect(await ws.prepareReviewer(repo, 3, 7)).toBe(path);
    expect(existsSync(join(path, 'one'))).toBe(true);
  });

  test('two epics of the same repo in parallel share one clone and get separate reviewer checkouts', async () => {
    const ws = workspaces();
    const sha = git(work, 'rev-parse', 'HEAD');
    openPr(7, sha);
    openPr(8, sha);
    const [a, b, r1, r2] = await Promise.all([
      ws.prepareAuthor(repo, 1),
      ws.prepareAuthor(repo, 2),
      ws.prepareReviewer(repo, 1, 7),
      ws.prepareReviewer(repo, 2, 8),
    ]);
    expect(a).toBe(b);
    expect(new Set([r1, r2, a]).size).toBe(3);
    expect(git(r1, 'rev-parse', 'HEAD')).toBe(sha);
    expect(git(r2, 'rev-parse', 'HEAD')).toBe(sha);
  });

  test('findWorktree reads where a branch is really checked out, from `git worktree list`', async () => {
    const ws = workspaces();
    const clone = await ws.prepareAuthor(repo, 3);
    // What Solve's ship does: the epic branch and a lane get their own worktrees outside the engine folder.
    const epicPath = join(root, 'worktrees', 'demo', 'feature');
    git(clone, 'worktree', 'add', '-q', '-b', 'feat/feature/epic', epicPath, 'origin/main');
    git(clone, 'worktree', 'add', '-q', '-b', 'feat/feature/001-x', join(root, 'worktrees', 'demo', 'feature--lane-1'), 'origin/main');

    expect(await ws.findWorktree(repo, 'feat/feature/epic')).toBe(epicPath);
    expect(await ws.findWorktree(repo, 'feat/feature/001-x')).toBe(join(root, 'worktrees', 'demo', 'feature--lane-1'));
    expect(await ws.findWorktree(repo, 'feat/feature')).toBeNull(); // a prefix is not the branch
    expect(await ws.findWorktree(repo, 'feat/other/epic')).toBeNull();
    git(clone, 'checkout', '-q', '-b', 'feat/inplace/epic');
    expect(await ws.findWorktree(repo, 'feat/inplace/epic')).toBeNull(); // not isolated: the clone is shared, it is nobody's workspace
  });

  test('cleanUp removes the epic worktree, its lanes and its reviewer checkout, and deletes only the local branches on the remote', async () => {
    const ws = workspaces();
    openPr(7, git(work, 'rev-parse', 'HEAD'));
    const clone = await ws.prepareAuthor(repo, 3);
    const review = await ws.prepareReviewer(repo, 3, 7);
    const epicPath = join(root, 'worktrees', 'demo', 'feature');
    git(clone, 'worktree', 'add', '-q', '-b', 'feat/feature/epic', epicPath, 'origin/main');
    git(clone, 'worktree', 'add', '-q', '--detach', `${epicPath}--lane-1`, 'origin/main');
    git(clone, 'worktree', 'add', '-q', '-b', 'feat/feature/001-x', `${epicPath}--lane-2`, 'origin/main');
    writeFileSync(join(`${epicPath}--lane-2`, 'local'), 'only here');
    git(`${epicPath}--lane-2`, 'add', '.');
    git(`${epicPath}--lane-2`, 'commit', '-qm', 'local only'); // never pushed: its branch must stay
    const other = join(root, 'worktrees', 'demo', 'other');
    git(clone, 'worktree', 'add', '-q', '-b', 'feat/other/epic', other, 'origin/main');
    git(clone, 'branch', 'feat/featurex/epic', 'origin/main'); // a sibling prefix, not this epic's

    expect(await ws.cleanUp(repo, 3, 'feat/feature/epic')).toEqual({ kept: ['feat/feature/001-x'] });
    for (const gone of [review, epicPath, `${epicPath}--lane-1`, `${epicPath}--lane-2`]) expect(existsSync(gone)).toBe(false);
    expect(existsSync(other)).toBe(true);
    const branches = git(clone, 'for-each-ref', '--format=%(refname:short)', 'refs/heads/');
    expect(branches).not.toContain('feat/feature/epic');
    expect(branches).toContain('feat/feature/001-x');
    expect(branches).toContain('feat/other/epic');
    expect(branches).toContain('feat/featurex/epic');
    expect(git(clone, 'worktree', 'list')).not.toContain(epicPath + '\n');

    // Again, and for an epic that never had a branch: nothing left to do, nothing fails.
    expect(await ws.cleanUp(repo, 3, 'feat/feature/epic')).toEqual({ kept: ['feat/feature/001-x'] });
    expect(await ws.cleanUp(repo, 4, null)).toEqual({ kept: [] });
  });

  test('cleanUp keeps a worktree with uncommitted files or with commits on no branch, and the branch it has checked out', async () => {
    const ws = workspaces();
    const clone = await ws.prepareAuthor(repo, 3);
    const epicPath = join(root, 'worktrees', 'demo', 'unsaved');
    git(clone, 'worktree', 'add', '-q', '-b', 'feat/unsaved/epic', epicPath, 'origin/main');
    writeFileSync(join(epicPath, 'notes.md'), 'not committed');
    const detached = `${epicPath}--lane-1`;
    git(clone, 'worktree', 'add', '-q', '--detach', detached, 'origin/main');
    writeFileSync(join(detached, 'x'), 'x');
    git(detached, 'add', '.');
    git(detached, 'commit', '-qm', 'on no branch');

    expect(await ws.cleanUp(repo, 3, 'feat/unsaved/epic')).toEqual({ kept: [epicPath, detached, 'feat/unsaved/epic'] });
    for (const path of [epicPath, detached]) expect(existsSync(path)).toBe(true);
  });

  test('the token never reaches a git config, and a failing minting is reported without leaking', async () => {
    const ws = workspaces(async () => 'SECRET-TOKEN-123');
    openPr(7, git(work, 'rev-parse', 'HEAD'));
    const clone = await ws.prepareAuthor(repo, 3);
    const review = await ws.prepareReviewer(repo, 3, 7);
    const configs = [join(clone, '.git', 'config'), ...readdirSync(join(clone, '.git', 'worktrees')).map((d) => join(clone, '.git', 'worktrees', d, 'config.worktree'))];
    for (const file of configs.filter(existsSync)) expect(readFileSync(file, 'utf8')).not.toContain('SECRET');
    expect(readFileSync(join(review, '.git'), 'utf8')).not.toContain('SECRET');
    expect(git(clone, 'remote', 'get-url', 'origin')).toBe(bare);

    await expect(new GitWorkspaces({ places: enginePlacesOf(root), remoteUrl: () => bare, token: async () => Promise.reject(new Error('no token')) }).prepareAuthor(repo, 3)).rejects.toThrow('no token');
  });

  test('rejects malformed input before touching the disk', async () => {
    const ws = workspaces();
    for (const bad of ['demo', '../x', 'a/..', 'a/b/c', 'a b/c', '-x/y/']) await expect(ws.prepareAuthor(bad, 1)).rejects.toThrow();
    await expect(ws.prepareAuthor(repo, 0)).rejects.toThrow('invalid epic');
    await expect(ws.prepareReviewer(repo, 1, -1)).rejects.toThrow('invalid pr');
    expect(existsSync(root)).toBe(false);
  });
});

// Real GitHub through Forge, read only: clone and fetch, no push, no GitHub write. Needs both set explicitly:
//   CARRIER_IT_WS_REPO=owner/name (e.g. AshuLab/agent-forge)  CARRIER_IT_WS_FORGE_AGENT=<agent in the Forge registry>
// The reviewer checkout is at the repo's current commit, so the test needs no PR.
const { CARRIER_IT_WS_REPO: realRepo, CARRIER_IT_WS_FORGE_AGENT: agent } = process.env;
const enabled = Boolean(realRepo && agent);
if (!enabled) console.warn('GitWorkspaces Forge test skipped: set CARRIER_IT_WS_REPO and CARRIER_IT_WS_FORGE_AGENT to run it.');

describe.skipIf(!enabled)('GitWorkspaces against GitHub through Forge', () => {
  test(
    'clones, fetches and checks out a commit without leaving a token behind',
    async () => {
      const real = mkdtempSync(join(tmpdir(), 'carrier-ws-real-'));
      try {
        let sha = '';
        const ws = new GitWorkspaces({
          places: enginePlacesOf(real),
          token: profileToken({ kind: 'forge', agent: agent! }),
          reviewRef: () => sha,
          timeoutMs: 120_000,
        });
        const clone = await ws.prepareAuthor(realRepo!, 1);
        sha = git(clone, 'rev-parse', 'origin/HEAD');
        expect(await ws.prepareAuthor(realRepo!, 1)).toBe(clone);

        const review = await ws.prepareReviewer(realRepo!, 1, 1);
        expect(git(review, 'rev-parse', 'HEAD')).toBe(sha);
        expect(git(clone, 'remote', 'get-url', 'origin')).toBe(`https://github.com/${realRepo}.git`);
        expect(readFileSync(join(clone, '.git', 'config'), 'utf8')).not.toMatch(/extraheader|x-access-token|ghs_/i);
      } finally {
        rmSync(real, { recursive: true, force: true });
      }
    },
    300_000,
  );
});
