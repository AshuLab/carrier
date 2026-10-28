import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import { realGit } from './git.ts';
import { createProjects } from './projects.ts';
import { ChatRefused } from './runner.ts';
import { createWorktree, removeWorktree } from './worktree.ts';
import { openChatDatabase } from './db.ts';
import { FakeChatRunner } from './fake.ts';
import { createSessions } from './sessions.ts';
import { FakeClock } from '../orchestration/fake.ts';
import type { Config } from '../config/schema.ts';
import { fetchFolder, inspectFolder } from './workspace.ts';

// What the host's `workspace` request finds in real repositories made in temporary folders, with the `git` on this
// machine: a repository with and without a remote, a detached HEAD, a bare repository, a linked worktree as the
// folder, an untracked file and a modified file counted in `dirty`. Nothing leaves the machine: the "remote" is a
// bare repository in a temporary folder, and only its URL is then changed to a GitHub one. It also makes session
// worktrees (from a local and from a remote branch, from a detached HEAD and from a linked worktree), checks that the
// base folder is the same after, that a failure leaves nothing and that removing takes the folder and the branch. It only runs when this is
// set explicitly (it also deletes sessions in worktrees through the host's sessions, with a fake agent, a temporary SQLite and the real git, with the base folder there and gone):
//   CARRIER_IT_GIT=1
// It also clones, fetches and aborts a clone through `cloneRepo`, with the GitHub URLs rewritten to local ones by a git config of its own (no network, no token).
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

