import { statSync } from 'node:fs';
import { resolve } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { Git, GitResult } from './git.ts';
import { ChatRefused } from './runner.ts';

const log = createScopedLogger('chat');

/** What a folder is as a git repository: the answer to the `workspace` request. */
export type WorkspaceInfo = {
  folder: string;
  git: boolean;
  bare: boolean;
  linkedWorktree: boolean;
  repo: { owner: string; name: string } | null;
  branch: string | null;
  defaultBranch: string | null;
  dirty: number;
  branches: { name: string; remote: boolean }[];
  fetchedAt: number | null;
};

const lines = (out: string) => out.split('\n').filter((line) => line !== '');

/** `owner/name` of a GitHub remote in its https or ssh form (with or without `.git`, a trailing slash or credentials); null for any other remote. */
export function parseOrigin(url: string): { owner: string; name: string } | null {
  const found = /^(?:https:\/\/(?:[^@/\s]+@)?github\.com\/|(?:ssh:\/\/)?git@github\.com[:/])([\w.-]+)\/([\w.-]+?)(?:\.git)?\/?$/i.exec(url.trim());
  if (found === null || [found[1], found[2]].some((part) => part === '.' || part === '..')) return null;
  return { owner: found[1]!, name: found[2]! };
}

/** The number of lines `git status --porcelain` printed. */
export const countPorcelain = (out: string) => lines(out).length;

/** From `for-each-ref --format=%(refname) refs/heads refs/remotes/origin`: local branches, then `origin/x` ones, `origin/HEAD` left out. */
export function parseBranches(out: string): { name: string; remote: boolean }[] {
  const found: { name: string; remote: boolean }[] = [];
  for (const ref of lines(out)) {
    if (ref.startsWith('refs/heads/')) found.push({ name: ref.slice('refs/heads/'.length), remote: false });
    else if (ref.startsWith('refs/remotes/origin/') && ref !== 'refs/remotes/origin/HEAD') found.push({ name: ref.slice('refs/remotes/'.length), remote: true });
  }
  return found.sort((a, b) => Number(a.remote) - Number(b.remote)); // stable: each group stays in git's order
}

/** `origin/HEAD` (`symbolic-ref` printed `refs/remotes/origin/main`) when set, else `main`, else `master` when listed, else null. */
export function parseDefaultBranch(originHead: string | null, branches: { name: string }[]): string | null {
  const prefix = 'refs/remotes/origin/';
  const head = originHead?.trim() ?? '';
  if (head.startsWith(prefix) && head.length > prefix.length) return head.slice(prefix.length);
  return ['main', 'master'].find((name) => branches.some((branch) => branch.name === name || branch.name === `origin/${name}`)) ?? null;
}

const refused = () => new ChatRefused('Git could not read that folder');

/** A command whose failure with exit status 1 is an answer ("not set", "detached"): the output, or null for that answer; any other failure refuses. */
function answer(result: GitResult, what: string): string | null {
  if (result.ok) return result.out.trim();
  if (result.code === 1) return null;
  log.error(`git ${what} failed`, { code: result.code });
  throw refused();
}

function mustRun(result: GitResult, what: string): string {
  if (result.ok) return result.out;
  log.error(`git ${what} failed`, { code: result.code });
  throw refused();
}

const mtimeOf = (path: string) => {
  try {
    return Math.floor(statSync(path).mtimeMs);
  } catch {
    return null;
  }
};

/** Asks git what `folder` (already checked, a real path) is. A folder git does not know as a repository answers `git: false`. */
export async function inspectFolder(git: Git, folder: string): Promise<WorkspaceInfo> {
  const plain: WorkspaceInfo = { folder, git: false, bare: false, linkedWorktree: false, repo: null, branch: null, defaultBranch: null, dirty: 0, branches: [], fetchedAt: null };
  const probe = await git.run(folder, ['rev-parse', '--is-bare-repository', '--git-dir', '--git-common-dir', '--git-path', 'FETCH_HEAD']);
  if (probe.ok === false && probe.code === 128) return plain; // "not a git repository"
  const [bare, gitDir, commonDir, fetchHead] = lines(mustRun(probe, 'rev-parse'));
  if (fetchHead === undefined) throw refused();
  const isBare = bare === 'true';
  const [url, branch, originHead, refs, status] = await Promise.all([
    git.run(folder, ['config', '--get', 'remote.origin.url']),
    git.run(folder, ['symbolic-ref', '-q', '--short', 'HEAD']),
    git.run(folder, ['symbolic-ref', '-q', 'refs/remotes/origin/HEAD']),
    git.run(folder, ['for-each-ref', '--format=%(refname)', 'refs/heads', 'refs/remotes/origin']),
    isBare ? Promise.resolve<GitResult>({ ok: true, out: '' }) : git.run(folder, ['--no-optional-locks', 'status', '--porcelain']),
  ]);
  const branches = parseBranches(mustRun(refs, 'for-each-ref'));
  const origin = answer(url, 'config');
  return {
    folder,
    git: true,
    bare: isBare,
    linkedWorktree: resolve(folder, gitDir!) !== resolve(folder, commonDir!),
    repo: origin === null ? null : parseOrigin(origin),
    branch: answer(branch, 'symbolic-ref') || null,
    defaultBranch: parseDefaultBranch(answer(originHead, 'symbolic-ref'), branches),
    dirty: countPorcelain(mustRun(status, 'status')),
    branches,
    fetchedAt: mtimeOf(resolve(folder, fetchHead)),
  };
}
