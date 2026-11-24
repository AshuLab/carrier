import { readForgeAgents } from '../terminal/wizard/forge-registry.ts';
import { isObject, readObject, refuse, write } from './engine-edit.ts';
import { providersProblem, readProvidersFile } from './providers.ts';
import { efforts } from './schema.ts';

// The writes of `engine.json` the Agents page, a repo's role screens and the Engine page ask for (ADR 0053): the roles, their persona and failover, the lead reviewer and the orchestrator's profile.
// Same way as `engine-edit.ts` (read again, changed, checked whole, renamed); the words of each refusal are the ones `macos/Sources/CarrierCore` used before it asked for these.

export type Role = 'author' | 'reviewer' | 'leadReviewer';
const titles: Record<Role, string> = { author: 'Author', reviewer: 'Reviewer', leadReviewer: 'Lead reviewer' };

/** Who a role signs as: a bot of the Agent Forge registry, or the person's own `gh` login. */
export type Identity = { kind: 'forge'; agent: string } | { kind: 'gh' };
/** What a role edit changes; a field left out stays, `effort: null` takes it out (the CLI's own). */
export type RoleChanges = { identity?: Identity; provider?: string; model?: string; effort?: string | null };
/** The fields a repo sets for a role: a field left out is not the repo's own. */
export type RepoRoleFields = { profile?: string; provider?: string; model?: string; effort?: string; persona?: { name?: string; prompt?: string } };
export type FailoverStep = { provider: string; model?: string; effort?: string };

type Json = Record<string, unknown>;
const object = (value: unknown): Json => (isObject(value) ? { ...value } : {});
const text = (value: unknown) => (typeof value === 'string' && value.trim() !== '' ? value.trim() : undefined);
/** A persona as the engine reads it: every text trimmed, an empty one left out, none when neither is left. */
const personaOf = (persona: { name?: string; prompt?: string } | undefined) => {
  const name = text(persona?.name);
  const prompt = text(persona?.prompt);
  return name === undefined && prompt === undefined ? undefined : { ...(name !== undefined && { name }), ...(prompt !== undefined && { prompt }) };
};

/** The accounts of `providers.json` (the default ones when there is no file); a file that does not read is refused as a write refuses it. */
function accountsOf(folder: string): string[] {
  const read = readProvidersFile(folder);
  if (read.ok === false) throw refuse('(providers.json)', 'invalid', providersProblem(folder, read.errors));
  return Object.keys(read.providers);
}

// ponytail: a registry that does not read is no bot at all, and the refusal says the bot is not in the list; the wizard's reader throws, the app's showed a note.
function botNames(): string[] {
  try {
    return readForgeAgents().map((agent) => agent.name);
  } catch {
    return [];
  }
}

const noEntry = (role: Role) => refuse(`agents.${role}`, 'noEntry', `${titles[role]} has no entry in engine.json. Add it there first.`);

/** The first thing the engine would refuse in these (trimmed) fields, with the words of every one of them. */
function fieldsProblem(fields: RepoRoleFields, profiles: string[], accounts: string[], at: string) {
  const found: [string, string, string][] = [];
  if (fields.profile !== undefined && profiles.includes(fields.profile) === false) found.push(['profile', 'notDeclared', `Identity “${fields.profile}” is not declared in profiles. Pick another one.`]);
  if (fields.provider !== undefined && accounts.includes(fields.provider) === false) found.push(['provider', 'notAnAccount', `Provider “${fields.provider}” is not an account of providers.json. Pick another one.`]);
  if (fields.effort !== undefined && (efforts as readonly string[]).includes(fields.effort) === false) found.push(['effort', 'notOneOf', `Effort must be one of ${efforts.join(', ')}.`]);
  const { name, prompt } = fields.persona ?? {};
  if (name !== undefined && (name.length > 40 || /[\r\n]/.test(name))) found.push(['persona.name', 'tooLong', 'The persona’s name is one line of up to 40 characters.']);
  if (prompt !== undefined && prompt.length > 4000) found.push(['persona.prompt', 'tooLong', 'The persona’s prompt is up to 4000 characters.']);
  if (found.length > 0) throw refuse(`${at}.${found[0]![0]}`, found[0]![1], found.map((one) => one[2]).join(' '));
}

/** `name` for a profile, or `name-2`, `name-3`… when `name` already means something else. */
function freeName(name: string, profiles: Json) {
  let candidate = name;
  for (let number = 2; candidate in profiles; number++) candidate = `${name}-${number}`;
  return candidate;
}

