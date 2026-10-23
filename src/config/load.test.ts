import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { defaults, loadConfig } from './load.ts';

const valid = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { 'author-bot': { kind: 'forge', agent: 'artanis-agent' }, 'reviewer-bot': { kind: 'gh' } },
  orchestratorProfile: 'author-bot',
  agents: {
    author: { profile: 'author-bot', harness: 'claude', model: 'm' },
    reviewer: { profile: 'reviewer-bot', harness: 'codex', model: 'm' },
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
    expect(paths.errors.map((e) => e.path).sort()).toEqual(['agents', 'orchestratorProfile', 'profiles', 'repos']);
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

describe('local models', () => {
  const reviewer = { profile: 'reviewer-bot', harness: 'codex', model: 'google/gemma-4-12b' };

  test('`provider` is optional, per role, and only lmstudio or ollama', () => {
    expect(load({ agents: { ...valid.agents, reviewer: { ...reviewer, provider: 'lmstudio' } } })).toMatchObject({ ok: true, config: { agents: { reviewer: { provider: 'lmstudio' } } } });
    expect(load({})).toMatchObject({ ok: true }); // no local anywhere
    expect(errorsOf({ agents: { ...valid.agents, reviewer: { ...reviewer, provider: 'vllm' } } }).map((e) => e.path)).toEqual(['agents.reviewer.provider']);
  });

  test('a repo can override it', () => {
    const result = load({ repos: [{ name: 'AshuLab/carrier', agents: { reviewer: { model: 'qwen3:8b', provider: 'ollama' } } }] });
    expect(result).toMatchObject({ ok: true, config: { repos: [{ agents: { reviewer: { provider: 'ollama' } } }] } });
  });
});

describe('harness and provider', () => {
  test('agy is a harness, but it cannot use a local provider (globally or through a repo override)', () => {
    expect(load({ agents: { ...valid.agents, author: { profile: 'author-bot', harness: 'agy', model: 'gemini-3.8-flash-low' } } })).toMatchObject({ ok: true });
    const agy = { profile: 'author-bot', harness: 'agy', model: 'm', provider: 'ollama' };
    expect(errorsOf({ agents: { ...valid.agents, author: agy } })).toEqual([{ path: 'agents.author.provider', message: 'agy cannot use the provider "ollama"' }]);
    const viaRepo = errorsOf({ agents: { ...valid.agents, author: { profile: 'author-bot', harness: 'codex', model: 'm', provider: 'ollama' } }, repos: [{ name: 'AshuLab/carrier', agents: { author: { harness: 'agy' } } }] });
    expect(viaRepo.map((e) => e.path)).toEqual(['repos.0.agents.author']);
  });
});
