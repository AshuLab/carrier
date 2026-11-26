import { expect, test } from 'vitest';
import { priorFrom } from './prior.ts';

const accounts = { providers: { claude: { harness: 'claude' }, codex: { harness: 'codex' } } };
const file = (extraReviewers?: unknown) => ({
  repos: [{ name: 'X/y' }],
  profiles: { a: { kind: 'gh' }, b: { kind: 'forge', agent: 'bot' } },
  agents: {
    author: { profile: 'a', provider: 'claude', model: 'm' },
    reviewer: { profile: 'a', provider: 'codex', model: 'm' },
    ...(extraReviewers !== undefined && { extraReviewers }),
  },
});

test('the extra reviewers of a map are read in its order, each with its key, name, type, role and failover', () => {
  const prior = priorFrom(
    file({
      'seguridad-api': { type: 'security', name: 'Seguridad API', profile: 'b', provider: 'codex', model: 'gpt', effort: 'low', failover: [{ provider: 'claude' }] },
      usabilidad: { type: 'ux', name: 'Usabilidad', profile: 'a', provider: 'claude', model: 'opus' },
    }),
    accounts,
  );
  if ('error' in prior) throw new Error(prior.error);
  expect(prior.extraReviewers).toEqual([
    { key: 'seguridad-api', name: 'Seguridad API', type: 'security', role: { identity: { kind: 'forge', agent: 'bot' }, provider: 'codex', model: 'gpt', effort: 'low' }, failover: [{ provider: 'claude' }] },
    { key: 'usabilidad', name: 'Usabilidad', type: 'ux', role: { identity: { kind: 'gh' }, provider: 'claude', model: 'opus' } },
  ]);
});

test('a list is an error that names the map the file needs', () => {
  const prior = priorFrom(file([{ profile: 'a', provider: 'claude', model: 'm' }]), accounts);
  expect(prior).toMatchObject({ error: expect.stringMatching(/^agents\.extraReviewers: must be a map from a key to a reviewer, not a list/) });
});

test('a file with no extra reviewers has none', () => {
  expect(priorFrom(file(), accounts)).not.toHaveProperty('extraReviewers');
});
