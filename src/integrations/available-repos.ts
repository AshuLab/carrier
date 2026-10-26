import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { repoNamePattern } from '../config/schema.ts';

export type AvailableRepo = { name: string; private: boolean; pushedAt: string | null };

export const pageSize = 30;

/** One page of the repos the gh login can push to, newest push first: the raw count of the page on the first line, then one repo per line (tab separated), archived and disabled left out. */
export const ghReposArgs = (page: number) => [
  'api',
  `user/repos?affiliation=owner,organization_member&sort=pushed&per_page=${pageSize}&page=${page}`,
  '--jq',
  '(length | tostring), (.[] | select(.archived or .disabled | not) | select(.permissions.push) | [.full_name, .private, .pushed_at // ""] | @tsv)',
];

/** `hasMore` follows the raw page (it came back full), not what survived the filter. A line that does not fit (a name that is not `owner/name`) is dropped. */
export function parseRepos(output: string): { repos: AvailableRepo[]; hasMore: boolean } {
  const [count, ...lines] = output.split('\n');
  const repos = lines.flatMap((line) => {
    const [name = '', isPrivate, pushedAt] = line.split('\t');
    return repoNamePattern.test(name) ? [{ name, private: isPrivate === 'true', pushedAt: pushedAt || null }] : [];
  });
  return { repos, hasMore: Number(count) === pageSize };
}

/** The first page, without blocking the engine; throws when gh is missing, not logged in, offline or past `timeoutMs`. */
export async function listAvailableRepos(timeoutMs: number): Promise<AvailableRepo[]> {
  const { stdout } = await promisify(execFile)('gh', ghReposArgs(1), { encoding: 'utf8', timeout: timeoutMs });
  return parseRepos(stdout).repos;
}
