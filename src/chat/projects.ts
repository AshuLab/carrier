import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { carrierHome } from '../config/default-path.ts';
import { listAvailableRepos, type AvailableRepo } from '../integrations/available-repos.ts';
import type { Clock } from '../orchestration/clock.ts';
import { repoNamePattern } from '../config/schema.ts';
import { readChatConfig } from './config.ts';
import { checkProjectsFolder } from './folder.ts';
import type { Git, GitResult } from './git.ts';
import { ChatRefused } from './runner.ts';
import { parseOrigin } from './workspace.ts';

const log = createScopedLogger('chat');

/** A project's name: one plain folder name (no empty, `.`, `..`, leading dot or slash), at most a hundred characters. */
export const projectNamePattern = /^\w[\w.-]{0,99}$/;

/** Per git command, the engine's limit. */
export const GIT_TIMEOUT_MS = 10 * 60_000;

/** The token of the person's active `gh` login. Throws a `ChatRefused` saying what to do when `gh` is missing or signed out. */
export const ghToken = (): Promise<string> =>
  new Promise((resolve, reject) => {
    execFile('gh', ['auth', 'token'], { encoding: 'utf8', timeout: 15_000 }, (error, stdout) => {
      if ((error as NodeJS.ErrnoException | null)?.code === 'ENOENT') return reject(new ChatRefused('The GitHub CLI (gh) is not installed'));
      const token = stdout.trim();
      if (error !== null || token === '') return reject(new ChatRefused('gh is not signed in to GitHub; run "gh auth login"'));
      resolve(token);
    });
  });

/** What a failed `gh` call comes to, in a sentence for the person: gh missing, signed out, offline or too slow. What gh printed is logged by code only, never forwarded. */
export function ghRefusal(error: unknown, did: string): ChatRefused {
  const { code, killed, stderr } = error as { code?: unknown; killed?: boolean; stderr?: unknown };
  const said = typeof stderr === 'string' ? stderr : '';
  log.error(`gh ${did} failed`, { code: typeof code === 'number' || typeof code === 'string' ? code : null, killed: killed === true });
  if (code === 'ENOENT') return new ChatRefused('The GitHub CLI (gh) is not installed');
  if (killed === true) return new ChatRefused('GitHub took too long to answer');
  if (/gh auth login|not logged in|http 401|bad credentials/i.test(said)) return new ChatRefused('gh is not signed in to GitHub; run "gh auth login"');
  if (/error connecting|could not resolve|no such host|dial tcp|network is unreachable|timed out/i.test(said)) return new ChatRefused('GitHub could not be reached; check the network connection');
  return new ChatRefused(`GitHub did not answer; check "gh auth status"`);
}

/** One page of every repository the person's `gh` login can read, thirty at a time, newest push first. */
export const ghRepos = (page: number, timeoutMs: number): Promise<{ repos: AvailableRepo[]; hasMore: boolean }> =>
  listAvailableRepos(page, timeoutMs, 'read').catch((error) => {
    throw ghRefusal(error, 'repos');
  });

/** The login that is active in `gh`. */
export const ghLogin = (timeoutMs: number): Promise<string> =>
  promisify(execFile)('gh', ['api', 'user', '--jq', '.login'], { encoding: 'utf8', timeout: timeoutMs }).then(
    ({ stdout }) => stdout.trim(),
    (error) => {
      throw ghRefusal(error, 'login');
    },
  );

export type RepoBranches = { default: string; branches: string[]; hasMore: boolean };

const BRANCHES_PER_PAGE = 100;

/** The default branch and the first hundred branches of a repository (`owner/name`, already checked against `repoNamePattern`) the person's `gh` login can read. */
export async function ghBranches(repo: string, timeoutMs: number): Promise<RepoBranches> {
  const gh = (args: string[]) => promisify(execFile)('gh', ['api', ...args], { encoding: 'utf8', timeout: timeoutMs });
  try {
    const [head, listed] = await Promise.all([gh([`repos/${repo}`, '--jq', '.default_branch']), gh([`repos/${repo}/branches?per_page=${BRANCHES_PER_PAGE}`, '--jq', '.[].name'])]);
    const branches = listed.stdout.split('\n').filter((name) => name !== '');
    return { default: head.stdout.trim(), branches, hasMore: branches.length === BRANCHES_PER_PAGE };
  } catch (error) {
    throw ghRefusal(error, 'branches');
  }
}

// What git's stderr says, read here and never forwarded: it can hold a URL.
const notVisible = /repository not found|not found|authentication failed|could not read username|error: 40[134]/i;
const offline = /could not resolve host|failed to connect|connection (timed out|refused|reset)|network is unreachable|unable to access/i;

