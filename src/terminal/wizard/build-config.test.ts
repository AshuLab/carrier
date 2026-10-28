import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../config/load.ts';
import { buildConfig, parseHarnessModel, parseIdentity, type AgentOption } from './build-config.ts';

const options: Record<string, AgentOption> = { claude: { harness: 'claude', model: 'sonnet' }, codex: { harness: 'codex', model: 'x:y' } };
const answers = { repos: ['A/b'], author: { identity: parseIdentity('gh'), option: 'claude' }, reviewer: { identity: parseIdentity('forge:bot'), option: 'codex' }, options };

test('buildConfig names a forge profile after its agent and the login "gh", and points each role at its option', () => {
  const config = buildConfig(answers);
  expect(config.profiles).toEqual({ gh: { kind: 'gh' }, bot: { kind: 'forge', agent: 'bot' } });
  expect(config.agents.reviewer).toEqual({ profile: 'bot', option: 'codex' });
  expect(config.agentOptions).toEqual(options);
  expect(loadConfig(defaults, config).ok).toBe(true);
  expect(() => parseIdentity('forge')).toThrow('invalid identity');
  expect(parseHarnessModel('codex:x:y')).toEqual({ harness: 'codex', model: 'x:y' });
  expect(() => parseHarnessModel('gpt:4')).toThrow('invalid agent');
});

test('buildConfig writes identities only when shared, with one profile for both roles', () => {
  const same = { ...answers, reviewer: { identity: parseIdentity('gh'), option: 'codex' } };
  expect(buildConfig({ ...same, identities: 'separate' })).not.toHaveProperty('identities');
  const shared = buildConfig({ ...same, identities: 'shared' });
  expect(shared).toMatchObject({ identities: 'shared', profiles: { gh: { kind: 'gh' } }, orchestratorProfile: 'gh' });
  expect(shared.agents.author.profile).toBe(shared.agents.reviewer.profile);
});

test('buildConfig writes a persona only when given, and the config loads', () => {
  const config = buildConfig({ ...answers, reviewer: { ...answers.reviewer, persona: { name: 'Rex', prompt: 'Strict.' } } });
  expect(config.agents.author).not.toHaveProperty('persona');
  expect(config.agents.reviewer).toMatchObject({ persona: { name: 'Rex', prompt: 'Strict.' } });
  const loaded = loadConfig(defaults, config);
  expect(loaded.ok && loaded.config.agents.reviewer.persona).toEqual({ name: 'Rex', prompt: 'Strict.' });
});

test('buildConfig writes the failover block only when given, and a config with folders and a block loads', () => {
  expect(buildConfig(answers)).not.toHaveProperty('failover');
  const config = buildConfig({ ...answers, options: { ...options, personal: { harness: 'claude', model: 'opus', configDir: '~/.claude-personal' } }, failover: { enabled: true, order: ['personal', 'codex'] } });
  expect(config.failover).toEqual({ enabled: true, order: ['personal', 'codex'] });
  expect(loadConfig(defaults, config).ok).toBe(true);
});
