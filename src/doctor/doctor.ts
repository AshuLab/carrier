import { execFile, spawn, spawnSync } from 'node:child_process';
import { createScopedLogger } from '@ashulab/universal-logger';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { socketPathFits } from '../control/server.ts';
import { enginePlacesOf } from '../config/places.ts';
import { resolveRepoConfig, sameAccount } from '../config/resolve.ts';
import type { Config } from '../config/schema.ts';
import { profileToken } from '../execution/git-workspaces.ts';
import { forgeCwd } from '../integrations/forge-cwd.ts';
import { GhGitHub, type GitHubProfile } from '../integrations/github.ts';
import { listLocalModels, localLabel, localUrl, type LocalProvider } from '../harnesses/local.ts';
import { configDirVariable, harnessLabel } from '../harnesses/names.ts';
import { createSkills, type Skills } from '../harnesses/skills.ts';
import { defaultLabels, hasLabel } from '../orchestration/github.ts';
import type { CodedText, TextParams } from '../orchestration/text-params.ts';
import { fixes, installFix } from './fixes.ts';

/**
 * `fix` is one remedy line for the person at the terminal; only failures and warnings have one.
 * `detailCode` and `detailParams` stand for `detail`, `fixCode` and `fixParams` for `fix` ([ADR 0055](../../docs/adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)): each pair is there when its words are, and the words stay.
 * `repo` and `profiles` are set together on the checks about one repo: the names under `config.profiles` the check stands for, never empty.
 */
export type Check = {
  name: string;
  status: 'ok' | 'warn' | 'fail';
  detail?: string;
  detailCode?: string;
  detailParams?: TextParams;
  fix?: string;
  fixCode?: string;
  fixParams?: TextParams;
  repo?: string;
  profiles?: string[];
};

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
  loggedIn: (harness: 'claude' | 'codex', configDir: string | undefined, command?: string) => Promise<boolean>;
  /** Whether an account's `command` runs (`--version` ends well); false when it does not exist or fails. */
  commandRuns: (command: string) => Promise<boolean>;
  /** Starts `agy -p /usage` for the Antigravity login check; throws when it cannot start. */
  startAgy: () => AgyProcess;
  /** Whether the harness of a role finds a skill, for its account and its repo folder. */
  skills: Skills;
}

const log = createScopedLogger('doctor');
const LOGIN_TIMEOUT_MS = 20_000;
const AGY_TIMEOUT_MS = 30_000; // logged in answers in about five seconds
const AGY_LOGGED_OUT = 'Authentication required';

// Antigravity has no status command, so ask for /usage: it costs nothing. The stderr is never kept past the first line (it holds the login URL).
export function startAgy(): AgyProcess {
  const cwd = mkdtempSync(join(tmpdir(), 'carrier-agy-'));
  const child = spawn('agy', ['-p', '/usage', '--output-format', 'json'], { cwd, env: { ...process.env, BROWSER: 'true' }, stdio: ['ignore', 'pipe', 'pipe'] });
  child.once('close', () => rmSync(cwd, { recursive: true, force: true }));
  return child;
}

