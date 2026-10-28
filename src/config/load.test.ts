import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { defaults, loadConfig } from './load.ts';

const valid = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { 'author-bot': { kind: 'forge', agent: 'artanis-agent' }, 'reviewer-bot': { kind: 'gh' } },
  orchestratorProfile: 'author-bot',
  agentOptions: { claude: { harness: 'claude', model: 'm' }, codex: { harness: 'codex', model: 'm' } },
  agents: {
    author: { profile: 'author-bot', option: 'claude' },
    reviewer: { profile: 'reviewer-bot', option: 'codex' },
  },
};

const load = (user: object) => loadConfig(defaults, { ...valid, ...user });
const errorsOf = (user: object) => {
  const result = load(user);
  if (result.ok) throw new Error('expected invalid config');
  return result.errors;
};

describe('merge', () => {
  test('logLevel defaults to info, accepts a library level and rejects anything else', () => {
    expect(load({})).toMatchObject({ ok: true, config: { logLevel: 'info' } });
    expect(load({ logLevel: 'debug' })).toMatchObject({ ok: true, config: { logLevel: 'debug' } });
    expect(errorsOf({ logLevel: 'loud' }).map((e) => e.path)).toEqual(['logLevel']);
  });

  test('applies defaults when the user omits them', () => {
    const result = load({});
    expect(result).toMatchObject({ ok: true, config: { pollIntervalMinutes: 5, limits: defaults.limits } });
  });

  test('limits.optionChoiceSeconds defaults to 60 and must be a positive whole number', () => {
    expect(load({})).toMatchObject({ ok: true, config: { limits: { optionChoiceSeconds: 60 } } });
    expect(load({ limits: { optionChoiceSeconds: 15 } })).toMatchObject({ ok: true, config: { limits: { optionChoiceSeconds: 15 } } });
    for (const bad of [0, -1, 1.5, '60']) expect(errorsOf({ limits: { optionChoiceSeconds: bad } }).map((e) => e.path)).toEqual(['limits.optionChoiceSeconds']);
  });

  test('merges objects field by field', () => {
    const result = load({ limits: { maxReviews: 9 } });
    expect(result).toMatchObject({ ok: true, config: { limits: { ...defaults.limits, maxReviews: 9 } } });
  });

  test('replaces simple values', () => {
    expect(load({ pollIntervalMinutes: 1 })).toMatchObject({ ok: true, config: { pollIntervalMinutes: 1 } });
  });

  test('replaces lists whole', () => {
    const repos = [{ name: 'a/b' }];
    const base = { ...defaults, ...valid, repos: [{ name: 'x/y' }, { name: 'z/w' }] };
    expect(loadConfig(base, { repos })).toMatchObject({ ok: true, config: { repos } });
  });

  test('rejects an incompatible type without converting it', () => {
    expect(errorsOf({ limits: { maxReviews: '5' } })).toEqual([
      { path: 'limits.maxReviews', message: expect.any(String) },
    ]);
  });

  test('rejects a non-object config file', () => {
    expect(loadConfig(defaults, 'nope')).toMatchObject({ ok: false, errors: [{ path: '(root)' }] });
  });
});

