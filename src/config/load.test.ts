import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { defaultConfigPath } from './default-path.ts';
import { defaults, loadConfig } from './load.ts';
import { resolveRepoConfig } from './resolve.ts';
import { loadProviders } from './providers.ts';
import { loadWithProviders } from './testing.ts';

const valid = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { 'author-bot': { kind: 'forge', agent: 'artanis-agent' }, 'reviewer-bot': { kind: 'gh' } },
  orchestratorProfile: 'author-bot',
  providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } },
  agents: {
    author: { profile: 'author-bot', provider: 'claude', model: 'm' },
    reviewer: { profile: 'reviewer-bot', provider: 'codex', model: 'm' },
  },
};

const load = (user: object) => loadWithProviders({ ...valid, ...user });
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

  test('limits.optionChoiceSeconds is refused naming the key and saying an epic starts at once on its roles', () => {
    const errors = errorsOf({ limits: { optionChoiceSeconds: 15 } });
    expect(errors.map((e) => e.path)).toEqual(['limits']);
    expect(errors[0]!.message).toContain('limits.optionChoiceSeconds is gone');
    expect(errors[0]!.message).toContain('starts at once on its roles');
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
    const { providers, ...file } = valid;
    const base = { ...defaults, ...file, repos: [{ name: 'x/y' }, { name: 'z/w' }] };
    expect(loadConfig(base, { repos }, providers as never)).toMatchObject({ ok: true, config: { repos } });
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
    expect(paths.errors.map((e) => e.path).sort()).toEqual(['agents', 'profiles', 'repos']);
  });

  test('no repos yet is allowed', () => {
    expect(load({ repos: [] }).ok).toBe(true);
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

describe('sharing is derived', () => {
  const same = { profiles: { me: { kind: 'gh' }, bot: { kind: 'gh' } }, orchestratorProfile: 'me', providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } }, agents: { author: { profile: 'me', provider: 'claude', model: 'm' }, reviewer: { profile: 'me', provider: 'codex', model: 'm' } } };

  test('the same profile for both roles, or for the author and the lead reviewer, loads: there is no key to say it', () => {
    expect(load(same).ok).toBe(true);
    expect(load({ agents: { ...valid.agents, leadReviewer: { profile: 'author-bot', provider: 'claude', model: 'm' } } }).ok).toBe(true);
    const perRepo = { ...valid, repos: [{ name: 'a/one' }, { name: 'a/two', agents: { reviewer: { profile: 'author-bot' } } }] };
    expect(loadWithProviders(perRepo).ok).toBe(true);
  });

  test.each(['separate', 'shared', 'both', '', true])('an identities key of %j is refused, naming the key and saying sharing is derived', (identities) => {
    expect(errorsOf({ identities })).toEqual([{ path: 'identities', message: expect.stringContaining('shared when its author and reviewer resolve to the same account') }]);
  });

  test('profiles that are not declared are still refused', () => {
    expect(errorsOf({ ...same, orchestratorProfile: 'ghost' }).map((e) => e.path)).toEqual(['orchestratorProfile']);
    expect(errorsOf({ agents: { ...valid.agents, leadReviewer: { profile: 'phantom', provider: 'claude', model: 'm' } } })).toEqual([{ path: 'agents.leadReviewer.profile', message: expect.stringContaining('phantom') }]);
    expect(errorsOf({ agents: { ...valid.agents, leadReviewer: { profile: 'reviewer-bot', provider: 'phantom', model: 'm' } } })).toEqual([{ path: 'agents.leadReviewer.provider', message: expect.stringContaining('phantom') }]);
  });
});

