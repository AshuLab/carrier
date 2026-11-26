import { expect, test } from 'vitest';
import type { Agent, EffectiveRepoConfig } from '../config/resolve.ts';
import { agentOfSlot, failoverStepsOfSlot, isExtraSlot, roundSlots, withAgentOfSlot } from './slots.ts';

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
    extraReviewers: [
      { ...ollama, key: 'usabilidad', name: 'Usabilidad', type: 'ux', skills, sharedIdentity: true as const },
      { ...ollama, key: 'seguridad-api', name: 'Seguridad API', type: 'security', skills, failover, sharedIdentity: true as const },
    ],
  },
} as unknown as EffectiveRepoConfig;

test('the lead moved to an option that leaves fields unset does not keep the old option\'s runtime fields, but keeps what it has besides an agent', () => {
  const moved = agentOfSlot(withAgentOfSlot(config, 'lead', claude), 'lead') as Record<string, unknown>;
  expect(moved).toEqual({ ...claude, sharedIdentity: true });
  for (const field of ['provider', 'configDir', 'effort', 'command']) expect(moved).not.toHaveProperty(field);
});

test('an extra reviewer moved the same way keeps its key, name, type, skills, failover steps and shared identity, and nothing of the old agent', () => {
  const moved = agentOfSlot(withAgentOfSlot(config, 'seguridad-api', claude), 'seguridad-api') as Record<string, unknown>;
  expect(moved).toEqual({ ...claude, key: 'seguridad-api', name: 'Seguridad API', type: 'security', skills, failover, sharedIdentity: true });
  for (const field of ['provider', 'configDir', 'effort', 'command']) expect(moved).not.toHaveProperty(field);
});

test('an extra reviewer is found by its key, and moving one leaves the other as it was', () => {
  const moved = withAgentOfSlot(config, 'seguridad-api', claude);
  expect(agentOfSlot(moved, 'usabilidad')).toBe(config.agents.extraReviewers![0]);
  expect(agentOfSlot(config, 'reviewer-2')).toBeUndefined(); // the old names are not read
  expect(moved.agents.extraReviewers!.map((extra) => extra.key)).toEqual(['usabilidad', 'seguridad-api']);
});

test('the failover steps of an extra reviewer are its own by its key, and the reviewer\'s when it declares none', () => {
  const reviewerSteps = [{ provider: 'r' }] as never;
  const withSteps = { ...config, failover: { roles: { reviewer: reviewerSteps } } } as unknown as EffectiveRepoConfig;
  expect(failoverStepsOfSlot(withSteps, 'seguridad-api')).toBe(failover);
  expect(failoverStepsOfSlot(withSteps, 'usabilidad')).toBe(reviewerSteps);
});

test('the round runs the mandatory reviewer and then the extra ones in the order of the saved configuration, whatever their keys sort to', () => {
  expect(roundSlots(config)).toEqual(['reviewer', 'usabilidad', 'seguridad-api']);
  expect(roundSlots(null)).toEqual(['reviewer']);
});

test('an extra reviewer saved with no key is no slot, and only an extra reviewer\'s key is an extra slot', () => {
  const keyless = { agents: { extraReviewers: [{ ...claude }, { ...claude, key: 'usabilidad' }] } } as unknown as EffectiveRepoConfig;
  expect(roundSlots(keyless)).toEqual(['reviewer', 'usabilidad']);
  expect(['reviewer', 'lead', null, 'usabilidad'].map(isExtraSlot)).toEqual([false, false, false, true]);
});

test('the author and the mandatory reviewer are replaced whole, and the other roles are left as they were', () => {
  const moved = withAgentOfSlot(config, 'reviewer', ollama);
  expect(agentOfSlot(moved, 'reviewer')).toEqual(ollama);
  expect(agentOfSlot(moved, 'lead')).toBe(agentOfSlot(config, 'lead'));
  expect(agentOfSlot(withAgentOfSlot(config, null, ollama), null)).toEqual(ollama);
});
