import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { styleText } from 'node:util';
import { defaultConfigPath } from '../config/default-path.ts';
import { defaults, loadConfig } from '../config/load.ts';
import { repoNamePattern } from '../config/schema.ts';
import { runDoctor, type Check } from '../doctor/doctor.ts';
import { buildConfig, identityText, parseIdentity, parseProviderModel, type Identity, type Role } from './build-config.ts';
import { readForgeAgents, type ForgeAgent } from './forge-registry.ts';

type Option<T extends string> = { value: T; label: string; hint?: string };

/** What the wizard needs from the terminal. The real one is clack (src/init/clack-ui.ts); tests script it. */
export interface Ui {
  intro(title: string): void;
  outro(message: string): void;
  note(message: string, title: string): void;
  warn(message: string): void;
  check(check: Check): void;
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
  exists: (path: string) => boolean;
  write: (path: string, content: string) => void;
  doctor: typeof runDoctor;
}

/** Flags answer questions ahead of time; whatever is missing is asked. */
/** `authorProfile` / `reviewerProfile` are `forge:<agent>` or `gh`; `author` / `reviewer` are `<claude|codex>:<model>`. */
export type InitFlags = { repo?: string[]; authorProfile?: string; reviewerProfile?: string; author?: string; reviewer?: string; out?: string; yes?: boolean };

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
  exists: existsSync,
  write: (path, content) => {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, content);
  },
  doctor: runDoctor,
};

// Aliases the Claude CLI resolves to the latest model of each family, so they do not go stale like a model id does.
const claudeModels: Option<string>[] = [
  { value: 'sonnet', label: 'sonnet', hint: 'latest Sonnet' },
  { value: 'opus', label: 'opus', hint: 'latest Opus' },
  { value: 'fable', label: 'fable', hint: 'latest Fable' },
];
const otherModel = '\0other';

