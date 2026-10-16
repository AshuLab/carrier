import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { promisify } from 'node:util';
import { repoNamePattern } from '../config/schema.ts';
import type { GitHubProfile } from '../integrations/github.ts';
import type { Workspaces } from './workspaces.ts';

const execFileAsync = promisify(execFile);

export interface GitWorkspacesOptions {
  /** Shared root: clones go to `<root>/repos/<owner>/<name>`, reviewer checkouts to `<root>/reviews/<name>/<epic>`. */
  root: string;
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
  private readonly root: string;
  private readonly token?: (repo: string) => Promise<string>;
  private readonly remoteUrl: (repo: string) => string;
  private readonly reviewRef: (pr: number) => string;
  private readonly timeoutMs: number;
  private readonly queues = new Map<string, Promise<unknown>>();

  constructor(options: GitWorkspacesOptions) {
    this.root = options.root;
    this.token = options.token;
    this.remoteUrl = options.remoteUrl ?? defaultRemoteUrl;
    this.reviewRef = options.reviewRef ?? ((pr) => `refs/pull/${pr}/head`);
    this.timeoutMs = options.timeoutMs ?? 10 * 60_000;
  }

  private clonePath(repo: string) {
    return join(this.root, 'repos', repo);
  }

  /** One git operation at a time per repo: concurrent fetches and worktree adds on one clone collide on its locks. */
  private serial<T>(repo: string, work: () => Promise<T>): Promise<T> {
    const run = (this.queues.get(repo) ?? Promise.resolve()).catch(() => {}).then(work);
    this.queues.set(repo, run.catch(() => {}));
    return run;
  }

  /** Git over the network with the profile's token in the environment (not in argv, not in any config file). */
  private async remote(repo: string, args: string[], cwd?: string) {
    const env: NodeJS.ProcessEnv = {};
    if (this.token) {
      const basic = Buffer.from(`x-access-token:${await this.token(repo)}`).toString('base64');
      Object.assign(env, { GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraHeader', GIT_CONFIG_VALUE_0: `Authorization: Basic ${basic}` });
    }
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

  /** A checkout detached at the PR's head, apart from the author's and from Solve's `worktrees/`; each round re-points it. */
  async prepareReviewer(repo: string, epic: number, pr: number) {
    assertCount(epic, 'epic');
    assertCount(pr, 'pr');
    return this.serial(repo, async () => {
      const clone = await this.ensureClone(repo);
      await this.remote(repo, ['fetch', 'origin', this.reviewRef(pr)], clone);
      const sha = await git(['rev-parse', '--verify', 'FETCH_HEAD^{commit}'], { cwd: clone });
      const path = join(this.root, 'reviews', repo.split('/')[1]!, String(epic));
      if (existsSync(join(path, '.git'))) await git(['switch', '--detach', sha], { cwd: path });
      else {
        await mkdir(dirname(path), { recursive: true });
        await git(['worktree', 'prune'], { cwd: clone });
        await git(['worktree', 'add', '--detach', path, sha], { cwd: clone });
      }
      return path;
    });
  }
}

function assertCount(value: number, name: string) {
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error(`invalid ${name} ${value}`);
}