/** 'in' on status SUCCESS, 'out' at the first stderr line asking for login (the process is killed then, not awaited), 'unknown' otherwise. */
export function agyLogin(deps: Pick<DoctorDeps, 'startAgy'>): Promise<'in' | 'out' | 'unknown'> {
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
export function cliLoggedIn(harness: 'claude' | 'codex', configDir: string | undefined, timeoutMs = LOGIN_TIMEOUT_MS, command: string = harness) {
  const env = configDir ? { ...process.env, [configDirVariable[harness]]: configDir } : process.env;
  const args = harness === 'claude' ? ['auth', 'status'] : ['login', 'status'];
  return new Promise<boolean>((resolve, reject) => {
    const child = spawn(command, args, { env, stdio: ['ignore', 'pipe', 'ignore'], detached: true });
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
  loggedIn: (harness, configDir, command) => cliLoggedIn(harness, configDir, undefined, command),
  commandRuns: (command) => new Promise((resolve) => execFile(command, ['--version'], { timeout: 10_000 }, (error) => resolve(error === null))),
  startAgy,
  skills: createSkills(),
  which: (command) => spawnSync('which', [command]).status === 0,
  mint: (profile, repo) => profileToken(profile)(repo),
  listLabels: (config, repo, folder) =>
    new GhGitHub({
      profile: () => config.profiles[config.orchestratorProfile]!,
      cwd: forgeCwd(enginePlacesOf(folder)),
      timeoutMs: () => config.limits.githubCallTimeoutSeconds * 1000,
    }).listLabels(repo),
};

const identity = (profile: GitHubProfile) => (profile.kind === 'forge' ? `forge agent ${profile.agent}` : 'your gh login');
const message = (error: unknown) => (error instanceof Error ? error.message : String(error));
/** The detail of a check: its words with its code and parameters. */
const said = ({ code, text, params }: CodedText) => ({ detail: text, detailCode: code, detailParams: params });
/** The remedy of a check, or nothing at all when none applies: a remedy that does not apply is no key. */
const remedy = (fix: CodedText | undefined) => (fix === undefined ? {} : { fix: fix.text, fixCode: fix.code, fixParams: fix.params });

/** What the machine has to be able to do, and whether each identity can act on each repo. Reads only; creates nothing on GitHub. */
export async function runDoctor(config: Config, folder: string, overrides: Partial<DoctorDeps> = {}, onCheck: (check: Check) => void = () => {}, onStart: (name: string) => void = () => {}): Promise<Check[]> {
  const deps = { ...realDeps, ...overrides };
  const checks: Check[] = [];
  const report = (check: Check) => {
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
    return report(found ? { name, status: 'ok' } : { name, status: 'fail', ...said({ code: 'doctor.notOnPath', text: 'not found on PATH', params: {} }), ...remedy(installFix[command]) });
  };

  const repos = config.repos.map((repo) => resolveRepoConfig(config, repo));
  const orchestrator = config.profiles[config.orchestratorProfile]!;
  const rolesOf = (repo: (typeof repos)[number]) => [repo.agents.author, repo.agents.reviewer, ...(repo.agents.extraReviewers ?? []), ...(repo.agents.leadReviewer ? [repo.agents.leadReviewer] : [])];
  const profiles = [orchestrator, ...repos.flatMap((repo) => rolesOf(repo).map((agent) => config.profiles[agent.profile]!))];

  // Only a path that does not fit is reported: Carrier works without the socket, it just has none for the app to use.
  const socket = enginePlacesOf(folder).socket;
  const { fits, bytes } = socketPathFits(socket);
  if (fits === false) report({ name: 'control socket path fits', status: 'warn', ...said({ code: 'doctor.socketPathTooLong', text: `${socket} is ${bytes} bytes and a socket path holds 103, so Carrier starts without its control socket`, params: { path: socket, bytes, max: 103 } }), ...remedy(fixes.socketPath) });

  const hasGit = installed('git');
  const hasGh = installed('gh');
  // An agent that has its own `command` is not looked up on the PATH; the account's own check below runs it.
  for (const harness of new Set(repos.flatMap((repo) => rolesOf(repo).filter((agent) => agent.command === undefined).map((agent) => agent.harness)))) installed(harness);
  const hasForge = profiles.some((profile) => profile.kind === 'forge') ? installed('agent-forge') : true;

  // A local model needs its server up and the model downloaded; one check per distinct server and model.
  const locals = new Map<string, { provider: LocalProvider; model: string }>();
  for (const repo of repos) for (const { provider, model } of rolesOf(repo)) if (provider) locals.set(`${provider}|${model}`, { provider, model });
  for (const { provider, model } of locals.values()) {
    const name = `${localLabel[provider]} has ${model}`;
    onStart(name);
    try {
      const have = await deps.localModels(provider);
      report(have.includes(model) ? { name, status: 'ok' } : { name, status: 'fail', ...said({ code: 'doctor.modelNotDownloaded', text: `not downloaded there (it has: ${have.join(', ') || 'nothing'})`, params: { have: have.join(', ') } }), ...remedy(fixes.modelMissing(model)) });
    } catch (error) {
      log.error('a local model server did not answer', error, { provider });
      report({ name, status: 'fail', ...said({ code: 'doctor.serverNotAnswering', text: `${localLabel[provider]} is not answering at ${localUrl[provider]}; start its server`, params: { server: localLabel[provider], url: localUrl[provider] } }), ...remedy(fixes.serverDown) });
    }
  }

  // A `command` that does not exist or does not run fails its account, whether a role uses it or not: the run would not start.
  const commandRuns = async (provider: string, harness: string, command: string) => {
    const name = `${harness} provider ${provider} command runs`;
    onStart(name);
    const runs = await deps.commandRuns(command).catch(() => false);
    return report(runs ? { name, status: 'ok' } : { name, status: 'fail', ...said({ code: 'doctor.commandNotRunnable', text: `${command} does not exist or does not run`, params: { command } }), ...remedy(fixes.command(provider)) });
  };

  // Every Claude and Codex provider, whether a role uses it or not: a login that has run out shows here before an epic needs it.
  // A role's provider that is not logged in fails; any other only warns. Antigravity has no folder and a behaviour test instead.
  const roleProviders = new Set(repos.flatMap((repo) => rolesOf(repo).flatMap((agent) => [agent.option, agent.providerName].filter((v): v is string => v !== undefined))));
  for (const [provider, { harness, configDir, command }] of Object.entries(config.providers)) {
    if (command === undefined ? missing.has(harness) : !(await commandRuns(provider, harness, command))) continue;
    if (harness === 'agy') {
      const name = `agy provider ${provider} is logged in`;
      onStart(name);
      try {
        const login = await agyLogin(deps);
        if (login === 'in') report({ name, status: 'ok' });
        else if (login === 'out') report({ name, status: roleProviders.has(provider) ? 'fail' : 'warn', ...said({ code: 'doctor.loginMissing', text: 'not logged in', params: {} }), ...remedy(fixes.login('agy', undefined)) });
        else report({ name, status: 'warn', ...said({ code: 'doctor.agyLoginUnknown', text: 'could not tell whether agy is logged in (it neither answered nor asked for a login in time)', params: {} }) });
      } catch (error) {
        log.error('could not run agy to check the login', error, { provider });
        report({ name, status: 'warn', ...said({ code: 'doctor.agyNotRunnable', text: 'could not run agy to check the login', params: {} }), ...remedy(installFix.agy) });
      }
      continue;
    }
    if (harness !== 'claude' && harness !== 'codex') continue;
    const name = `${harness} provider ${provider} is logged in`;
    const status = roleProviders.has(provider) ? 'fail' : 'warn';
    onStart(name);
    try {
      report((await deps.loggedIn(harness, configDir, ...(command === undefined ? [] : [command]))) ? { name, status: 'ok' } : { name, status, ...said(configDir ? { code: 'doctor.loginMissingAt', text: `not logged in at ${configDir}`, params: { configDir } } : { code: 'doctor.loginMissingInEnvironment', text: 'not logged in in the environment Carrier runs in', params: {} }), ...remedy(fixes.login(harness, configDir)) });
    } catch (error) {
      log.error(`could not run ${harness} to check the login`, error, { provider });
      report({ name, status, ...said(configDir ? { code: 'doctor.loginCheckFailedAt', text: `could not run ${harness} to check the login at ${configDir}`, params: { harness, configDir } } : { code: 'doctor.loginCheckFailedInEnvironment', text: `could not run ${harness} to check the login in the environment Carrier runs in`, params: { harness } }), ...remedy(installFix[harness]) });
    }
  }

  // Without gh, or without agent-forge for a forge profile, the checks below would only repeat the same failure.
  const usable = (profile: GitHubProfile) => hasGit && hasGh && (profile.kind === 'gh' || hasForge);
  for (const repo of repos) {
    // One mint check per identity, standing for every profile name the roles of this repo use for it.
    const minted = new Map<string, string[]>();
    for (const agent of rolesOf(repo)) {
      const key = identity(config.profiles[agent.profile]!);
      minted.set(key, [...new Set([...(minted.get(key) ?? []), agent.profile])]);
    }
    for (const names of minted.values()) {
      const profile = config.profiles[names[0]!]!;
      if (!usable(profile)) continue;
      const name = `${identity(profile)} can mint a token for ${repo.name}`;
      onStart(name);
      try {
        await deps.mint(profile, repo.name);
        report({ name, status: 'ok', repo: repo.name, profiles: names });
      } catch (error) {
        report({ name, status: 'fail', ...said({ code: 'doctor.mintFailed', text: message(error), params: { error: message(error) } }), ...remedy(fixes.mint(profile, repo.name, message(error))), repo: repo.name, profiles: names });
      }
    }
    if (!usable(orchestrator)) continue;
    const name = `${identity(orchestrator)} can read ${repo.name}`;
    onStart(name);
    let labels: string[];
    try {
      labels = await deps.listLabels(config, repo.name, folder);
    } catch (error) {
      report({ name, status: 'fail', ...said({ code: 'doctor.readFailed', text: message(error), params: { error: message(error) } }), ...remedy(fixes.read(repo.name, message(error))), repo: repo.name, profiles: [config.orchestratorProfile] });
      continue;
    }
    report({ name, status: 'ok', repo: repo.name, profiles: [config.orchestratorProfile] });
    // The labels the read check already fetched say whether Solve is set up: no second call.
    const solveName = `${repo.name} has the Solve labels`;
    onStart(solveName);
    const missing = [config.labels.epic, config.labels.ready].filter((label) => !hasLabel(labels, label));
    // Solve creates the default labels; one the person chose is theirs to create.
    const own = missing.filter((label) => !hasLabel([defaultLabels.epic, defaultLabels.ready], label));
    const fix = own.length === 0 ? fixes.solve : fixes.ownLabels(own);
    report(missing.length === 0 ? { name: solveName, status: 'ok', repo: repo.name, profiles: [config.orchestratorProfile] } : { name: solveName, status: 'fail', ...said({ code: 'doctor.labelsMissing', text: `missing ${missing.join(', ')}`, params: { labels: missing.join(', '), count: missing.length } }), ...remedy(fix), repo: repo.name, profiles: [config.orchestratorProfile] });
  }

  // The skills each role invokes, for the account it runs on, looked for from the repo's clone: the worktree of an epic does not exist yet.
  // A skill the person named that is absent is a problem; a default that is absent, or any answer that cannot tell, is a warning.
  for (const repo of repos) {
    const clone = join(enginePlacesOf(folder).repos, repo.name);
    const invoked = [
      { role: 'author', agent: repo.agents.author, skills: [repo.skills!.ship, repo.skills!.fix] },
      { role: 'reviewer', agent: repo.agents.reviewer, skills: [repo.skills!.review.review, repo.skills!.review.publish] },
      // The slots the engine names them by: `reviewer-2` to `reviewer-4`, and `lead`.
      ...(repo.agents.extraReviewers ?? []).map((agent, i) => ({ role: `reviewer-${i + 2}`, agent, skills: [agent.skills.review, agent.skills.publish] })),
      ...(repo.agents.leadReviewer && repo.skills!.lead ? [{ role: 'lead', agent: repo.agents.leadReviewer, skills: [repo.skills!.lead.review, repo.skills!.lead.publish] }] : []),
    ];
    for (const { role, agent, skills } of invoked) {
      for (const skill of skills) {
        if (skill === null) continue;
        const name = `${repo.name} ${role} can use the skill ${skill.name}`;
        onStart(name);
        const answer = await deps.skills.has(agent.harness, agent.configDir, clone, skill.name);
        const where = { repo: repo.name, profiles: [agent.profile] };
        if (answer === 'present') report({ name, status: 'ok', ...where });
        else if (answer === 'cannot-tell') report({ name, status: 'warn', ...said({ code: 'doctor.skillUnreadable', text: `could not tell whether ${harnessLabel[agent.harness]} finds it: some place it looks could not be read`, params: { harness: harnessLabel[agent.harness] } }), ...remedy(fixes.skillUnread), ...where });
        else if (skill.named) report({ name, status: 'fail', ...said({ code: 'doctor.skillNotFound', text: `${harnessLabel[agent.harness]} does not find it for the account of the ${role}`, params: { harness: harnessLabel[agent.harness], role } }), ...remedy(fixes.skill(skill.name)), ...where });
        else report({ name, status: 'warn', ...said({ code: 'doctor.skillNotFoundDefault', text: `${harnessLabel[agent.harness]} does not find it for the account of the ${role} (it is Solve's default, so the epic runs anyway)`, params: { harness: harnessLabel[agent.harness], role } }), ...remedy(fixes.skill(skill.name)), ...where });
      }
    }
  }
  return checks;
}
