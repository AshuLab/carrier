import { homedir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, test } from 'vitest';
import { defaults, loadConfig } from './load.ts';

const valid = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { 'author-bot': {}, 'reviewer-bot': {} },
  orchestratorProfile: 'author-bot',
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
