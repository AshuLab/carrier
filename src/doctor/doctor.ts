import { spawn, spawnSync } from 'node:child_process';
import { createScopedLogger } from '@ashulab/universal-logger';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { socketPathFits } from '../control/server.ts';
import { enginePlacesOf } from '../config/engine-places.ts';
import { resolveRepoConfig, sameAccount } from '../config/resolve.ts';
import type { Config } from '../config/schema.ts';
import { profileToken } from '../execution/git-workspaces.ts';
import { forgeCwd } from '../integrations/forge-cwd.ts';
import { GhGitHub, type GitHubProfile } from '../integrations/github.ts';
import { listLocalModels, localLabel, localUrl, type LocalProvider } from '../harnesses/local.ts';
import { configDirVariable } from '../harnesses/names.ts';
import { fixes, installFix } from './fixes.ts';

/** `fix` is one remedy line for the person at the terminal; only failures and warnings have one. */
export type Check = { name: string; status: 'ok' | 'warn' | 'fail'; detail?: string; fix?: string };

/** The part of the agy process the login check reads; the check kills it as soon as it knows. */
export interface AgyProcess {
  stdout: NodeJS.ReadableStream;
  stderr: NodeJS.ReadableStream;
  kill: () => unknown;
  once: (event: 'close' | 'error', listener: (error?: Error) => void) => unknown;
}

export interface DoctorDeps {
  which: (command: string) => boolean;
  mint: (profile: GitHubProfile, repo: string) => Promise<string>;
  listLabels: (config: Config, repo: string, folder: string) => Promise<string[]>;
  /** What a local model server has; throws when it does not answer. */
  localModels: (local: LocalProvider) => Promise<string[]>;
  /** Whether a Claude or Codex login works, with the option's config folder (the process environment when none); throws when the CLI cannot run. */
  loggedIn: (harness: 'claude' | 'codex', configDir: string | undefined) => Promise<boolean>;
  /** Starts `agy -p /usage` for the Antigravity login check; throws when it cannot start. */
  startAgy: () => AgyProcess;
}

const log = createScopedLogger('doctor');
const LOGIN_TIMEOUT_MS = 20_000;
const AGY_TIMEOUT_MS = 30_000; // logged in answers in about five seconds
const AGY_LOGGED_OUT = 'Authentication required';

// Antigravity has no status command, so ask for /usage: it costs nothing. The stderr is never kept past the first line (it holds the login URL).
function startAgy(): AgyProcess {
  const cwd = mkdtempSync(join(tmpdir(), 'carrier-agy-'));
  const child = spawn('agy', ['-p', '/usage', '--output-format', 'json'], { cwd, env: { ...process.env, BROWSER: 'true' }, stdio: ['ignore', 'pipe', 'pipe'] });
  child.once('close', () => rmSync(cwd, { recursive: true, force: true }));
  return child;
}

/** 'in' on status SUCCESS, 'out' at the first stderr line asking for login (the process is killed then, not awaited), 'unknown' otherwise. */
function agyLogin(deps: Pick<DoctorDeps, 'startAgy'>): Promise<'in' | 'out' | 'unknown'> {
  return new Promise((resolve, reject) => {
    const child = deps.startAgy();
    let out = '';
    let err = '';
    let settled = false;
    const settle = (verdict: 'in' | 'out' | 'unknown') => {
      if (settled) return; // killing the process closes it, which comes back here
      settled = true;
      clearTimeout(timer);
      resolve(verdict);
      child.kill();
    };
    const timer = setTimeout(() => settle('unknown'), AGY_TIMEOUT_MS);
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.stdout.on('data', (chunk) => (out += chunk));
    child.stderr.on('data', (chunk) => {
      if (err.length < AGY_LOGGED_OUT.length) err += chunk; // only the start of the first line matters
      if (err.startsWith(AGY_LOGGED_OUT)) settle('out');
    });
    child.once('close', () => {
      try {
        settle((JSON.parse(out) as { status?: unknown }).status === 'SUCCESS' ? 'in' : 'unknown');
      } catch {
        settle('unknown');
      }
    });
  });
}

