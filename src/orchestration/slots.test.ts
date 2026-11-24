import { expect, test } from 'vitest';
import type { Agent, EffectiveRepoConfig } from '../config/resolve.ts';
import { agentOfSlot, withAgentOfSlot } from './slots.ts';

const ollama: Agent = { profile: 'p', harness: 'claude', model: 'qwen', provider: 'ollama', configDir: '/old', effort: 'high', command: 'old-cmd' } as Agent;
const claude: Agent = { profile: 'p', harness: 'claude', model: 'opus' };
const skills = { review: 'code-review', publish: 'code-post' } as never;
const failover = [{ provider: 'b', model: 'm' }] as never;

const config = {
  name: 'r',
  agents: {
    author: claude,
    reviewer: claude,
    leadReviewer: { ...ollama, sharedIdentity: true as const },
    extraReviewers: [{ ...ollama, skills, failover, sharedIdentity: true as const }],
  },
} as unknown as EffectiveRepoConfig;

test('the lead moved to an option that leaves fields unset does not keep the old option\'s runtime fields, but keeps what it has besides an agent', () => {
  const moved = agentOfSlot(withAgentOfSlot(config, 'lead', claude), 'lead') as Record<string, unknown>;
  expect(moved).toEqual({ ...claude, sharedIdentity: true });
  for (const field of ['provider', 'configDir', 'effort', 'command']) expect(moved).not.toHaveProperty(field);
});

test('an extra reviewer moved the same way keeps its skills, failover steps and shared identity, and nothing of the old agent', () => {
  const moved = agentOfSlot(withAgentOfSlot(config, 'reviewer-2', claude), 'reviewer-2') as Record<string, unknown>;
  expect(moved).toEqual({ ...claude, skills, failover, sharedIdentity: true });
  for (const field of ['provider', 'configDir', 'effort', 'command']) expect(moved).not.toHaveProperty(field);
});

test('the author and the mandatory reviewer are replaced whole, and the other roles are left as they were', () => {
  const moved = withAgentOfSlot(config, 'reviewer', ollama);
  expect(agentOfSlot(moved, 'reviewer')).toEqual(ollama);
  expect(agentOfSlot(moved, 'lead')).toBe(agentOfSlot(config, 'lead'));
  expect(agentOfSlot(withAgentOfSlot(config, null, ollama), null)).toEqual(ollama);
});
