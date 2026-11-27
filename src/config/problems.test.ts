import { expect, test } from 'vitest';
import { configProblem } from './problems.ts';
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

/** The kinds `loadConfig` reports for a config that has one problem, read from the words the schema gives it. */
const problemsOf = (user: object) => {
  const result = loadWithProviders({ ...valid, ...user });
  if (result.ok) throw new Error('expected invalid config');
  return result.errors.map(configProblem);
};
const known = (path: string, problem: string) => ({ code: 'config.problem', params: { path, problem } });

test.each([
  ['a repo that is not owner/name', { repos: [{ name: 'AshuLab/carrier' }, { name: 'ok/one' }, { name: 'nope' }] }, known('repos[2]', 'notARepo')],
  ['a failover step that repeats another', { failover: { roles: { reviewer: [{ provider: 'claude', model: 'x' }, { provider: 'claude', model: 'x' }] } } }, known('failover.roles.reviewer.1', 'stepRepeated')],
  ["a failover step that is the role's own provider and model", { failover: { roles: { author: [{ provider: 'claude', model: 'm' }] } } }, known('failover.roles.author.0', 'stepOwnRole')],
  ['a failover step with a provider that is not declared', { failover: { roles: { leadReviewer: [{ provider: 'ghost' }] }, } }, known('failover.roles.leadReviewer.0', 'providerNotDeclared')],
])('%s is told by its key path and its kind', (_what, user, expected) => {
  expect(problemsOf(user)).toContainEqual(expected);
});

test.each([
  ['a profile that is not declared', { agents: { ...valid.agents, author: { ...valid.agents.author, profile: 'ghost' } } }],
  ['a field out of range', { limits: { maxReviews: 0 } }],
  ['a failover step of an extra reviewer', { agents: { ...valid.agents, extraReviewers: { sec: { type: 'security', name: 'Sec', profile: 'reviewer-bot', provider: 'codex', model: 'm', failover: [{ provider: 'ghost' }] } } } }],
])('%s is not a known kind', (_what, user) => {
  expect(problemsOf(user).every((problem) => problem === null)).toBe(true);
});