// Reads only the verdict: the output holds an email and an organisation, which never leave this function.
// Async, so the wizard and the doctor's spinner go on while the CLI answers. After the timeout the whole process group is killed and the
// probe rejects at once: a CLI that traps SIGTERM, or leaves a child holding the pipe, cannot keep it waiting.
export function cliLoggedIn(harness: 'claude' | 'codex', configDir: string | undefined, timeoutMs = LOGIN_TIMEOUT_MS) {
  const env = configDir ? { ...process.env, [configDirVariable[harness]]: configDir } : process.env;
  const [command, args] = harness === 'claude' ? ['claude', ['auth', 'status']] : ['codex', ['login', 'status']];
  return new Promise<boolean>((resolve, reject) => {
    const child = spawn(command!, args as string[], { env, stdio: ['ignore', 'pipe', 'ignore'], detached: true });
    let out = '';
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', (chunk) => (out += chunk));
    const timer = setTimeout(() => {
      try {
        process.kill(-child.pid!, 'SIGKILL');
      } catch {
        child.kill('SIGKILL'); // no process group to signal (not POSIX), or it is already gone
      }
      reject(new Error(`${command} ${args.join(' ')} did not answer in ${timeoutMs / 1000} s`));
    }, timeoutMs);
    child.once('error', (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.once('close', (status) => {
      clearTimeout(timer);
      if (harness === 'codex') return resolve(status === 0);
      try {
        resolve((JSON.parse(out) as { loggedIn?: unknown }).loggedIn === true);
      } catch {
        // the parse error carries the start of the output: only this fixed text is logged and thrown
        log.warn('could not read the output of claude auth status');
        reject(new Error('could not read the output of claude auth status'));
      }
    });
  });
}

const realDeps: DoctorDeps = {
  localModels: (local) => listLocalModels(local),
  loggedIn: cliLoggedIn,
  startAgy,
  which: (command) => spawnSync('which', [command]).status === 0,
  mint: (profile, repo) => profileToken(profile)(repo),
  listLabels: (config, repo, folder) =>
    new GhGitHub({
      profile: config.profiles[config.orchestratorProfile]!,
      cwd: forgeCwd(enginePlacesOf(folder)),
      timeoutMs: config.limits.githubCallTimeoutSeconds * 1000,
    }).listLabels(repo),
};

const identity = (profile: GitHubProfile) => (profile.kind === 'forge' ? `forge agent ${profile.agent}` : 'your gh login');
const message = (error: unknown) => (error instanceof Error ? error.message : String(error));

/** What the machine has to be able to do, and whether each identity can act on each repo. Reads only; creates nothing on GitHub. */
export async function runDoctor(config: Config, folder: string, overrides: Partial<DoctorDeps> = {}, onCheck: (check: Check) => void = () => {}, onStart: (name: string) => void = () => {}): Promise<Check[]> {
  const deps = { ...realDeps, ...overrides };
  const checks: Check[] = [];
  const report = (check: Check) => {
    if (check.fix === undefined) delete check.fix; // a remedy that does not apply is no key at all
    checks.push(check);
    onCheck(check);
    return check.status === 'ok';
  };
  const missing = new Set<string>();
  const installed = (command: string) => {
    const name = `${command} installed`;
    onStart(name);
    const found = deps.which(command);
    if (!found) missing.add(command);
    return report(found ? { name, status: 'ok' } : { name, status: 'fail', detail: 'not found on PATH', fix: installFix[command] });
  };

  const repos = config.repos.map((repo) => resolveRepoConfig(config, repo));
  const orchestrator = config.profiles[config.orchestratorProfile]!;
  const rolesOf = (repo: (typeof repos)[number]) => [repo.agents.author, repo.agents.reviewer, ...(repo.agents.leadReviewer ? [repo.agents.leadReviewer] : [])];
  const profiles = [orchestrator, ...repos.flatMap((repo) => rolesOf(repo).map((agent) => config.profiles[agent.profile]!))];

  // Only a path that does not fit is reported: Carrier works without the socket, it just has none for the app to use.
  const socket = enginePlacesOf(folder).socket;
  const { fits, bytes } = socketPathFits(socket);
  if (fits === false) report({ name: 'control socket path fits', status: 'warn', detail: `${socket} is ${bytes} bytes and a socket path holds 103, so Carrier starts without its control socket`, fix: fixes.socketPath });

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
    } catch (error) {
      log.error('a local model server did not answer', error, { provider });
      report({ name, status: 'fail', detail: `${localLabel[provider]} is not answering at ${localUrl[provider]}; start its server`, fix: fixes.serverDown });
    }
  }

  // Every Claude and Codex provider, whether a role uses it or not: a login that has run out shows here before an epic needs it.
  // A role's provider that is not logged in fails; any other only warns. Antigravity has no folder and a behaviour test instead.
  const roleProviders = new Set(repos.flatMap((repo) => rolesOf(repo).flatMap((agent) => [agent.option, agent.providerName].filter((v): v is string => v !== undefined))));
  for (const [provider, { harness, configDir }] of Object.entries(config.providers)) {
    if (missing.has(harness)) continue;
    if (harness === 'agy') {
      const name = `agy provider ${provider} is logged in`;
      onStart(name);
      try {
        const login = await agyLogin(deps);
        if (login === 'in') report({ name, status: 'ok' });
        else if (login === 'out') report({ name, status: roleProviders.has(provider) ? 'fail' : 'warn', detail: 'not logged in', fix: fixes.login('agy', undefined) });
        else report({ name, status: 'warn', detail: 'could not tell whether agy is logged in (it neither answered nor asked for a login in time)' });
      } catch (error) {
        log.error('could not run agy to check the login', error, { provider });
        report({ name, status: 'warn', detail: 'could not run agy to check the login', fix: installFix.agy });
      }
      continue;
    }
    if (harness !== 'claude' && harness !== 'codex') continue;
    const name = `${harness} provider ${provider} is logged in`;
    const status = roleProviders.has(provider) ? 'fail' : 'warn';
    const where = configDir ? `at ${configDir}` : 'in the environment Carrier runs in';
    onStart(name);
    try {
      report((await deps.loggedIn(harness, configDir)) ? { name, status: 'ok' } : { name, status, detail: `not logged in ${where}`, fix: fixes.login(harness, configDir) });
    } catch (error) {
      log.error(`could not run ${harness} to check the login`, error, { provider });
      report({ name, status, detail: `could not run ${harness} to check the login ${where}`, fix: installFix[harness] });
    }
  }

  // The schema compares profile names; two names can still point at the same bot or the same login. A shared identity allows it.
  if (config.identities === 'separate') {
    onStart('author and reviewer are different identities');
    const clashes = repos.flatMap((repo) => {
      const author = config.profiles[repo.agents.author.profile]!;
      const reviewer = config.profiles[repo.agents.reviewer.profile]!;
      const lead = repo.agents.leadReviewer ? config.profiles[repo.agents.leadReviewer.profile] : undefined;
      const issues: string[] = [];
      if (sameAccount(author, reviewer)) issues.push(`${repo.name}: author and reviewer both use ${identity(author)}`);
      if (lead && sameAccount(author, lead)) issues.push(`${repo.name}: author and lead reviewer both use ${identity(author)}`);
      return issues;
    });
    report(clashes.length === 0 ? { name: 'author and reviewer are different identities', status: 'ok' } : { name: 'author and reviewer are different identities', status: 'fail', detail: clashes.join('; '), fix: fixes.clash });
  }

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
      await deps.listLabels(config, repo.name, folder);
      report({ name, status: 'ok' });
    } catch (error) {
      report({ name, status: 'fail', detail: message(error), fix: fixes.read(repo.name, message(error)) });
    }
  }
  return checks;
}
