import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { ConfigRefused } from './engine-edit.ts';
import { engineConfigPathOf, providersPathOf } from './places.ts';
import { editFailover, editPersona, editRepoRole, editRole, setLeadReviewer, setOrchestratorProfile } from './role-edit.ts';
import { validEngineFile } from './testing.ts';

// The role writes of `engine.json`: the file after each request (every key it does not touch stays), a refusal with the words the app's checks gave, its code and its key path and kind, and the file as it was.
let folder: string;
let file: string;
beforeEach(() => {
  folder = mkdtempSync(join(tmpdir(), 're-'));
  file = engineConfigPathOf(folder);
  writeFileSync(file, JSON.stringify(validEngineFile, null, 2));
  writeFileSync(join(folder, 'agents.json'), JSON.stringify({ agents: [{ name: 'artanis-agent' }, { name: 'nova' }, { name: 'zeus' }] }));
  vi.stubEnv('AGENT_FORGE_CONFIG', join(folder, 'agents.json'));
});
afterEach(() => {
  vi.unstubAllEnvs();
  rmSync(folder, { recursive: true, force: true });
});
const written = () => JSON.parse(readFileSync(file, 'utf8'));
const withFile = (change: (file: Record<string, any>) => void) => {
  const edited = structuredClone(validEngineFile) as Record<string, any>;
  change(edited);
  writeFileSync(file, JSON.stringify(edited, null, 2));
};
const refusal = (run: () => unknown) => {
  try {
    run();
  } catch (error) {
    if (error instanceof ConfigRefused) return error;
    throw error;
  }
  throw new Error('expected a refusal');
};
/** The refusal as the engine answers it, and the file untouched (and no temporary file left). */
function refused(run: () => unknown) {
  const before = readFileSync(file, 'utf8');
  const error = refusal(run);
  expect(readFileSync(file, 'utf8')).toBe(before);
  expect(readdirSync(folder).filter((name) => name.endsWith('.tmp'))).toEqual([]);
  return [error.message, error.code, error.params];
}

describe('editRole', () => {
  test('applies the changes together, keeps every other key and the order, and answers the role', () => {
    const result = editRole('author', { provider: 'codex', model: ' gpt-5 ', effort: 'high' }, file, folder);
    expect(written()).toEqual({ ...validEngineFile, agents: { ...validEngineFile.agents, author: { profile: 'author-bot', provider: 'codex', model: 'gpt-5', effort: 'high' } } });
    expect(Object.keys(written())).toEqual(Object.keys(validEngineFile));
    expect(result.saved.agents).toEqual({ author: { profile: 'author-bot', provider: 'codex', model: 'gpt-5', effort: 'high' } });
    editRole('author', { effort: null }, file, folder);
    expect(written().agents.author).toEqual({ profile: 'author-bot', provider: 'codex', model: 'gpt-5' });
  });

  test('a bot or the gh login reuses the profile that already means it, and otherwise gets a free name', () => {
    editRole('reviewer', { identity: { kind: 'forge', agent: 'artanis-agent' } }, file, folder);
    expect(written().agents.reviewer.profile).toBe('author-bot');
    editRole('author', { identity: { kind: 'gh' } }, file, folder);
    expect(written().agents.author.profile).toBe('reviewer-bot');
    withFile((edited) => (edited.profiles.nova = { kind: 'gh' }));
    editRole('author', { identity: { kind: 'forge', agent: 'nova' } }, file, folder);
    expect(written().profiles['nova-2']).toEqual({ kind: 'forge', agent: 'nova' });
    expect(written().agents.author.profile).toBe('nova-2');
    withFile((edited) => ((edited.profiles = { 'my-gh': { kind: 'forge', agent: 'zeus' }, gh: { kind: 'forge', agent: 'zeus' } }), (edited.orchestratorProfile = 'gh'), (edited.agents.author.profile = 'gh'), (edited.agents.reviewer.profile = 'gh')));
    editRole('author', { identity: { kind: 'gh' } }, file, folder);
    expect(written().profiles['gh-2']).toEqual({ kind: 'gh' });
  });

  test('a role that now runs on the provider and model of a failover step drops it, an emptied list goes and failover with it', () => {
    withFile((edited) => (edited.failover = { triggers: ['usage_limit'], roles: { author: [{ provider: 'codex', model: 'g' }, { provider: 'agy', model: 'x' }], reviewer: [{ provider: 'agy', model: 'x' }] } }));
    editRole('author', { provider: 'codex', model: 'g' }, file, folder);
    expect(written().failover.roles).toEqual({ author: [{ provider: 'agy', model: 'x' }], reviewer: [{ provider: 'agy', model: 'x' }] });
    editRole('author', { provider: 'agy', model: 'x' }, file, folder);
    expect(written().failover.roles).toEqual({ reviewer: [{ provider: 'agy', model: 'x' }] });
    editRole('reviewer', { provider: 'agy', model: 'x' }, file, folder);
    expect(written().failover).toEqual({ triggers: ['usage_limit'] });
    withFile((edited) => (edited.failover = { roles: { reviewer: [{ provider: 'agy', model: 'x' }] } }));
    editRole('reviewer', { provider: 'agy', model: 'x' }, file, folder);
    expect('failover' in written()).toBe(false);
  });

  test.each([
    ['a bot the registry does not list', 'author', { identity: { kind: 'forge', agent: 'ghost' } }, '“ghost” is not in Agent Forge’s list. Pick another one.', 'agents.author.profile', 'botNotListed'],
    ['a provider that is not an account', 'author', { provider: 'nope' }, 'Provider “nope” is not an account of providers.json. Pick another one.', 'agents.author.provider', 'notAnAccount'],
    ['an empty model', 'author', { model: '   ' }, 'The model cannot be empty.', 'agents.author.model', 'empty'],
    ['an effort that is not a level', 'author', { effort: 'ultra' }, 'Effort must be one of low, medium, high, xhigh, max.', 'agents.author.effort', 'notOneOf'],
    ['a role with no entry', 'leadReviewer', { model: 'm' }, 'Lead reviewer has no entry in engine.json. Add it there first.', 'agents.leadReviewer', 'noEntry'],
  ] as const)('%s is refused with its words, a code and its key path and kind, nothing written', (_what, role, changes, words, path, kind) => {
    expect(refused(() => editRole(role, changes as never, file, folder))).toEqual([words, 'config.problem', { path, problem: kind }]);
  });

  test('a role is not changed when one of its changes is refused (one write or none)', () => {
    refused(() => editRole('author', { model: 'good', provider: 'nope' }, file, folder));
    expect(written()).toEqual(validEngineFile);
  });

  test('a file the schema refuses after the change is refused with its key path and left as it was', () => {
    withFile((edited) => (edited.agents.author.mystery = 1));
    expect(refused(() => editRole('author', { model: 'm3' }, file, folder))[1]).toBe('config.problem');
  });
});

