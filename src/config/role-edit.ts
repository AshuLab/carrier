import { readForgeAgents } from '../terminal/wizard/forge-registry.ts';
import { isObject, readObject, refuse, write } from './engine-edit.ts';
import { extraReviewerKey, maxSlugLength, reservedKeys, slugPattern } from './extra-reviewer-key.ts';
import { providersProblem, readProvidersFile } from './providers.ts';
import { efforts } from './schema.ts';

// The writes of `engine.json` the Agents page, a repo's role screens and the Engine page ask for (ADR 0053): the roles, their persona and failover, the lead reviewer and the orchestrator's profile.
// Same way as `engine-edit.ts` (read again, changed, checked whole, renamed); the words of each refusal are the ones `macos/Sources/CarrierCore` used before it asked for these.

export type Role = 'author' | 'reviewer' | 'leadReviewer';
/** What `editRole`, `editPersona` and `editFailover` point at: a role, or an extra reviewer by its key. */
export type Target = Role | { extraReviewer: string };
const titles: Record<Role, string> = { author: 'Author', reviewer: 'Reviewer', leadReviewer: 'Lead reviewer' };

/** Who a role signs as: a bot of the Agent Forge registry, or the person's own `gh` login. */
export type Identity = { kind: 'forge'; agent: string } | { kind: 'gh' };
/** What a role edit changes; a field left out stays, `effort: null` takes it out (the CLI's own). */
export type RoleChanges = { identity?: Identity; provider?: string; model?: string; effort?: string | null };
/** What `editRole` changes: the same, and for an extra reviewer its `name` and `type`, which no role has. */
export type EditRoleChanges = RoleChanges & { name?: string; type?: string };
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

const extrasAt = 'agents.extraReviewers';
const isExtra = (target: Target): target is { extraReviewer: string } => typeof target === 'object';
/** Where the target's entry is in the file, for the key path of a refusal. */
const atOf = (target: Target) => (isExtra(target) ? `${extrasAt}.${target.extraReviewer}` : `agents.${target}`);

/** A copy of the target's entry, or the refusal of a role or a key the file does not hold. */
function entryOf(current: Json, target: Target): Json {
  const agents = object(current.agents);
  if (isExtra(target) === false) {
    if (isObject(agents[target]) === false) throw noEntry(target);
    return object(agents[target]);
  }
  const extras = object(agents.extraReviewers);
  const entry = Object.hasOwn(extras, target.extraReviewer) ? extras[target.extraReviewer] : undefined;
  if (isObject(entry) === false) throw refuse(atOf(target), 'noEntry', `There is no extra reviewer “${target.extraReviewer}” in engine.json.`);
  return object(entry);
}

/** `current` with `entry` in the target's place (an extra reviewer keeps its place in the map). */
function withEntry(current: Json, target: Target, entry: Json): Json {
  const agents = object(current.agents);
  if (isExtra(target) === false) return { ...current, agents: { ...agents, [target]: entry } };
  return { ...current, agents: { ...agents, extraReviewers: { ...object(agents.extraReviewers), [target.extraReviewer]: entry } } };
}

/** What `saved` answers for the target's entry. */
const savedOf = (target: Target, entry: Json) => (isExtra(target) ? { agents: { extraReviewers: { [target.extraReviewer]: entry } } } : { agents: { [target]: entry } });

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