describe.skipIf(!enabled)('a session worktree, with the real git', () => {
  let home: string;
  beforeAll(() => void (dir = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-wt-')))));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  beforeEach(() => {
    home = join(dir, `home-${Math.random().toString(36).slice(2)}`);
    vi.stubEnv('CARRIER_HOME', home);
  });
  afterEach(() => void vi.unstubAllEnvs());

  /** Everything the base folder is: HEAD, branch, index, working tree changes and the refs other than the new branch. */
  const snapshot = (folder: string) => ({
    head: git(folder, 'rev-parse', 'HEAD').trim(),
    branch: git(folder, 'branch', '--show-current').trim(),
    index: git(folder, 'ls-files', '-s'),
    status: git(folder, 'status', '--porcelain'),
    refs: git(folder, 'for-each-ref', '--format=%(refname) %(objectname)').split('\n').filter((line) => line.includes('refs/heads/carrier/') === false).join('\n'),
    stash: git(folder, 'stash', 'list'),
  });
  const cloneOf = (name: string) => {
    const bare = join(dir, `${name}.git`);
    git(dir, 'clone', '-q', '--bare', repoAt(`${name}-src`), bare);
    const other = join(dir, `${name}-other`);
    git(dir, 'clone', '-q', bare, other);
    git(other, 'push', '-q', 'origin', 'main:release');
    const clone = join(dir, name);
    git(dir, 'clone', '-q', bare, clone);
    git(clone, 'fetch', '-q', 'origin');
    git(clone, 'remote', 'set-url', 'origin', 'git@github.com:acme/app.git');
    return realpathSync(clone);
  };

  test('from a local and from a remote branch: the folder, the new branch at the right commit, the base untouched, then removed with its branch', async () => {
    const clone = cloneOf('both');
    git(clone, 'checkout', '-q', '-b', 'local-only');
    writeFileSync(join(clone, 'b.txt'), 'b\n');
    git(clone, 'add', '.');
    git(clone, 'commit', '-q', '-m', 'two');
    writeFileSync(join(clone, 'a.txt'), 'dirty\n'); // uncommitted: must survive
    writeFileSync(join(clone, 'untracked.txt'), 'u\n');
    const before = snapshot(clone);

    const fromLocal = await createWorktree(realGit, clone, { from: 'local-only', name: 'one' });
    expect(fromLocal).toEqual({ path: join(home, 'chat', 'worktrees', 'acme', 'app', 'one'), branch: 'carrier/one', from: 'local-only', base: clone });
    expect(git(fromLocal.path, 'branch', '--show-current').trim()).toBe('carrier/one');
    expect(git(clone, 'rev-parse', 'carrier/one').trim()).toBe(before.head);
    expect(git(clone, 'for-each-ref', '--format=%(upstream)', 'refs/heads/carrier/one').trim()).toBe(''); // no upstream

    const fromRemote = await createWorktree(realGit, clone, { from: 'origin/release', name: 'two' });
    expect(git(fromRemote.path, 'branch', '--show-current').trim()).toBe('carrier/two');
    expect(git(clone, 'rev-parse', 'carrier/two').trim()).toBe(git(clone, 'rev-parse', 'origin/release').trim());
    expect(git(clone, 'for-each-ref', '--format=%(upstream)', 'refs/heads/carrier/two').trim()).toBe('');
    expect(snapshot(clone)).toEqual(before);

    await removeWorktree(realGit, fromLocal);
    expect(existsSync(fromLocal.path)).toBe(false);
    expect(git(clone, 'branch', '--list', 'carrier/one').trim()).toBe('');
    expect(git(clone, 'worktree', 'list')).not.toContain(fromLocal.path);
    expect(existsSync(fromRemote.path)).toBe(true); // only the one asked
    expect(snapshot(clone)).toEqual(before);
  });

  test('a name is generated when none is given, and refused when taken by a branch', async () => {
    const repo = repoAt('names');
    git(repo, 'branch', 'carrier/taken');
    const made = await createWorktree(realGit, repo, { from: 'main' });
    expect(made.branch).toMatch(/^carrier\/[a-z]+-[a-z]+-[a-z]+$/);
    expect(made.path).toBe(join(home, 'chat', 'worktrees', 'local', 'names', made.branch.slice('carrier/'.length)));
    await expect(createWorktree(realGit, repo, { from: 'main', name: 'taken' })).rejects.toBeInstanceOf(ChatRefused);
    await expect(createWorktree(realGit, repo, { from: 'dev', name: 'free' })).rejects.toThrow('not one this repository lists');
  });

  test('from a base folder with a detached HEAD, which stays detached', async () => {
    const repo = repoAt('detached-base');
    git(repo, 'checkout', '-q', '--detach');
    const before = snapshot(repo);
    const made = await createWorktree(realGit, repo, { from: 'main', name: 'from-detached' });
    expect(git(made.path, 'branch', '--show-current').trim()).toBe('carrier/from-detached');
    expect(snapshot(repo)).toEqual(before);
    expect(before.branch).toBe('');
  });

  test('from a base folder that is itself a linked worktree', async () => {
    const repo = repoAt('linked-main');
    const linked = join(dir, 'linked-base');
    git(repo, 'worktree', 'add', '-q', '-b', 'side', linked);
    const base = realpathSync(linked);
    const before = snapshot(base);
    const mainBefore = snapshot(repo);
    const made = await createWorktree(realGit, base, { from: 'main', name: 'from-linked' });
    expect(made.base).toBe(base);
    expect(existsSync(made.path)).toBe(true);
    expect(snapshot(base)).toEqual(before);
    expect(snapshot(repo)).toEqual(mainBefore);
  });

  test('a failure of git leaves no folder, no branch and no worktree entry', async () => {
    const repo = repoAt('failing');
    mkdirSync(home, { recursive: true });
    writeFileSync(join(home, 'chat'), 'a file where the folder should go');
    const before = snapshot(repo);
    await expect(createWorktree(realGit, repo, { from: 'main', name: 'doomed' })).rejects.toThrow('Git could not create the worktree');
    expect(git(repo, 'branch', '--list', 'carrier/*').trim()).toBe('');
    expect(git(repo, 'worktree', 'list').trim().split('\n')).toHaveLength(1);
    expect(snapshot(repo)).toEqual(before);
  });

  test('a bare repository and a plain folder are refused', async () => {
    const bare = join(dir, 'refused.git');
    git(dir, 'clone', '-q', '--bare', repoAt('refused-src'), bare);
    await expect(createWorktree(realGit, realpathSync(bare), { from: 'main' })).rejects.toThrow('bare');
    const plain = join(dir, 'refused-plain');
    mkdirSync(plain);
    await expect(createWorktree(realGit, plain, { from: 'main' })).rejects.toThrow('Worktrees need a git repository');
  });
});

