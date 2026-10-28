import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { buildConfig, parseHarnessModel, parseIdentity } from './build-config.ts';

test('buildConfig names a forge profile after its agent and the login "gh"', () => {
  const config = buildConfig({
    repos: ['A/b'],
    author: { identity: parseIdentity('gh'), ...parseHarnessModel('claude:sonnet') },
    reviewer: { identity: parseIdentity('forge:bot'), ...parseHarnessModel('codex:x:y') },
  });
  expect(config.profiles).toEqual({ gh: { kind: 'gh' }, bot: { kind: 'forge', agent: 'bot' } });
  expect(config.agents.reviewer).toEqual({ profile: 'bot', option: 'codex' });
  expect(config.agentOptions.codex).toEqual({ harness: 'codex', model: 'x:y' });
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

test('buildConfig writes a persona only when given, and the config loads', () => {
  const author = { identity: parseIdentity('gh'), ...parseHarnessModel('claude:sonnet') };
  const reviewer = { identity: parseIdentity('forge:bot'), ...parseHarnessModel('codex:x'), persona: { name: 'Rex', prompt: 'Strict.' } };
  const config = buildConfig({ repos: ['A/b'], author, reviewer });
  expect(config.agents.author).not.toHaveProperty('persona');
  expect(config.agents.reviewer).toMatchObject({ persona: { name: 'Rex', prompt: 'Strict.' } });
  const loaded = loadConfig(defaults, config);
  expect(loaded.ok && loaded.config.agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Strict.' });
});

test('buildConfig names one option per role after its harness, shares it when harness, model and provider match, and calls the reviewer\'s <harness>-reviewer when only the model differs', () => {
  const role = (agent: string, provider?: 'ollama') => ({ identity: parseIdentity('gh'), ...parseHarnessModel(agent), ...(provider && { provider }) });
  const optionsOf = (author: ReturnType<typeof role>, reviewer: ReturnType<typeof role>) => {
    const config = buildConfig({ repos: ['A/b'], author, reviewer, identities: 'shared' });
    expect(loadConfig(defaults, config).ok).toBe(true);
    return { options: config.agentOptions, roles: [config.agents.author.option, config.agents.reviewer.option] };
  };
  expect(optionsOf(role('claude:m'), role('codex:m'))).toEqual({ options: { claude: { harness: 'claude', model: 'm' }, codex: { harness: 'codex', model: 'm' } }, roles: ['claude', 'codex'] });
  expect(optionsOf(role('claude:m'), role('claude:m'))).toEqual({ options: { claude: { harness: 'claude', model: 'm' } }, roles: ['claude', 'claude'] });
  expect(optionsOf(role('claude:m'), role('claude:other'))).toEqual({ options: { claude: { harness: 'claude', model: 'm' }, 'claude-reviewer': { harness: 'claude', model: 'other' } }, roles: ['claude', 'claude-reviewer'] });
  expect(optionsOf(role('codex:m'), role('codex:m', 'ollama')).roles).toEqual(['codex', 'codex-reviewer']);
});