/** A role that now runs on the provider and model one of its failover steps names has no use for that step (the engine refuses the file otherwise): it goes, the others stay, and an emptied list goes with `failover`. */
function dropFailoverSteps(file: Json, role: Role, entry: Json) {
  const failover = object(file.failover);
  const roles = object(failover.roles);
  const steps = roles[role];
  if (Array.isArray(steps) === false) return;
  const kept = steps.filter((step) => isObject(step) === false || step.provider !== entry.provider || step.model !== entry.model);
  if (kept.length === steps.length) return;
  if (kept.length > 0) roles[role] = kept;
  else delete roles[role];
  if (Object.keys(roles).length > 0) failover.roles = roles;
  else delete failover.roles;
  if (Object.keys(failover).length > 0) file.failover = failover;
  else delete file.failover;
}

/** `current` with the changes made to `role` together, or a refusal; with `creating` the role may not be in the file yet, and then the changes have to make the whole role. */
function changeRole(current: Json, role: Role, changes: RoleChanges, creating: boolean, folder: string) {
  const agents = object(current.agents);
  if (isObject(agents[role]) === false && creating === false) throw noEntry(role);
  const entry = object(agents[role]);
  const profiles = object(current.profiles);
  const { identity } = changes;
  if (identity !== undefined) {
    if (identity.kind === 'forge' && botNames().includes(identity.agent) === false) {
      throw refuse(`agents.${role}.profile`, 'botNotListed', `“${identity.agent}” is not in Agent Forge’s list. Pick another one.`);
    }
    // the profile that already means it, else a free name
    const means = (profile: unknown) => isObject(profile) && profile.kind === identity.kind && (identity.kind === 'gh' || profile.agent === identity.agent);
    const name = Object.keys(profiles).sort().find((key) => means(profiles[key])) ?? freeName(identity.kind === 'gh' ? 'gh' : identity.agent, profiles);
    profiles[name] ??= identity;
    entry.profile = name;
  }
  if (changes.provider !== undefined) entry.provider = changes.provider;
  if (changes.model !== undefined) entry.model = changes.model.trim();
  if (changes.effort === null) delete entry.effort;
  else if (changes.effort !== undefined) entry.effort = changes.effort;
  const fields: RepoRoleFields = { profile: text(entry.profile), provider: text(entry.provider), model: text(entry.model), effort: text(entry.effort) };
  if (fields.model === undefined) throw refuse(`agents.${role}.model`, 'empty', 'The model cannot be empty.');
  if (fields.profile === undefined || fields.provider === undefined) throw refuse(`agents.${role}`, 'incomplete', `${titles[role]} needs an identity, a provider and a model.`);
  fieldsProblem(fields, Object.keys(profiles), accountsOf(folder), `agents.${role}`);
  const next = { ...current, agents: { ...agents, [role]: entry }, profiles };
  dropFailoverSteps(next, role, entry);
  return { next, entry };
}

/** The global role's changes, together: one write, or none. */
export function editRole(role: Role, changes: RoleChanges, file: string, folder: string) {
  const { next, entry } = changeRole(readObject(file), role, changes, false, folder);
  write(file, next, folder);
  return { saved: { agents: { [role]: entry }, profiles: next.profiles } };
}

/** Turns the lead reviewer on with a complete draft (an incomplete one is refused before the file is read), or off with `null`: `agents.leadReviewer` and its failover steps go, nothing else, and a file with neither is left as it is. */
export function setLeadReviewer(draft: RoleChanges | null, file: string, folder: string) {
  if (draft !== null) {
    const missing = [draft.identity === undefined && 'an identity', draft.provider === undefined && 'a provider', !draft.model?.trim() && 'a model'].filter(Boolean);
    if (missing.length > 0) throw refuse('agents.leadReviewer', 'incomplete', `The lead reviewer needs ${missing.join(', ')}.`);
    const { next, entry } = changeRole(readObject(file), 'leadReviewer', draft, true, folder);
    write(file, next, folder);
    return { saved: { agents: { leadReviewer: entry }, profiles: next.profiles } };
  }
  const next = readObject(file);
  const agents = object(next.agents);
  const failover = object(next.failover);
  const roles = object(failover.roles);
  if ('leadReviewer' in agents === false && 'leadReviewer' in roles === false) return { saved: {} };
  delete agents.leadReviewer;
  next.agents = agents;
  if ('leadReviewer' in roles) {
    delete roles.leadReviewer;
    next.failover = { ...failover, roles };
  }
  write(file, next, folder);
  return { saved: {} };
}

