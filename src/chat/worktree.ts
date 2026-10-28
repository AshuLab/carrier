import { existsSync, rmSync } from 'node:fs';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { Git } from './git.ts';
import { BRANCH_PREFIX, invalidReason, repository, worktreePath } from './names.ts';
import { ChatRefused } from './runner.ts';

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
  // The start point is spelled as a full ref, so it cannot read as an option, and `--no-track` leaves the new branch without an upstream.
  const added = await git.run(folder, ['worktree', 'add', '--no-track', '-b', made.branch, made.path, `${start.remote ? 'refs/remotes/' : 'refs/heads/'}${start.name}`], { timeoutMs: ADD_TIMEOUT_MS });
  if (added.ok === false) {
    log.error('git worktree add failed', { code: added.code, timedOut: added.timedOut === true });
    await removeWorktree(git, made);
    throw new ChatRefused(added.timedOut === true ? 'Creating the worktree took too long and was stopped' : 'Git could not create the worktree');
  }
  return made;
}

/** Takes away what `createWorktree` made, whatever state it was left in: the worktree, its folder and its branch. Never throws; what cannot be removed is logged. */
export async function removeWorktree(git: Git, { path, branch, base }: MadeWorktree): Promise<void> {
  await git.run(base, ['worktree', 'remove', '--force', path]);
  if (existsSync(path)) rmSync(path, { recursive: true, force: true });
  await git.run(base, ['worktree', 'prune']);
  const exists = await git.run(base, ['rev-parse', '--verify', '--quiet', `refs/heads/${branch}`]);
  if (exists.ok === false) return;
  const deleted = await git.run(base, ['branch', '-D', branch]);
  if (deleted.ok === false) log.error('the branch of a worktree that was not kept could not be removed', { code: deleted.code });
}
