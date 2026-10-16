import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { repoNamePattern } from '../config/schema.ts';

/**
 * Where to run `gh` / Forge for a repo. Forge picks the App installation from the `origin` of the cwd, so it must
 * be a repo under the right owner: the managed clone (`<root>/repos/<owner>/<name>`) once it exists, and before the
 * first clone (the first poll comes first) a stub repo whose only content is that `origin`.
 */
export function forgeCwd(root: string, remoteUrl: (repo: string) => string = (repo) => `https://github.com/${repo}.git`): (repo: string) => string {
  return (repo) => {
    if (!repoNamePattern.test(repo)) throw new Error(`invalid repo "${repo}", expected owner/name`);
    const clone = join(root, 'repos', repo);
    if (existsSync(join(clone, '.git'))) return clone;
    const stub = join(root, 'orchestrator', 'forge-cwd', repo);
    if (!existsSync(join(stub, '.git'))) {
      mkdirSync(stub, { recursive: true });
      execFileSync('git', ['init', '-q'], { cwd: stub });
      execFileSync('git', ['remote', 'add', 'origin', remoteUrl(repo)], { cwd: stub });
    }
    return stub;
  };
}