function refusal(result: Extract<GitResult, { ok: false }>, did: 'clone' | 'fetch', repo: string) {
  log.error(`git ${did} failed`, { repo, code: result.code, timedOut: result.timedOut === true });
  if (result.timedOut === true) return new ChatRefused(`The ${did} took more than ten minutes and was stopped`);
  if (notVisible.test(result.stderr)) return new ChatRefused(`${repo} was not found, or your GitHub login cannot see it`);
  if (offline.test(result.stderr)) return new ChatRefused('GitHub could not be reached; check the network connection');
  return new ChatRefused(`git could not ${did} ${repo}`);
}

/** The projects folder of `chat.json`, read at each call. `inside` is a path below it that is checked again: a projects folder that is the Carrier folder itself would put `engine/x` in the engine's own folder. */
const projectsFolder = (inside?: string): string => {
  const loaded = readChatConfig();
  if (loaded.ok === false) throw new ChatRefused(`chat.json is not valid: ${loaded.errors[0]!.path}: ${loaded.errors[0]!.message}`);
  const folder = checkProjectsFolder(loaded.settings.projectsFolder, carrierHome());
  return inside === undefined ? folder : checkProjectsFolder(join(folder, inside), carrierHome());
};

/** Where a new project of this name is made: `<projects folder>/local/<name>`. */
export function projectFolder(name: string): string {
  if (projectNamePattern.test(name) === false) throw new ChatRefused(`"${name}" is not a plain folder name`);
  return join(projectsFolder(), 'local', name);
}

/** Makes the project's folder and runs `git init -b main` in it. A name that is taken is refused and nothing is changed; a `git init` that fails removes what this call made. */
export async function createProject(git: Git, name: string): Promise<{ folder: string }> {
  const dest = projectFolder(name);
  await mkdir(dirname(dest), { recursive: true });
  try {
    await mkdir(dest); // not recursive: it fails when anything is there, and what is there is not ours to touch
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'EEXIST') throw new ChatRefused(`${name} is already a project; choose another name`);
    throw error;
  }
  const init = await git.run(dest, ['init', '-b', 'main']);
  if (init.ok === false) {
    log.error('git init failed', { name, code: init.code });
    await rm(dest, { recursive: true, force: true });
    throw new ChatRefused(`git could not start the project ${name}`);
  }
  return { folder: dest };
}

/** What the host takes of GitHub as a dependency, so a test injects a fake. Both throw a `ChatRefused` in words. */
export type GithubRepos = { repos: (page: number) => Promise<{ repos: AvailableRepo[]; hasMore: boolean }>; login: () => Promise<string>; branches: (repo: string) => Promise<RepoBranches> };

type CloneReply = { folder: string; repo: string; fetched: boolean };
type Job = { done: Promise<CloneReply>; mode: 'clone' | 'fetch'; waiters: number; abort: AbortController; listeners: Set<(line: string) => void>; latest?: string };

// The only stderr lines of git that leave this file: its progress, as "Receiving objects: 45%". Anything else can hold a URL.
const progressLine = /^(?:remote: )?((?:Counting|Compressing|Receiving|Resolving|Updating) [A-Za-z ]+: +\d+)%/;

/**
 * Brings GitHub repositories into the projects folder with the person's own `gh` login (ADR 0015). The folder is read
 * from `chat.json` at each request, so a change applies to the next one.
 */