describe('invalid config', () => {
  test('missing required fields are all listed at once', () => {
    const paths = loadConfig(defaults, {}) as { errors: { path: string }[] };
    expect(paths.errors.map((e) => e.path).sort()).toEqual(['agentOptions', 'agents', 'orchestratorProfile', 'profiles', 'repos']);
  });

  test('empty repos', () => {
    expect(errorsOf({ repos: [] }).map((e) => e.path)).toEqual(['repos']);
  });

  test('wrong type', () => {
    expect(errorsOf({ pollIntervalMinutes: 'soon' }).map((e) => e.path)).toEqual(['pollIntervalMinutes']);
  });

  test('finishedWindowDays defaults to 15 and accepts 1 and 30', () => {
    expect(load({})).toMatchObject({ ok: true, config: { finishedWindowDays: 15 } });
    expect(load({ finishedWindowDays: 1 })).toMatchObject({ ok: true, config: { finishedWindowDays: 1 } });
    expect(load({ finishedWindowDays: 30 })).toMatchObject({ ok: true, config: { finishedWindowDays: 30 } });
  });

  test.each([0, 31, 7.5, '7'])('finishedWindowDays %j is refused and the error names the field', (value) => {
    expect(errorsOf({ finishedWindowDays: value }).map((e) => e.path)).toEqual(['finishedWindowDays']);
  });

  test('maxConcurrentEpics 0', () => {
    expect(errorsOf({ limits: { maxConcurrentEpics: 0 } }).map((e) => e.path)).toEqual(['limits.maxConcurrentEpics']);
  });

  test.each([0, -1, 1.5, 'forever'])('maxExecutionHours %j', (value) => {
    expect(errorsOf({ limits: { maxExecutionHours: value } }).map((e) => e.path)).toEqual(['limits.maxExecutionHours']);
  });

  test('unknown profile references', () => {
    const errors = errorsOf({
      orchestratorProfile: 'ghost',
      agents: { ...valid.agents, reviewer: { ...valid.agents.reviewer, profile: 'phantom' } },
    });
    expect(errors).toEqual([
      { path: 'orchestratorProfile', message: expect.stringContaining('ghost') },
      { path: 'agents.reviewer.profile', message: expect.stringContaining('phantom') },
    ]);
  });

  test('reports every error together', () => {
    const errors = errorsOf({ limits: { maxConcurrentEpics: 0, maxExecutionHours: 0 }, orchestratorProfile: 'ghost' });
    expect(errors.map((e) => e.path).sort()).toEqual([
      'limits.maxConcurrentEpics',
      'limits.maxExecutionHours',
      'orchestratorProfile',
    ]);
  });
});

describe('maxExecutionHours', () => {
  test('"unlimited" is valid', () => {
    expect(load({ limits: { maxExecutionHours: 'unlimited' } }).ok).toBe(true);
  });
});

describe('identities', () => {
  const same = { profiles: { me: { kind: 'gh' }, bot: { kind: 'gh' } }, orchestratorProfile: 'me', agents: { author: { profile: 'me', option: 'claude' }, reviewer: { profile: 'me', option: 'codex' } } };
  const perRepo = { ...valid, repos: [{ name: 'a/one' }, { name: 'a/two', agents: { reviewer: { profile: 'author-bot' } } }, { name: 'a/three', agents: { reviewer: { profile: 'author-bot' } } }] };

  test('defaults to separate', () => {
    expect(load({})).toMatchObject({ ok: true, config: { identities: 'separate' } });
  });

  test.each([{}, { identities: 'separate' }])('the same profile for both roles is refused when identities is absent or separate: %j', (identities) => {
    expect(errorsOf({ ...same, ...identities }).map((e) => e.path)).toEqual(['agents']);
  });

  test('a per-repo override that makes the roles equal is refused once per repo under separate and accepted under shared', () => {
    expect(loadConfig(defaults, perRepo).ok).toBe(false);
    const errors = (loadConfig(defaults, perRepo) as { errors: { path: string }[] }).errors;
    expect(errors.map((e) => e.path)).toEqual(['repos.1.agents', 'repos.2.agents']);
    expect(loadConfig(defaults, { ...perRepo, identities: 'shared' }).ok).toBe(true);
  });

  test('shared accepts the same profile for both roles and also two different ones', () => {
    expect(load({ ...same, identities: 'shared' })).toMatchObject({ ok: true, config: { identities: 'shared' } });
    expect(load({ identities: 'shared' })).toMatchObject({ ok: true, config: { identities: 'shared' } });
  });

  test('shared still checks that the profiles exist', () => {
    expect(errorsOf({ ...same, identities: 'shared', orchestratorProfile: 'ghost' }).map((e) => e.path)).toEqual(['orchestratorProfile']);
  });

  test.each(['both', 'Shared', '', true])('rejects %j', (identities) => {
    expect(errorsOf({ identities }).map((e) => e.path)).toEqual(['identities']);
  });
});

describe('root', () => {
  test('expands ~', () => {
    expect(load({ root: '~/work' })).toMatchObject({ ok: true, config: { root: join(homedir(), 'work') } });
    expect(load({})).toMatchObject({ ok: true, config: { root: join(homedir(), '.solve') } });
  });
});

describe('profiles', () => {
  const withProfile = (profile: unknown) => ({ profiles: { ...valid.profiles, 'author-bot': profile } });

  test('accepts a forge bot and the gh login', () => {
    expect(load({}).ok).toBe(true);
  });

  test.each([
    ['an empty object', {}],
    ['an unknown kind', { kind: 'pat', token: 'x' }],
    ['forge without agent', { kind: 'forge' }],
    ['forge with an empty agent', { kind: 'forge', agent: '' }],
    ['gh with an agent', { kind: 'gh', agent: 'x' }],
    ['a secret next to the kind', { kind: 'forge', agent: 'x', token: 'ghp_secret' }],
    ['a string', 'forge'],
  ])('rejects %s, naming the profile', (_name, profile) => {
    const errors = errorsOf(withProfile(profile));
    expect(errors.length).toBeGreaterThan(0);
    for (const e of errors) expect(e.path).toMatch(/^profiles\.author-bot/);
  });
});

