import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import { realGit } from './git.ts';
import { createProjects } from './projects.ts';
import { ChatRefused } from './runner.ts';
import { clearWorktree, createWorktree, previewWorktree, removeWorktree, restoreWorktree } from './worktree.ts';
import { openChatDatabase } from './db.ts';
import { loadChatConfig } from './config.ts';
import { FakeChatRunner, fakeProjects } from './fake.ts';
import { createSessions } from './sessions.ts';
import { sessions } from './schema.ts';
import { eq } from 'drizzle-orm';
import { FakeClock } from '../orchestration/fake.ts';
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
    expect(info.branches).toEqual([{ name: 'mine', remote: false }, { name: 'release', remote: false, ahead: 0, behind: 0 }, { name: 'origin/main', remote: true }, { name: 'origin/release', remote: true }]);
    expect(info.fetchedAt).toBeGreaterThan(Date.now() - 60_000);
    git(clone, 'checkout', '-q', 'release');
    git(clone, 'commit', '-q', '--allow-empty', '-m', 'local only');
    git(origin, 'commit', '-q', '--allow-empty', '-m', 'remote one');
    git(origin, 'commit', '-q', '--allow-empty', '-m', 'remote two');
    git(bare, 'fetch', '-q', origin, 'release:release'); // the origin the clone follows moves two ahead
    git(clone, 'fetch', '-q', bare, '+release:refs/remotes/origin/release'); // by path: `origin` is a GitHub URL by now
    expect((await inspectFolder(realGit, realpathSync(clone))).branches).toContainEqual({ name: 'release', remote: false, ahead: 1, behind: 2 });
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

  test('the cleanup removes only the folder, ignored files with it, and the folder comes back on the same branch with its commits', async () => {
    const repo = repoAt('cleaned');
    writeFileSync(join(repo, '.gitignore'), 'build/\n');
    git(repo, 'add', '.');
    git(repo, 'commit', '-q', '-m', 'ignore');
    const made = await createWorktree(realGit, repo, { from: 'main', name: 'cleaned' });
    writeFileSync(join(made.path, 'work.txt'), 'w\n');
    git(made.path, 'add', '.');
    git(made.path, 'commit', '-q', '-m', 'work');
    const tip = git(made.path, 'rev-parse', 'HEAD').trim();
    mkdirSync(join(made.path, 'build'));
    writeFileSync(join(made.path, 'build', 'big.bin'), 'x'); // ignored: not uncommitted work, goes with the folder
    expect(await previewWorktree(realGit, made, [made.branch])).toMatchObject({ dirty: 0 });

    await clearWorktree(realGit, made);
    expect(existsSync(made.path)).toBe(false);
    expect(git(repo, 'rev-parse', made.branch).trim()).toBe(tip);

    await restoreWorktree(realGit, made);
    expect(git(made.path, 'branch', '--show-current').trim()).toBe(made.branch);
    expect(readFileSync(join(made.path, 'work.txt'), 'utf8')).toBe('w\n');
    expect(existsSync(join(made.path, 'build'))).toBe(false);
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

  test('with a local main behind origin/main a remote start begins at origin/main\'s tip and a local start at the local main', async () => {
    const clone = cloneOf('behind');
    const other = join(dir, 'behind-other');
    writeFileSync(join(other, 'newer.txt'), 'n\n');
    git(other, 'add', '.');
    git(other, 'commit', '-q', '-m', 'landed on origin');
    git(other, 'push', '-q', 'origin', 'main');
    git(clone, 'fetch', '-q', join(dir, 'behind.git'), '+refs/heads/*:refs/remotes/origin/*'); // the clone's origin URL is a GitHub one: fetch from the bare repository itself
    const stale = git(clone, 'rev-parse', 'main').trim();
    const tip = git(clone, 'rev-parse', 'origin/main').trim();
    expect(tip).not.toBe(stale);

    const fromRemote = await createWorktree(realGit, clone, { from: 'main', name: 'fresh', startFrom: 'remote' });
    expect(fromRemote.from).toBe('origin/main');
    expect(git(fromRemote.path, 'rev-parse', 'HEAD').trim()).toBe(tip);
    expect(git(clone, 'for-each-ref', '--format=%(upstream)', 'refs/heads/carrier/fresh').trim()).toBe('');
    const fromLocal = await createWorktree(realGit, clone, { from: 'main', name: 'stale', startFrom: 'local' });
    expect(git(fromLocal.path, 'rev-parse', 'HEAD').trim()).toBe(stale);
    expect(git(clone, 'rev-parse', 'main').trim()).toBe(stale); // the local main is never moved
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

  const sessionsOf = () => createSessions({ db: openChatDatabase(join(home, 'chat.db')), agents: [{ name: 'claude', account: 'claude' }], clock: new FakeClock(), runners: { claude: new FakeChatRunner() }, env: {}, git: realGit, projects: fakeProjects(realGit), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
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

  test('the default clock pass takes the folder of a session archived and idle 14 days, with its ignored build, and keeps the branch, the unpushed commit and the session; resuming brings the folder back', async () => {
    const base = repoAt('clock-clean');
    writeFileSync(join(base, '.gitignore'), 'build/\n');
    git(base, 'add', '.');
    git(base, 'commit', '-q', '-m', 'ignore');
    mkdirSync(home, { recursive: true });
    const clock = new FakeClock();
    const s = createSessions({ db: openChatDatabase(join(home, 'chat.db')), agents: [{ name: 'claude', account: 'claude' }], clock, runners: { claude: new FakeChatRunner() }, env: {}, git: realGit, projects: fakeProjects(realGit), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
    const { session: opened } = await s.open({ agent: 'claude', folder: base, worktree: { from: 'main', name: 'parked' } });
    const { path, branch } = opened.workspace as { path: string; branch: string };
    writeFileSync(join(path, 'work.txt'), 'w\n');
    git(path, 'add', '.');
    git(path, 'commit', '-q', '-m', 'work'); // on no remote
    const tip = git(path, 'rev-parse', 'HEAD').trim();
    mkdirSync(join(path, 'build'));
    writeFileSync(join(path, 'build', 'big.bin'), 'x'.repeat(100_000));
    await s.close({ sessionId: opened.id });
    await s.archive({ sessionId: opened.id, archived: true });
    const settings = loadChatConfig({});
    if (settings.ok === false) throw new Error('the defaults load');

    clock.time += 13 * 24 * 60 * 60_000;
    await s.applyClock(settings.settings);
    expect(existsSync(path)).toBe(true); // 13 days: not yet
    clock.time += 24 * 60 * 60_000;
    await s.applyClock(settings.settings);
    expect(existsSync(path)).toBe(false);
    expect(git(base, 'rev-parse', branch).trim()).toBe(tip);
    expect(s.list({ archived: true }).sessions.map((one) => one.id)).toEqual([opened.id]);

    await s.resume({ sessionId: opened.id });
    expect(git(path, 'branch', '--show-current').trim()).toBe(branch);
    expect(readFileSync(join(path, 'work.txt'), 'utf8')).toBe('w\n');
    expect(existsSync(join(path, 'build'))).toBe(false);
  });

  test('the clock pass keeps the folder when the worktree HEAD is detached with a commit or mid-rebase, and cleans one on another branch, whose commit the shared clone keeps', async () => {
    const base = repoAt('clock-head');
    mkdirSync(home, { recursive: true });
    const clock = new FakeClock();
    const s = createSessions({ db: openChatDatabase(join(home, 'chat.db')), agents: [{ name: 'claude', account: 'claude' }], clock, runners: { claude: new FakeChatRunner() }, env: {}, git: realGit, projects: fakeProjects(realGit), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
    const parked = async (name: string) => {
      const { session } = await s.open({ agent: 'claude', folder: base, worktree: { from: 'main', name } });
      await s.close({ sessionId: session.id });
      await s.archive({ sessionId: session.id, archived: true });
      return session.workspace as { path: string; branch: string };
    };
    const commit = (path: string, file: string, text: string) => {
      writeFileSync(join(path, file), text);
      git(path, 'add', '.');
      git(path, 'commit', '-q', '-m', `edit ${file}`);
      return git(path, 'rev-parse', 'HEAD').trim();
    };
    const detached = await parked('detached');
    git(detached.path, 'switch', '-q', '--detach');
    const lost = commit(detached.path, 'only-here.txt', 'x\n'); // held by no branch
    const aside = await parked('aside');
    git(aside.path, 'switch', '-q', '-c', 'other');
    const onOther = commit(aside.path, 'other.txt', 'x\n');
    const rebasing = await parked('rebasing');
    commit(rebasing.path, 'README.md', 'mine\n');
    commit(base, 'README.md', 'theirs\n'); // main moves on the same line
    expect(() => git(rebasing.path, 'rebase', 'main')).toThrow(); // stops on the conflict
    const settled = await parked('settled'); // control: on its branch, nothing to keep
    const settings = loadChatConfig({});
    if (settings.ok === false) throw new Error('the defaults load');

    clock.time += 14 * 24 * 60 * 60_000;
    await s.applyClock(settings.settings);
    expect([detached, aside, rebasing, settled].map((w) => existsSync(w.path))).toEqual([true, false, true, false]);
    expect(git(detached.path, 'rev-parse', 'HEAD').trim()).toBe(lost);
    expect(git(base, 'rev-parse', 'other').trim()).toBe(onOther); // the branch lives in the clone, not in the removed folder
  });

  /** A host over the real git with a clock of its own, and sessions parked (closed and archived) in worktrees of `base`; `pass` is the clock's cleanup 14 days later, with the default settings. */
  const parkedHost = (base: string) => {
    mkdirSync(home, { recursive: true });
    const clock = new FakeClock();
    const s = createSessions({ db: openChatDatabase(join(home, 'chat.db')), agents: [{ name: 'claude', account: 'claude' }], clock, runners: { claude: new FakeChatRunner() }, env: {}, git: realGit, projects: fakeProjects(realGit), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
    const parked = async (name: string) => {
      const { session } = await s.open({ agent: 'claude', folder: base, worktree: { from: 'main', name } });
      await s.close({ sessionId: session.id });
      await s.archive({ sessionId: session.id, archived: true });
      return { id: session.id, ...(session.workspace as { path: string; branch: string }) };
    };
    const pass = async () => {
      const settings = loadChatConfig({});
      if (settings.ok === false) throw new Error('the defaults load');
      clock.time += 14 * 24 * 60 * 60_000;
      await s.applyClock(settings.settings);
    };
    return { s, parked, pass };
  };
  const commitIn = (path: string, file: string, text: string) => {
    writeFileSync(join(path, file), text);
    git(path, 'add', '.');
    git(path, 'commit', '-q', '-m', `edit ${file}`);
    return git(path, 'rev-parse', 'HEAD').trim();
  };

  test('the clock pass keeps a worktree whose submodule holds a commit no branch has, though its status is clean', async () => {
    const base = repoAt('clock-sub');
    const source = repoAt('sub-source');
    const { parked, pass } = parkedHost(base);
    const subbed = await parked('subbed');
    const plain = await parked('plain'); // control
    git(subbed.path, '-c', 'protocol.file.allow=always', 'submodule', 'add', '-q', source, 'sub');
    git(subbed.path, 'commit', '-q', '-m', 'add the submodule');
    const inside = commitIn(join(subbed.path, 'sub'), 'inside.txt', 'x\n'); // in the submodule's git dir, which lives in the worktree's own
    git(subbed.path, 'add', 'sub');
    git(subbed.path, 'commit', '-q', '-m', 'move the pointer');
    expect(git(subbed.path, 'status', '--porcelain')).toBe('');
    await pass();
    expect([subbed, plain].map((w) => existsSync(w.path))).toEqual([true, false]);
    expect(git(join(subbed.path, 'sub'), 'rev-parse', 'HEAD').trim()).toBe(inside);
  });

  test('the clock pass keeps a worktree with changes git is told not to see, and one whose git config hides untracked files', async () => {
    const base = repoAt('clock-shadow');
    const { parked, pass } = parkedHost(base);
    const assumed = await parked('assumed');
    const skipped = await parked('skipped');
    const hidden = await parked('hidden');
    const settled = await parked('settled'); // control
    for (const [w, flag] of [[assumed, '--assume-unchanged'], [skipped, '--skip-worktree']] as const) {
      git(w.path, 'update-index', flag, 'a.txt');
      writeFileSync(join(w.path, 'a.txt'), 'only here\n');
      expect(git(w.path, 'status', '--porcelain')).toBe('');
    }
    git(hidden.path, 'config', 'status.showUntrackedFiles', 'no');
    writeFileSync(join(hidden.path, 'notes.md'), 'only here\n');
    expect(git(hidden.path, 'status', '--porcelain')).toBe('');
    await pass();
    expect([assumed, skipped, hidden, settled].map((w) => existsSync(w.path))).toEqual([true, true, true, false]);
    expect(readFileSync(join(assumed.path, 'a.txt'), 'utf8')).toBe('only here\n');
  });

  test('the clock pass keeps a worktree with a commit made on a detached HEAD and then switched back to its branch, and not one whose commits were only amended or rebased', async () => {
    const base = repoAt('clock-dangling');
    const { parked, pass } = parkedHost(base);
    const dangling = await parked('dangling');
    git(dangling.path, 'switch', '-q', '--detach');
    const lost = commitIn(dangling.path, 'only-here.txt', 'x\n');
    git(dangling.path, 'switch', '-q', dangling.branch);
    expect(git(dangling.path, 'status', '--porcelain')).toBe('');
    const rewritten = await parked('rewritten'); // a commit amended and one rebased away: their old versions are in the reflog and held by no branch
    commitIn(rewritten.path, 'one.txt', '1\n');
    git(rewritten.path, 'commit', '-q', '--amend', '-m', 'amended');
    commitIn(rewritten.path, 'two.txt', '2\n');
    commitIn(base, 'moved.txt', 'm\n');
    git(rewritten.path, 'rebase', '-q', 'main');
    const pushed = await parked('pushed'); // a detached commit that a branch holds is safe
    git(pushed.path, 'switch', '-q', '--detach');
    commitIn(pushed.path, 'kept.txt', 'x\n');
    git(pushed.path, 'branch', 'saved');
    git(pushed.path, 'switch', '-q', pushed.branch);
    await pass();
    expect([dangling, rewritten, pushed].map((w) => existsSync(w.path))).toEqual([true, false, false]);
    expect(git(dangling.path, 'cat-file', '-t', lost).trim()).toBe('commit');
  });

  test('a commit made detached and left behind is still found under a long reflog, with no window on it', async () => {
    const base = repoAt('clock-long-reflog');
    const { parked, pass } = parkedHost(base);
    const buried = await parked('buried');
    git(buried.path, 'switch', '-q', '--detach');
    const lost = commitIn(buried.path, 'only-here.txt', 'x\n');
    git(buried.path, 'switch', '-q', buried.branch);
    // 1,100 later entries of HEAD's reflog, written the way git does, so the commit is far from its top
    const log = join(git(buried.path, 'rev-parse', '--absolute-git-dir').trim(), 'logs', 'HEAD');
    const tip = git(buried.path, 'rev-parse', 'HEAD').trim();
    appendFileSync(log, Array.from({ length: 1100 }, () => `${tip} ${tip} Carrier <c@example.com> 1700000000 +0000\tcheckout: moving from a to b\n`).join(''));
    await pass();
    expect(existsSync(buried.path)).toBe(true);
    expect(git(buried.path, 'cat-file', '-t', lost).trim()).toBe('commit');
  });

  test('a folder git cannot read, with no .git or a .git that is a dangling link, is kept with all its files, and a good one beside it is cleaned', async () => {
    const base = repoAt('clock-half');
    const { parked, pass } = parkedHost(base);
    const none = await parked('none');
    const dangling = await parked('dangling-link');
    const good = await parked('good');
    for (const w of [none, dangling]) writeFileSync(join(w.path, 'mine.txt'), 'm');
    rmSync(join(none.path, '.git'));
    rmSync(join(dangling.path, '.git'));
    symlinkSync(join(dir, 'nowhere'), join(dangling.path, '.git'));
    await pass();
    expect([none, dangling, good].map((w) => existsSync(w.path))).toEqual([true, true, false]);
    expect([none, dangling].map((w) => readFileSync(join(w.path, 'mine.txt'), 'utf8'))).toEqual(['m', 'm']);
    expect(git(base, 'worktree', 'list').trim().split('\n')).toHaveLength(3); // registrations stay: the fix is by hand
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

describe.skipIf(!enabled)('the worktrees of a project, with the real git', () => {
  let home: string;
  beforeAll(() => void (dir = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-pw-')))));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  beforeEach(() => {
    home = join(dir, `home-${Math.random().toString(36).slice(2)}`);
    mkdirSync(home, { recursive: true });
    vi.stubEnv('CARRIER_HOME', home);
  });
  afterEach(() => void vi.unstubAllEnvs());

  const db = () => openChatDatabase(join(home, 'chat.db'));
  const sessionsOf = (chatDb = db()) => createSessions({ db: chatDb, agents: [{ name: 'claude', account: 'claude' }], clock: new FakeClock(), runners: { claude: new FakeChatRunner() }, env: {}, git: realGit, projects: fakeProjects(realGit), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });

  test('lists the main clone and each worktree under the worktrees folder, joined to its session, with each state, an orphan and a vanished folder left out', async () => {
    const chatDb = db();
    const s = sessionsOf(chatDb);
    const base = repoAt('project');
    const open = async (name: string, { live = false } = {}) => {
      const { session } = await s.open({ agent: 'claude', folder: base, worktree: { from: 'main', name } });
      if (live === false) await s.close({ sessionId: session.id });
      return { id: session.id, ...(session.workspace as { path: string; branch: string }) };
    };
    const [clean, pushed, ahead, dirty, merged, orphan, gone] = [await open('clean'), await open('pushed'), await open('ahead'), await open('dirty'), await open('merged'), await open('orphan'), await open('gone')];
    const live = await open('live', { live: true });
    git(pushed.path, 'commit', '-q', '--allow-empty', '-m', 'pushed');
    git(pushed.path, 'update-ref', `refs/remotes/origin/${pushed.branch}`, git(pushed.path, 'rev-parse', 'HEAD').trim());
    git(ahead.path, 'commit', '-q', '--allow-empty', '-m', 'mine'); // a commit no other branch holds
    writeFileSync(join(dirty.path, 'a.txt'), 'changed\n');
    git(merged.path, 'commit', '-q', '--allow-empty', '-m', 'squashed on GitHub'); // not on any remote branch either, but its pull request is merged
    chatDb.update(sessions).set({ prState: 'merged' }).where(eq(sessions.id, merged.id)).run();
    chatDb.delete(sessions).where(eq(sessions.id, orphan.id)).run();
    git(orphan.path, 'checkout', '-q', '--detach'); // no branch to hold commits: only its files count
    rmSync(gone.path, { recursive: true, force: true }); // git still lists the folder until it prunes
    git(base, 'worktree', 'add', '-q', '-b', 'mine', join(dir, `elsewhere-${Math.random().toString(36).slice(2)}`)); // a worktree git lists that is not under the worktrees folder

    const { main, worktrees } = await s.projectWorktrees({ folder: base });
    const found = Object.fromEntries(worktrees.map((entry) => [entry.path, entry]));
    // the project's only commit is held by a remote branch (the pushed worktree's)
    expect(main).toEqual({ path: realpathSync(base), branch: 'main', state: 'clean' });
    expect(Object.keys(found).sort()).toEqual([clean, pushed, ahead, dirty, merged, live, orphan].map((entry) => entry.path).sort());
    expect(found[clean.path]).toMatchObject({ branch: clean.branch, session: { id: clean.id }, state: 'clean' });
    expect(found[pushed.path]).toMatchObject({ state: 'clean' });
    expect(found[ahead.path]).toMatchObject({ state: 'notPushed' });
    expect(found[dirty.path]).toMatchObject({ state: 'uncommitted' });
    expect(found[merged.path]).toMatchObject({ state: 'merged' });
    expect(found[live.path]).toMatchObject({ state: 'sessionOpen' });
    // an orphan has no session, and its age is the folder's modification time
    expect(found[orphan.path]).toMatchObject({ branch: null, session: null, state: 'clean', lastActiveAt: statSync(orphan.path).mtimeMs });
    // with a session the age is its last activity
    expect(found[clean.path]!.lastActiveAt).toBe(chatDb.select().from(sessions).where(eq(sessions.id, clean.id)).get()!.lastActiveAt);
    // the main clone: a commit no remote holds is not pushed, a changed file is uncommitted (and wins over it)
    git(base, 'commit', '-q', '--allow-empty', '-m', 'local only');
    expect((await s.projectWorktrees({ folder: base })).main.state).toBe('notPushed');
    writeFileSync(join(base, 'a.txt'), 'changed\n');
    expect((await s.projectWorktrees({ folder: base })).main.state).toBe('uncommitted');
  });

  /** A project with one session per name, each in its own worktree and closed unless `live`. */
  const projectWith = async (names: string[], live: string[] = []) => {
    const chatDb = db();
    const s = sessionsOf(chatDb);
    const base = repoAt(`project-${Math.random().toString(36).slice(2)}`);
    const made: Record<string, { id: string; path: string; branch: string }> = {};
    for (const name of names) {
      const { session } = await s.open({ agent: 'claude', folder: base, worktree: { from: 'main', name } });
      if (live.includes(name) === false) await s.close({ sessionId: session.id });
      made[name] = { id: session.id, ...(session.workspace as { path: string; branch: string }) };
    }
    return { chatDb, s, base, made };
  };
  const merge = (chatDb: ReturnType<typeof db>, id: string) => chatDb.update(sessions).set({ prState: 'merged' }).where(eq(sessions.id, id)).run();

  test('removing a worktree takes only its folder (ignored files too): the branch and its commits and the session stay, and the next message of the session brings the folder back', async () => {
    const { chatDb, s, base, made } = await projectWith(['gone-soon']);
    const { id, path, branch } = made['gone-soon']!;
    writeFileSync(join(path, 'work.txt'), 'w\n');
    git(path, 'add', '.');
    git(path, 'commit', '-q', '-m', 'work');
    const tip = git(path, 'rev-parse', 'HEAD').trim();
    mkdirSync(join(path, 'node_modules'));
    writeFileSync(join(path, 'node_modules', 'big.bin'), 'x'); // untracked but ignored through info/exclude below
    writeFileSync(join(base, '.git', 'info', 'exclude'), 'node_modules/\n');

    await s.removeProjectWorktree({ folder: base, path });
    expect(existsSync(path)).toBe(false);
    expect(git(base, 'rev-parse', branch).trim()).toBe(tip);
    expect(chatDb.select().from(sessions).where(eq(sessions.id, id)).get()).toMatchObject({ worktreePath: path, worktreeBranch: branch });
    expect((await s.projectWorktrees({ folder: base })).worktrees).toEqual([]);

    await s.resume({ sessionId: id });
    expect(git(path, 'branch', '--show-current').trim()).toBe(branch);
    expect(readFileSync(join(path, 'work.txt'), 'utf8')).toBe('w\n');
    expect(existsSync(join(path, 'node_modules'))).toBe(false);
  });

  test('removing is refused with its reason for a worktree whose session is open, one with uncommitted changes and one the project does not list, and nothing is touched', async () => {
    const { s, base, made } = await projectWith(['open', 'dirty', 'fine'], ['open']);
    writeFileSync(join(made['dirty']!.path, 'a.txt'), 'changed\n');
    await expect(s.removeProjectWorktree({ folder: base, path: made['open']!.path })).rejects.toThrow('Its session is open');
    await expect(s.removeProjectWorktree({ folder: base, path: made['dirty']!.path })).rejects.toThrow('It has uncommitted changes');
    await expect(s.removeProjectWorktree({ folder: base, path: join(dir, 'not-listed') })).rejects.toThrow('That is not a worktree of this project');
    expect([made['open'], made['dirty']].map((entry) => existsSync(entry!.path))).toEqual([true, true]);
    expect(readFileSync(join(made['dirty']!.path, 'a.txt'), 'utf8')).toBe('changed\n');
    // what is not blocked goes by hand, merged or not
    await s.removeProjectWorktree({ folder: base, path: made['fine']!.path });
    expect(existsSync(made['fine']!.path)).toBe(false);
  });

  test('a worktree with no session can be removed by hand, and is never in the clean-up', async () => {
    const { chatDb, s, base, made } = await projectWith(['orphan']);
    chatDb.delete(sessions).where(eq(sessions.id, made['orphan']!.id)).run();
    expect(await s.cleanProjectWorktrees({ folder: base, run: true })).toEqual({ removed: [], skipped: [] });
    expect(existsSync(made['orphan']!.path)).toBe(true);
    await s.removeProjectWorktree({ folder: base, path: made['orphan']!.path });
    expect(existsSync(made['orphan']!.path)).toBe(false);
    expect(git(base, 'branch', '--list', made['orphan']!.branch).trim()).toBe(made['orphan']!.branch);
  });

  test('the clean-up lists the merged worktrees nothing blocks with their size and the blocked ones with the reason, and removing takes the first only', async () => {
    const { chatDb, s, base, made } = await projectWith(['done', 'done-too', 'busy', 'wip', 'unmerged'], ['busy']);
    writeFileSync(join(base, '.git', 'info', 'exclude'), '*.bin\n');
    writeFileSync(join(made['done']!.path, 'big.bin'), 'x'.repeat(100_000)); // ignored: not uncommitted work
    writeFileSync(join(made['wip']!.path, 'a.txt'), 'changed\n');
    for (const name of ['done', 'done-too', 'busy', 'wip']) merge(chatDb, made[name]!.id);

    const preview = await s.cleanProjectWorktrees({ folder: base, run: false });
    expect(preview.removed.map((entry) => entry.path).sort()).toEqual([made['done']!.path, made['done-too']!.path].sort());
    expect(preview.removed.find((entry) => entry.path === made['done']!.path)!.bytes).toBeGreaterThanOrEqual(100_000);
    expect(preview.skipped.sort((a, b) => a.path.localeCompare(b.path))).toEqual([{ path: made['busy']!.path, reason: 'Its session is open', code: 'worktree.sessionOpen', params: {} }, { path: made['wip']!.path, reason: 'It has uncommitted changes', code: 'worktree.uncommitted', params: {} }].sort((a, b) => a.path.localeCompare(b.path)));
    expect(Object.values(made).every((entry) => existsSync(entry.path))).toBe(true); // a preview removes nothing

    expect(await s.cleanProjectWorktrees({ folder: base, run: true })).toEqual(preview);
    expect(Object.fromEntries(Object.entries(made).map(([name, entry]) => [name, existsSync(entry.path)]))).toEqual({ done: false, 'done-too': false, busy: true, wip: true, unmerged: true });
    // the branches and the sessions stay
    expect(git(base, 'branch', '--list', 'carrier/done*').trim().split('\n').map((line) => line.trim()).sort()).toEqual(['carrier/done', 'carrier/done-too']);
    expect(chatDb.select().from(sessions).where(eq(sessions.id, made['done']!.id)).get()).toBeDefined();
  });

  test('a folder that is not a repository is refused in words', async () => {
    const plain = join(dir, 'plain-pw');
    mkdirSync(plain);
    await expect(sessionsOf().projectWorktrees({ folder: plain })).rejects.toThrow('Git could not list the worktrees of this folder');
  });
});

describe.skipIf(!enabled)('sshHost, with the real ssh', () => {
  test('a host answers with what ssh -G resolves it to, and a name ssh does not know or takes for an option answers with itself', async () => {
    expect(await realGit.sshHost('github.com')).toBe('github.com');
    expect(await realGit.sshHost('no-such-alias.invalid')).toBe('no-such-alias.invalid');
    expect(await realGit.sshHost('-oProxyCommand=x')).toBe('-oProxyCommand=x');
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
    // the projects folder is read from the chat's own config in the Carrier folder
    vi.stubEnv('CARRIER_HOME', join(work, 'home'));
    mkdirSync(join(work, 'home', 'chat'), { recursive: true });
    writeFileSync(join(work, 'home', 'chat.json'), JSON.stringify({ projectsFolder: join(work, 'projects') }));
  });
  afterAll(() => {
    vi.unstubAllEnvs();
    if (previousGlobal === undefined) delete process.env.GIT_CONFIG_GLOBAL;
    else process.env.GIT_CONFIG_GLOBAL = previousGlobal;
    rmSync(work, { recursive: true, force: true });
  });
  const projects = () => createProjects({ git: realGit, token: async () => 'unused', github: { repos: async () => ({ repos: [], hasMore: false }), login: async () => 'unused', branches: async () => ({ default: 'main', branches: [], hasMore: false }) }, clock: new FakeClock() });

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
    await expect(cloning).rejects.toThrow(new ChatRefused('project.cancelled', 'The clone was cancelled', { step: 'clone' }));
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
