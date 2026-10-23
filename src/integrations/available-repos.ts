import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { repoNamePattern } from '../config/schema.ts';

export type AvailableRepo = { name: string; private: boolean; pushedAt: string | null };

/** The repos the gh login can push to, newest push first, archived and disabled left out: one line each, tab separated. */
export const ghReposArgs = [
  'api',
  'user/repos?affiliation=owner,organization_member&sort=pushed&per_page=100',
  '--jq',
  '.[] | select(.archived or .disabled | not) | select(.permissions.push) | [.full_name, .private, .pushed_at // ""] | @tsv',
];

/** A line that does not fit (a name that is not `owner/name`) is dropped. */
export function parseRepos(output: string): AvailableRepo[] {
  return output.split('\n').flatMap((line) => {
    const [name = '', isPrivate, pushedAt] = line.split('\t');
    return repoNamePattern.test(name) ? [{ name, private: isPrivate === 'true', pushedAt: pushedAt || null }] : [];
  });
}

/** Without blocking the engine; throws when gh is missing, not logged in, offline or past `timeoutMs`. */
export async function listAvailableRepos(timeoutMs: number): Promise<AvailableRepo[]> {
  const { stdout } = await promisify(execFile)('gh', ghReposArgs, { encoding: 'utf8', timeout: timeoutMs });
  return parseRepos(stdout);
}
