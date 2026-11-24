import { randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { ChatRefused } from '../chat/runner.ts';
import type { HarnessName } from '../harnesses/names.ts';
import { localKinds } from '../harnesses/local.ts';
import { chatConfigPathOf, engineConfigPathOf, carrierHome, providersPathOf } from './places.ts';
import { providersFileSchema } from './providers.ts';

// The writing of `providers.json` (ADR 0053): the chat host answers these requests, and `carrier config` runs the same code when no host does.
// Each one reads the raw file again now (a file that is not there is `{}`), changes it, validates the whole result with the file's strict schema and writes it
// through a temporary file and a rename, so every key the person wrote stays and a refusal leaves the file as it was.

type Raw = Record<string, unknown>;
const isObject = (value: unknown): value is Raw => typeof value === 'object' && value !== null && !Array.isArray(value);

/** A JSON file as a raw object; `undefined` when it is not there. A file that does not parse or is not an object is refused (`what` says the file). */
function readObject(file: string, what: string): Raw | undefined {
  let text: string;
  try {
    text = readFileSync(file, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return undefined;
    throw new ChatRefused('config.problem', `${file} cannot be read, so it was not changed`, { path: what, problem: 'unreadable' });
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new ChatRefused('config.problem', `${file} is not valid JSON, so it was not changed`, { path: what, problem: 'notJson' });
  }
  if (isObject(parsed) === false) throw new ChatRefused('config.problem', `${file} is not a JSON object, so it was not changed`, { path: what, problem: 'notAnObject' });
  return parsed;
}

/** Changes the file in place through `change`, then checks and writes it. Answers the file as written. */
function edit(folder: string, change: (file: Raw) => void): Raw {
  const path = providersPathOf(folder);
  const next: Raw = readObject(path, '(file)') ?? {};
  change(next);
  const checked = providersFileSchema.safeParse(next);
  if (checked.success === false) {
    const issue = checked.error.issues[0]!;
    const key = issue.path.join('.') || '(root)';
    throw new ChatRefused('config.problem', `${key}: ${issue.message}`, { path: key, problem: issue.code });
  }
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  mkdirSync(dirname(path), { recursive: true });
  try {
    writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`);
    renameSync(temporary, path);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
  return next;
}

/** The `providers` map of the file, made when it is not there; one that is not a map is refused, so the app never writes over what it cannot read. */
function accountsOf(file: Raw): Raw {
  file.providers ??= {};
  if (isObject(file.providers) === false) throw new ChatRefused('config.problem', 'providers is not a map of accounts, so providers.json was not changed', { path: 'providers', problem: 'notAnObject' });
  return file.providers;
}

const taken = (name: string) => new ChatRefused('account.taken', `There is already an account named ${name}.`, { name });
const missing = (name: string) => new ChatRefused('account.missing', `There is no account named ${name} in providers.json.`, { name });

/** The part of the file that an account request changed: the accounts it names, as the file now has them. */
const savedAccounts = (file: Raw, names: string[]) => ({ providers: Object.fromEntries(names.map((name) => [name, (file.providers as Raw)[name]])) });

/** Adds each account, `{ harness }` (found by detection); a taken name is refused and the file is left as it was. */
export function setAccounts(accounts: { name: string; harness: HarnessName }[], folder = carrierHome()) {
  const file = edit(folder, (file) => {
    const map = accountsOf(file);
    for (const { name, harness } of accounts) {
      if (Object.hasOwn(map, name)) throw taken(name);
      map[name] = { harness };
    }
  });
  return { saved: savedAccounts(file, accounts.map((a) => a.name)) };
}

/** The config folder as the file keeps it: absolute or `~/…` as typed, anything else taken from the home folder (`work` is `~/work`, `./work` too). */
export function normalizedConfigDir(text: string): string {
  const path = text.trim();
  if (path === '' || path.startsWith('/') || path === '~' || path.startsWith('~/')) return path;
  return `~/${path.startsWith('./') ? path.slice(2) : path}`;
}

/** A new account of Claude Code or Codex (Antigravity has one), with its config folder when given. */
export function addAccount(account: { name: string; harness: HarnessName; configDir?: string | undefined }, folder = carrierHome()) {
  if (account.harness === 'agy') throw new ChatRefused('account.harnessTakesOne', 'Only Claude Code and Codex take more accounts.', { harness: account.harness });
  const configDir = normalizedConfigDir(account.configDir ?? '');
  if (/[\u0000-\u001f\u007f]/.test(configDir)) throw new ChatRefused('config.problem', `providers.${account.name}.configDir: Config folder has a character that a path cannot have.`, { path: `providers.${account.name}.configDir`, problem: 'invalid_format' });
  const file = edit(folder, (file) => {
    const map = accountsOf(file);
    if (Object.hasOwn(map, account.name)) throw taken(account.name);
    map[account.name] = { harness: account.harness, ...(configDir !== '' && { configDir }) };
  });
  return { saved: savedAccounts(file, [account.name]) };
}

/** The keys of an account that the editor changes. */
export const accountKeys = ['displayName', 'label', 'icon', 'color', 'command', 'configDir', 'autoCompact', 'launchArgs', 'idleCompaction'] as const;
export type AccountChanges = Partial<Record<(typeof accountKeys)[number], unknown>>;

/** Sets each key of `changes` on the account (null, or a text that is empty once trimmed, removes it); every other key of the account stays as the person wrote it. */
export function editAccount(name: string, changes: AccountChanges, folder = carrierHome()) {
  const file = edit(folder, (file) => {
    const account = accountsOf(file)[name];
    if (isObject(account) === false) throw missing(name);
    for (const [key, value] of Object.entries(changes)) {
      const text = typeof value === 'string' ? (key === 'configDir' ? normalizedConfigDir(value) : value.trim()) : value;
      if (text === null || text === undefined || text === '') delete account[key];
      else account[key] = text;
    }
  });
  return { saved: savedAccounts(file, [name]) };
}

const roleTitles = { author: 'Author', reviewer: 'Reviewer', leadReviewer: 'Lead reviewer' } as const;

/** Who names each account in `engine.json` (a role, a repo's override of one, a failover list, also one that is off) and `chat.json` (a chat agent), in words. A file that is there and cannot be read stops the answer. */
export function accountUses(folder = carrierHome()): Map<string, string[]> {
  const uses = new Map<string, string[]>();
  const add = (account: unknown, use: string) => typeof account === 'string' && uses.set(account, [...(uses.get(account) ?? []), use]);
  const engine = readObject(engineConfigPathOf(folder), 'engine.json') ?? {};
  const roles = isObject(engine.agents) ? engine.agents : {};
  for (const [role, title] of Object.entries(roleTitles)) add(isObject(roles[role]) && roles[role].provider, title);
  for (const repo of Array.isArray(engine.repos) ? engine.repos : []) {
    if (isObject(repo) === false || typeof repo.name !== 'string' || isObject(repo.agents) === false) continue;
    for (const [role, title] of Object.entries(roleTitles)) add(isObject(repo.agents[role]) && repo.agents[role].provider, `${title} in ${repo.name}`);
  }
  const lists = isObject(engine.failover) && isObject(engine.failover.roles) ? engine.failover.roles : {};
  for (const [role, title] of Object.entries(roleTitles)) {
    for (const step of Array.isArray(lists[role]) ? lists[role] : []) add(isObject(step) && step.provider, `Failover of ${title}`);
  }
  // without a chat.json (or one with no agents) the chat's agents are `claude` and `codex`, each on the account of its name
  const chat = readObject(chatConfigPathOf(folder), 'chat.json') ?? {};
  const agents = isObject(chat.agents) ? chat.agents : { claude: { account: 'claude' }, codex: { account: 'codex' } };
  for (const agent of Object.keys(agents).sort()) add(isObject(agents[agent]) && agents[agent].account, `Chat agent ${agent}`);
  return uses;
}

/** Removes the account, unless a role, a repo override, a failover list or a chat agent names it. */
export function removeAccount(name: string, folder = carrierHome()) {
  edit(folder, (file) => {
    const map = accountsOf(file);
    if (Object.hasOwn(map, name) === false) throw missing(name);
    const by = accountUses(folder).get(name) ?? [];
    if (by.length > 0) throw new ChatRefused('account.inUse', `${name} is used by ${by.join(', ')}, so it stays. Point those at another account first.`, { name, uses: by.join(', ') });
    delete map[name];
  });
  return { saved: { providers: {} } };
}

/** The entry the app writes is named after its server, so the entries it wrote before are the ones with those names. */
const generatorServers: readonly string[] = localKinds;

/** Chooses the text generator: one entry `textGenerators.<server>` of `{ kind, model }` and `textGenerator` naming it, in place of what the app wrote before; null clears the choice and that entry. An entry written by hand stays. */
export function setTextGenerator(choice: { server: string; model: string } | null, folder = carrierHome()) {
  const file = edit(folder, (file) => {
    if (file.textGenerators !== undefined && isObject(file.textGenerators) === false) throw new ChatRefused('config.problem', 'textGenerators is not a map, so it was not changed', { path: 'textGenerators', problem: 'notAnObject' });
    const generators: Raw = { ...(file.textGenerators as Raw | undefined) };
    for (const server of generatorServers) delete generators[server];
    delete file.textGenerator;
    if (choice !== null) {
      const model = choice.model.trim();
      if (generatorServers.includes(choice.server) === false || model === '') {
        throw new ChatRefused('config.problem', `textGenerators.${choice.server}: a text generator is a model of LM Studio or Ollama`, { path: `textGenerators.${choice.server}`, problem: 'invalid_value' });
      }
      generators[choice.server] = { kind: choice.server, model };
      file.textGenerator = choice.server;
    }
    if (Object.keys(generators).length === 0) delete file.textGenerators;
    else file.textGenerators = generators;
  });
  return { saved: { ...(file.textGenerators !== undefined && { textGenerators: file.textGenerators }), ...(file.textGenerator !== undefined && { textGenerator: file.textGenerator }) } };
}
