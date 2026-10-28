import { existsSync, rmSync } from 'node:fs';
import { resolve, sep } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { Git, GitResult } from './git.ts';
import { BRANCH_PREFIX, invalidReason, repository, worktreePath, worktreesDir } from './names.ts';
import { ChatRefused } from './runner.ts';
import { countPorcelain } from './workspace.ts';

const log = createScopedLogger('chat');

/** What opening a session in a worktree made: the new folder, its branch, the branch it was cut from (a name `workspace` listed) and the base folder. */
export type MadeWorktree = { path: string; branch: string; from: string; base: string };

/** What a checkout of a big repository may take before the host gives up on it. */
const ADD_TIMEOUT_MS = 60_000;

/**
 * Creates `<CARRIER_HOME>/chat/worktrees/<owner>/<repo>/<name>` on a new branch `carrier/<name>` cut from `from`, in the
 * repository of `folder` (already checked, a real path). The base folder is only read: git adds the worktree without a
 * checkout, stash or commit in it. Refuses, with a reason in words, a folder that is not a repository or is bare, a `from`
 * that `workspace` does not list and a name that is invalid or taken. When git fails nothing is left behind.
 * Callers run it one at a time, so what it checked is still true when git adds.
 */
export async function createWorktree(git: Git, folder: string, request: { from: string; name?: string }, random?: () => number): Promise<MadeWorktree> {
  const { info, takenBecause, freeName } = await repository(git, folder);
  const start = info.branches.find((branch) => branch.name === request.from);
  if (start === undefined) throw new ChatRefused('The branch to start from is not one this repository lists');
  if (request.name !== undefined) {
    const refusal = invalidReason(request.name) ?? takenBecause(request.name);
    if (refusal !== null) throw new ChatRefused(refusal);
  }
  const name = request.name ?? freeName(random);
  const made = { path: worktreePath(info, name), branch: `${BRANCH_PREFIX}${name}`, from: start.name, base: folder };
  // What is absent right before the add is what this call may take away if the add fails: a branch or folder that appears in between is someone else's.
  const mine = {
    branch: (await git.run(folder, ['rev-parse', '--verify', '--quiet', `refs/heads/${made.branch}`])).ok === false,
    folder: existsSync(made.path) === false,
  };
  // The start point is spelled as a full ref, so it cannot read as an option, and `--no-track` leaves the new branch without an upstream.
  const added = await git.run(folder, ['worktree', 'add', '--no-track', '-b', made.branch, made.path, `${start.remote ? 'refs/remotes/' : 'refs/heads/'}${start.name}`], { timeoutMs: ADD_TIMEOUT_MS });
  if (added.ok === false) {
    log.error('git worktree add failed', { code: added.code, timedOut: added.timedOut === true });
    await removeWorktree(git, made, mine);
    throw new ChatRefused(added.timedOut === true ? 'Creating the worktree took too long and was stopped' : 'Git could not create the worktree');
  }
  return made;
}

/** Takes away what `createWorktree` made, whatever state it was left in: the worktree, its folder and its branch. `mine` leaves alone the branch or the folder this call did not make. Never throws; what cannot be removed is logged. */
export async function removeWorktree(git: Git, { path, branch, base }: MadeWorktree, mine = { branch: true, folder: true }): Promise<void> {
  if (mine.folder) {
    await git.run(base, ['worktree', 'remove', '--force', path]);
    if (existsSync(path)) rmSync(path, { recursive: true, force: true });
    await git.run(base, ['worktree', 'prune']);
  }
  if (mine.branch === false) return;
  const exists = await git.run(base, ['rev-parse', '--verify', '--quiet', `refs/heads/${branch}`]);
  if (exists.ok === false) return;
  const deleted = await git.run(base, ['branch', '-D', branch]);
  if (deleted.ok === false) log.error('the branch of a worktree that was not kept could not be removed', { code: deleted.code });
}

/** The number `git rev-list --count` printed. */
export const parseCount = (out: string) => Number.parseInt(out.trim(), 10) || 0;

/** The path of a recorded worktree when it lies under the worktrees folder and its branch is a `carrier/` one; refuses anything else, so a tampered record removes nothing. */
function recorded({ path, branch }: MadeWorktree): string {
  const target = resolve(path);
  if (target.startsWith(resolve(worktreesDir()) + sep) === false || branch.startsWith(BRANCH_PREFIX) === false) throw new ChatRefused('This session\'s worktree is not one Carrier made, so nothing was removed');
  return target;
}

/** What deleting a worktree would discard: the lines `git status --porcelain` prints in it and the commits of its branch that no other branch or remote branch contains. With the base folder gone git can read nothing, so it counts 0; a worktree folder that is gone has nothing uncommitted. */
export async function previewWorktree(git: Git, made: MadeWorktree): Promise<{ dirty: number; unpushed: number }> {
  if (existsSync(made.base) === false) return { dirty: 0, unpushed: 0 };
  const where = existsSync(made.path) ? made.path : made.base;
  const [status, ahead] = await Promise.all([
    where === made.path ? git.run(where, ['--no-optional-locks', 'status', '--porcelain']) : Promise.resolve<GitResult>({ ok: true, out: '' }),
    // the branch is spelled as a full ref and the exclusion is a value of its own option, so neither can read as an option
    git.run(where, ['rev-list', '--count', `refs/heads/${made.branch}`, '--not', `--exclude=${made.branch}`, '--branches', '--remotes']),
  ]);
  if (status.ok === false || ahead.ok === false) {
    log.error('git could not read a worktree to preview its deletion', { status: status.ok ? 0 : status.code, ahead: ahead.ok ? 0 : ahead.code });
    throw new ChatRefused('Git could not read the worktree of a session');
  }
  return { dirty: countPorcelain(status.out), unpushed: parseCount(ahead.out) };
}

/**
 * Removes the worktree a session recorded, then its recorded branch, and refuses with a reason in words when git cannot, so the session stays.
 * Only a path under the worktrees folder is touched. When the base folder is gone git cannot do it: the worktree folder is removed directly and the branch is left.
 */
export async function deleteWorktree(git: Git, made: MadeWorktree): Promise<void> {
  const path = recorded(made);
  if (existsSync(made.base) === false) return rmSync(path, { recursive: true, force: true });
  const cannot = (what: string, result: Extract<GitResult, { ok: false }>) => {
    log.error(`git ${what} failed while deleting a worktree`, { code: result.code, timedOut: result.timedOut === true });
    return new ChatRefused(`Git could not ${what === 'branch' ? 'delete the branch of' : 'remove'} the worktree, so the session was kept`);
  };
  // a folder that is already gone only leaves its entry for git to forget
  const removed = await git.run(made.base, existsSync(path) ? ['worktree', 'remove', '--force', path] : ['worktree', 'prune']);
  if (removed.ok === false) throw cannot('worktree', removed);
  const found = await git.run(made.base, ['rev-parse', '--verify', '--quiet', `refs/heads/${made.branch}`]);
  if (found.ok === false) {
    if (found.code === 1) return; // the branch is already gone
    throw cannot('branch', found);
  }
  const deleted = await git.run(made.base, ['branch', '-D', made.branch]);
  if (deleted.ok === false) throw cannot('branch', deleted);
}