export async function runInit(flags: InitFlags, ui: Ui, deps: InitDeps = realDeps) {
  ui.intro('Carrier setup');

  let forge: ForgeAgent[] = [];
  try {
    forge = deps.forgeAgents();
  } catch (error) {
    ui.warn(`Could not read the Agent Forge registry: ${error instanceof Error ? error.message : String(error)}`);
  }
  const providers = (['claude', 'codex'] as const).filter((p) => deps.which(p));
  const login = deps.ghLogin();
  const status = (ok: boolean, label: string) => `${ok ? styleText('green', '●') : styleText('red', '○')} ${label}`;
  ui.note(
    [
      [status(providers.includes('claude'), 'claude'), status(providers.includes('codex'), 'codex'), status(deps.which('git'), 'git'), status(login !== undefined, login ? `gh (${login})` : 'gh')].join('   '),
      forge.length > 0 ? `${styleText('green', '●')} Agent Forge: ${forge.map((a) => a.name).join(', ')}` : `${styleText('yellow', '▲')} Agent Forge: no agents found (run "agent-forge add")`,
    ].join('\n'),
    'This machine',
  );

  const repos = flags.repo ?? (await askRepos(ui, deps));

  // One role at a time (who it acts as, which CLI, which model), each under its own box, so the two read as separate things.
  if (!(flags.authorProfile && flags.author)) ui.note('Implements the epic: runs ship, then answers the reviewer.', 'Author');
  const authorIdentity = flags.authorProfile ? parseIdentity(flags.authorProfile) : await askIdentity(ui, 'author', forge, login, []);
  const author = { identity: authorIdentity, ...(await askAgent(ui, 'author', flags.author, providers, deps, 'claude')) };

  if (!(flags.reviewerProfile && flags.reviewer)) ui.note('Reviews the final PR. Needs a different GitHub identity from the author.', 'Reviewer');
  const reviewerIdentity = flags.reviewerProfile ? parseIdentity(flags.reviewerProfile) : await askIdentity(ui, 'reviewer', forge, login, [authorIdentity]);
  const reviewer = { identity: reviewerIdentity, ...(await askAgent(ui, 'reviewer', flags.reviewer, providers, deps, providers.includes('codex') ? 'codex' : 'claude')) };

  const user = buildConfig({ repos, author, reviewer });
  const loaded = loadConfig(defaults, user);
  if (!loaded.ok) throw new Error(`the answers do not make a valid config:\n${loaded.errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`);

  const fallback = defaultConfigPath();
  const out = resolve(flags.out ?? (await askOut(ui, fallback)));
  if (deps.exists(out) && !flags.yes && !(await ui.confirm(`${out} exists. Overwrite it?`))) throw new Error(`${out} already exists`);
  deps.write(out, `${JSON.stringify(user, null, 2)}\n`);
  ui.note(out, 'Config written');

  const checks = await deps.doctor(loaded.config, {}, ui.check);
  const use = out === fallback ? '' : ` --config ${out}`; // the default location needs no flag
  const failed = checks.filter((c) => c.status === 'fail').length;
  ui.outro(
    failed > 0
      ? `${failed} check${failed === 1 ? '' : 's'} failed. Fix them and run: carrier doctor${use}`
      : `Ready. Start it with: carrier${use}\nThen mark an epic of ${repos[0]} as solve:epic:ready.`,
  );
  return { path: out, checks };
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

async function askRepos(ui: Ui, deps: InitDeps) {
  const origin = deps.originRepo();
  let listed: string[] = [];
  try {
    listed = deps.listRepos();
  } catch (error) {
    ui.warn(`Could not list your repos (${error instanceof Error ? error.message.split('\n')[0] : String(error)}); type them instead.`);
  }
  const typed = async (message: string) => {
    const answer = await ui.text({
      message,
      placeholder: origin ?? 'AshuLab/my-repo',
      defaultValue: origin,
      validate: (value) => (value.split(',').every((n) => repoNamePattern.test(n.trim())) ? undefined : 'Each repo must be owner/name'),
    });
    return answer.split(',').map((s) => s.trim());
  };
  if (listed.length === 0) return typed('Repos to watch (owner/name, comma separated)');

  // The folder you are in goes first and marked, even when it is not among the recent ones; one section per owner.
  const names = origin === undefined ? listed : [origin, ...listed.filter((n) => n !== origin)];
  const owners = [...new Set(names.map((n) => n.split('/')[0]!))];
  const other = { value: otherRepo, label: 'Other…', hint: 'type owner/name' };
  const groups: Record<string, Option<string>[]> = Object.fromEntries(
    owners.map((owner) => [owner, names.filter((n) => n.startsWith(`${owner}/`)).map((value) => ({ value, label: owners.length > 1 ? value.slice(owner.length + 1) : value }))]),
  );
  if (owners.length > 1) groups.Other = [other];
  else groups[owners[0]!]!.push(other);
  const picked = await ui.multiselect({ message: 'Repos to watch', options: groups, initialValues: origin === undefined ? [] : [origin] });
  const chosen = picked.filter((n) => n !== otherRepo);
  const extra = picked.includes(otherRepo) ? await typed('Other repos (owner/name, comma separated)') : [];
  return [...new Set([...chosen, ...extra])];
}

async function askIdentity(ui: Ui, role: 'author' | 'reviewer', forge: ForgeAgent[], login: string | undefined, taken: Identity[]): Promise<Identity> {
  const options: Option<string>[] = [
    ...forge.map((a) => ({ value: `forge:${a.name}`, label: a.name, hint: a.label && a.label !== a.name ? a.label : 'Agent Forge bot' })),
    { value: 'gh', label: 'My own gh login', hint: login },
  ].filter((o) => !taken.some((t) => identityText(t) === o.value));
  if (options.length === 0) {
    throw new Error('Author and reviewer need different identities and there is nothing left to pick. Add a bot with "agent-forge add" and run this again.');
  }
  const first = options[0]!;
  if (options.length === 1) {
    ui.note(`${first.label}${first.hint ? ` (${first.hint})` : ''} — the only identity left`, `GitHub identity for the ${role}`);
    return parseIdentity(first.value);
  }
  return parseIdentity(await ui.select({ message: `GitHub identity for the ${role}`, options, initialValue: first.value }));
}

async function askAgent(ui: Ui, role: 'author' | 'reviewer', flag: string | undefined, installed: readonly ('claude' | 'codex')[], deps: InitDeps, preferred: 'claude' | 'codex'): Promise<Pick<Role, 'provider' | 'model'>> {
  if (flag) return parseProviderModel(flag);
  const options = installed.map((p) => ({ value: p, label: p === 'claude' ? 'Claude' : 'Codex' }));
  if (options.length === 0) throw new Error('Neither claude nor codex is installed; install one and run this again.');
  const provider = options.length === 1 ? options[0]!.value : await ui.select({ message: `Which agent CLI runs the ${role}?`, options, initialValue: preferred });
  const known = provider === 'claude' ? claudeModels : deps.codexModels();
  const configured = provider === 'codex' ? deps.codexModel() : undefined; // what the user already runs Codex with
  const typed = async (suggestion?: string) => (await ui.text({ message: `Model for the ${role}`, placeholder: suggestion ?? 'model name', defaultValue: suggestion, validate: (v) => (v.trim() ? undefined : 'Required') })).trim();
  let model: string;
  if (known.length === 0) model = await typed(configured);
  else {
    const initial = [configured, 'sonnet'].find((m) => known.some((k) => k.value === m)) ?? known[0]!.value;
    const choice = await ui.select({ message: `Model for the ${role}`, options: [...known, { value: otherModel, label: 'Other…', hint: 'type a model id' }], initialValue: initial });
    model = choice === otherModel ? await typed() : choice;
  }
  return { provider, model };
}
