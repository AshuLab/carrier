import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { defaultConfigPath } from './default-path.ts';
import { defaults, loadConfig } from './load.ts';

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
    expect(paths.errors.map((e) => e.path).sort()).toEqual(['agents', 'orchestratorProfile', 'profiles', 'providers', 'repos']);
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
  const same = { profiles: { me: { kind: 'gh' }, bot: { kind: 'gh' } }, orchestratorProfile: 'me', providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } }, agents: { author: { profile: 'me', provider: 'claude', model: 'm' }, reviewer: { profile: 'me', provider: 'codex', model: 'm' } } };
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

  test('lead reviewer profile and provider validation', () => {
    expect(load({ agents: { ...valid.agents, leadReviewer: { profile: 'reviewer-bot', provider: 'claude', model: 'm' } } })).toMatchObject({
      ok: true,
      config: { agents: { leadReviewer: { profile: 'reviewer-bot', provider: 'claude', model: 'm' } } },
    });
    // Under separate identities, lead reviewer cannot share profile with author
    expect(errorsOf({ agents: { ...valid.agents, leadReviewer: { profile: 'author-bot', provider: 'claude', model: 'm' } } })).toEqual([
      { path: 'agents', message: expect.stringContaining('agents.author.profile and agents.leadReviewer.profile must differ') },
    ]);
    // Unknown profile or provider
    expect(errorsOf({ agents: { ...valid.agents, leadReviewer: { profile: 'phantom', provider: 'claude', model: 'm' } } })).toEqual([
      { path: 'agents.leadReviewer.profile', message: expect.stringContaining('phantom') },
    ]);
    expect(errorsOf({ agents: { ...valid.agents, leadReviewer: { profile: 'reviewer-bot', provider: 'phantom', model: 'm' } } })).toEqual([
      { path: 'agents.leadReviewer.provider', message: expect.stringContaining('phantom') },
    ]);
  });

  test.each(['both', 'Shared', '', true])('rejects %j', (identities) => {
    expect(errorsOf({ identities }).map((e) => e.path)).toEqual(['identities']);
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

  test('`provider` is optional and only lmstudio or ollama', () => {
    expect(load(withProviders({ ...valid.providers, codex: { harness: 'codex', provider: 'lmstudio' } }))).toMatchObject({ ok: true, config: { providers: { codex: { provider: 'lmstudio' } } } });
    expect(providerPaths({ ...valid.providers, codex: { harness: 'codex', provider: 'vllm' } })).toEqual(['providers.codex.provider']);
  });

  test('agy is a harness, but it cannot use a provider', () => {
    expect(load(withProviders({ ...valid.providers, agy: { harness: 'agy' } }, { ...valid.agents, author: { profile: 'author-bot', provider: 'agy', model: 'gemini-3.8-flash-low' } }))).toMatchObject({ ok: true });
    expect(errorsOf(withProviders({ ...valid.providers, claude: { harness: 'agy', provider: 'ollama' } }))).toEqual([{ path: 'providers.claude.provider', message: 'providers.claude: agy cannot use the provider "ollama"' }]);
  });

  test('a provider name is a lowercase word of up to 40 characters', () => {
    const provider = { harness: 'codex' };
    for (const name of ['a', 'claude-ashu', 'x1-2', 'a'.repeat(40)]) expect(load(withProviders({ ...valid.providers, [name]: provider })).ok).toBe(true);
    for (const name of ['Claude', '1claude', '-claude', 'claude_work', 'claude work', '', 'a'.repeat(41)]) {
      const errors = errorsOf(withProviders({ ...valid.providers, [name]: provider }));
      expect(errors.map((e) => e.path)).toEqual([`providers.${name}`]);
      expect(errors[0]!.message).toContain('lowercase word');
    }
  });

  test('a role or a repo override pointing at a provider that is not declared names the field', () => {
    expect(errorsOf({ agents: { ...valid.agents, reviewer: { ...valid.agents.reviewer, provider: 'ghost' } } })).toEqual([{ path: 'agents.reviewer.provider', message: expect.stringContaining('ghost') }]);
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { author: { provider: 'phantom' } } }] })).toEqual([{ path: 'repos.0.agents.author.provider', message: expect.stringContaining('phantom') }]);
  });

  test('`configDir` is expanded from ~ and must then be absolute; an empty one is refused', () => {
    expect(load(withProviders({ ...valid.providers, claude: { harness: 'claude', configDir: '~/.claude-ashu' } }))).toMatchObject({ ok: true, config: { providers: { claude: { configDir: join(homedir(), '.claude-ashu') } } } });
    expect(load(withProviders({ ...valid.providers, codex: { harness: 'codex', configDir: '/srv/codex' } }))).toMatchObject({ ok: true, config: { providers: { codex: { configDir: '/srv/codex' } } } });
    for (const configDir of ['', 'relative/dir', '.claude', '~other/dir']) expect(providerPaths({ ...valid.providers, claude: { harness: 'claude', configDir } })).toEqual(['providers.claude.configDir']);
  });

  test('an agy provider cannot have a `configDir`', () => {
    const errors = errorsOf(withProviders({ ...valid.providers, claude: { harness: 'agy', configDir: '/srv/agy' } }));
    expect(errors).toEqual([{ path: 'providers.claude.configDir', message: expect.stringContaining('agy') }]);
  });

  test('an unknown field inside a provider is refused', () => {
    const errors = errorsOf(withProviders({ ...valid.providers, claude: { harness: 'claude', token: 'x' } }));
    expect(errors).toEqual([{ path: 'providers.claude', message: expect.stringContaining('token') }]);
  });

  test('`option` inside agents.<role> or a repo override is refused with where it went', () => {
    const errors = errorsOf({ agents: { ...valid.agents, author: { ...valid.agents.author, option: 'legacy' } } });
    expect(errors).toEqual([{ path: 'agents.author.option', message: expect.stringMatching(/was replaced by "provider" and "model"/) }]);
  });
});