describe('setLeadReviewer', () => {
  test('an incomplete draft is refused before the file is read', () => {
    rmSync(file);
    expect(refusal(() => setLeadReviewer({ provider: 'codex' }, file, folder))).toMatchObject({ message: 'The lead reviewer needs an identity, a model.', code: 'config.problem', params: { path: 'agents.leadReviewer', problem: 'incomplete' } });
    expect(refusal(() => setLeadReviewer({ model: ' ' }, file, folder)).message).toBe('The lead reviewer needs an identity, a provider, a model.');
  });

  test('a complete draft writes the whole role in one write', () => {
    setLeadReviewer({ identity: { kind: 'forge', agent: 'nova' }, provider: 'codex', model: 'm', effort: 'max' }, file, folder);
    expect(written().agents.leadReviewer).toEqual({ profile: 'nova', provider: 'codex', model: 'm', effort: 'max' });
    expect(written().profiles.nova).toEqual({ kind: 'forge', agent: 'nova' });
    expect(refused(() => setLeadReviewer({ identity: { kind: 'forge', agent: 'ghost' }, provider: 'codex', model: 'm' }, file, folder))[2]).toEqual({ path: 'agents.leadReviewer.profile', problem: 'botNotListed' });
  });

  test('off removes agents.leadReviewer and its failover steps and nothing else; a file with neither is not written and still answers saved', () => {
    withFile((edited) => ((edited.agents.leadReviewer = { profile: 'author-bot', provider: 'claude', model: 'm' }), (edited.failover = { triggers: ['usage_limit'], roles: { leadReviewer: [{ provider: 'codex', model: 'g' }], author: [{ provider: 'agy', model: 'x' }] } })));
    expect(setLeadReviewer(null, file, folder)).toEqual({ saved: {} });
    expect(written()).toEqual({ ...validEngineFile, failover: { triggers: ['usage_limit'], roles: { author: [{ provider: 'agy', model: 'x' }] } } });
    writeFileSync(file, '{"repos":[ ] }');
    expect(setLeadReviewer(null, file, folder)).toEqual({ saved: {} });
    expect(readFileSync(file, 'utf8')).toBe('{"repos":[ ] }');
  });
});

