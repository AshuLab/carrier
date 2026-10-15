import { describe, expect, test } from 'vitest';
import { defaults, loadConfig } from './load.ts';
import { resolveRepoConfig } from './resolve.ts';

const base = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: {}, b: {}, c: {} },
  orchestratorProfile: 'a',
  agents: {
    author: { profile: 'a', provider: 'claude', model: 'm1' },
    reviewer: { profile: 'b', provider: 'codex', model: 'm2' },
  },
};

const load = (user: object) => loadConfig(defaults, { ...base, ...user });
const errorsOf = (user: object) => {
  const result = load(user);
  if (result.ok) throw new Error('expected invalid config');
  return result.errors;
};
const resolveFirst = (user: object) => {
  const result = load(user);
  if (!result.ok) throw new Error(JSON.stringify(result.errors));
  return resolveRepoConfig(result.config, result.config.repos[0]!);
};

describe('resolveRepoConfig', () => {
  test('a repo without overrides gets the global values', () => {
    expect(resolveFirst({}).agents).toEqual(base.agents);
  });

  test('a model-only override keeps the global profile and provider', () => {
    const { agents } = resolveFirst({ repos: [{ name: 'x/y', agents: { reviewer: { model: 'other' } } }] });
    expect(agents.reviewer).toEqual({ profile: 'b', provider: 'codex', model: 'other' });
    expect(agents.author).toEqual(base.agents.author);
  });

  test('overrides replace every field they set', () => {
    const { agents } = resolveFirst({
      repos: [{ name: 'x/y', agents: { author: { profile: 'c', provider: 'codex', model: 'z' } } }],
    });
    expect(agents.author).toEqual({ profile: 'c', provider: 'codex', model: 'z' });
  });

  test('effective config round-trips through JSON and carries no extra data', () => {
    const effective = resolveFirst({
      profiles: { ...base.profiles, a: { token: 'secret' } },
      repos: [{ name: 'x/y', agents: { reviewer: { model: 'other' } } }],
    });
    expect(JSON.parse(JSON.stringify(effective))).toEqual(effective);
    expect(JSON.stringify(effective)).not.toContain('secret');
    expect(Object.keys(effective)).toEqual(['name', 'agents']);
  });
});

describe('profile separation', () => {
  test('same profile after a repo override names the repo and fields', () => {
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { reviewer: { profile: 'a' } } }] })).toEqual([
      { path: 'repos.0.agents', message: expect.stringMatching(/repo "x\/y".*agents\.author\.profile.*agents\.reviewer\.profile/) },
    ]);
  });

  test('an override can break the tie only if the global ones already differ', () => {
    const same = { ...base.agents, reviewer: { ...base.agents.reviewer, profile: 'a' } };
    expect(errorsOf({ agents: same })).toEqual([
      { path: 'agents', message: expect.stringMatching(/agents\.author\.profile.*agents\.reviewer\.profile/) },
    ]);
    expect(errorsOf({ agents: same, repos: [{ name: 'x/y', agents: { reviewer: { profile: 'b' } } }] })).toHaveLength(1);
  });
});

describe('override validation', () => {
  test('undeclared profile reports the field path', () => {
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { author: { profile: 'ghost' } } }] })).toEqual([
      { path: 'repos.0.agents.author.profile', message: expect.stringContaining('ghost') },
    ]);
  });

  test('unknown override fields and bad providers are rejected', () => {
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { author: { provider: 'gpt' } } }] }).map((e) => e.path)).toEqual([
      'repos.0.agents.author.provider',
    ]);
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { judge: {} } }] })).toHaveLength(1);
  });
});