describe('what a repo\'s page writes under repos[].agents', () => {
  const inRepo = (agents: object) => ({ repos: [{ name: 'AshuLab/carrier', agents }] });

  test.each([
    ['only a persona', { reviewer: { persona: { name: 'Rex', prompt: 'Be strict.' } } }],
    ['only a persona with a name', { reviewer: { persona: { name: 'Rex' } } }],
    ['only a persona with a prompt', { reviewer: { persona: { prompt: 'Be strict.' } } }],
    ['only a model', { reviewer: { model: 'qwen3-coder' } }],
    ['only an account', { reviewer: { provider: 'claude' } }],
    ['only an effort', { reviewer: { effort: 'xhigh' } }],
    ['only a profile', { reviewer: { profile: 'author-bot' } }],
    ['a role with no field', { reviewer: {} }],
    ['no role at all', {}],
    ['an identity equal to the other role\'s', { author: { profile: 'reviewer-bot' } }],
  ])('%s loads', (_, agents) => {
    expect(load(inRepo(agents)).ok).toBe(true);
  });

  test('an unknown profile or account is refused naming the key', () => {
    expect(errorsOf(inRepo({ reviewer: { profile: 'ghost' } }))).toEqual([{ path: 'repos.0.agents.reviewer.profile', message: expect.stringContaining('ghost') }]);
    expect(errorsOf(inRepo({ author: { provider: 'ghost' } }))).toEqual([{ path: 'repos.0.agents.author.provider', message: expect.stringContaining('ghost') }]);
  });
});

describe('what the Agents page writes under agents.<role> and profiles', () => {
  const author = valid.agents.author;
  const bot = { kind: 'forge', agent: 'spare' };

  const written: [string, object][] = [
    ['a bot chosen for the author', { profiles: { ...valid.profiles, spare: bot }, agents: { ...valid.agents, author: { ...author, profile: 'spare' } } }],
    ['the person\'s login chosen for the author', { profiles: { ...valid.profiles, gh: { kind: 'gh' } }, agents: { ...valid.agents, author: { ...author, profile: 'gh' } } }],
    ['another account', { agents: { ...valid.agents, author: { ...author, provider: 'codex' } } }],
    ['another model', { agents: { ...valid.agents, author: { ...author, model: 'gpt-5' } } }],
    ['no effort', { agents: { ...valid.agents, author: { ...author } } }],
    ...['low', 'medium', 'high', 'xhigh', 'max'].map((effort): [string, object] => [`effort ${effort}`, { agents: { ...valid.agents, author: { ...author, effort } } }]),
    ['the same bot for both roles', { profiles: { ...valid.profiles, spare: bot }, agents: { author: { ...author, profile: 'spare' }, reviewer: { ...valid.agents.reviewer, profile: 'spare' } } }],
    ['two names for the same bot', { profiles: { ...valid.profiles, one: bot, two: bot }, agents: { author: { ...author, profile: 'one' }, reviewer: { ...valid.agents.reviewer, profile: 'two' } } }],
  ];

  test.each(written)('%s loads', (_, user) => {
    expect(load(user).ok).toBe(true);
  });

  test('both roles on one bot, by one name or two, are one account for the engine', () => {
    for (const names of [['spare', 'spare'], ['one', 'two']] as const) {
      const profiles = { ...valid.profiles, spare: bot, one: bot, two: bot };
      const loaded = load({ profiles, agents: { author: { ...author, profile: names[0] }, reviewer: { ...valid.agents.reviewer, profile: names[1] } } });
      if (!loaded.ok) throw new Error('expected a valid config');
      expect(resolveRepoConfig(loaded.config, loaded.config.repos[0]!).sharedIdentity).toBe(true);
    }
  });
});

describe('orchestratorProfile', () => {
  const { orchestratorProfile: _, ...withoutOrchestrator } = valid;

  test('left out, it is the author\'s profile', () => {
    expect(loadWithProviders(withoutOrchestrator)).toMatchObject({ ok: true, config: { orchestratorProfile: 'author-bot' } });
  });

  test('given, it is kept', () => {
    expect(load({ orchestratorProfile: 'reviewer-bot' })).toMatchObject({ ok: true, config: { orchestratorProfile: 'reviewer-bot' } });
  });
});

describe('root', () => {
  test('is an unknown key like any other, and the same config without it loads', () => {
    expect(errorsOf({ root: '~/work' })).toEqual([{ path: '(root)', message: 'Unrecognized key: "root"' }]);
    expect(load({})).toMatchObject({ ok: true });
  });
});