describe('repos', () => {
  test('rejects two repos with the same folder name in different organizations', () => {
    const errors = errorsOf({ repos: [{ name: 'AshuLab/demo' }, { name: 'other/Demo' }] });
    expect(errors.map((e) => e.path)).toEqual(['repos.1.name']);
    expect(errors[0]!.message).toContain('AshuLab/demo');
    expect(load({ repos: [{ name: 'AshuLab/demo' }, { name: 'other/demo2' }] }).ok).toBe(true);
  });

  test('names must be owner/name with plain folder names', () => {
    for (const name of ['demo', '../x', 'a/..', 'a/b/c', '/x']) expect(errorsOf({ repos: [{ name }] }).map((e) => e.path)).toEqual(['repos.0.name']);
  });
});

describe('agent options', () => {
  const withOptions = (agentOptions: object, agents: object = valid.agents) => ({ agentOptions, agents });
  const optionPaths = (agentOptions: object, agents?: object) => errorsOf(withOptions(agentOptions, agents)).map((e) => e.path);

  test('roles point at declared options, and a repo override of `option` is the one resolved for that repo', () => {
    expect(load({})).toMatchObject({ ok: true, config: { agentOptions: valid.agentOptions, agents: { author: { option: 'claude' }, reviewer: { option: 'codex' } } } });
    const result = load({ repos: [{ name: 'AshuLab/carrier', agents: { reviewer: { option: 'claude' } } }] });
    expect(result).toMatchObject({ ok: true, config: { repos: [{ agents: { reviewer: { option: 'claude' } } }] } });
  });

  test('`provider` is optional and only lmstudio or ollama', () => {
    expect(load(withOptions({ ...valid.agentOptions, codex: { harness: 'codex', model: 'google/gemma-4-12b', provider: 'lmstudio' } }))).toMatchObject({ ok: true, config: { agentOptions: { codex: { provider: 'lmstudio' } } } });
    expect(optionPaths({ ...valid.agentOptions, codex: { harness: 'codex', model: 'm', provider: 'vllm' } })).toEqual(['agentOptions.codex.provider']);
  });

  test('agy is a harness, but it cannot use a provider', () => {
    expect(load(withOptions({ ...valid.agentOptions, agy: { harness: 'agy', model: 'gemini-3.8-flash-low' } }, { ...valid.agents, author: { profile: 'author-bot', option: 'agy' } }))).toMatchObject({ ok: true });
    expect(errorsOf(withOptions({ ...valid.agentOptions, claude: { harness: 'agy', model: 'm', provider: 'ollama' } }))).toEqual([{ path: 'agentOptions.claude.provider', message: 'agentOptions.claude: agy cannot use the provider "ollama"' }]);
  });

  test('an option name is a lowercase word of up to 40 characters', () => {
    const option = { harness: 'codex', model: 'm' };
    for (const name of ['a', 'claude-ashu', 'x1-2', 'a'.repeat(40)]) expect(load(withOptions({ ...valid.agentOptions, [name]: option })).ok).toBe(true);
    for (const name of ['Claude', '1claude', '-claude', 'claude_work', 'claude work', '', 'a'.repeat(41)]) {
      const errors = errorsOf(withOptions({ ...valid.agentOptions, [name]: option }));
      expect(errors.map((e) => e.path)).toEqual([`agentOptions.${name}`]);
      expect(errors[0]!.message).toContain('lowercase word');
    }
  });

  test('a role or a repo override pointing at an option that is not declared names the field', () => {
    expect(errorsOf({ agents: { ...valid.agents, reviewer: { ...valid.agents.reviewer, option: 'ghost' } } })).toEqual([{ path: 'agents.reviewer.option', message: expect.stringContaining('ghost') }]);
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { author: { option: 'phantom' } } }] })).toEqual([{ path: 'repos.0.agents.author.option', message: expect.stringContaining('phantom') }]);
  });

  test('`configDir` is expanded from ~ and must then be absolute; an empty one is refused', () => {
    expect(load(withOptions({ ...valid.agentOptions, claude: { harness: 'claude', model: 'm', configDir: '~/.claude-ashu' } }))).toMatchObject({ ok: true, config: { agentOptions: { claude: { configDir: join(homedir(), '.claude-ashu') } } } });
    expect(load(withOptions({ ...valid.agentOptions, codex: { harness: 'codex', model: 'm', configDir: '/srv/codex' } }))).toMatchObject({ ok: true, config: { agentOptions: { codex: { configDir: '/srv/codex' } } } });
    for (const configDir of ['', 'relative/dir', '.claude', '~other/dir']) expect(optionPaths({ ...valid.agentOptions, claude: { harness: 'claude', model: 'm', configDir } })).toEqual(['agentOptions.claude.configDir']);
  });

  test('an agy option cannot have a `configDir`', () => {
    const errors = errorsOf(withOptions({ ...valid.agentOptions, claude: { harness: 'agy', model: 'm', configDir: '/srv/agy' } }));
    expect(errors).toEqual([{ path: 'agentOptions.claude.configDir', message: expect.stringContaining('agy') }]);
  });

  test('an unknown field inside an option is refused', () => {
    const errors = errorsOf(withOptions({ ...valid.agentOptions, claude: { harness: 'claude', model: 'm', token: 'x' } }));
    expect(errors).toEqual([{ path: 'agentOptions.claude', message: expect.stringContaining('token') }]);
  });

  test.each(['harness', 'model', 'provider'])('the old shape, `%s` inside agents.<role> or a repo override, is refused with where it went', (key) => {
    const paths = (user: object) => errorsOf(user).map((e) => e.path);
    const old = { ...valid.agents, author: { ...valid.agents.author, [key]: key === 'model' ? 'm' : key === 'harness' ? 'claude' : 'ollama' } };
    const errors = errorsOf({ agents: old });
    expect(errors).toEqual([{ path: `agents.author.${key}`, message: expect.stringMatching(new RegExp(`"${key}" moved to agentOptions.*docs/configuration\\.md`)) }]);
    expect(paths({ repos: [{ name: 'x/y', agents: { reviewer: { [key]: 'x' } } }] })).toEqual([`repos.0.agents.reviewer.${key}`]);
  });
});