describe('editRepoRole', () => {
  test('sets the fields that are set, trimmed, keeps the entry other keys, and a field not set is not the repo own', () => {
    withFile((edited) => (edited.repos[1].agents.author = { model: 'opus', effort: 'low', skills: { ship: 'ship' } }));
    editRepoRole('acme/web', 'author', { profile: 'reviewer-bot', model: ' qwen ', persona: { name: ' Rex ', prompt: '  ' } }, file, folder);
    expect(written().repos[1].agents.author).toEqual({ profile: 'reviewer-bot', model: 'qwen', persona: { name: 'Rex' }, skills: { ship: 'ship' } });
    expect(written().repos[0]).toEqual(validEngineFile.repos[0]);
    expect(Object.keys(written())).toEqual(Object.keys(validEngineFile));
  });

  test('removes the entry when nothing is left, and agents when it was the last; fields null removes the whole override', () => {
    editRepoRole('acme/web', 'author', { model: '  ' }, file, folder);
    expect(written().repos[1]).toEqual({ name: 'acme/web' });
    editRepoRole('acme/web', 'reviewer', { model: 'a' }, file, folder);
    editRepoRole('acme/web', 'author', { model: 'b' }, file, folder);
    editRepoRole('acme/web', 'reviewer', null, file, folder);
    expect(written().repos[1].agents).toEqual({ author: { model: 'b' } });
    editRepoRole('acme/web', 'author', null, file, folder);
    expect(written().repos[1]).toEqual({ name: 'acme/web' });
  });

  test.each([
    ['an undeclared profile', { profile: 'ghost' }, 'Identity “ghost” is not declared in profiles. Pick another one.', 'repos[1].agents.reviewer.profile', 'notDeclared'],
    ['an undeclared account', { provider: 'ollama' }, 'Provider “ollama” is not an account of providers.json. Pick another one.', 'repos[1].agents.reviewer.provider', 'notAnAccount'],
    ['a persona name of 41 characters', { persona: { name: 'x'.repeat(41) } }, 'The persona’s name is one line of up to 40 characters.', 'repos[1].agents.reviewer.persona.name', 'tooLong'],
    ['a persona prompt over 4000 characters', { persona: { prompt: 'x'.repeat(4001) } }, 'The persona’s prompt is up to 4000 characters.', 'repos[1].agents.reviewer.persona.prompt', 'tooLong'],
  ])('%s is refused with its words, code and key path', (_what, fields, words, path, kind) => {
    expect(refused(() => editRepoRole('acme/web', 'reviewer', fields, file, folder))).toEqual([words, 'config.problem', { path, problem: kind }]);
  });

  test('a repo that is no longer in the file is refused', () => {
    expect(refused(() => editRepoRole('x/y', 'reviewer', { model: 'a' }, file, folder))).toEqual(['x/y is no longer in the config file.', 'config.problem', { path: 'repos', problem: 'notWatched' }]);
  });
});

describe('editPersona', () => {
  test('sets the name and the prompt trimmed, either alone, and null for both takes it out', () => {
    editPersona('author', ' Ada ', ' Be brief. ', file, folder);
    expect(written().agents.author.persona).toEqual({ name: 'Ada', prompt: 'Be brief.' });
    editPersona('author', null, 'Only this', file, folder);
    expect(written().agents.author.persona).toEqual({ prompt: 'Only this' });
    editPersona('author', null, null, file, folder);
    expect(written()).toEqual(validEngineFile);
  });

  test.each([
    ['a blank name', ' ', null, 'The persona’s name cannot be empty. Leave it out instead.', 'agents.author.persona.name', 'empty'],
    ['a blank prompt', null, '', 'The persona’s prompt cannot be empty. Leave it out instead.', 'agents.author.persona.prompt', 'empty'],
    ['a name over 40 characters', 'x'.repeat(41), null, 'The persona’s name is one line of up to 40 characters.', 'agents.author.persona.name', 'tooLong'],
    ['a name with a line break', 'a\nb', null, 'The persona’s name is one line of up to 40 characters.', 'agents.author.persona.name', 'tooLong'],
    ['a prompt over 4000 characters', null, 'x'.repeat(4001), 'The persona’s prompt is up to 4000 characters.', 'agents.author.persona.prompt', 'tooLong'],
  ])('%s is refused', (_what, name, prompt, words, path, kind) => {
    expect(refused(() => editPersona('author', name, prompt, file, folder))).toEqual([words, 'config.problem', { path, problem: kind }]);
  });

  test('a role with no entry is refused', () => {
    expect(refused(() => editPersona('leadReviewer', 'a', null, file, folder))[2]).toEqual({ path: 'agents.leadReviewer', problem: 'noEntry' });
  });
});

