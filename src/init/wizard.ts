import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { styleText } from 'node:util';
import { defaultConfigPath } from '../config/default-path.ts';
import { defaults, loadConfig } from '../config/load.ts';
import type { Config } from '../config/schema.ts';
import { forgeCwd } from '../integrations/forge-cwd.ts';
import { GhGitHub } from '../integrations/github.ts';
import { repoNamePattern } from '../config/schema.ts';
import { installFix, runDoctor, type Check } from '../doctor/doctor.ts';
import { listLocalModels, localKinds, localLabel, type LocalProvider } from '../harnesses/local.ts';
import { harnessLabel, harnessNames, localProvidersOf, nativeProvider, type HarnessName } from '../harnesses/names.ts';
import { buildConfig, identityText, parseIdentity, parseProvider, parseHarnessModel, type Identity, type Role } from './build-config.ts';
import { readForgeAgents, type ForgeAgent } from './forge-registry.ts';

/** The user said no (Ctrl+C, Esc, or declined the final question): not an error, the caller exits quietly. */
export class Cancelled extends Error {}

type Option<T extends string> = { value: T; label: string; hint?: string; disabled?: boolean };

/** What the wizard needs from the terminal. The real one is clack (src/init/clack-ui.ts); tests script it. */
export interface Ui {
  /** False with `--yes` and without a terminal: nothing may be asked, and confirmations are skipped. */
  interactive: boolean;
  intro(title: string): void;
  outro(message: string): void;
  note(message: string, title: string): void;
  warn(message: string): void;
  /** A check is about to run (the UI may show a spinner); `check` follows with its result. */
  checkStart(name: string): void;
  check(check: Check): void;
  /** All the checks ran: `total` of them, `failed` of which failed. */
  checksEnd(total: number, failed: number): void;
  text(options: { message: string; placeholder?: string; defaultValue?: string; validate?: (value: string) => string | undefined }): Promise<string>;
  select<T extends string>(options: { message: string; options: Option<T>[]; initialValue?: T }): Promise<T>;
  confirm(message: string): Promise<boolean>;
  /** At least one. Several groups are shown as sections; a single group is a plain list to filter by typing. */
  multiselect(options: { message: string; options: Record<string, Option<string>[]>; initialValues?: string[] }): Promise<string[]>;
}