describe('persona', () => {
  const author = valid.agents.author;
  const withPersona = (persona: unknown) => ({ agents: { ...valid.agents, author: { ...author, persona } } });

  test('an agent takes a persona with a name, a prompt or both, globally and per repo', () => {
    for (const persona of [{ name: 'Ada' }, { prompt: 'Be strict about migrations.' }, { name: 'Ada', prompt: 'Be strict.' }]) {
      expect(load(withPersona(persona))).toMatchObject({ ok: true, config: { agents: { author: { persona } } } });
    }
    expect(load({ repos: [{ name: 'AshuLab/carrier', agents: { reviewer: { persona: { name: 'Rex' } } } }] })).toMatchObject({ ok: true, config: { repos: [{ agents: { reviewer: { persona: { name: 'Rex' } } } }] } });
  });

  test('the name is one trimmed line of 1 to 40 characters', () => {
    expect(load(withPersona({ name: '  Ada  ' }))).toMatchObject({ config: { agents: { author: { persona: { name: 'Ada' } } } } });
    expect(load(withPersona({ name: 'a'.repeat(40) }))).toMatchObject({ ok: true });
    for (const name of ['', '   ', 'Ada\nLovelace', 'Ada\rL', 'a'.repeat(41)]) expect([...new Set(errorsOf(withPersona({ name })).map((e) => e.path))]).toEqual(['agents.author.persona.name']);
  });

  test('the prompt is 1 to 4000 characters', () => {
    expect(load(withPersona({ prompt: 'a'.repeat(4000) }))).toMatchObject({ ok: true });
    for (const prompt of ['', '  ', 'a'.repeat(4001)]) expect(errorsOf(withPersona({ prompt })).map((e) => e.path)).toEqual(['agents.author.persona.prompt']);
  });

  test('a persona is an object with only name and prompt', () => {
    for (const persona of ['Ada', null, ['Ada']]) expect(errorsOf(withPersona(persona)).map((e) => e.path)).toEqual(['agents.author.persona']);
    expect(errorsOf(withPersona({ name: 'Ada', role: 'x' })).map((e) => e.path)).toEqual(['agents.author.persona']);
  });
});
