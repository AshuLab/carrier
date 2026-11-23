import { existsSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { lstat, readdir } from 'node:fs/promises';
import { isAbsolute, join, resolve, sep } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { Git, GitResult } from './git.ts';
import { realOfNearest } from './folder.ts';
import { BRANCH_PREFIX, invalidReason, repository, worktreePath, worktreesDir } from './names.ts';
import { ChatRefused } from './runner.ts';
import { countPorcelain } from './workspace.ts';

const log = createScopedLogger('chat');

/** What opening a session in a worktree made: the new folder, its branch, the branch it was cut from (a name `workspace` listed) and the base folder. */
export type MadeWorktree = { path: string; branch: string; from: string; base: string };

/** What a checkout of a big repository may take before the host gives up on it. */
const ADD_TIMEOUT_MS = 60_000;

/** What removing a big worktree folder may take: git is not stopped halfway, which leaves a folder with no `.git`. */
const REMOVE_TIMEOUT_MS = 180_000;

/**
 * `startFrom` says which copy of the branch `from` the worktree is cut from: `remote` is `origin/<from>` when the repository lists it (else the local branch,
 * which is all there is for a branch never pushed), `local` is the local branch. A `from` that already carries `origin/`, or no `startFrom`, is the ref `from` names.
 * Creates `<CARRIER_HOME>/chat/worktrees/<owner>/<repo>/<name>` on a new branch `carrier/<name>` cut from that, in the
 * repository of `folder` (already checked, a real path). The base folder is only read: git adds the worktree without a
 * checkout, stash or commit in it. Refuses, with a reason in words, a folder that is not a repository or is bare, a `from`
 * that `workspace` does not list and a name that is invalid or taken. When git fails nothing is left behind.
 * Callers run it one at a time, so what it checked is still true when git adds. `signal` stops the add, and what it made is taken away.
 */
export async function createWorktree(git: Git, folder: string, request: { from: string; name?: string; startFrom?: 'remote' | 'local' }, signal?: AbortSignal): Promise<MadeWorktree> {
  const { info, takenBecause, freeName } = await repository(git, folder);
  const listed = (name: string) => info.branches.find((branch) => branch.name === name);
  const start = request.startFrom === 'remote' && request.from.startsWith('origin/') === false ? (listed(`origin/${request.from}`) ?? listed(request.from)) : listed(request.from);
  if (start === undefined) throw new ChatRefused('The branch to start from is not one this repository lists');
  if (request.name !== undefined) {
    const refusal = invalidReason(request.name) ?? takenBecause(request.name);
    if (refusal !== null) throw new ChatRefused(refusal);
  }
  const name = request.name ?? freeName();
  const made = { path: worktreePath(info, name), branch: `${BRANCH_PREFIX}${name}`, from: start.name, base: folder };
  // What is absent right before the add is what this call may take away if the add fails: a branch or folder that appears in between is someone else's.
  const mine = {
    branch: (await branchExists(git, folder, made.branch)) === false,
    folder: existsSync(made.path) === false,
  };
  // The start point is spelled as a full ref, so it cannot read as an option, and `--no-track` leaves the new branch without an upstream.
  const added = await git.run(folder, ['worktree', 'add', '--no-track', '-b', made.branch, made.path, `${start.remote ? 'refs/remotes/' : 'refs/heads/'}${start.name}`], { timeoutMs: ADD_TIMEOUT_MS, signal });
  if (added.ok === false) {
    if (added.aborted === true) log.info('git worktree add stopped'); // the person left: not a failure of git
    else log.error('git worktree add failed', { code: added.code, timedOut: added.timedOut === true });
    await removeWorktree(git, made, mine);
    throw new ChatRefused(added.aborted === true ? 'Creating the worktree was cancelled' : added.timedOut === true ? 'Creating the worktree took too long and was stopped' : 'Git could not create the worktree');
  }
  return made;
}

/** Whether `refs/heads/<branch>` exists in `base`. A missing branch is an answer; any other git failure refuses, since guessing would decide what gets deleted. */
async function branchExists(git: Git, base: string, branch: string): Promise<boolean> {
  const found = await git.run(base, ['rev-parse', '--verify', '--quiet', `refs/heads/${branch}`]);
  if (found.ok) return true;
  if (found.code === 1) return false;
  log.error('git could not tell whether a branch exists', { code: found.code, timedOut: found.timedOut === true });
  throw new ChatRefused('Git could not read the branches of the repository');
}

/** Removes a folder Carrier made. One that cannot be removed is logged and left, and `false` says so. */
function removeFolder(path: string): boolean {
  try {
    rmSync(path, { recursive: true, force: true });
    return true;
  } catch (error) {
    log.error('a worktree folder could not be removed', error);
    return false;
  }
}

/** Takes away what `createWorktree` made, whatever state it was left in: the worktree, its folder and its branch. `mine` leaves alone the branch or the folder this call did not make. Never throws; what cannot be removed is logged. */
export async function removeWorktree(git: Git, { path, branch, base }: MadeWorktree, mine = { branch: true, folder: true }): Promise<void> {
  if (mine.folder) {
    await git.run(base, ['worktree', 'remove', '--force', path]);
    if (existsSync(path)) removeFolder(path);
    await git.run(base, ['worktree', 'prune']);
  }
  if (mine.branch === false) return;
  const exists = await git.run(base, ['rev-parse', '--verify', '--quiet', `refs/heads/${branch}`]);
  if (exists.ok === false) {
    if (exists.code !== 1) log.error('git could not tell whether the branch of a worktree that was not kept exists', { code: exists.code });
    return;
  }
  const deleted = await git.run(base, ['branch', '-D', branch]);
  if (deleted.ok === false) log.error('the branch of a worktree that was not kept could not be removed', { code: deleted.code });
}

/** A worktree as `git worktree list --porcelain` reports it: its folder and its branch, null when HEAD is detached or the repository is bare. */
export type ListedWorktree = { path: string; branch: string | null };

/** The paragraphs of `git worktree list --porcelain`: the main working tree first, then each linked one. */
export function parseWorktreeList(out: string): ListedWorktree[] {
  return out
    .split(/\n\n+/)
    .map((block) => block.split('\n'))
    .flatMap((lines) => {
      const path = lines.find((line) => line.startsWith('worktree '))?.slice('worktree '.length);
      const branch = lines.find((line) => line.startsWith('branch refs/heads/'))?.slice('branch refs/heads/'.length) ?? null;
      return path === undefined ? [] : [{ path, branch }];
    });
}

/** What git lists for `folder`: its main working tree first, then the linked ones. A folder git cannot read refuses with a fixed sentence. */
export async function listWorktrees(git: Git, folder: string): Promise<ListedWorktree[]> {
  const listed = await git.run(folder, ['worktree', 'list', '--porcelain']);
  if (listed.ok === false) {
    log.error('git could not list the worktrees of a folder', { code: listed.code, timedOut: listed.timedOut === true });
    throw new ChatRefused('Git could not list the worktrees of this folder');
  }
  return parseWorktreeList(listed.out);
}

/** What a folder takes on disk, in bytes: the blocks of every file and folder under it, links not followed. A path that cannot be read counts nothing. ponytail: a file hard-linked twice counts twice. */
export async function folderBytes(path: string): Promise<number> {
  try {
    const stats = await lstat(path);
    let total = stats.blocks * 512;
    if (stats.isDirectory() === false) return total;
    for (const name of await readdir(path)) total += await folderBytes(join(path, name));
    return total;
  } catch {
    return 0;
  }
}

/** The number `git rev-list --count` printed. */
export const parseCount = (out: string) => Number.parseInt(out.trim(), 10) || 0;

/** The entries a worktree folder holds besides its `.git` link: what is left to lose when git cannot read the worktree. */
const filesLeft = (path: string) => (existsSync(path) ? readdirSync(path).filter((entry) => entry !== '.git').length : 0);

/**
 * The path of a recorded worktree, which must be `<worktrees>/<owner>/<repo>/<name>` with the branch `carrier/<name>`; refuses anything else, so a tampered record removes nothing.
 * Both are compared with their symlinks resolved, as git lists a worktree by its real path, so a Carrier folder that is a link (or sits under one) holds the path either way.
 */
function recorded({ path, branch }: MadeWorktree): string {
  const target = resolve(path);
  const real = realOfNearest(target);
  const root = realOfNearest(resolve(worktreesDir()));
  const [owner, repo, name, ...deeper] = real.startsWith(root + sep) ? real.slice(root.length + 1).split(sep) : [];
  if (owner === undefined || repo === undefined || name === undefined || deeper.length > 0 || invalidReason(name) !== null || branch !== `${BRANCH_PREFIX}${name}`) throw new ChatRefused('This session\'s worktree is not one Carrier made, so nothing was removed');
  return target;
}

/** What deleting a worktree would discard: the lines `git status --porcelain` prints in it and the commits of its branch that no other branch of `batch` (the branches of the sessions deleted together, this one included) or remote branch contains. With the base folder gone git reads nothing and the commits went with it, so only the files left in the worktree folder count. A branch that is already gone has no commits to lose. */
export async function previewWorktree(git: Git, made: MadeWorktree, batch: string[]): Promise<{ dirty: number; unpushed: number }> {
  if (existsSync(made.base) === false) return { dirty: filesLeft(made.path), unpushed: 0 };
  const where = isWorktreeFolder(made.path) ? made.path : made.base; // a folder with no `.git` is what a stopped removal left: git reads nothing there
  const hasBranch = await branchExists(git, made.base, made.branch);
  const [status, ahead] = await Promise.all([
    where === made.path ? git.run(where, ['--no-optional-locks', 'status', '--porcelain', '--untracked-files=normal']) : Promise.resolve<GitResult>({ ok: true, out: '' }),
    // the branch is spelled as a full ref and each exclusion is a value of its own option, so neither can read as an option
    hasBranch ? git.run(where, ['rev-list', '--count', `refs/heads/${made.branch}`, '--not', ...[...new Set([made.branch, ...batch])].map((branch) => `--exclude=${branch}`), '--branches', '--remotes']) : Promise.resolve<GitResult>({ ok: true, out: '0' }),
  ]);
  if (status.ok === false || ahead.ok === false) {
    log.error('git could not read a worktree to preview its deletion', { status: status.ok ? 0 : status.code, ahead: ahead.ok ? 0 : ahead.code });
    throw new ChatRefused('Git could not read the worktree of a session');
  }
  return { dirty: countPorcelain(status.out), unpushed: parseCount(ahead.out) };
}

/** What moving a project's own folder to the Trash would lose: the lines `git status --porcelain` prints in it and the commits of its branch that no remote branch holds (all of them with no remote). No branch, or one with no commits yet, has none. */
export async function previewMain(git: Git, folder: string, branch: string | null): Promise<{ dirty: number; unpushed: number }> {
  const hasBranch = branch !== null && (await branchExists(git, folder, branch));
  const [status, ahead] = await Promise.all([
    git.run(folder, ['--no-optional-locks', 'status', '--porcelain', '--untracked-files=normal']),
    hasBranch ? git.run(folder, ['rev-list', '--count', `refs/heads/${branch}`, '--not', '--remotes']) : Promise.resolve<GitResult>({ ok: true, out: '0' }),
  ]);
  if (status.ok === false || ahead.ok === false) {
    log.error('git could not read a project folder to preview its deletion', { status: status.ok ? 0 : status.code, ahead: ahead.ok ? 0 : ahead.code });
    throw new ChatRefused('Git could not read the folder of this project');
  }
  return { dirty: countPorcelain(status.out), unpushed: parseCount(ahead.out) };
}

/**
 * Whether the worktree's HEAD is somewhere else than its recorded branch: detached (also in the middle of a rebase) or on another branch.
 * Commits made there are held by no branch this session kept, so the folder is not removed. A detached HEAD already contained in a branch counts too: the safe side.
 */
export async function headAway(git: Git, made: MadeWorktree): Promise<boolean> {
  const head = await git.run(made.path, ['symbolic-ref', '-q', '--short', 'HEAD']);
  if (head.ok) return head.out.trim() !== made.branch;
  if (head.code === 1) return true; // `-q` exits 1 when HEAD is not a branch
  log.error('git could not tell where the HEAD of a worktree is', { code: head.code, timedOut: head.timedOut === true });
  throw new ChatRefused('Git could not read the worktree of a session');
}

/**
 * Whether a folder is a worktree git can work in. Git makes `.git` first and `worktree remove` deletes it first, so a folder without one is what a removal left when it was stopped,
 * not a worktree: its registration is still in the base folder and the files git had not yet reached are still in it.
 */
export const isWorktreeFolder = (path: string) => existsSync(join(path, '.git'));

/** Takes away what a stopped removal left of a recorded worktree: its registration and its files. Whether there was any. Nothing else is touched, and the path is one Carrier made (`recorded`). */
async function dropLeftover(git: Git, made: MadeWorktree): Promise<boolean> {
  const path = recorded(made);
  if (existsSync(path) === false || isWorktreeFolder(path)) return false;
  log.info('removing what a stopped removal left of a worktree folder', { branch: made.branch });
  if (removeFolder(path) === false) throw new ChatRefused('The leftovers of a worktree folder could not be removed');
  if (existsSync(made.base)) await git.run(made.base, ['worktree', 'prune']);
  return true;
}

const readText = (file: string) => {
  try {
    return readFileSync(file, 'utf8');
  } catch {
    return '';
  }
};

/**
 * What a worktree holds that `status` does not show, in words, or null: commits that only this folder keeps and that the other checks (`dirty`, `unpushed`, `headAway`) cannot see.
 * A submodule (or a repository inside) keeps its commits in the worktree's own git dir, which goes with the folder; a file marked `--assume-unchanged` or `--skip-worktree` is
 * edited with no mark in `status`; and a commit made on a detached HEAD, then left by switching back to the branch, is held by nothing but the worktree's own reflog
 * (a commit of the branch's own reflog, amended or rebased, is not: its new version is the branch's). ponytail: a marked file that is there counts even if it is unchanged, and a
 * commit made detached and then cherry-picked to the branch with the same words still keeps the folder; the reflog is only read for `commit`, `cherry-pick` and `revert`.
 */
export async function hiddenWork(git: Git, made: MadeWorktree): Promise<string | null> {
  const path = recorded(made);
  const unread = (what: string, result: Extract<GitResult, { ok: false }>) => {
    log.error(`git could not read a worktree to look for ${what}`, { code: result.code, timedOut: result.timedOut === true });
    return new ChatRefused('Git could not read the worktree of a session');
  };
  // the worktree's own git dir: where its submodules' repositories live
  const gitDir = /^gitdir: (.+)$/m.exec(readText(join(path, '.git')))?.[1]?.trim();
  if (gitDir !== undefined && existsSync(join(isAbsolute(gitDir) ? gitDir : join(path, gitDir), 'modules'))) return 'a submodule';
  const [index, reflog] = await Promise.all([git.run(path, ['ls-files', '-v', '-s', '-z']), git.run(path, ['reflog', 'show', '-n', '1000', '--format=%H%x09%gs', 'HEAD'])]);
  if (index.ok === false) throw unread('a submodule', index);
  if (reflog.ok === false) throw unread('commits', reflog);
  for (const entry of index.out.split('\0')) {
    const [head, file] = entry.split('\t');
    const [tag, mode] = head?.split(' ') ?? [];
    if (file === undefined) continue;
    if (mode === '160000' && existsSync(join(path, file, '.git'))) return 'a submodule';
    if (/^[hsS]$/.test(tag ?? '') && existsSync(join(path, file))) return 'a file with changes git was told not to show';
  }
  const fresh = new Set(reflog.out.split('\n').flatMap((line) => (/^[0-9a-f]{40,64}\t(commit|cherry-pick|revert)/.test(line) ? [line.slice(0, line.indexOf('\t'))] : [])));
  if (fresh.size === 0) return null;
  const branch = await git.run(path, ['reflog', 'show', '-n', '1000', '--format=%H', `refs/heads/${made.branch}`]); // a branch that is gone has no reflog, and nothing was made on it
  const ofBranch = new Set(branch.ok ? branch.out.split('\n') : []);
  const candidates = [...fresh].filter((sha) => ofBranch.has(sha) === false);
  if (candidates.length === 0) return null;
  const held = await git.run(path, ['rev-list', '--count', ...candidates, '--not', '--branches', '--remotes', '--tags']);
  if (held.ok === false) throw unread('commits', held);
  return parseCount(held.out) > 0 ? 'a commit no branch holds' : null;
}

/**
 * The cleanup's half of a delete: removes only the folder of a session's recorded worktree and keeps its branch, so `restoreWorktree`
 * can bring it back. The caller has checked it holds no uncommitted work and that its HEAD is on its branch; every file git ignores (builds, dependencies, a local `.env`) goes with it.
 * What a stopped removal left (a folder with no `.git`) is taken away without asking git to remove it again, as git refuses that.
 */
export async function clearWorktree(git: Git, made: MadeWorktree): Promise<void> {
  const path = recorded(made);
  if (existsSync(path) === false || existsSync(made.base) === false) return;
  if (await dropLeftover(git, made)) return;
  const removed = await git.run(made.base, ['worktree', 'remove', '--force', path], { timeoutMs: REMOVE_TIMEOUT_MS });
  if (removed.ok === false) {
    log.error('git could not remove the folder of a cleaned-up worktree', { code: removed.code, timedOut: removed.timedOut === true });
    throw new ChatRefused('Git could not remove the worktree folder');
  }
}

/** Brings back the folder of a recorded worktree the cleanup removed, on its kept branch; refuses with a reason in words when it cannot. What a stopped removal left of it is taken away first. */
export async function restoreWorktree(git: Git, made: MadeWorktree): Promise<void> {
  const path = recorded(made);
  if (isWorktreeFolder(path)) return;
  if (existsSync(made.base) === false) throw new ChatRefused('This session\'s worktree was cleaned up and the folder it was made from is gone, so it cannot be opened again');
  if ((await branchExists(git, made.base, made.branch)) === false) throw new ChatRefused(`This session's worktree was cleaned up and its branch ${made.branch} is gone, so it cannot be opened again`);
  await dropLeftover(git, made);
  await git.run(made.base, ['worktree', 'prune']);
  // recorded() checked the branch is `carrier/<a valid name>`, so it cannot read as an option
  const added = await git.run(made.base, ['worktree', 'add', path, made.branch], { timeoutMs: ADD_TIMEOUT_MS });
  if (added.ok === false) {
    log.error('git could not bring back a cleaned-up worktree', { code: added.code, timedOut: added.timedOut === true });
    throw new ChatRefused('Git could not bring back the worktree of this session');
  }
}

/**
 * Removes the worktree a session recorded, then its recorded branch, and refuses with a reason in words when git cannot, so the session stays.
 * Only a path under the worktrees folder is touched. When the base folder is gone git cannot do it: the worktree folder is removed directly and the branch is left.
 */
export async function deleteWorktree(git: Git, made: MadeWorktree): Promise<void> {
  const path = recorded(made);
  if (existsSync(made.base) === false) {
    if (removeFolder(path) === false) throw new ChatRefused('Its folder could not be removed, so the session was kept');
    return;
  }
  const cannot = (what: string, result: Extract<GitResult, { ok: false }>) => {
    log.error(`git ${what} failed while deleting a worktree`, { code: result.code, timedOut: result.timedOut === true });
    return new ChatRefused(`Git could not ${what === 'branch' ? 'delete the branch of' : 'remove'} the worktree, so the session was kept`);
  };
  // a folder that is already gone, or that a stopped removal left with no `.git`, only leaves its entry for git to forget
  if (existsSync(path) && isWorktreeFolder(path) === false && removeFolder(path) === false) throw new ChatRefused('Its folder could not be removed, so the session was kept');
  const removed = await git.run(made.base, existsSync(path) ? ['worktree', 'remove', '--force', path] : ['worktree', 'prune'], { timeoutMs: REMOVE_TIMEOUT_MS });
  if (removed.ok === false) throw cannot('worktree', removed);
  const found = await git.run(made.base, ['rev-parse', '--verify', '--quiet', `refs/heads/${made.branch}`]);
  if (found.ok === false) {
    if (found.code === 1) return; // the branch is already gone
    throw cannot('branch', found);
  }
  const deleted = await git.run(made.base, ['branch', '-D', made.branch]);
  if (deleted.ok === false) throw cannot('branch', deleted);
}