describe('the config\'s place', () => {
  test('is config.json in the Carrier folder, wherever that is', () => {
    const before = process.env.CARRIER_HOME;
    try {
      process.env.CARRIER_HOME = '/tmp/some-home';
      expect(defaultConfigPath()).toBe('/tmp/some-home/config.json');
      delete process.env.CARRIER_HOME;
      expect(defaultConfigPath()).toBe(join(homedir(), '.carrier', 'config.json'));
    } finally {
      if (before === undefined) delete process.env.CARRIER_HOME;
      else process.env.CARRIER_HOME = before;
    }
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

describe('providers', () => {
  const withProviders = (providers: object, agents: object = valid.agents) => ({ providers, agents });
  const providerPaths = (providers: object, agents?: object) => errorsOf(withProviders(providers, agents)).map((e) => e.path);

  test('roles point at declared providers', () => {
    expect(load({})).toMatchObject({ ok: true, config: { providers: valid.providers, agents: { author: { provider: 'claude' }, reviewer: { provider: 'codex' } } } });
    const result = load({ repos: [{ name: 'AshuLab/carrier', agents: { reviewer: { provider: 'claude' } } }] });
    expect(result).toMatchObject({ ok: true, config: { repos: [{ agents: { reviewer: { provider: 'claude' } } }] } });
  });

  test('a role or a repo override pointing at a provider that is not declared names the field', () => {
    expect(errorsOf({ agents: { ...valid.agents, reviewer: { ...valid.agents.reviewer, provider: 'ghost' } } })).toEqual([{ path: 'agents.reviewer.provider', message: expect.stringContaining('ghost') }]);
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { author: { provider: 'phantom' } } }] })).toEqual([{ path: 'repos.0.agents.author.provider', message: expect.stringContaining('phantom') }]);
  });

  test('the accounts come from providers.json: two of them, and the roles resolve to the harness, model and config folder of the one they name', () => {
    const accounts = loadProviders({ providers: { work: { harness: 'claude', configDir: '/srv/claude-work', model: 'opus' }, spare: { harness: 'codex', configDir: '/srv/codex' } } });
    if (!accounts.ok) throw new Error('expected valid accounts');
    const { providers: _, ...file } = valid;
    const roles = { agents: { author: { profile: 'author-bot', provider: 'work', model: 'm1' }, reviewer: { profile: 'reviewer-bot', provider: 'spare', model: 'm' } } };
    const loaded = loadConfig(defaults, { ...file, ...roles }, accounts.providers);
    if (!loaded.ok) throw new Error(JSON.stringify(loaded.errors));
    expect(loaded.config.providers).toEqual(accounts.providers);
    const { agents } = resolveRepoConfig(loaded.config, loaded.config.repos[0]!);
    expect(agents.author).toMatchObject({ harness: 'claude', model: 'm1', configDir: '/srv/claude-work' });
    expect(agents.reviewer).toMatchObject({ harness: 'codex', model: 'm', configDir: '/srv/codex' });
  });

  test('without providers.json a role that names an account fails as an undeclared one', () => {
    const { providers: _, ...file } = valid;
    const loaded = loadConfig(defaults, file);
    expect(loaded.ok === false && loaded.errors.map((e) => e.path)).toEqual(['agents.author.provider', 'agents.reviewer.provider']);
    expect(loaded.ok === false && loaded.errors[0]!.message).toBe('provider "claude" is not declared in providers');
  });

  test('with no providers.json the config has claude, codex and agy, and a role that names claude loads', () => {
    const { providers: _, ...file } = valid;
    const accounts = loadProviders({});
    if (!accounts.ok) throw new Error('defaults');
    const loaded = loadConfig(defaults, file, accounts.providers);
    expect(loaded).toMatchObject({ ok: true, config: { providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' }, agy: { harness: 'agy' } }, agents: { author: { provider: 'claude' } } } });
  });

  test('a config.json that still has `providers` is refused with a message that names providers.json', () => {
    expect(loadConfig(defaults, valid)).toEqual({ ok: false, errors: [{ path: 'providers', message: expect.stringContaining('providers.json') }] });
  });

  test('`option` inside agents.<role> or a repo override is refused with where it went', () => {
    const errors = errorsOf({ agents: { ...valid.agents, author: { ...valid.agents.author, option: 'legacy' } } });
    expect(errors).toEqual([{ path: 'agents.author.option', message: expect.stringMatching(/was replaced by "provider" and "model"/) }]);
  });
});

describe('failover', () => {
  const roles = (author: unknown) => ({ failover: { roles: { author } } });
  const used = 'a role has failover when its list of steps is not empty';

  test('absent, and an empty list, load: no failover for the role', () => {
    const absent = load({});
    expect(absent.ok && absent.config.failover).toBeUndefined();
    expect(load(roles([]))).toMatchObject({ ok: true, config: { failover: { roles: { author: [] } } } });
  });

  test('steps with a provider and an optional model, and the triggers, load as written', () => {
    const failover = { triggers: ['usage_limit', 'service_down'], roles: { author: [{ provider: 'codex', model: 'gpt-5' }, { provider: 'claude', model: 'haiku' }], leadReviewer: [{ provider: 'claude' }] } };
    expect(load({ failover })).toMatchObject({ ok: true, config: { failover } });
  });

  // One row per refusal: the input, the path of the error and a part of its message.
  test.each([
    ['failover.enabled', { failover: { enabled: true, roles: { author: [{ provider: 'codex' }] } } }, 'failover', used],
    ['failover.default', { failover: { default: ['codex'] } }, 'failover', used],
    ['a step given as a string', roles(['codex']), 'failover.roles.author.0', 'a failover step is { "provider"'],
    ['a step with an empty provider', roles([{ provider: '' }]), 'failover.roles.author.0.provider', ''],
    ['a step with an empty model', roles([{ provider: 'codex', model: '' }]), 'failover.roles.author.0.model', ''],
    ['a step repeated in its list', roles([{ provider: 'codex' }, { provider: 'claude', model: 'x' }, { provider: 'claude', model: 'x' }]), 'failover.roles.author.2', 'repeats another step'],
    ['a step equal to the role\'s own provider and model', roles([{ provider: 'codex' }, { provider: 'claude', model: 'm' }]), 'failover.roles.author.1', "the role's own provider and model"],
    ['a provider that is not declared', roles([{ provider: 'codex' }, { provider: 'ghost' }]), 'failover.roles.author.1.provider', '"ghost" is not declared in providers'],
    ['a provider named like an Object property', roles([{ provider: 'constructor' }]), 'failover.roles.author.0.provider', '"constructor" is not declared in providers'],
    ['an unknown field', { failover: { retries: 2 } }, 'failover', ''],
  ])('%s is refused naming its place', (_, user, path, message) => {
    const errors = errorsOf(user);
    expect(errors.map((e) => e.path)).toEqual([path]);
    expect(errors[0]!.message).toContain(message);
  });

  test('the same provider on another model is a step of its own, and so is the role\'s provider on another model', () => {
    expect(load(roles([{ provider: 'codex', model: 'a' }, { provider: 'codex', model: 'b' }, { provider: 'claude', model: 'other' }])).ok).toBe(true);
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

describe('effort', () => {
  const withEffort = (effort: unknown) => ({ agents: { ...valid.agents, author: { ...valid.agents.author, effort } } });
  const inRepo = (effort: unknown) => ({ repos: [{ name: 'AshuLab/carrier', agents: { reviewer: { effort } } }] });

  test('a role takes one of the five levels or none, globally and in a repo', () => {
    for (const effort of ['low', 'medium', 'high', 'xhigh', 'max']) {
      expect(load(withEffort(effort))).toMatchObject({ ok: true, config: { agents: { author: { effort } } } });
      expect(load(inRepo(effort))).toMatchObject({ ok: true });
    }
    expect(load({})).toMatchObject({ ok: true });
  });

  test('anything else is refused naming the key', () => {
    for (const effort of ['Max', '', 'ultra', 3]) {
      expect(errorsOf(withEffort(effort)).map((e) => e.path)).toEqual(['agents.author.effort']);
      expect(errorsOf(inRepo(effort)).map((e) => e.path)).toEqual(['repos.0.agents.reviewer.effort']);
    }
  });
});

describe('chat', () => {
  test('a `chat` section is refused as an unknown key; the chat has its own chat.json', () => {
    const errors = errorsOf({ chat: { agents: {} } });
    expect(errors).toEqual([{ path: '(root)', message: 'Unrecognized key: "chat"' }]);
    expect(load({})).toMatchObject({ ok: true });
  });
});
