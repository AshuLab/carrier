import { describe, expect, test } from 'vitest';
import { FakeGit } from './fake.ts';
import { countPorcelain, inspectFolder, parseBranches, parseDefaultBranch, parseOrigin } from './workspace.ts';

describe('parseOrigin', () => {
  test.each([
    ['https://github.com/acme/app.git', 'acme', 'app'],
    ['https://github.com/acme/app', 'acme', 'app'],
    ['https://github.com/acme/app/', 'acme', 'app'],
    ['https://x-access-token:secret@github.com/acme/app.git', 'acme', 'app'],
    ['git@github.com:acme/app.git', 'acme', 'app'],
    ['git@github.com:acme/app', 'acme', 'app'],
    ['ssh://git@github.com/acme/app.git', 'acme', 'app'],
    ['https://github.com/acme/my.dotted-repo_2.git', 'acme', 'my.dotted-repo_2'],
    ['https://github.com/acme/.github', 'acme', '.github'],
    ['HTTPS://GitHub.com/Acme/App\n', 'Acme', 'App'],
  ])('%s', (url, owner, name) => expect(parseOrigin(url)).toEqual({ owner, name }));

  test.each(['https://gitlab.com/acme/app.git', 'git@gitlab.com:acme/app.git', 'https://github.com.evil.io/acme/app', 'https://evil.io/github.com/acme/app', 'http://github.com/acme/app', '/srv/git/app.git', 'https://github.com/acme', 'https://github.com/acme/app/extra', 'https://github.com/acme/..', ''])('%s is not GitHub', (url) => expect(parseOrigin(url)).toBeNull());
});

test('countPorcelain counts the lines git prints', () => {
  expect(countPorcelain('')).toBe(0);
  expect(countPorcelain(' M a.ts\n?? b.ts\nA  c.ts\n')).toBe(3);
});

describe('parseBranches', () => {
  test('local first, then origin ones as origin/x, origin/HEAD left out, slashes kept', () => {
    const out = 'refs/heads/feat/x\nrefs/heads/main\nrefs/remotes/origin/HEAD\nrefs/remotes/origin/dev\nrefs/remotes/origin/feat/y\n';
    expect(parseBranches(out)).toEqual([
      { name: 'feat/x', remote: false },
      { name: 'main', remote: false },
      { name: 'origin/dev', remote: true },
      { name: 'origin/feat/y', remote: true },
    ]);
  });
  test('a ref of another remote is not listed, and nothing gives nothing', () => {
    expect(parseBranches('refs/remotes/upstream/main\nrefs/tags/v1\n')).toEqual([]);
    expect(parseBranches('')).toEqual([]);
  });
});

describe('parseDefaultBranch', () => {
  const some = (...names: string[]) => names.map((name) => ({ name }));
  test('origin/HEAD wins, whatever it is called', () => expect(parseDefaultBranch('refs/remotes/origin/trunk\n', some('main'))).toBe('trunk'));
  test('without it, main then master, local or on origin', () => {
    expect(parseDefaultBranch(null, some('master', 'main'))).toBe('main');
    expect(parseDefaultBranch(null, some('master'))).toBe('master');
    expect(parseDefaultBranch(null, some('origin/master'))).toBe('master');
  });
  test('else null', () => {
    expect(parseDefaultBranch(null, some('dev'))).toBeNull();
    expect(parseDefaultBranch('refs/remotes/origin/', some())).toBeNull();
  });
});

describe('inspectFolder with the fake git', () => {
  const folder = '/work/app';
  const withRepo = (repo: Parameters<FakeGit['repos']['set']>[1]) => {
    const git = new FakeGit();
    git.repos.set(folder, repo);
    return git;
  };

  test('a repository with no remote and nothing fetched', async () => {
    expect(await inspectFolder(withRepo({ head: 'main', branches: ['main'] }), folder)).toEqual({ folder, git: true, bare: false, linkedWorktree: false, repo: null, branch: 'main', defaultBranch: 'main', dirty: 0, branches: [{ name: 'main', remote: false }], fetchedAt: null });
  });
  test('a detached HEAD has no branch', async () => expect((await inspectFolder(withRepo({ head: null, branches: ['main'] }), folder)).branch).toBeNull());
  test('a remote that is not GitHub gives no repo', async () => expect((await inspectFolder(withRepo({ head: 'main', branches: ['main'], origin: 'https://gitlab.com/acme/app.git' }), folder)).repo).toBeNull());
  test('a linked worktree and a bare repository are told apart, and a bare one is not asked its status', async () => {
    expect((await inspectFolder(withRepo({ head: 'main', branches: ['main'], linked: true }), folder)).linkedWorktree).toBe(true);
    const git = withRepo({ head: 'main', branches: ['main'], bare: true });
    expect(await inspectFolder(git, folder)).toMatchObject({ git: true, bare: true, dirty: 0 });
    expect(git.calls.some((call) => call.args.includes('status'))).toBe(false);
  });
  test('a folder git does not know is a plain one', async () => expect(await inspectFolder(new FakeGit(), folder)).toMatchObject({ git: false, branches: [], dirty: 0 }));
  test('git failing in any other way refuses in words', async () => {
    const git = withRepo({ head: 'main', branches: ['main'] });
    git.failures.set('for-each-ref --format=%(refname) refs/heads refs/remotes/origin', { ok: false, code: 128, stderr: 'fatal: https://user:secret@host broke' });
    const refused = await inspectFolder(git, folder).catch((error: Error) => error);
    expect(refused).toMatchObject({ message: 'Git could not read that folder' });
  });
  test('every command is an array of arguments run in the folder', async () => {
    const git = withRepo({ head: 'main', branches: ['main'] });
    await inspectFolder(git, folder);
    expect(git.calls.length).toBeGreaterThan(0);
    for (const call of git.calls) expect(call.folder).toBe(folder);
  });
});
