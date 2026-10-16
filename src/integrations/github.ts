import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { z } from 'zod';
import { AuthError, GitHubUnavailable, readyLabel, type GitHub } from '../orchestration/github.ts';

const execFileAsync = promisify(execFile);

export type GitHubProfile = { kind: 'forge'; agent: string } | { kind: 'gh' };

export interface GhGitHubOptions {
  profile: GitHubProfile;
  /** Where to run `gh`. Forge picks the App installation from this directory's `origin`, so it must be a clone under the repo's owner. */
  cwd: (repo: string) => string;
  /** Per call; the process is killed when it passes. */
  timeoutMs: number;
  /** Replaces `agent-forge` (forge profiles) or `gh` (gh profiles); for tests. */
  executable?: string;
}

const PER_PAGE = 100;
const repoPattern = /^[\w.-]+\/[\w.-]+$/;

// Forge reports every failure with exit 1, so credentials problems are told apart by their stderr.
const authStderr =
  /Agent not found:|Private key for .* not found or unreadable|App JWT was rejected|has no installations|Bad credentials|HTTP 401|not logged in|gh auth login/i;
const networkStderr =
  /error connecting|dial tcp|no such host|ENOTFOUND|ECONNRESET|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|network is unreachable|i\/o timeout|connection reset|TLS handshake/i;

/** Any non-2xx answer that is neither "GitHub is down" nor "bad credentials", e.g. 404 or 422. */
class HttpError extends Error {
  readonly status: number;

  constructor(status: number, body: string) {
    super(`GitHub answered HTTP ${status}: ${body.slice(0, 300)}`);
    this.status = status;
  }
}

const issueRow = z.object({ number: z.int().positive(), title: z.string(), pull_request: z.unknown().optional() });
const issueDetail = z.object({ state: z.enum(['open', 'closed']), labels: z.array(z.object({ name: z.string() })) });
const pullRow = z.object({
  number: z.int().positive(),
  state: z.enum(['open', 'closed']),
  merged_at: z.string().nullable(),
  body: z.string().nullable(),
  head: z.object({ sha: z.string().min(1) }),
});
const labelRow = z.object({ name: z.string() });

function retryAfterMs(headers: Record<string, string>) {
  const retryAfter = Number(headers['retry-after']);
  if (headers['retry-after'] !== undefined && Number.isFinite(retryAfter)) return retryAfter * 1000;
  const reset = Number(headers['x-ratelimit-reset']);
  if (headers['x-ratelimit-remaining'] === '0' && Number.isFinite(reset)) return Math.max(0, reset * 1000 - Date.now());
  return undefined;
}

function statusFailure(status: number, headers: Record<string, string>, body: string) {
  const wait = retryAfterMs(headers);
  const rateLimited = status === 429 || (status === 403 && (wait !== undefined || /rate limit/i.test(body)));
  if (rateLimited || status >= 500) return new GitHubUnavailable(wait, `HTTP ${status}`);
  if (status === 401) return new AuthError(`GitHub rejected the credentials (HTTP 401)`);
  return new HttpError(status, body);
}

// `gh api -i` prints the status line, the headers, a blank line and the body, also on errors.
function parseResponse(stdout: string) {
  const match = /^HTTP\/\S+ (\d{3})[^\n]*\n([\s\S]*?)\r?\n\r?\n([\s\S]*)$/.exec(stdout);
  if (!match) return null;
  const headers: Record<string, string> = {};
  for (const line of match[2]!.split(/\r?\n/)) {
    const colon = line.indexOf(':');
    if (colon > 0) headers[line.slice(0, colon).toLowerCase()] = line.slice(colon + 1).trim();
  }
  return { status: Number(match[1]), headers, body: match[3]! };
}

export class GhGitHub implements GitHub {
  private readonly options: GhGitHubOptions;

  constructor(options: GhGitHubOptions) {
    this.options = options;
  }

