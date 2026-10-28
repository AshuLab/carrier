import { describe, expect, test } from 'vitest';
import { defaults, loadConfig } from './load.ts';
import { resolveRepoConfig } from './resolve.ts';

const base = {
  repos: [{ name: 'AshuLab/carrier' }],
  profiles: { a: { kind: 'gh' }, b: { kind: 'gh' }, c: { kind: 'gh' } },
  orchestratorProfile: 'a',
  agentOptions: { claude: { harness: 'claude', model: 'm1' }, codex: { harness: 'codex', model: 'm2' }, local: { harness: 'codex', model: 'm3', provider: 'ollama', configDir: '/srv/codex' } },
  agents: {
    author: { profile: 'a', option: 'claude' },
    reviewer: { profile: 'b', option: 'codex' },
  },
};
const resolvedAuthor = { profile: 'a', option: 'claude', harness: 'claude', model: 'm1' };
const resolvedReviewer = { profile: 'b', option: 'codex', harness: 'codex', model: 'm2' };

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
  test('a repo without overrides gets the option each role points at, with its name', () => {
    expect(resolveFirst({}).agents).toEqual({ author: resolvedAuthor, reviewer: resolvedReviewer });
  });

  test('an option override is the one used for that repo, with its provider and configDir', () => {
    const { agents } = resolveFirst({ repos: [{ name: 'x/y', agents: { reviewer: { option: 'local' } } }] });
    expect(agents.reviewer).toEqual({ profile: 'b', option: 'local', harness: 'codex', model: 'm3', provider: 'ollama', configDir: '/srv/codex' });
    expect(agents.author).toEqual(resolvedAuthor);
  });

  test('overrides replace every field they set', () => {
    const { agents } = resolveFirst({ repos: [{ name: 'x/y', agents: { author: { profile: 'c', option: 'codex' } } }] });
    expect(agents.author).toEqual({ profile: 'c', option: 'codex', harness: 'codex', model: 'm2' });
  });

  test('effective config round-trips through JSON and carries no extra data', () => {
    const effective = resolveFirst({
      profiles: { ...base.profiles, a: { kind: 'forge', agent: 'secret' } },
      repos: [{ name: 'x/y', agents: { reviewer: { option: 'local' } } }],
    });
    expect(JSON.parse(JSON.stringify(effective))).toEqual(effective);
    expect(JSON.stringify(effective)).not.toContain('secret');
    expect(Object.keys(effective)).toEqual(['name', 'sharedIdentity', 'options', 'agents']);
  });
});

describe('sharedIdentity', () => {
  const shared = (user: object) => resolveFirst({ identities: 'shared', ...user }).sharedIdentity;
  const same = { ...base.agents, reviewer: { ...base.agents.reviewer, profile: 'a' } };

  test('the same profile, or two names for the same gh login or the same bot, is shared', () => {
    expect(shared({ agents: same })).toBe(true);
    expect(shared({})).toBe(true); // a and b are both gh
    expect(shared({ profiles: { a: { kind: 'forge', agent: 'x' }, b: { kind: 'forge', agent: 'x' } } })).toBe(true);
  });

  test('a bot against a login, or two bots, is not', () => {
    expect(shared({ profiles: { a: { kind: 'forge', agent: 'x' }, b: { kind: 'gh' } } })).toBe(false);
    expect(shared({ profiles: { a: { kind: 'forge', agent: 'x' }, b: { kind: 'forge', agent: 'y' } } })).toBe(false);
  });

  test('a repo override that brings in a bot is not', () => {
    expect(shared({ agents: same, profiles: { ...base.profiles, c: { kind: 'forge', agent: 'x' } }, repos: [{ name: 'x/y', agents: { reviewer: { profile: 'c' } } }] })).toBe(false);
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

  test('unknown override fields are rejected', () => {
    expect(errorsOf({ repos: [{ name: 'x/y', agents: { judge: {} } }] })).toHaveLength(1);
  });
});

test('a repo persona replaces the global one of that role whole', () => {
  const global = { author: { ...base.agents.author, persona: { name: 'Ada', prompt: 'Be terse.' } }, reviewer: { ...base.agents.reviewer, persona: { name: 'Rex' } } };
  const { agents } = resolveFirst({ agents: global, repos: [{ name: 'x/y', agents: { author: { persona: { prompt: 'Be verbose.' } } } }] });
  expect(agents.author.persona).toEqual({ prompt: 'Be verbose.' });
  expect(agents.reviewer.persona).toEqual({ name: 'Rex' });
  expect(resolveFirst({ agents: global }).agents.author.persona).toEqual({ name: 'Ada', prompt: 'Be terse.' });
});