describe.skipIf(!enabled)('deleting a session in a worktree, with the real git', () => {
  let home: string;
  beforeAll(() => void (dir = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-del-')))));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  beforeEach(() => {
    home = join(dir, `home-${Math.random().toString(36).slice(2)}`);
    vi.stubEnv('CARRIER_HOME', home);
  });
  afterEach(() => void vi.unstubAllEnvs());

  const sessionsOf = () => createSessions({ db: openChatDatabase(join(home, 'chat.db')), config: { root: join(dir, 'root') } as Config, clock: new FakeClock(), runners: { claude: new FakeChatRunner() }, env: {}, git: realGit, binaryFound: () => true, onLiveChange: () => {} });
  const stateOf = (folder: string) => ({ head: git(folder, 'rev-parse', 'HEAD').trim(), status: git(folder, 'status', '--porcelain'), branches: git(folder, 'branch', '--format=%(refname:short)').split('\n').filter((line) => line.startsWith('carrier/') === false).join('\n') });
  /** A session in a worktree with an uncommitted change, an untracked file and one commit nobody else has. */
  async function session(name: string) {
    const base = repoAt(name);
    mkdirSync(home, { recursive: true });
    const s = sessionsOf();
    const { session: opened } = await s.open({ agent: 'claude', folder: base, worktree: { from: 'main', name: 'work' } });
    const { path, branch } = opened.workspace as { path: string; branch: string };
    writeFileSync(join(path, 'committed.txt'), 'c\n');
    git(path, 'add', 'committed.txt');
    git(path, 'commit', '-q', '-m', 'two');
    writeFileSync(join(path, 'a.txt'), 'changed\n');
    writeFileSync(join(path, 'untracked.txt'), 'u\n');
    return { s, id: opened.id, base: realpathSync(base), path, branch };
  }

  test('the preview counts the changes and the commit, and delete removes the folder and the branch and leaves the base as it was', async () => {
    const { s, id, base, path, branch } = await session('with-base');
    const before = stateOf(base);
    expect(await s.deletePreview({ sessionIds: [id] })).toEqual({ sessions: [{ sessionId: id, worktree: { path, branch, dirty: 2, unpushed: 1 } }] });
    git(path, 'update-ref', `refs/remotes/origin/${branch}`, git(path, 'rev-parse', 'HEAD').trim()); // as if it was pushed: nobody else's any more
    expect((await s.deletePreview({ sessionIds: [id] })).sessions[0]!.worktree).toMatchObject({ dirty: 2, unpushed: 0 });
    git(base, 'update-ref', '-d', `refs/remotes/origin/${branch}`);

    await s.delete({ sessionId: id });
    expect(existsSync(path)).toBe(false);
    expect(git(base, 'branch', '--list', branch).trim()).toBe('');
    expect(git(base, 'worktree', 'list').trim().split('\n')).toHaveLength(1);
    expect(stateOf(base)).toEqual(before);
    expect(s.list({}).sessions).toEqual([]);
  });

  test('with the base folder removed first the files left in the worktree folder are counted, and the folder is removed directly', async () => {
    const { s, id, base, path } = await session('no-base');
    rmSync(base, { recursive: true, force: true });
    // a.txt, committed.txt and untracked.txt: the commit went with the base folder, so only the files are counted
    expect((await s.deletePreview({ sessionIds: [id] })).sessions[0]!.worktree).toMatchObject({ dirty: 3, unpushed: 0 });
    await s.delete({ sessionId: id });
    expect(existsSync(path)).toBe(false);
    expect(s.list({}).sessions).toEqual([]);
  });

  test('two sessions that share a commit: the preview of each counts it, since deleting both loses it', async () => {
    const { s, id, base, branch } = await session('shared');
    const { session: twin } = await s.open({ agent: 'claude', folder: base, worktree: { from: branch, name: 'twin' } });
    expect((await s.deletePreview({ sessionIds: [id, twin.id] })).sessions.map((preview) => preview.worktree?.unpushed)).toEqual([1, 1]);
  });

  test('a branch deleted by hand: the preview counts nothing and does not refuse the batch', async () => {
    const { s, id, base, path, branch } = await session('no-branch');
    git(base, 'worktree', 'remove', '--force', path);
    git(base, 'branch', '-D', branch);
    expect((await s.deletePreview({ sessionIds: [id] })).sessions[0]!.worktree).toMatchObject({ dirty: 0, unpushed: 0 });
    await s.delete({ sessionId: id });
    expect(s.list({}).sessions).toEqual([]);
  });

  test('a worktree folder already deleted by hand is forgotten by git and the branch still goes', async () => {
    const { s, id, base, path, branch } = await session('hand');
    rmSync(path, { recursive: true, force: true });
    await s.delete({ sessionId: id });
    expect(git(base, 'branch', '--list', branch).trim()).toBe('');
    expect(git(base, 'worktree', 'list').trim().split('\n')).toHaveLength(1);
  });
});

