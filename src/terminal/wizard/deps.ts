import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import type { Config } from '../../config/schema.ts';
import { repoNamePattern } from '../../config/schema.ts';
import { defaults } from '../../config/load.ts';
import { cliLoggedIn, runDoctor } from '../../doctor/doctor.ts';
import { ghReposArgs, parseRepos } from '../../integrations/available-repos.ts';
import { forgeCwd } from '../../integrations/forge-cwd.ts';
import { GhGitHub } from '../../integrations/github.ts';
import { listLocalModels, type LocalProvider } from '../../harnesses/local.ts';
import type { Option } from '../prompts/types.ts';
import { readForgeAgents, type ForgeAgent } from './forge-registry.ts';

/** Everything that touches the machine, replaceable for tests. */
export interface InitDeps {
  which: (command: string) => boolean;
  forgeAgents: () => ForgeAgent[];
  ghLogin: () => string | undefined;
  /** `owner/name` of the repos the gh login can push to on that page (1 is the first), most recently pushed first, and whether GitHub has more pages. Throws when it cannot list. */
  listRepos: (page: number) => { names: string[]; hasMore: boolean };
  originRepo: () => string | undefined;
  codexModel: () => string | undefined;
  /** The models Codex itself lists as available (its local cache); empty when it has none. */
  codexModels: () => Option<string>[];
  /** The models `agy models` lists; empty when it cannot. */
  agyModels: () => Option<string>[];
  /** The models a local server has; throws when it is not running. */
  localModels: (local: LocalProvider) => Promise<string[]>;
  /** The config folders of that harness found in the home folder (`~/.claude`, `~/.claude-*`, `~/.codex`), absolute. */
  configFolders: (harness: 'claude' | 'codex') => string[];
  /** Whether that harness is logged in with that config folder (the environment when none); throws when its CLI cannot run. */
  loggedIn: typeof cliLoggedIn;
  exists: (path: string) => boolean;
  write: (path: string, content: string) => void;
  doctor: typeof runDoctor;
  /** The user's config at `path`, parsed; throws when unreadable. */
  readConfig: (path: string) => unknown;
  /** Runs `agent-forge add` on the terminal; true when it ended well. */
  forgeAdd: () => boolean;
  /** Epics labeled ready now, per repo; undefined for a repo that cannot be read. */
  readyEpics: (config: Config) => Promise<Record<string, number | undefined>>;
}


export const realDeps: InitDeps = {
  which: (command) => spawnSync('which', [command], { stdio: 'ignore' }).status === 0,
  forgeAgents: () => readForgeAgents(),
  ghLogin: () => {
    try {
      return execFileSync('gh', ['api', 'user', '--jq', '.login'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() || undefined;
    } catch {
      return undefined; // not logged in or no gh: the doctor reports it, here it only means no hint
    }
  },
  listRepos: (page) => {
    // no config yet at init: the default bounds the call
    const { repos, hasMore } = parseRepos(execFileSync('gh', ghReposArgs(page), { encoding: 'utf8', timeout: defaults.limits.githubCallTimeoutSeconds * 1000, stdio: ['ignore', 'pipe', 'pipe'] }));
    return { names: repos.map((repo) => repo.name), hasMore };
  },
  originRepo: () => {
    const url = spawnSync('git', ['remote', 'get-url', 'origin'], { encoding: 'utf8' }).stdout.trim();
    const repo = /github\.com[:/]([\w.-]+\/[\w.-]+?)(?:\.git)?$/.exec(url)?.[1];
    return repo !== undefined && repoNamePattern.test(repo) ? repo : undefined;
  },
  codexModel: () => {
    try {
      return /^model\s*=\s*"([^"]+)"/m.exec(readFileSync(join(process.env.CODEX_HOME ?? join(homedir(), '.codex'), 'config.toml'), 'utf8'))?.[1];
    } catch {
      return undefined;
    }
  },
  codexModels: () => {
    try {
      const cache = JSON.parse(readFileSync(join(process.env.CODEX_HOME ?? join(homedir(), '.codex'), 'models_cache.json'), 'utf8')) as { models?: { slug?: string; description?: string; visibility?: string }[] };
      return (cache.models ?? []).flatMap((m) => (m.visibility === 'list' && m.slug ? [{ value: m.slug, label: m.slug, hint: m.description }] : []));
    } catch {
      return []; // no cache yet: the model is typed
    }
  },
  agyModels: () => {
    try {
      // "Fetching available models..." then `id<TAB>label` per line.
      const out = execFileSync('agy', ['models'], { encoding: 'utf8', timeout: 20_000, stdio: ['ignore', 'pipe', 'ignore'] });
      return out.split('\n').flatMap((line) => {
        const [id, label] = line.split('\t');
        return id && label ? [{ value: id, label: id, hint: label }] : [];
      });
    } catch {
      return []; // not installed, not logged in or offline: the model is typed
    }
  },
  localModels: (local) => listLocalModels(local),
  configFolders: (harness) => {
    const home = homedir();
    const isFolder = (path: string) => {
      try {
        return statSync(path).isDirectory();
      } catch {
        return false; // a dangling link
      }
    };
    return readdirSync(home)
      .filter((name) => (harness === 'claude' ? name === '.claude' || name.startsWith('.claude-') : name === '.codex') && isFolder(join(home, name)))
      .sort()
      .map((name) => join(home, name));
  },
  loggedIn: cliLoggedIn,
  exists: existsSync,
  write: (path, content) => {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, content);
  },
  doctor: runDoctor,
  readConfig: (path) => JSON.parse(readFileSync(path, 'utf8')),
  forgeAdd: () => spawnSync('agent-forge', ['add'], { stdio: 'inherit' }).status === 0,
  readyEpics: async (config) => {
    const github = new GhGitHub({ profile: config.profiles[config.orchestratorProfile]!, cwd: forgeCwd(config.root), timeoutMs: config.limits.githubCallTimeoutSeconds * 1000 });
    return Object.fromEntries(await Promise.all(config.repos.map(async (repo) => [repo.name, await github.listReadyEpics(repo.name).then((epics) => epics.length, () => undefined)] as const)));
  },
};