/** The changes applied to `entry` and `profiles` (both are copies the caller owns), or a refusal at `at`; `title` is how the refusal calls the entry. */
function applyChanges(entry: Json, profiles: Json, changes: RoleChanges, at: string, title: string, folder: string) {
  const { identity } = changes;
  if (identity !== undefined) {
    if (identity.kind === 'forge' && botNames().includes(identity.agent) === false) {
      throw refuse(`${at}.profile`, 'botNotListed', `“${identity.agent}” is not in Agent Forge’s list. Pick another one.`);
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
  if (fields.model === undefined) throw refuse(`${at}.model`, 'empty', 'The model cannot be empty.');
  if (fields.profile === undefined || fields.provider === undefined) throw refuse(at, 'incomplete', `${title} needs an identity, a provider and a model.`);
  fieldsProblem(fields, Object.keys(profiles), accountsOf(folder), at);
}

/** `current` with the changes made to `role` together, or a refusal; with `creating` the role may not be in the file yet, and then the changes have to make the whole role. */
function changeRole(current: Json, role: Role, changes: RoleChanges, creating: boolean, folder: string) {
  const agents = object(current.agents);
  if (isObject(agents[role]) === false && creating === false) throw noEntry(role);
  const entry = object(agents[role]);
  const profiles = object(current.profiles);
  applyChanges(entry, profiles, changes, `agents.${role}`, titles[role], folder);
  const next = { ...current, agents: { ...agents, [role]: entry }, profiles };
  dropFailoverSteps(next, role, entry);
  return { next, entry };
}

/** A name an extra reviewer may have: one line of 1 to 40 characters, not another reviewer's without regard to case (`others` are the entries of the map without this one). */
function checkedName(name: string, others: unknown[], at: string) {
  const trimmed = name.trim();
  if (trimmed === '') throw refuse(`${at}.name`, 'empty', 'The name cannot be empty.');
  if (trimmed.length > maxSlugLength || /[\r\n]/.test(name)) throw refuse(`${at}.name`, 'tooLong', 'The name is one line of up to 40 characters.');
  if (others.some((other) => isObject(other) && typeof other.name === 'string' && other.name.trim().toLowerCase() === trimmed.toLowerCase())) throw refuse(`${at}.name`, 'taken', `“${trimmed}” is already another reviewer’s name. Pick another one.`);
  return trimmed;
}

function checkedType(type: string, at: string) {
  const trimmed = type.trim();
  if (slugPattern.test(trimmed) === false) throw refuse(`${at}.type`, 'notASlug', 'The type is a slug of up to 40 characters: it starts with a letter and holds lowercase letters, digits and hyphens.');
  return trimmed;
}

/** A reviewer that now runs on the provider and model one of its own failover steps names has no use for that step: it goes, and an emptied list goes with `failover`. */
function dropOwnSteps(entry: Json) {
  if (Array.isArray(entry.failover) === false) return;
  const kept = (entry.failover as unknown[]).filter((step) => isObject(step) === false || step.provider !== entry.provider || step.model !== entry.model);
  if (kept.length > 0) entry.failover = kept;
  else delete entry.failover;
}

/** The target's changes, together: one write, or none. `name` and `type` are an extra reviewer's only; its key never changes. */
export function editRole(target: Target, changes: EditRoleChanges, file: string, folder: string) {
  const { name, type, ...fields } = changes;
  if (isExtra(target) === false) {
    for (const [label, value] of [['name', name], ['type', type]] as const) {
      if (value !== undefined) throw refuse(`agents.${target}.${label}`, 'notAnExtraReviewer', `${titles[target]} has no ${label}: only an extra reviewer has one.`);
    }
    const { next, entry } = changeRole(readObject(file), target, fields, false, folder);
    write(file, next, folder);
    return { saved: { agents: { [target]: entry }, profiles: next.profiles } };
  }
  const current = readObject(file);
  const at = atOf(target);
  const entry = entryOf(current, target);
  const others = Object.entries(object(object(current.agents).extraReviewers)).filter(([key]) => key !== target.extraReviewer).map(([, other]) => other);
  if (name !== undefined) entry.name = checkedName(name, others, extrasAt);
  if (type !== undefined) entry.type = checkedType(type, extrasAt);
  const profiles = object(current.profiles);
  applyChanges(entry, profiles, fields, at, 'The extra reviewer', folder);
  dropOwnSteps(entry);
  const next = { ...withEntry(current, target, entry), profiles };
  write(file, next, folder);
  return { saved: { ...savedOf(target, entry), profiles } };
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

/** What `addExtraReviewer` takes; a field left out is refused by name, so the request never writes half a reviewer. */
export type ExtraReviewerDraft = { name?: string; type?: string; identity?: Identity; provider?: string; model?: string; effort?: string };
const maxExtraReviewers = 3;

/** Adds a reviewer at the end of the global `agents.extraReviewers`, whole, in one write; its key comes from its name (`extraReviewerKey`, the rule `carrier init` uses). */
export function addExtraReviewer(draft: ExtraReviewerDraft, file: string, folder: string) {
  const missing = ([['name', draft.name?.trim()], ['type', draft.type?.trim()], ['identity', draft.identity], ['provider', draft.provider?.trim()], ['model', draft.model?.trim()]] as const).filter(([, value]) => !value).map(([label]) => label);
  if (missing.length > 0) throw refuse(`${extrasAt}.${missing[0]}`, 'incomplete', `An extra reviewer needs ${missing.join(', ')}.`);
  const name = draft.name!.trim();
  if (name.length > maxSlugLength || /[\r\n]/.test(draft.name!)) throw refuse(`${extrasAt}.name`, 'tooLong', 'The name is one line of up to 40 characters.');
  const type = checkedType(draft.type!, extrasAt);
  if (draft.effort !== undefined && (efforts as readonly string[]).includes(draft.effort) === false) throw refuse(`${extrasAt}.effort`, 'notOneOf', `Effort must be one of ${efforts.join(', ')}.`);
  const current = readObject(file);
  const agents = object(current.agents);
  if (agents.extraReviewers !== undefined && isObject(agents.extraReviewers) === false) throw refuse(extrasAt, 'notAMap', 'agents.extraReviewers has to be a map from a key to a reviewer. Fix it in engine.json first.');
  const extras = object(agents.extraReviewers);
  const entries = Object.values(extras);
  if (entries.length >= maxExtraReviewers) throw refuse(extrasAt, 'full', `At most ${maxExtraReviewers} extra reviewers: remove one first.`);
  if (entries.some((other) => isObject(other) && typeof other.name === 'string' && other.name.trim().toLowerCase() === name.toLowerCase())) throw refuse(`${extrasAt}.name`, 'taken', `“${name}” is already another reviewer’s name. Pick another one.`);
  const entry: Json = { type, name };
  const profiles = object(current.profiles);
  applyChanges(entry, profiles, { identity: draft.identity, provider: draft.provider, model: draft.model, effort: draft.effort }, extrasAt, 'An extra reviewer', folder);
  const key = extraReviewerKey(name, Object.keys(extras));
  const next = { ...current, agents: { ...agents, extraReviewers: { ...extras, [key]: entry } }, profiles };
  write(file, next, folder);
  return { saved: { agents: { extraReviewers: { [key]: entry } }, profiles } };
}

/** Removes an extra reviewer, entry and failover steps with it, from the global `agents.extraReviewers` (the map goes with the last one); the profile it used and every other key stay. */
export function removeExtraReviewer(key: string, file: string, folder: string) {
  const current = readObject(file);
  entryOf(current, { extraReviewer: key });
  const agents = object(current.agents);
  const { [key]: _gone, ...extras } = object(agents.extraReviewers);
  const { extraReviewers: _old, ...rest } = agents;
  write(file, { ...current, agents: Object.keys(extras).length > 0 ? { ...rest, extraReviewers: extras } : rest }, folder);
  return { saved: {} };
}

/** What a repo's own extra reviewer carries as `setRepoExtraReviewers` takes it; a field left out is refused by name. Persona, failover steps and skills are the Reviewer's. */
export type RepoExtraReviewer = { type?: string; name?: string; profile?: string; provider?: string; model?: string; effort?: string };

/** A repo's own list of extra reviewers, sent whole: a map replaces the repo's earlier one, `{}` is none and `null` takes the key out (the global map applies). The repo's other `agents` keys stay, and `agents` goes when it is left empty. */
export function setRepoExtraReviewers(repo: string, reviewers: Record<string, RepoExtraReviewer> | null, file: string, folder: string) {
  const current = readObject(file);
  const repos = Array.isArray(current.repos) ? [...current.repos] : [];
  const index = repos.findIndex((entry) => isObject(entry) && entry.name === repo);
  if (index === -1) throw refuse('repos', 'notWatched', `${repo} is no longer in the config file.`);
  const at = `repos[${index}].agents.extraReviewers`;
  let own: Record<string, Json> | undefined;
  if (reviewers !== null) {
    if (Object.keys(reviewers).length > maxExtraReviewers) throw refuse(at, 'full', `At most ${maxExtraReviewers} extra reviewers.`);
    const profiles = Object.keys(object(current.profiles));
    const accounts = accountsOf(folder);
    own = {};
    for (const [key, sent] of Object.entries(reviewers)) {
      const where = `${at}.${key}`;
      if (slugPattern.test(key) === false || (reservedKeys as readonly string[]).includes(key)) throw refuse(where, 'badKey', `The key “${key}” is a slug of up to 40 characters that starts with a letter, and it is not ${reservedKeys.join(', ')}.`);
      const missing = (['type', 'name', 'profile', 'provider', 'model'] as const).filter((label) => text(sent[label]) === undefined);
      if (missing.length > 0) throw refuse(`${where}.${missing[0]}`, 'incomplete', `An extra reviewer needs ${missing.join(', ')}.`);
      const entry: Json = { type: checkedType(sent.type!, where), name: checkedName(sent.name!, Object.values(own), where), profile: text(sent.profile), provider: text(sent.provider), model: text(sent.model) };
      if (text(sent.effort) !== undefined) entry.effort = text(sent.effort);
      fieldsProblem({ profile: text(sent.profile), provider: text(sent.provider), effort: text(sent.effort) }, profiles, accounts, where);
      own[key] = entry;
    }
  }
  const entry = object(repos[index]);
  const agents = object(entry.agents);
  if (own === undefined) delete agents.extraReviewers;
  else agents.extraReviewers = own;
  if (Object.keys(agents).length > 0) entry.agents = agents;
  else delete entry.agents;
  repos[index] = entry;
  write(file, { ...current, repos }, folder);
  return { saved: { repos: [entry] } };
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

/** The persona of a global role or an extra reviewer: a name, a prompt, or both; `null` for both takes it out. */
export function editPersona(target: Target, name: string | null, prompt: string | null, file: string, folder: string) {
  const at = atOf(target);
  for (const [label, value] of [['name', name], ['prompt', prompt]] as const) {
    if (value !== null && value.trim() === '') throw refuse(`${at}.persona.${label}`, 'empty', `The persona’s ${label} cannot be empty. Leave it out instead.`);
  }
  const persona = personaOf({ name: name ?? undefined, prompt: prompt ?? undefined });
  fieldsProblem({ persona }, [], [], at);
  const current = readObject(file);
  const entry = entryOf(current, target);
  if (persona === undefined) delete entry.persona;
  else entry.persona = persona;
  write(file, withEntry(current, target, entry), folder);
  return { saved: savedOf(target, entry) };
}

/** The first two steps of a global role's failover, or of an extra reviewer's own (the steps after them stay); both `null` is Switch automatically off, the list goes. */
export function editFailover(target: Target, first: FailoverStep | null, second: FailoverStep | null, file: string, folder: string) {
  const at = (index: number) => (isExtra(target) ? `${atOf(target)}.failover.${index}` : `failover.roles.${target}.${index}`);
  if (first === null && second !== null) throw refuse(at(1), 'firstMissing', 'Then needs a First step.');
  const accounts = accountsOf(folder);
  const edited = [first, second].flatMap((step) => (step === null ? [] : [{ provider: step.provider.trim(), model: text(step.model), effort: text(step.effort) }]));
  edited.forEach((step, index) => {
    if (accounts.includes(step.provider) === false) throw refuse(at(index), 'providerNotDeclared', `${index === 0 ? 'First' : 'Then'}: “${step.provider}” is not an account of providers.json. Pick another one.`);
  });
  const current = readObject(file);
  const own = entryOf(current, target);
  const failover = object(current.failover);
  const roles = object(failover.roles);
  const before = isExtra(target) ? own.failover : roles[target];
  const steps: Json[] = [...edited, ...(Array.isArray(before) ? (before as Json[]).slice(2) : [])];
  if (edited.length > 0) {
    const seen: string[] = [];
    steps.forEach((step, index) => {
      const label = index === 0 ? 'First' : index === 1 ? 'Then' : `Step ${index + 1}`;
      const pair = JSON.stringify([step.provider, step.model]);
      if (seen.includes(pair)) throw refuse(at(index), 'stepRepeated', `${label} repeats another step of the list.`);
      if (step.provider === own.provider && step.model === own.model) throw refuse(at(index), 'stepOwnRole', `${label} is the ${isExtra(target) ? 'reviewer' : 'role'}’s own provider and model, so it would move nowhere.`);
      seen.push(pair);
    });
  }
  if (isExtra(target)) {
    if (edited.length > 0) own.failover = steps;
    else delete own.failover;
    write(file, withEntry(current, target, own), folder);
    return { saved: savedOf(target, own) };
  }
  if (edited.length > 0) roles[target] = steps;
  else delete roles[target];
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