  /** One `gh api` call: argv separated, no shell. Returns the body of a 2xx answer, throws for anything else. */
  private async api(repo: string, args: string[]): Promise<string> {
    if (!repoPattern.test(repo)) throw new Error(`invalid repo "${repo}"`);
    const { profile, executable } = this.options;
    const [command, ...prefix] = profile.kind === 'forge' ? [executable ?? 'agent-forge', 'gh', profile.agent] : [executable ?? 'gh'];
    try {
      const { stdout } = await execFileAsync(command!, [...prefix, 'api', '-i', ...args], {
        cwd: this.options.cwd(repo),
        timeout: this.options.timeoutMs,
        maxBuffer: 64 * 1024 * 1024,
        encoding: 'utf8',
      });
      const response = parseResponse(stdout);
      if (!response) throw new Error(`unexpected gh output: ${stdout.slice(0, 200)}`);
      if (response.status >= 300) throw statusFailure(response.status, response.headers, response.body);
      return response.body;
    } catch (error) {
      if (error instanceof GitHubUnavailable || error instanceof AuthError || error instanceof HttpError) throw error;
      const failed = error as { killed?: boolean; code?: unknown; stdout?: string; stderr?: string; message: string };
      // Exceeding maxBuffer also kills the child, but that is not a timeout.
      if (failed.killed && failed.code !== 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER') throw new GitHubUnavailable(undefined, `timed out after ${this.options.timeoutMs} ms`);
      const response = parseResponse(failed.stdout ?? '');
      if (response) throw statusFailure(response.status, response.headers, response.body);
      const stderr = failed.stderr ?? '';
      if (authStderr.test(stderr)) throw new AuthError(stderr.trim().slice(0, 300));
      if (networkStderr.test(stderr)) throw new GitHubUnavailable(undefined, stderr.trim().slice(0, 300));
      throw new Error(`gh failed: ${(stderr || failed.message).trim().slice(0, 300)}`);
    }
  }

  private async get<T>(repo: string, path: string, schema: z.ZodType<T>): Promise<T> {
    return schema.parse(JSON.parse(await this.api(repo, [`repos/${repo}/${path}`])));
  }

  /** Pages of a list endpoint, fetched lazily until one comes back short. */
  private async *pages<T>(repo: string, path: string, params: Record<string, string>, row: z.ZodType<T>): AsyncGenerator<T[]> {
    for (let page = 1; ; page++) {
      const query = new URLSearchParams({ ...params, per_page: String(PER_PAGE), page: String(page) });
      const rows = await this.get(repo, `${path}?${query}`, z.array(row));
      yield rows;
      if (rows.length < PER_PAGE) return;
    }
  }

  async listReadyEpics(repo: string) {
    const epics: { issue: number; title: string }[] = [];
    for await (const rows of this.pages(repo, 'issues', { labels: readyLabel, state: 'open' }, issueRow)) {
      for (const row of rows) if (row.pull_request === undefined) epics.push({ issue: row.number, title: row.title });
    }
    return epics;
  }

  async getIssue(repo: string, issue: number) {
    const { state, labels } = await this.get(repo, `issues/${issue}`, issueDetail);
    return { state, labels: labels.map((label) => label.name) };
  }

  async getPullRequest(repo: string, number: number) {
    try {
      const pull = await this.get(repo, `pulls/${number}`, pullRow);
      return { state: pull.merged_at === null ? pull.state : ('merged' as const), body: pull.body ?? '', headSha: pull.head.sha };
    } catch (error) {
      if (error instanceof HttpError && error.status === 404) return null;
      throw error;
    }
  }

  async findPullRequest(repo: string, issue: number) {
    // Closing keywords GitHub honors, optionally with an explicit reference to this same repo.
    const closes = new RegExp(`\\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?\\s+(?:${repo.replaceAll('.', '\\.')})?#${issue}(?!\\d)`, 'i');
    // Newest first: the epic's final PR is nearly always on the first page.
    for await (const rows of this.pages(repo, 'pulls', { state: 'all', sort: 'created', direction: 'desc' }, pullRow)) {
      const found = rows.find((pull) => closes.test(pull.body ?? ''));
      if (found) return { number: found.number, state: found.merged_at === null ? found.state : ('merged' as const), headSha: found.head.sha };
    }
    return null;
  }

  async setLabels(repo: string, issue: number, { add, remove }: { add: string[]; remove: string[] }) {
    // Add first so the issue is never left without its state label.
    if (add.length > 0) await this.api(repo, ['-X', 'POST', `repos/${repo}/issues/${issue}/labels`, ...add.flatMap((label) => ['-f', `labels[]=${label}`])]);
    for (const label of remove) {
      try {
        await this.api(repo, ['-X', 'DELETE', `repos/${repo}/issues/${issue}/labels/${encodeURIComponent(label)}`]);
      } catch (error) {
        // Removing a label the issue lacks is a no-op.
        if (!(error instanceof HttpError && error.status === 404 && /label does not exist/i.test(error.message))) throw error;
      }
    }
  }

  async listLabels(repo: string) {
    const names: string[] = [];
    for await (const rows of this.pages(repo, 'labels', {}, labelRow)) names.push(...rows.map((row) => row.name));
    return names;
  }

  async createLabel(repo: string, name: string) {
    try {
      await this.api(repo, ['-X', 'POST', `repos/${repo}/labels`, '-f', `name=${name}`]);
    } catch (error) {
      if (!(error instanceof HttpError && error.status === 422 && /already_exists/.test(error.message))) throw error;
    }
  }
}