export function createProjects({ git, token, github, clock }: { git: Git; token: () => Promise<string>; github: GithubRepos; clock: Clock }) {
  const running = new Map<string, Job>();

  // Not in argv, in a file or in a log: git reads the header from its environment, as `git-workspaces.ts` does.
  const authEnv = async (): Promise<NodeJS.ProcessEnv> => {
    const basic = Buffer.from(`x-access-token:${await token()}`).toString('base64');
    return { GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraHeader', GIT_CONFIG_VALUE_0: `Authorization: Basic ${basic}` };
  };

  async function fetchOrClone(repo: string, dest: string, signal: AbortSignal, onProgress: (line: string) => void): Promise<CloneReply> {
    if (existsSync(dest)) {
      const origin = existsSync(join(dest, '.git')) ? await git.run(dest, ['config', '--get', 'remote.origin.url']) : undefined;
      const found = origin?.ok === true ? parseOrigin(origin.out) : null;
      if (found === null || `${found.owner}/${found.name}`.toLowerCase() !== repo.toLowerCase()) throw new ChatRefused(`${dest} is already there and is not a clone of ${repo}; it was left as it is`);
      const fetched = await git.run(dest, ['fetch', 'origin', '--prune'], { timeoutMs: GIT_TIMEOUT_MS, env: await authEnv(), signal });
      if (fetched.ok === false) throw refusal(fetched, 'fetch', repo);
      return { folder: dest, repo, fetched: true };
    }
    const env = await authEnv();
    await mkdir(dirname(dest), { recursive: true });
    try {
      await mkdir(dest); // not recursive: it fails if something appeared since the check, and what is there now is ours to remove only if we made it
    } catch {
      throw new ChatRefused(`${dest} is already there and is not a clone of ${repo}; it was left as it is`);
    }
    try {
      const cloned = await git.run(dirname(dest), ['clone', '--', `https://github.com/${repo}.git`, dest], { timeoutMs: GIT_TIMEOUT_MS, env, signal, onProgress });
      if (cloned.ok === false) throw refusal(cloned, 'clone', repo);
    } catch (error) {
      await rm(dest, { recursive: true, force: true });
      throw error;
    }
    return { folder: dest, repo, fetched: false };
  }

  /** `<projects folder>/<owner>/<name>`, where `repo` is or would be cloned. */
  const repoFolder = (repo: string): string => {
    if (repoNamePattern.test(repo) === false) throw new ChatRefused(`"${repo}" is not a repository; write it as owner/name`);
    return projectsFolder(repo);
  };

  return {
    repoFolder,

    /** What bringing `repo` is: `fetch` when it is already in the projects folder, `clone` when it is not, or what the one in progress is doing (a clone being made is not yet a repository to fetch). */
    stepOf(repo: string): 'clone' | 'fetch' {
      const dest = repoFolder(repo);
      return running.get(dest.toLowerCase())?.mode ?? (existsSync(dest) ? 'fetch' : 'clone');
    },

    /** The default branch and the branches of a repository that need not be on disk, read from GitHub with the person's login. */
    repoBranches({ repo }: { repo: string }): Promise<RepoBranches> {
      if (repoNamePattern.test(repo) === false) throw new ChatRefused(`"${repo}" is not a repository; write it as owner/name`);
      return github.branches(repo);
    },

    /** A page of the repositories the person's login can read; page 1 also says the login. */
    async githubRepos({ page }: { page: number }): Promise<{ repos: AvailableRepo[]; hasMore: boolean; login?: string }> {
      if (page > 1) return github.repos(page);
      const [first, who] = await Promise.all([github.repos(page), github.login()]);
      return { ...first, login: who };
    },

    /** Makes `<projects folder>/local/<name>` and runs `git init -b main` in it (the `createProject` request, for apps older than the plan). */
    createProject: ({ name }: { name: string }) => createProject(git, name),

    /**
     * Clones `repo` to `<projects folder>/<owner>/<name>`, or fetches it when it is already there. `signal` is the waiter's: when it aborts, this waiter
     * leaves, and git is aborted and a destination this request made is removed once nobody waits for it. `onProgress` gets git's progress lines of a
     * clone ("Receiving objects: 45%"), at most one a second and no other line of git's.
     */
    async cloneRepo({ repo }: { repo: string }, signal: AbortSignal, onProgress?: (line: string) => void): Promise<CloneReply> {
      const dest = repoFolder(repo);
      const key = dest.toLowerCase();
      // a clone being aborted finishes first, so a new one never meets its leftovers
      for (let old = running.get(key); old?.abort.signal.aborted === true; old = running.get(key)) await old.done.catch(() => {});
      let job = running.get(key);
      if (job === undefined) {
        const abort = new AbortController();
        const listeners = new Set<(line: string) => void>();
        let last = -Infinity;
        const report = (raw: string) => {
          const found = progressLine.exec(raw.trim());
          if (found === null || clock.now() - last < 1000) return;
          last = clock.now();
          const line = `${found[1]!.replace(/ +/g, ' ')}%`;
          started.latest = line;
          for (const listener of listeners) listener(line);
        };
        const started: Job = { done: fetchOrClone(repo, dest, abort.signal, report), mode: existsSync(dest) ? 'fetch' : 'clone', waiters: 0, abort, listeners };
        const forget = () => void (running.get(key) === started && running.delete(key));
        started.done.then(forget, forget);
        running.set(key, (job = started));
      }
      const joined = job;
      joined.waiters++;
      if (onProgress !== undefined) {
        joined.listeners.add(onProgress);
        if (joined.latest !== undefined) onProgress(joined.latest);
      }
      return new Promise<CloneReply>((resolve, reject) => {
        // the clone stops when nobody waits for it any more, and the last one to leave hears of it once the half clone is removed
        const leave = async () => {
          if (onProgress !== undefined) joined.listeners.delete(onProgress);
          if (--joined.waiters === 0) {
            joined.abort.abort();
            await joined.done.catch(() => {});
          }
          reject(new ChatRefused('The clone was cancelled'));
        };
        if (signal.aborted) return leave();
        signal.addEventListener('abort', leave, { once: true });
        const settled = () => (signal.removeEventListener('abort', leave), onProgress !== undefined && joined.listeners.delete(onProgress));
        // a waiter that has left is answered by `leave`
        joined.done.then(
          (reply) => (settled(), signal.aborted || resolve(reply)),
          (error) => (settled(), signal.aborted || reject(error)),
        );
      });
    },
  };
}
