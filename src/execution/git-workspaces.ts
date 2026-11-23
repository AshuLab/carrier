import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { promisify } from 'node:util';
import type { EnginePlaces } from '../config/places.ts';
import { repoNamePattern } from '../config/schema.ts';
import type { GitHubProfile } from '../integrations/github.ts';
import type { Workspaces } from './workspaces.ts';

const execFileAsync = promisify(execFile);

/** The environment that makes git send `token` as the HTTPS credential: in the environment, never in argv, a file or a log. */
export const tokenEnv = (token: string): NodeJS.ProcessEnv => ({
  GIT_CONFIG_COUNT: '1',
  GIT_CONFIG_KEY_0: 'http.extraHeader',
  GIT_CONFIG_VALUE_0: `Authorization: Basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}`,
});

export interface GitWorkspacesOptions {
  /** The engine's places: clones go to `<repos>/<owner>/<name>`, reviewer checkouts to `<reviews>/<name>/<epic>`. */
  places: Pick<EnginePlaces, 'repos' | 'reviews'>;
  /** Token for git over HTTPS as the author's profile, minted per command and never stored. Absent: no credentials (local remotes). */
  token?: (repo: string) => Promise<string>;
  /** Defaults to the GitHub HTTPS URL; never carries a token. */
  remoteUrl?: (repo: string) => string;
  /** What the reviewer checks out for a PR; defaults to GitHub's `refs/pull/<pr>/head`. */
  reviewRef?: (pr: number) => string;
  /** Per git command; the process is killed when it passes. */
  timeoutMs?: number;
}

const defaultRemoteUrl = (repo: string) => `https://github.com/${repo}.git`;

async function git(args: string[], opts: { cwd?: string; env?: NodeJS.ProcessEnv; timeoutMs?: number } = {}) {
  try {
    const { stdout } = await execFileAsync('git', args, {
      cwd: opts.cwd,
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0', ...opts.env },
      timeout: opts.timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
      encoding: 'utf8',
    });
    return stdout.trim();
  } catch (error) {
    // execFile's own message repeats the argv; the credentials only travel in the environment, which it never prints.
    const failed = error as { stderr?: string; message: string };
    throw new Error(`git ${args[0]} failed: ${(failed.stderr || failed.message).trim().slice(0, 500)}`);
  }
}

/**
 * Token of a GitHub profile. Forge picks the App installation from the `origin` of the cwd, so it runs in a
 * throwaway repo pointing at the target: that works before the clone exists, too.
 */
export function profileToken(profile: GitHubProfile, remoteUrl: (repo: string) => string = defaultRemoteUrl): (repo: string) => Promise<string> {
  return async (repo) => {
    if (profile.kind === 'gh') return (await execFileAsync('gh', ['auth', 'token'], { encoding: 'utf8' })).stdout.trim();
    const scratch = await mkdtemp(join(tmpdir(), 'carrier-token-'));
    try {
      await git(['init', '-q'], { cwd: scratch });
      await git(['remote', 'add', 'origin', remoteUrl(repo)], { cwd: scratch });
      return (await execFileAsync('agent-forge', ['token', '--agent', profile.agent], { cwd: scratch, encoding: 'utf8' })).stdout.trim();
    } catch (error) {
      // Never echo the child's output or argv beyond this: they are the only place a token could appear.
      throw new Error(`could not mint a token for ${profile.kind === 'forge' ? profile.agent : 'gh'}: ${(error as { stderr?: string }).stderr?.trim().slice(0, 300) ?? 'failed'}`);
    } finally {
      await rm(scratch, { recursive: true, force: true });
    }
  };
}

export class GitWorkspaces implements Workspaces {
  private readonly places: GitWorkspacesOptions['places'];
  private readonly token?: (repo: string) => Promise<string>;
  private readonly remoteUrl: (repo: string) => string;
  private readonly reviewRef: (pr: number) => string;
  private readonly timeoutMs: number;
  private readonly queues = new Map<string, Promise<unknown>>();

  constructor(options: GitWorkspacesOptions) {
    this.places = options.places;
    this.token = options.token;
    this.remoteUrl = options.remoteUrl ?? defaultRemoteUrl;
    this.reviewRef = options.reviewRef ?? ((pr) => `refs/pull/${pr}/head`);
    this.timeoutMs = options.timeoutMs ?? 10 * 60_000;
  }

  private clonePath(repo: string) {
    return join(this.places.repos, repo);
  }

  /** One git operation at a time per repo: concurrent fetches and worktree adds on one clone collide on its locks. */
  private serial<T>(repo: string, work: () => Promise<T>): Promise<T> {
    const run = (this.queues.get(repo) ?? Promise.resolve()).catch(() => {}).then(work);
    this.queues.set(repo, run.catch(() => {}));
    return run;
  }

  /** Git over the network with the profile's token in the environment (not in argv, not in any config file). */
  private async remote(repo: string, args: string[], cwd?: string) {
    const env = this.token ? tokenEnv(await this.token(repo)) : {};
    return git(args, { cwd, env, timeoutMs: this.timeoutMs });
  }

  /** Clones or fetches; returns the clone. Callers hold the repo's queue. */
  private async ensureClone(repo: string) {
    if (!repoNamePattern.test(repo)) throw new Error(`invalid repo "${repo}", expected owner/name`);
    const path = this.clonePath(repo);
    if (existsSync(join(path, '.git'))) await this.remote(repo, ['fetch', '--prune', 'origin'], path);
    else {
      await mkdir(dirname(path), { recursive: true });
      await this.remote(repo, ['clone', this.remoteUrl(repo), path]);
    }
    return path;
  }

