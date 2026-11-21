import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { repoNamePattern } from '../config/schema.ts';

/** `description` is read only for the chat (`read`), which shows it in its clone sheet; the engine's picker never asks for it. */
export type AvailableRepo = { name: string; private: boolean; pushedAt: string | null; description?: string };

export const pageSize = 30;

/**
 * One page of the repos the gh login can reach, newest push first: the raw count of the page on the first line, then one repo per
 * line (tab separated), archived and disabled left out. `push` (the engine's picker, the default) keeps what the login can push to;
 * `read` (the chat) also takes the repos it is only a collaborator on, keeps every one it can read, and adds the description as a fourth column.
 */
export const ghReposArgs = (page: number, scope: 'push' | 'read' = 'push') => [
  'api',
  `user/repos?affiliation=${scope === 'push' ? 'owner,organization_member' : 'owner,collaborator,organization_member'}&sort=pushed&per_page=${pageSize}&page=${page}`,
  '--jq',
  `(length | tostring), (.[] | select(.archived or .disabled | not) | ${scope === 'push' ? 'select(.permissions.push) | ' : ''}[.full_name, .private, .pushed_at // ""${scope === 'read' ? ', (.description // "" | gsub("[\\t\\r\\n]+"; " "))' : ''}] | @tsv)`,
];

/** `hasMore` follows the raw page (it came back full), not what survived the filter. A line that does not fit (a name that is not `owner/name`) is dropped. */
export function parseRepos(output: string): { repos: AvailableRepo[]; hasMore: boolean } {
  const [count, ...lines] = output.split('\n');
  const repos = lines.flatMap((line) => {
    const [name = '', isPrivate, pushedAt, description] = line.split('\t');
    return repoNamePattern.test(name) ? [{ name, private: isPrivate === 'true', pushedAt: pushedAt || null, ...(description ? { description } : {}) }] : [];
  });
  return { repos, hasMore: Number(count) === pageSize };
}

/** One page, without blocking the engine; throws when gh is missing, not logged in, offline or past `timeoutMs`. */
export async function listAvailableRepos(page: number, timeoutMs: number, scope: 'push' | 'read' = 'push'): Promise<{ repos: AvailableRepo[]; hasMore: boolean }> {
  const { stdout } = await promisify(execFile)('gh', ghReposArgs(page, scope), { encoding: 'utf8', timeout: timeoutMs });
  return parseRepos(stdout);
}
