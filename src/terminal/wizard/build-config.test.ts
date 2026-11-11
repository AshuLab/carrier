import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { buildConfig, parseHarnessModel, parseIdentity, type AIProvider } from './build-config.ts';

const providers: Record<string, AIProvider> = { claude: { harness: 'claude' }, codex: { harness: 'codex' } };
const answers = {
  repos: ['A/b'],
  author: { identity: parseIdentity('gh'), provider: 'claude', model: 'sonnet' },
  reviewer: { identity: parseIdentity('forge:bot'), provider: 'codex', model: 'x:y' },
};

test('buildConfig names a forge profile after its agent and the login "gh", and points each role at its provider and model', () => {
  const config = buildConfig(answers);
  expect(config.profiles).toEqual({ gh: { kind: 'gh' }, bot: { kind: 'forge', agent: 'bot' } });
  expect(config.agents.reviewer).toEqual({ profile: 'bot', provider: 'codex', model: 'x:y' });
  expect(config).not.toHaveProperty('providers'); // the accounts go in providers.json
  expect(loadConfig(defaults, config, providers).ok).toBe(true);
  expect(() => parseIdentity('forge')).toThrow('invalid identity');
  expect(parseHarnessModel('codex:x:y')).toEqual({ harness: 'codex', model: 'x:y' });
  expect(() => parseHarnessModel('gpt:4')).toThrow('invalid agent');
});

test('buildConfig never writes identities, and a shared pair is one profile for both roles', () => {
  const shared = buildConfig({ ...answers, reviewer: { identity: parseIdentity('gh'), provider: 'codex', model: 'x:y' } });
  expect(shared).not.toHaveProperty('identities');
  expect(shared).toMatchObject({ profiles: { gh: { kind: 'gh' } }, orchestratorProfile: 'gh' });
  expect(shared.agents.author.profile).toBe(shared.agents.reviewer.profile);
});

test('buildConfig writes an effort only when given, and the config loads with it', () => {
  const config = buildConfig({ ...answers, reviewer: { ...answers.reviewer, effort: 'max' } });
  expect(config.agents.author).not.toHaveProperty('effort');
  expect(config.agents.reviewer).toMatchObject({ effort: 'max' });
  const loaded = loadConfig(defaults, config, providers);
  expect(loaded.ok && loaded.config.agents.reviewer.effort).toBe('max');
});

test('buildConfig writes a persona only when given, and the config loads', () => {
  const config = buildConfig({ ...answers, reviewer: { ...answers.reviewer, persona: { name: 'Rex', prompt: 'Strict.' } } });
  expect(config.agents.author).not.toHaveProperty('persona');
  expect(config.agents.reviewer).toMatchObject({ persona: { name: 'Rex', prompt: 'Strict.' } });
  const loaded = loadConfig(defaults, config, providers);
  expect(loaded.ok && loaded.config.agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Strict.' });
});

test('buildConfig writes the failover block only when given, and a config with folders and a block loads', () => {
  expect(buildConfig(answers)).not.toHaveProperty('failover');
  const config = buildConfig({ ...answers, failover: { roles: { author: [{ provider: 'personal' }, { provider: 'codex', model: 'gpt' }] } } });
  expect(config.failover).toEqual({ roles: { author: [{ provider: 'personal' }, { provider: 'codex', model: 'gpt' }] } });
  expect(loadConfig(defaults, config, { ...providers, personal: { harness: 'claude', configDir: '/home/me/.claude-personal' } }).ok).toBe(true);
});
