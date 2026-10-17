import { spawnSync } from 'node:child_process';
import { resolveRepoConfig } from '../config/resolve.ts';
import type { Config } from '../config/schema.ts';
import { profileToken } from '../execution/git-workspaces.ts';
import { forgeCwd } from '../integrations/forge-cwd.ts';
import { GhGitHub, type GitHubProfile } from '../integrations/github.ts';
import { listLocalModels, localLabel, localUrl, type LocalProvider } from '../harnesses/local.ts';

/** `fix` is one remedy line for the person at the terminal; only failures have one. */
export type Check = { name: string; status: 'ok' | 'warn' | 'fail'; detail?: string; fix?: string };

export interface DoctorDeps {
  which: (command: string) => boolean;
  mint: (profile: GitHubProfile, repo: string) => Promise<string>;
  listLabels: (config: Config, repo: string) => Promise<string[]>;
  /** What a local model server has; throws when it does not answer. */
  localModels: (local: LocalProvider) => Promise<string[]>;
}

const realDeps: DoctorDeps = {
  localModels: (local) => listLocalModels(local),
  which: (command) => spawnSync('which', [command]).status === 0,
  mint: (profile, repo) => profileToken(profile)(repo),
  listLabels: (config, repo) =>
    new GhGitHub({
      profile: config.profiles[config.orchestratorProfile]!,
      cwd: forgeCwd(config.root),
      timeoutMs: config.limits.githubCallTimeoutSeconds * 1000,
    }).listLabels(repo),
};

// Every remedy lives here. They only repeat what a check already knows (names, owners): nothing from a child's output.
const installFix: Record<string, string> = {
  git: 'install git (xcode-select --install on macOS)',
  gh: 'install the GitHub CLI (https://cli.github.com) and run: gh auth login',
  claude: 'install Claude Code (https://claude.com/claude-code) and sign in once',
  codex: 'install the Codex CLI and run: codex login',
  agy: 'install Antigravity and run agy once to sign in',
  'agent-forge': 'install it: pnpm add -g @ashulab/agent-forge (https://github.com/AshuLab/agent-forge)',
};
const fixes = {
  mint(profile: GitHubProfile, repo: string, detail: string) {
    if (profile.kind === 'gh') return 'run: gh auth login';
    if (/agent not found/i.test(detail)) return 'agent-forge --list shows your agents; add one with: agent-forge add';
    if (/installation/i.test(detail)) return `install the GitHub App of that agent on ${repo.split('/')[0]}`;
    if (/private key/i.test(detail)) return 'check privateKeyPath of that agent in your Forge registry';
    return `run: agent-forge token --agent ${profile.agent} from a clone of the repo to see the full error`;
  },
  read(repo: string, detail: string) {
    if (detail.includes('404')) return `the repo does not exist or this identity cannot see it: install the App on ${repo.split('/')[0]} and give it access to ${repo}`;
    if (detail.includes('401')) return "the identity's credentials were rejected: for gh run gh auth login, for a bot check its App in Forge";
    return undefined;
  },
  clash: 'use two different bots (agent-forge add) or one bot and your gh login',
  serverDown: 'start the server (LM Studio: lms server start, Ollama: ollama serve) and download the model',
  modelMissing: (model: string) => `download it in LM Studio / ollama pull ${model}`,
};

const identity = (profile: GitHubProfile) => (profile.kind === 'forge' ? `forge agent ${profile.agent}` : 'your gh login');
const message = (error: unknown) => (error instanceof Error ? error.message : String(error));

/** What the machine has to be able to do, and whether each identity can act on each repo. Reads only; creates nothing on GitHub. */
export async function runDoctor(config: Config, overrides: Partial<DoctorDeps> = {}, onCheck: (check: Check) => void = () => {}, onStart: (name: string) => void = () => {}): Promise<Check[]> {
  const deps = { ...realDeps, ...overrides };
  const checks: Check[] = [];
  const report = (check: Check) => {
    if (check.fix === undefined) delete check.fix; // a remedy that does not apply is no key at all
    checks.push(check);
    onCheck(check);
    return check.status === 'ok';
  };
  const installed = (command: string) => {
    const name = `${command} installed`;
    onStart(name);
    return report(deps.which(command) ? { name, status: 'ok' } : { name, status: 'fail', detail: 'not found on PATH', fix: installFix[command] });
  };

  const repos = config.repos.map((repo) => resolveRepoConfig(config, repo));
  const orchestrator = config.profiles[config.orchestratorProfile]!;
  const rolesOf = (repo: (typeof repos)[number]) => [repo.agents.author, repo.agents.reviewer];
  const profiles = [orchestrator, ...repos.flatMap((repo) => rolesOf(repo).map((agent) => config.profiles[agent.profile]!))];

  const hasGit = installed('git');
  const hasGh = installed('gh');
  for (const harness of new Set(repos.flatMap((repo) => rolesOf(repo).map((agent) => agent.harness)))) installed(harness);
  const hasForge = profiles.some((profile) => profile.kind === 'forge') ? installed('agent-forge') : true;

  // A local model needs its server up and the model downloaded; one check per distinct server and model.
  const locals = new Map<string, { provider: LocalProvider; model: string }>();
  for (const repo of repos) for (const { provider, model } of rolesOf(repo)) if (provider) locals.set(`${provider}|${model}`, { provider, model });
  for (const { provider, model } of locals.values()) {
    const name = `${localLabel[provider]} has ${model}`;
    onStart(name);
    try {
      const have = await deps.localModels(provider);
      report(have.includes(model) ? { name, status: 'ok' } : { name, status: 'fail', detail: `not downloaded there (it has: ${have.join(', ') || 'nothing'})`, fix: fixes.modelMissing(model) });
    } catch {
      report({ name, status: 'fail', detail: `${localLabel[provider]} is not answering at ${localUrl[provider]}; start its server`, fix: fixes.serverDown });
    }
  }

  // The schema compares profile names; two names can still point at the same bot or the same login.
  onStart('author and reviewer are different identities');
  const clashes = repos.flatMap((repo) => {
    const [author, reviewer] = rolesOf(repo).map((agent) => config.profiles[agent.profile]!);
    return identity(author!) === identity(reviewer!) ? [`${repo.name}: author and reviewer both use ${identity(author!)}`] : [];
  });
  report(clashes.length === 0 ? { name: 'author and reviewer are different identities', status: 'ok' } : { name: 'author and reviewer are different identities', status: 'fail', detail: clashes.join('; '), fix: fixes.clash });

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
      onStart(name);
      try {
        await deps.mint(profile, repo.name);
        report({ name, status: 'ok' });
      } catch (error) {
        report({ name, status: 'fail', detail: message(error), fix: fixes.mint(profile, repo.name, message(error)) });
      }
    }
    if (!usable(orchestrator)) continue;
    const name = `${identity(orchestrator)} can read ${repo.name}`;
    onStart(name);
    try {
      await deps.listLabels(config, repo.name);
      report({ name, status: 'ok' });
    } catch (error) {
      report({ name, status: 'fail', detail: message(error), fix: fixes.read(repo.name, message(error)) });
    }
  }
  return checks;
}
