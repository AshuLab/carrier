import { expect, test } from 'vitest';
import { buildConfig, parseHarnessModel, parseIdentity } from './build-config.ts';

test('buildConfig names a forge profile after its agent and the login "gh"', () => {
  const config = buildConfig({
    repos: ['A/b'],
    author: { identity: parseIdentity('gh'), ...parseHarnessModel('claude:sonnet') },
    reviewer: { identity: parseIdentity('forge:bot'), ...parseHarnessModel('codex:x:y') },
  });
  expect(config.profiles).toEqual({ gh: { kind: 'gh' }, bot: { kind: 'forge', agent: 'bot' } });
  expect(config.agents.reviewer).toEqual({ profile: 'bot', harness: 'codex', model: 'x:y' });
  expect(() => parseIdentity('forge')).toThrow('invalid identity');
  expect(() => parseHarnessModel('gpt:4')).toThrow('invalid agent');
});

test('buildConfig writes identities only when shared, with one profile for both roles', () => {
  const answers = { repos: ['A/b'], author: { identity: parseIdentity('gh'), ...parseHarnessModel('claude:sonnet') }, reviewer: { identity: parseIdentity('gh'), ...parseHarnessModel('codex:x') } };
  expect(buildConfig({ ...answers, identities: 'separate' })).not.toHaveProperty('identities');
  const shared = buildConfig({ ...answers, identities: 'shared' });
  expect(shared).toMatchObject({ identities: 'shared', profiles: { gh: { kind: 'gh' } }, orchestratorProfile: 'gh' });
  expect(shared.agents.author.profile).toBe(shared.agents.reviewer.profile);
});