describe('failover', () => {
  const failover = (defaultOrder: string[], enabled = true) => ({ failover: { enabled, default: defaultOrder } });

  test('absent means off, and a declared default loads as written', () => {
    const absent = load({});
    expect(absent.ok && absent.config.failover).toBeUndefined();
    expect(load(failover(['codex', 'claude']))).toMatchObject({ ok: true, config: { failover: { enabled: true, default: ['codex', 'claude'] } } });
    expect(load(failover([], false)).ok).toBe(true);
  });

  test('a name that is not declared in providers is refused, naming the field', () => {
    expect(errorsOf(failover(['codex', 'ghost']))).toEqual([{ path: 'failover.default.1', message: 'failover.default: provider "ghost" is not declared in providers' }]);
    expect(errorsOf(failover(['codex', 'constructor']))).toEqual([{ path: 'failover.default.1', message: 'failover.default: provider "constructor" is not declared in providers' }]);
  });

  test('a duplicate name is refused, naming the field', () => {
    expect(errorsOf(failover(['codex', 'claude', 'codex']))).toEqual([{ path: 'failover.default.2', message: 'failover.default: provider "codex" appears twice' }]);
  });

  test('default and role-specific failover chains with triggers load as written', () => {
    const custom = {
      failover: {
        enabled: true,
        triggers: ['usage_limit', 'service_down'] as const,
        default: ['codex', 'claude'],
        roles: {
          leadReviewer: ['claude'],
        },
      },
    };
    expect(load(custom)).toMatchObject({
      ok: true,
      config: {
        failover: {
          enabled: true,
          triggers: ['usage_limit', 'service_down'],
          default: ['codex', 'claude'],
          roles: { leadReviewer: ['claude'] },
        },
      },
    });
  });

  test('a name in default or roles not declared in providers is refused', () => {
    expect(errorsOf({ failover: { enabled: true, default: ['codex', 'ghost'] } })).toEqual([
      { path: 'failover.default.1', message: 'failover.default: provider "ghost" is not declared in providers' },
    ]);
    expect(errorsOf({ failover: { enabled: true, roles: { author: ['ghost'] } } })).toEqual([
      { path: 'failover.roles.author.0', message: 'failover.roles.author: provider "ghost" is not declared in providers' },
    ]);
  });

  test('enabled failover with neither default nor roles is refused', () => {
    expect(errorsOf({ failover: { enabled: true } })).toEqual([
      { path: 'failover', message: expect.stringContaining('neither a default nor role-specific fallback order') },
    ]);
  });

  test('`enabled` is required, and an unknown field is refused', () => {
    expect(errorsOf({ failover: { default: ['codex'] } }).map((e) => e.path)).toEqual(['failover.enabled']);
    expect(errorsOf({ failover: { enabled: true, default: ['codex'], retries: 2 } }).map((e) => e.path)).toEqual(['failover']);
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

describe('chat', () => {
  test('a `chat` section is refused as an unknown key; the chat has its own chat.json', () => {
    const errors = errorsOf({ chat: { agents: {} } });
    expect(errors).toEqual([{ path: '(root)', message: 'Unrecognized key: "chat"' }]);
    expect(load({})).toMatchObject({ ok: true });
  });
});