  /** The clone, up to date. `ship` runs here and puts the epic's worktree where the repo's solve.md says. */
  async prepareAuthor(repo: string, epic: number) {
    assertCount(epic, 'epic');
    return this.serial(repo, () => this.ensureClone(repo));
  }

  /** The linked worktrees of the clone, as `git worktree list` says; `branch` is null for a detached one. */
  private async linkedWorktrees(clone: string) {
    const list = await git(['worktree', 'list', '--porcelain'], { cwd: clone });
    // One block per worktree: `worktree <path>`, then `branch refs/heads/<name>` unless it is detached.
    // The first is the clone itself: other epics of the repo share it, so an epic that was not isolated has no workspace.
    return list.split('\n\n').slice(1).map((block) => {
      const lines = block.split('\n');
      const branch = lines.find((l) => l.startsWith('branch refs/heads/'));
      return { path: lines.find((l) => l.startsWith('worktree '))!.slice('worktree '.length), branch: branch ? branch.slice('branch refs/heads/'.length) : null };
    });
  }

  async exists(path: string) {
    return existsSync(path);
  }

  async findWorktree(repo: string, branch: string) {
    return this.serial(repo, async () => (await this.linkedWorktrees(this.clonePath(repo))).find((w) => w.branch === branch)?.path ?? null);
  }

  /**
   * What a merged or cancelled epic leaves on the disk goes: its reviewer checkout, the author's worktree of `branch` and Solve's
   * `<that path>--lane-N` worktrees beside it, then the epic's local branches whose tip is already on the remote. A worktree with
   * work nowhere else and a branch not on the remote are kept, and returned so the caller can say why. Only paths `git worktree list`
   * reports for this clone are removed.
   */
  async cleanUp(repo: string, epic: number, branch: string | null) {
    assertCount(epic, 'epic');
    return this.serial(repo, async () => {
      const clone = this.clonePath(repo);
      if (!existsSync(join(clone, '.git'))) return { kept: [] };
      const linked = await this.linkedWorktrees(clone);
      const author = branch ? linked.find((w) => w.branch === branch)?.path : undefined;
      const review = this.reviewPath(repo, epic);
      const doomed = linked.filter((w) => w.path === review || (author && (w.path === author || w.path.startsWith(`${author}--lane-`))));
      // Fetched first, so a commit is judged against the remote as it is now.
      if (branch) await this.remote(repo, ['fetch', '--prune', 'origin'], clone);
      const kept: string[] = [];
      // One already deleted by hand is only a stale entry: `prune` drops it.
      for (const { path } of doomed.filter((w) => existsSync(w.path))) {
        // The reviewer's checkout is detached at the PR's head, which is on the remote; an author or lane worktree may hold work nowhere else:
        // uncommitted files, or commits of a detached HEAD on no branch. Such a one stays, and its branch with it (it is checked out).
        if (path !== review) {
          const dirty = (await git(['status', '--porcelain'], { cwd: path })) !== '';
          const unsaved = (await git(['rev-list', '--count', 'HEAD', '--not', '--branches', '--remotes'], { cwd: path })) !== '0';
          if (dirty || unsaved) {
            kept.push(path);
            continue;
          }
        }
        await git(['worktree', 'remove', '--force', path], { cwd: clone });
      }
      await git(['worktree', 'prune'], { cwd: clone });
      if (!branch) return { kept };
      // The epic branch and, for Solve's `<prefix>/epic`, its slices under `<prefix>/`; never a wider prefix.
      const refs = branch.endsWith('/epic') ? `refs/heads/${branch.slice(0, -'epic'.length)}` : `refs/heads/${branch}`;
      const locals = (await git(['for-each-ref', '--format=%(refname:short)', refs], { cwd: clone })).split('\n').filter(Boolean);
      // A branch still checked out (in the clone, or a worktree that is not the epic's) cannot go, and is not ours to move.
      const checkedOut = new Set([await git(['branch', '--show-current'], { cwd: clone }), ...(await this.linkedWorktrees(clone)).map((w) => w.branch)]);
      for (const local of locals) {
        const pushed = (await git(['branch', '-r', '--contains', local], { cwd: clone })) !== '';
        if (pushed && !checkedOut.has(local)) await git(['branch', '-D', local], { cwd: clone });
        else kept.push(local);
      }
      return { kept };
    });
  }

  private reviewPath(repo: string, epic: number) {
    return join(this.places.reviews, repo.split('/')[1]!, String(epic));
  }

  /**
   * A checkout detached at the PR's head, apart from the author's and from Solve's `worktrees/`; each round re-points it, resets the tracked
   * files to it and removes the untracked ones, keeping the ignored (a review does not rebuild its dependencies). Returns the commit it is at.
   */
  async prepareReviewer(repo: string, epic: number, pr: number) {
    assertCount(epic, 'epic');
    assertCount(pr, 'pr');
    return this.serial(repo, async () => {
      const clone = await this.ensureClone(repo);
      await this.remote(repo, ['fetch', 'origin', this.reviewRef(pr)], clone);
      const sha = await git(['rev-parse', '--verify', 'FETCH_HEAD^{commit}'], { cwd: clone });
      const path = this.reviewPath(repo, epic);
      if (existsSync(join(path, '.git'))) {
        await git(['reset', '--hard', sha], { cwd: path });
        await git(['clean', '-fd'], { cwd: path });
      } else {
        await mkdir(dirname(path), { recursive: true });
        await git(['worktree', 'prune'], { cwd: clone });
        await git(['worktree', 'add', '--detach', path, sha], { cwd: clone });
      }
      return { path, commit: sha };
    });
  }
}

function assertCount(value: number, name: string) {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error(`invalid ${name} ${value}`);
}