/** A repo's own role: the fields that are set, the entry's other keys kept; the entry goes when nothing is left (and `agents` with the last), and `fields: null` takes it out whole. */
export function editRepoRole(repo: string, role: Role, fields: RepoRoleFields | null, file: string, folder: string) {
  const current = readObject(file);
  const repos = Array.isArray(current.repos) ? [...current.repos] : [];
  const index = repos.findIndex((entry) => isObject(entry) && entry.name === repo);
  if (index === -1) throw refuse('repos', 'notWatched', `${repo} is no longer in the config file.`);
  const at = `repos[${index}].agents.${role}`;
  const own: Json = {};
  if (fields !== null) {
    const set: RepoRoleFields = { profile: text(fields.profile), provider: text(fields.provider), model: text(fields.model), effort: text(fields.effort), persona: personaOf(fields.persona) };
    fieldsProblem(set, Object.keys(object(current.profiles)), accountsOf(folder), at);
    Object.assign(own, object(object(object(repos[index]).agents)[role]));
    for (const [key, value] of Object.entries(set)) {
      if (value === undefined) delete own[key];
      else own[key] = value;
    }
  }
  const entry = object(repos[index]);
  const agents = object(entry.agents);
  if (Object.keys(own).length > 0) agents[role] = own;
  else delete agents[role];
  if (Object.keys(agents).length > 0) entry.agents = agents;
  else delete entry.agents;
  repos[index] = entry;
  write(file, { ...current, repos }, folder);
  return { saved: { repos: [entry] } };
}

/** The persona of a global role: a name, a prompt, or both; `null` for both takes it out. */
export function editPersona(role: Role, name: string | null, prompt: string | null, file: string, folder: string) {
  for (const [label, value] of [['name', name], ['prompt', prompt]] as const) {
    if (value !== null && value.trim() === '') throw refuse(`agents.${role}.persona.${label}`, 'empty', `The persona’s ${label} cannot be empty. Leave it out instead.`);
  }
  const persona = personaOf({ name: name ?? undefined, prompt: prompt ?? undefined });
  fieldsProblem({ persona }, [], [], `agents.${role}`);
  const current = readObject(file);
  const agents = object(current.agents);
  if (isObject(agents[role]) === false) throw noEntry(role);
  const entry = object(agents[role]);
  if (persona === undefined) delete entry.persona;
  else entry.persona = persona;
  write(file, { ...current, agents: { ...agents, [role]: entry } }, folder);
  return { saved: { agents: { [role]: entry } } };
}

/** The first two steps of a global role's failover (the steps after them stay); both `null` is Switch automatically off, the role's list goes. */
export function editFailover(role: Role, first: FailoverStep | null, second: FailoverStep | null, file: string, folder: string) {
  const at = (index: number) => `failover.roles.${role}.${index}`;
  if (first === null && second !== null) throw refuse(at(1), 'firstMissing', 'Then needs a First step.');
  const accounts = accountsOf(folder);
  const edited = [first, second].flatMap((step) => (step === null ? [] : [{ provider: step.provider.trim(), model: text(step.model), effort: text(step.effort) }]));
  edited.forEach((step, index) => {
    if (accounts.includes(step.provider) === false) throw refuse(at(index), 'providerNotDeclared', `${index === 0 ? 'First' : 'Then'}: “${step.provider}” is not an account of providers.json. Pick another one.`);
  });
  const current = readObject(file);
  const own = object(current.agents)[role];
  if (isObject(own) === false) throw noEntry(role);
  const failover = object(current.failover);
  const roles = object(failover.roles);
  if (edited.length === 0) delete roles[role];
  else {
    const steps: Json[] = [...edited, ...(Array.isArray(roles[role]) ? (roles[role] as Json[]).slice(2) : [])];
    const seen: string[] = [];
    steps.forEach((step, index) => {
      const label = index === 0 ? 'First' : index === 1 ? 'Then' : `Step ${index + 1}`;
      const pair = JSON.stringify([step.provider, step.model]);
      if (seen.includes(pair)) throw refuse(at(index), 'stepRepeated', `${label} repeats another step of the list.`);
      if (step.provider === own.provider && step.model === own.model) throw refuse(at(index), 'stepOwnRole', `${label} is the role’s own provider and model, so it would move nowhere.`);
      seen.push(pair);
    });
    roles[role] = steps;
  }
  const next = { ...current };
  if (Object.keys(roles).length > 0) failover.roles = roles;
  else delete failover.roles;
  if (Object.keys(failover).length > 0) next.failover = failover;
  else delete next.failover;
  write(file, next, folder);
  return { saved: { failover: next.failover ?? {} } };
}

/** `orchestratorProfile`, one of the file's profiles; `null` takes the key out (the author's profile). */
export function setOrchestratorProfile(name: string | null, file: string, folder: string) {
  const next = readObject(file);
  if (name === null) delete next.orchestratorProfile;
  else next.orchestratorProfile = name;
  write(file, next, folder);
  return { saved: name === null ? {} : { orchestratorProfile: name } };
}