describe.skipIf(!enabled)('cloneRepo, with the real git', () => {
  let work: string;
  let previousGlobal: string | undefined;
  beforeAll(() => {
    work = dir = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-clone-'))); // `repoAt` makes its repository in `dir`
    // the "remote" is a bare repository here; git rewrites the GitHub URL the host asks for to it. `ext::` is a transport that never answers, for the abort.
    const source = repoAt('source');
    git(source, 'clone', '-q', '--bare', source, join(work, 'remote.git'));
    writeFileSync(join(work, 'gitconfig'), `[url "${join(work, 'remote.git')}"]\n\tinsteadOf = https://github.com/acme/app.git\n[url "ext::sleep 5"]\n\tinsteadOf = https://github.com/acme/hang.git\n[protocol "ext"]\n\tallow = always\n`);
    previousGlobal = process.env.GIT_CONFIG_GLOBAL;
    process.env.GIT_CONFIG_GLOBAL = join(work, 'gitconfig');
  });
  afterAll(() => {
    if (previousGlobal === undefined) delete process.env.GIT_CONFIG_GLOBAL;
    else process.env.GIT_CONFIG_GLOBAL = previousGlobal;
    rmSync(work, { recursive: true, force: true });
  });
  const projects = () => createProjects({ git: realGit, token: async () => 'unused', config: { root: join(work, 'root'), chat: { projectsFolder: join(work, 'projects') } } as Config });

  test('a real clone lands in <projects>/<owner>/<repo>, and asking again fetches it', async () => {
    const dest = join(work, 'projects', 'acme', 'app');
    expect(await projects().cloneRepo({ repo: 'acme/app' }, new AbortController().signal)).toEqual({ folder: dest, repo: 'acme/app', fetched: false });
    expect(existsSync(join(dest, 'a.txt'))).toBe(true);
    expect(git(dest, 'config', '--get', 'remote.origin.url').trim()).toBe('https://github.com/acme/app.git');
    expect(await projects().cloneRepo({ repo: 'acme/app' }, new AbortController().signal)).toEqual({ folder: dest, repo: 'acme/app', fetched: true });
  });

  test('a real abort stops git and removes the destination this request made', async () => {
    const abort = new AbortController();
    const started = Date.now();
    const cloning = projects().cloneRepo({ repo: 'acme/hang' }, abort.signal);
    await new Promise((resolve) => setTimeout(resolve, 500));
    expect(existsSync(join(work, 'projects', 'acme', 'hang'))).toBe(true);
    abort.abort();
    await expect(cloning).rejects.toThrow(ChatRefused);
    await vi.waitFor(() => expect(existsSync(join(work, 'projects', 'acme', 'hang'))).toBe(false), { timeout: 3000 });
    expect(Date.now() - started).toBeLessThan(4000);
  });

  test('a real createProject makes a repository on main with no commit, and a second one of the same name is refused', async () => {
    const dest = join(work, 'projects', 'local', 'fresh');
    expect(await projects().createProject({ name: 'fresh' })).toEqual({ folder: dest });
    expect(git(dest, 'symbolic-ref', '--short', 'HEAD').trim()).toBe('main');
    expect(git(dest, 'rev-list', '--all').trim()).toBe('');
    await expect(projects().createProject({ name: 'fresh' })).rejects.toThrow(ChatRefused);
    expect(existsSync(join(dest, '.git'))).toBe(true);
  });
});