describe('editFailover', () => {
  test('sets the first two steps, trimmed, keeps the steps after them, and both null removes the list and failover with it', () => {
    withFile((edited) => (edited.failover = { triggers: ['usage_limit'], roles: { author: [{ provider: 'codex' }, { provider: 'agy', model: 'x' }, { provider: 'claude', model: 'kept' }] } }));
    editFailover('author', { provider: 'claude', model: ' haiku ', effort: 'low' }, { provider: 'codex' }, file, folder);
    expect(written().failover.roles.author).toEqual([{ provider: 'claude', model: 'haiku', effort: 'low' }, { provider: 'codex' }, { provider: 'claude', model: 'kept' }]);
    editFailover('author', null, null, file, folder);
    expect(written().failover).toEqual({ triggers: ['usage_limit'] });
    withFile((edited) => (edited.failover = { roles: { author: [{ provider: 'codex' }] } }));
    editFailover('author', null, null, file, folder);
    expect('failover' in written()).toBe(false);
  });

  test.each([
    ['a second step with no first', null, { provider: 'codex' }, 'Then needs a First step.', 'failover.roles.author.1', 'firstMissing'],
    ['a provider that is not an account', { provider: 'nope' }, null, 'First: “nope” is not an account of providers.json. Pick another one.', 'failover.roles.author.0', 'providerNotDeclared'],
    ['a second provider that is not an account', { provider: 'codex' }, { provider: 'nope' }, 'Then: “nope” is not an account of providers.json. Pick another one.', 'failover.roles.author.1', 'providerNotDeclared'],
    ['a repeated step', { provider: 'codex', model: 'g' }, { provider: 'codex', model: 'g' }, 'Then repeats another step of the list.', 'failover.roles.author.1', 'stepRepeated'],
    ['a step equal to the role own provider and model', { provider: 'claude', model: 'm' }, null, 'First is the role’s own provider and model, so it would move nowhere.', 'failover.roles.author.0', 'stepOwnRole'],
  ])('%s is refused with its words, code, key path and kind', (_what, first, second, words, path, kind) => {
    expect(refused(() => editFailover('author', first, second, file, folder))).toEqual([words, 'config.problem', { path, problem: kind }]);
  });

  test('a role with no entry is refused, and a step that repeats one kept after the first two too', () => {
    expect(refused(() => editFailover('leadReviewer', { provider: 'codex' }, null, file, folder))[2]).toEqual({ path: 'agents.leadReviewer', problem: 'noEntry' });
    withFile((edited) => (edited.failover = { roles: { author: [{ provider: 'codex' }, { provider: 'agy' }, { provider: 'claude', model: 'k' }] } }));
    expect(refused(() => editFailover('author', { provider: 'claude', model: 'k' }, { provider: 'agy' }, file, folder))[0]).toBe('Step 3 repeats another step of the list.');
  });

  test('the accounts are the ones of providers.json', () => {
    writeFileSync(providersPathOf(folder), JSON.stringify({ providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' }, work: { harness: 'claude' } } }));
    editFailover('author', { provider: 'work' }, null, file, folder);
    expect(written().failover.roles.author).toEqual([{ provider: 'work' }]);
    expect(refused(() => editFailover('author', { provider: 'agy' }, null, file, folder))[2]).toEqual({ path: 'failover.roles.author.0', problem: 'providerNotDeclared' });
  });
});

describe('setOrchestratorProfile', () => {
  test('sets the profile and null takes the key out, every other key staying', () => {
    withFile((edited) => delete edited.orchestratorProfile);
    expect(setOrchestratorProfile('author-bot', file, folder)).toEqual({ saved: { orchestratorProfile: 'author-bot' } });
    expect(written().orchestratorProfile).toBe('author-bot');
    expect(setOrchestratorProfile(null, file, folder)).toEqual({ saved: {} });
    expect('orchestratorProfile' in written()).toBe(false);
    expect(written().agents).toEqual(validEngineFile.agents);
  });

  test('a profile the file does not declare is refused by the schema and the file stays', () => {
    const [, code, params] = refused(() => setOrchestratorProfile('ghost', file, folder));
    expect([code, (params as { path: string }).path]).toEqual(['config.problem', 'orchestratorProfile']);
  });
});

test('a file that is not there, not JSON or not an object is refused and not made', () => {
  rmSync(file);
  expect(refusal(() => editRole('author', { model: 'm' }, file, folder)).params).toEqual({ path: '(file)', problem: 'notFound' });
  writeFileSync(file, '[]');
  expect(refusal(() => setOrchestratorProfile('a', file, folder)).params).toEqual({ path: '(file)', problem: 'notAnObject' });
  expect(readFileSync(file, 'utf8')).toBe('[]');
});