/** Everything that touches the machine, replaceable for tests. */
export interface InitDeps {
  which: (command: string) => boolean;
  forgeAgents: () => ForgeAgent[];
  ghLogin: () => string | undefined;
  /** `owner/name` of the repos the gh login can push to, most recently pushed first. Throws when it cannot list. */
  listRepos: () => string[];
  originRepo: () => string | undefined;
  codexModel: () => string | undefined;
  /** The models Codex itself lists as available (its local cache); empty when it has none. */
  codexModels: () => Option<string>[];
  /** The models `agy models` lists; empty when it cannot. */
  agyModels: () => Option<string>[];
  /** The models a local server has; throws when it is not running. */
  localModels: (local: LocalProvider) => Promise<string[]>;
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

/** Flags answer questions ahead of time; whatever is missing is asked. */
/** `authorProfile` / `reviewerProfile` are `forge:<agent>` or `gh`; `author` / `reviewer` are `<claude|codex>:<model>`; `authorProvider` / `reviewerProvider` are `lmstudio` or `ollama` when that model runs there. */
export type InitFlags = { repo?: string[]; authorProfile?: string; reviewerProfile?: string; author?: string; reviewer?: string; authorProvider?: string; reviewerProvider?: string; out?: string; yes?: boolean };

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
  listRepos: () =>
    execFileSync('gh', ['api', 'user/repos?affiliation=owner,organization_member&sort=pushed&per_page=100', '--jq', '.[] | select(.archived or .disabled | not) | select(.permissions.push) | .full_name'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })
      .split('\n')
      .filter(Boolean),
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

// Aliases the Claude CLI resolves to the latest model of each family, so they do not go stale like a model id does.
const claudeModels: Option<string>[] = [
  { value: 'sonnet', label: 'sonnet', hint: 'latest Sonnet' },
  { value: 'opus', label: 'opus', hint: 'latest Opus' },
  { value: 'fable', label: 'fable', hint: 'latest Fable' },
];
const otherModel = '\0other';

type Answered = Pick<Role, 'identity' | 'harness' | 'model' | 'provider'>;
/** What an existing config already says, to start from when editing it. */
type Prior = { repos: string[]; author: Answered; reviewer: Answered };

function priorFrom(raw: unknown): Prior | undefined {
  const loaded = loadConfig(defaults, raw);
  if (!loaded.ok) return undefined;
  const { config } = loaded;
  const role = (r: Config['agents']['author']): Answered => ({ identity: config.profiles[r.profile]!, harness: r.harness, model: r.model, ...(r.provider && { provider: r.provider }) });
  return { repos: config.repos.map((r) => r.name), author: role(config.agents.author), reviewer: role(config.agents.reviewer) };
}

const roleLine = (r: Answered) => `${r.identity.kind === 'gh' ? 'your gh login' : r.identity.agent} · ${harnessLabel[r.harness]} · ${r.model}${r.provider ? ` (${localLabel[r.provider]})` : ''}`;

/** What is about to be written, in one box. */
export const summary = (repos: string[], author: Answered, reviewer: Answered, out: string) =>
  [`Repos     ${repos.join(', ')}`, `Author    ${roleLine(author)}`, `Reviewer  ${roleLine(reviewer)}`, `Saved to  ${tilde(out)}`].join('\n');

export async function runInit(flags: InitFlags, ui: Ui, deps: InitDeps = realDeps) {
  ui.intro('Carrier setup');
  const interactive = ui.interactive && !flags.yes; // --yes never asks, whatever the terminal

  const forge = { agents: [] as ForgeAgent[] };
  const readForge = () => {
    try {
      forge.agents = deps.forgeAgents();
    } catch (error) {
      ui.warn(`Could not read the Agent Forge registry: ${error instanceof Error ? error.message : String(error)}`);
    }
  };
  readForge();
  const harnesses = harnessNames.filter((p) => deps.which(p));
  const login = deps.ghLogin();
  // Local model servers are optional: a server that is not running is shown as such, not as a failure.
  const locals: Partial<Record<LocalProvider, string[]>> = {};
  for (const kind of localKinds) locals[kind] = await deps.localModels(kind).catch(() => undefined);

  // Nothing is shown when the machine is fine. What cannot work at all stops here, with how to fix it.
  const lacking = [
    ...(['git', 'gh'] as const).filter((tool) => !deps.which(tool)).map((tool) => `${tool}: ${installFix[tool]}`),
    ...(harnesses.length === 0 ? ['an agent CLI, any of these:', ...harnessNames.map((h) => `  ${h}: ${installFix[h]}`)] : []),
  ];
  if (lacking.length > 0) throw new Error(`Carrier needs these before it can run:\n${lacking.map((line) => `  ${line}`).join('\n')}`);
  if (login === undefined) ui.warn('gh is not logged in (run: gh auth login): your repos cannot be listed, and a "my own gh login" identity will not work.');

  // A config that is already there: edit it (its answers become the starting points), start over, or leave it.
  const fallback = defaultConfigPath();
  let out = flags.out === undefined ? undefined : resolve(flags.out);
  let settled = false; // the question below settled where the config goes, and that it may be replaced
  let prior: Prior | undefined;
  if (flags.out === undefined && interactive && deps.exists(fallback)) {
    const choice = await ui.select({
      message: `A config already exists at ${tilde(fallback)}`,
      options: [
        { value: 'edit', label: 'Edit it', hint: 'its answers are the starting points' },
        { value: 'fresh', label: 'Start over', hint: 'replaces it' },
        { value: 'elsewhere', label: 'Save a new one in another file' },
        { value: 'cancel', label: 'Leave it as it is' },
      ],
      initialValue: 'edit',
    });
    if (choice === 'cancel') throw new Cancelled();
    if (choice === 'edit' || choice === 'fresh') {
      out = fallback;
      settled = true;
    }
    if (choice === 'edit') {
      try {
        prior = priorFrom(deps.readConfig(fallback));
      } catch {
        // unreadable: handled as no prior below
      }
      if (prior === undefined) ui.warn(`${tilde(fallback)} is not a valid config, so there is nothing to start from.`);
    }
  }

  const repos = flags.repo ?? (await askRepos(ui, deps, prior?.repos));

  // One role at a time (who it acts as, which CLI, which model), each under its own box, so the two read as separate things.
  if (!(flags.authorProfile && flags.author)) ui.note('Implements the epic: runs ship, then answers the reviewer.', 'Author');
  const authorIdentity = flags.authorProfile ? parseIdentity(flags.authorProfile) : await askIdentity(ui, 'author', forge, readForge, login, [], deps, interactive, prior?.author.identity);
  const author = { identity: authorIdentity, ...(await askAgent(ui, 'author', { flag: flags.author, provider: flags.authorProvider }, harnesses, locals, deps, 'claude', prior?.author)) };

  if (!(flags.reviewerProfile && flags.reviewer)) ui.note('Reviews the final PR. Needs a different GitHub identity from the author.', 'Reviewer');
  const reviewerIdentity = flags.reviewerProfile ? parseIdentity(flags.reviewerProfile) : await askIdentity(ui, 'reviewer', forge, readForge, login, [authorIdentity], deps, interactive, prior?.reviewer.identity);
  const reviewer = { identity: reviewerIdentity, ...(await askAgent(ui, 'reviewer', { flag: flags.reviewer, provider: flags.reviewerProvider }, harnesses, locals, deps, harnesses.includes('codex') ? 'codex' : 'claude', prior?.reviewer)) };

  const user = buildConfig({ repos, author, reviewer });
  const loaded = loadConfig(defaults, user);
  if (!loaded.ok) throw new Error(`the answers do not make a valid config:\n${loaded.errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`);

  out ??= resolve(await askOut(ui, fallback));
  if (!settled && deps.exists(out) && !flags.yes && !(await ui.confirm(`${out} exists. Overwrite it?`))) throw new Error(`${out} already exists`);
  if (interactive) {
    ui.note(summary(repos, author, reviewer, out), 'This is what will be saved');
    if (!(await ui.confirm('Save it?'))) throw new Cancelled();
  }
  deps.write(out, `${JSON.stringify(user, null, 2)}\n`);
  ui.note(tilde(out), 'Config written');

  const checks = await deps.doctor(loaded.config, {}, ui.check, ui.checkStart);
  const use = out === fallback ? '' : ` --config ${out}`; // the default location needs no flag
  const failed = checks.filter((c) => c.status === 'fail').length;
  ui.checksEnd(checks.length, failed);
  if (failed > 0) {
    ui.outro(`${failed} check${failed === 1 ? '' : 's'} failed. Fix them and run: carrier doctor${use}`);
    return { path: out, checks, config: loaded.config, start: false };
  }

  const ready = await deps.readyEpics(loaded.config);
  const waiting = Object.entries(ready).map(([repo, count]) => `${repo}: ${count === undefined ? 'could not read' : `${count} epic${count === 1 ? '' : 's'} marked ready`}`);
  ui.note(waiting.join('\n'), 'Waiting for Carrier');
  const start = interactive && (await ui.confirm('Start Carrier now? (Ctrl+C stops it)'));
  ui.outro(start ? 'Starting…' : `Ready. Start it with: carrier${use}\nThen mark an epic of ${repos[0]} as solve:epic:ready.`);
  return { path: out, checks, config: loaded.config, start };
}

const tilde = (path: string) => (path.startsWith(`${homedir()}/`) ? `~${path.slice(homedir().length)}` : path);

async function askOut(ui: Ui, fallback: string) {
  const choice = await ui.select({
    message: 'Where should the config be saved?',
    options: [
      { value: fallback, label: tilde(fallback), hint: 'global: "carrier" finds it without --config' },
      { value: otherPath, label: 'Somewhere else…', hint: 'then use --config to point at it' },
    ],
    initialValue: fallback,
  });
  if (choice !== otherPath) return choice;
  return ui.text({ message: 'Path of the config file', placeholder: 'carrier.config.json', defaultValue: 'carrier.config.json' });
}

const otherPath = '\0path';
const otherRepo = '\0other';

async function askRepos(ui: Ui, deps: InitDeps, current: string[] | undefined) {
  const origin = deps.originRepo();
  const suggested = current?.join(', ') ?? origin;
  let listed: string[] = [];
  try {
    listed = deps.listRepos();
  } catch (error) {
    ui.warn(`Could not list your repos (${error instanceof Error ? error.message.split('\n')[0] : String(error)}); type them instead.`);
  }
  const typed = async (message: string) => {
    const answer = await ui.text({
      message,
      placeholder: suggested ?? 'AshuLab/my-repo',
      defaultValue: suggested,
      validate: (value) => (value.split(',').every((n) => repoNamePattern.test(n.trim())) ? undefined : 'Each repo must be owner/name'),
    });
    return answer.split(',').map((s) => s.trim());
  };
  if (listed.length === 0) return typed('Repos to watch (owner/name, comma separated)');

  // What the config already has, or else the folder you are in, goes first and marked, even when it is not among the recent ones; one section per owner.
  const first = current ?? (origin === undefined ? [] : [origin]);
  const names = [...first, ...listed.filter((n) => !first.includes(n))];
  const owners = [...new Set(names.map((n) => n.split('/')[0]!))];
  const other = { value: otherRepo, label: 'Other…', hint: 'type owner/name' };
  const groups: Record<string, Option<string>[]> = Object.fromEntries(
    owners.map((owner) => [owner, names.filter((n) => n.startsWith(`${owner}/`)).map((value) => ({ value, label: owners.length > 1 ? value.slice(owner.length + 1) : value }))]),
  );
  if (owners.length > 1) groups.Other = [other];
  else groups[owners[0]!]!.push(other);
  const picked = await ui.multiselect({ message: 'Repos to watch', options: groups, initialValues: first });
  const chosen = picked.filter((n) => n !== otherRepo);
  const extra = picked.includes(otherRepo) ? await typed('Other repos (owner/name, comma separated)') : [];
  return [...new Set([...chosen, ...extra])];
}

const addBot = '\0add';

async function askIdentity(ui: Ui, role: 'author' | 'reviewer', forge: { agents: ForgeAgent[] }, readForge: () => void, login: string | undefined, taken: Identity[], deps: InitDeps, interactive: boolean, current?: Identity): Promise<Identity> {
  for (;;) {
    const options: Option<string>[] = [
      ...forge.agents.map((a) => ({ value: `forge:${a.name}`, label: a.name, hint: a.label && a.label !== a.name ? a.label : 'Agent Forge bot' })),
      { value: 'gh', label: 'My own gh login', hint: login },
    ].filter((o) => !taken.some((t) => identityText(t) === o.value));
    const canAdd = interactive && deps.which('agent-forge');
    if (options.length === 0 && !canAdd) {
      throw new Error('Author and reviewer need different identities and there is nothing left to pick. Add a bot with "agent-forge add" (https://github.com/AshuLab/agent-forge) and run this again.');
    }
    if (options.length === 1 && !canAdd) {
      ui.note(`${options[0]!.label}${options[0]!.hint ? ` (${options[0]!.hint})` : ''} — the only identity left`, `GitHub identity for the ${role}`);
      return parseIdentity(options[0]!.value);
    }
    const initialValue = options.find((o) => current && o.value === identityText(current))?.value ?? options[0]?.value;
    const picked = await ui.select({
      message: `GitHub identity for the ${role}`,
      options: canAdd ? [...options, { value: addBot, label: 'Add a new Agent Forge bot…', hint: 'runs: agent-forge add' }] : options,
      initialValue,
    });
    if (picked !== addBot) return parseIdentity(picked);
    if (!deps.forgeAdd()) ui.warn('agent-forge add did not finish; nothing was added.');
    readForge(); // the new bot, if any, is in the list the next time around
  }
}

const native = '\0native';

// Three questions, each with one meaning: the harness (the CLI that runs the loop and the tools), the provider that
// serves the model (the harness's own cloud, or a local server) and the model. The provider question only appears
// when there is a choice, so the common path stays at two.
async function askAgent(ui: Ui, role: 'author' | 'reviewer', given: { flag?: string; provider?: string }, installed: readonly HarnessName[], locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps, preferred: HarnessName, current?: Answered): Promise<Pick<Role, 'harness' | 'model' | 'provider'>> {
  if (given.flag) return { ...parseHarnessModel(given.flag), ...(given.provider && { provider: parseProvider(given.provider) }) };
  if (installed.length === 0) throw new Error(`None of ${harnessNames.join(', ')} is installed; install one and run this again.`);
  const harness: HarnessName = installed.length === 1 ? installed[0]! : await ui.select<HarnessName>({ message: `Which agent CLI runs the ${role}?`, options: installed.map((p) => ({ value: p, label: harnessLabel[p] })), initialValue: [current?.harness, preferred].find((h): h is HarnessName => h !== undefined && installed.includes(h)) ?? installed[0]! });

  let provider: LocalProvider | undefined;
  const servers = localKinds.filter((kind) => localProvidersOf[harness].includes(kind)); // Antigravity has none
  if (servers.some((kind) => locals[kind])) {
    const choice = await ui.select({
      message: `Which provider serves the ${role}'s model?`,
      options: [
        { value: native, label: nativeProvider[harness], hint: 'cloud' },
        ...servers.map((kind) => ({ value: kind as string, label: `${localLabel[kind]} (local)`, hint: locals[kind] ? `${locals[kind].length} models, runs on this machine` : 'not running: start its server to use it', disabled: !locals[kind] })),
      ],
      initialValue: current?.harness === harness && current.provider && locals[current.provider] ? current.provider : native,
    });
    if (choice !== native) provider = parseProvider(choice);
  }

  const typed = async (suggestion?: string) => (await ui.text({ message: `Model for the ${role}`, placeholder: suggestion ?? 'model name', defaultValue: suggestion, validate: (v) => (v.trim() ? undefined : 'Required') })).trim();
  const known: Option<string>[] = provider ? locals[provider]!.map((value) => ({ value, label: value })) : harness === 'claude' ? claudeModels : harness === 'codex' ? deps.codexModels() : deps.agyModels();
  const configured = !provider && harness === 'codex' ? deps.codexModel() : undefined; // what the user already runs Codex with
  if (known.length === 0) return { harness, model: await typed(configured), ...(provider && { provider }) };
  const same = current?.harness === harness && current.provider === provider ? current.model : undefined; // the model it has now, when the harness and provider did not change
  const options = same !== undefined && !known.some((k) => k.value === same) ? [{ value: same, label: same, hint: 'current' }, ...known] : known;
  const initial = [same, configured, 'sonnet'].find((m) => m !== undefined && options.some((k) => k.value === m)) ?? options[0]!.value;
  const choice = await ui.select({ message: `Model for the ${role}`, options: [...options, { value: otherModel, label: 'Other…', hint: 'type a model id' }], initialValue: initial });
  return { harness, model: choice === otherModel ? await typed() : choice, ...(provider && { provider }) };
}
