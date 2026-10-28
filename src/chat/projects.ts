import { execFile } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { defaults, loadConfig } from '../config/load.ts';
import { repoNamePattern, type Config } from '../config/schema.ts';
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

type CloneReply = { folder: string; repo: string; fetched: boolean };
type Job = { done: Promise<CloneReply>; waiters: number; abort: AbortController };

/**
 * Brings GitHub repositories into the projects folder with the person's own `gh` login (ADR 0015). `configPath`
 * is the file the host was started from: the folder is read from it at each request, so a change applies to the next one.
 */
export function createProjects({ git, token, config, configPath }: { git: Git; token: () => Promise<string>; config: Config; configPath?: string }) {
  const running = new Map<string, Job>();

  const current = (): Config => {
    if (configPath === undefined) return config;
    let user: unknown;
    try {
      user = JSON.parse(readFileSync(configPath, 'utf8'));
    } catch {
      throw new ChatRefused('The config file cannot be read');
    }
    const loaded = loadConfig(defaults, user);
    if (loaded.ok === false) throw new ChatRefused(`The config file is not valid: ${loaded.errors[0]!.path}: ${loaded.errors[0]!.message}`);
    return loaded.config;
  };

  const projectsFolder = (): string => {
    const fresh = current();
    return checkProjectsFolder(fresh.chat?.projectsFolder ?? join(fresh.root, 'chat', 'projects'), fresh.root);
  };

  // Not in argv, in a file or in a log: git reads the header from its environment, as `git-workspaces.ts` does.
  const authEnv = async (): Promise<NodeJS.ProcessEnv> => {
    const basic = Buffer.from(`x-access-token:${await token()}`).toString('base64');
    return { GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.extraHeader', GIT_CONFIG_VALUE_0: `Authorization: Basic ${basic}` };
  };

  async function fetchOrClone(repo: string, dest: string, signal: AbortSignal): Promise<CloneReply> {
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
      const cloned = await git.run(dirname(dest), ['clone', '--', `https://github.com/${repo}.git`, dest], { timeoutMs: GIT_TIMEOUT_MS, env, signal });
      if (cloned.ok === false) throw refusal(cloned, 'clone', repo);
    } catch (error) {
      await rm(dest, { recursive: true, force: true });
      throw error;
    }
    return { folder: dest, repo, fetched: false };
  }

  return {
    /** Makes `<projects folder>/local/<name>` and runs `git init -b main` in it. A name that is taken is refused and nothing is changed; a `git init` that fails removes what this request made. */
    async createProject({ name }: { name: string }): Promise<{ folder: string }> {
      if (projectNamePattern.test(name) === false) throw new ChatRefused(`"${name}" is not a plain folder name`);
      const dest = join(projectsFolder(), 'local', name);
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
    },

    /** Clones `repo` to `<projects folder>/<owner>/<name>`, or fetches it when it is already there. `signal` is the client's connection: when it closes, git is aborted and a destination this request made is removed. */
    async cloneRepo({ repo }: { repo: string }, signal: AbortSignal): Promise<CloneReply> {
      if (repoNamePattern.test(repo) === false) throw new ChatRefused(`"${repo}" is not a repository; write it as owner/name`);
      const dest = join(projectsFolder(), repo);
      const key = dest.toLowerCase();
      // a clone being aborted finishes first, so a new one never meets its leftovers
      for (let old = running.get(key); old?.abort.signal.aborted === true; old = running.get(key)) await old.done.catch(() => {});
      let job = running.get(key);
      if (job === undefined) {
        const abort = new AbortController();
        const started: Job = { done: fetchOrClone(repo, dest, abort.signal), waiters: 0, abort };
        const forget = () => void (running.get(key) === started && running.delete(key));
        started.done.then(forget, forget);
        running.set(key, (job = started));
      }
      const joined = job;
      joined.waiters++;
      return new Promise<CloneReply>((resolve, reject) => {
        // the clone stops when nobody waits for it any more
        const leave = () => {
          if (--joined.waiters === 0) joined.abort.abort();
          reject(new ChatRefused('The clone was cancelled'));
        };
        if (signal.aborted) return leave();
        signal.addEventListener('abort', leave, { once: true });
        const settled = () => signal.removeEventListener('abort', leave);
        joined.done.then(
          (reply) => (settled(), resolve(reply)),
          (error) => (settled(), reject(error)),
        );
      });
    },
  };
}
