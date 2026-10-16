import { spawnSync } from 'node:child_process';
import { resolveRepoConfig } from '../config/resolve.ts';
import type { Config } from '../config/schema.ts';
import { profileToken } from '../execution/git-workspaces.ts';
import { forgeCwd } from '../integrations/forge-cwd.ts';
import { GhGitHub, type GitHubProfile } from '../integrations/github.ts';

export type Check = { name: string; status: 'ok' | 'warn' | 'fail'; detail?: string };

export interface DoctorDeps {
  which: (command: string) => boolean;
  mint: (profile: GitHubProfile, repo: string) => Promise<string>;
  listLabels: (config: Config, repo: string) => Promise<string[]>;
}

const realDeps: DoctorDeps = {
  which: (command) => spawnSync('which', [command]).status === 0,
  mint: (profile, repo) => profileToken(profile)(repo),
  listLabels: (config, repo) =>
    new GhGitHub({
      profile: config.profiles[config.orchestratorProfile]!,
      cwd: forgeCwd(config.root),
      timeoutMs: config.limits.githubCallTimeoutSeconds * 1000,
    }).listLabels(repo),
};

const identity = (profile: GitHubProfile) => (profile.kind === 'forge' ? `forge agent ${profile.agent}` : 'your gh login');
const message = (error: unknown) => (error instanceof Error ? error.message : String(error));

/** What the machine has to be able to do, and whether each identity can act on each repo. Reads only; creates nothing on GitHub. */
export async function runDoctor(config: Config, overrides: Partial<DoctorDeps> = {}, onCheck: (check: Check) => void = () => {}): Promise<Check[]> {
  const deps = { ...realDeps, ...overrides };
  const checks: Check[] = [];
  const report = (check: Check) => {
    checks.push(check);
    onCheck(check);
    return check.status === 'ok';
  };
  const installed = (command: string) => report(deps.which(command) ? { name: `${command} installed`, status: 'ok' } : { name: `${command} installed`, status: 'fail', detail: 'not found on PATH' });

  const repos = config.repos.map((repo) => resolveRepoConfig(config, repo));
  const orchestrator = config.profiles[config.orchestratorProfile]!;
  const rolesOf = (repo: (typeof repos)[number]) => [repo.agents.author, repo.agents.reviewer];
  const profiles = [orchestrator, ...repos.flatMap((repo) => rolesOf(repo).map((agent) => config.profiles[agent.profile]!))];

  const hasGit = installed('git');
  const hasGh = installed('gh');
  for (const provider of new Set(repos.flatMap((repo) => rolesOf(repo).map((agent) => agent.provider)))) installed(provider);
  const hasForge = profiles.some((profile) => profile.kind === 'forge') ? installed('agent-forge') : true;

  // The schema compares profile names; two names can still point at the same bot or the same login.
  const clashes = repos.flatMap((repo) => {
    const [author, reviewer] = rolesOf(repo).map((agent) => config.profiles[agent.profile]!);
    return identity(author!) === identity(reviewer!) ? [`${repo.name}: author and reviewer both use ${identity(author!)}`] : [];
  });
  report(clashes.length === 0 ? { name: 'author and reviewer are different identities', status: 'ok' } : { name: 'author and reviewer are different identities', status: 'fail', detail: clashes.join('; ') });

  // Without gh, or without agent-forge for a forge profile, the checks below would only repeat the same failure.
  const usable = (profile: GitHubProfile) => hasGit && hasGh && (profile.kind === 'gh' || hasForge);
  const minted = new Set<string>();
  for (const repo of repos) {
    for (const agent of rolesOf(repo)) {
      const profile = config.profiles[agent.profile]!;
      const key = `${identity(profile)}|${repo.name}`;
      if (minted.has(key) || !usable(profile)) continue;
      minted.add(key);
      const name = `${identity(profile)} can mint a token for ${repo.name}`;
      try {
        await deps.mint(profile, repo.name);
        report({ name, status: 'ok' });
      } catch (error) {
        report({ name, status: 'fail', detail: message(error) });
      }
    }
    if (!usable(orchestrator)) continue;
    const name = `${identity(orchestrator)} can read ${repo.name}`;
    try {
      await deps.listLabels(config, repo.name);
      report({ name, status: 'ok' });
    } catch (error) {
      report({ name, status: 'fail', detail: message(error) });
    }
  }
  return checks;
}
