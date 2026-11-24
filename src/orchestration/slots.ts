import type { Agent, EffectiveRepoConfig } from '../config/resolve.ts';
import type { Slot } from '../storage/executions.ts';

// The extra reviewers live in the epic's saved configuration, which an epic saved before them lacks.
type SavedAgents = EffectiveRepoConfig['agents'] & { extraReviewers?: Agent[] };

// `reviewer-2` is the first of the extra ones.
const extraIndex = (slot: Slot) => Number(slot.slice(-1)) - 2;

/** The agent a slot runs with in the epic's saved configuration (null: the author); undefined when the epic saved none for it. */
export function agentOfSlot(config: EffectiveRepoConfig, slot: Slot | null): Agent | undefined {
  const agents: SavedAgents = config.agents;
  if (slot === null) return agents.author;
  if (slot === 'reviewer') return agents.reviewer;
  if (slot === 'lead') return agents.leadReviewer;
  return agents.extraReviewers?.[extraIndex(slot)];
}

/** The saved configuration with the slot's agent replaced: where a failover leaves the option the slot runs on. */
export function withAgentOfSlot(config: EffectiveRepoConfig, slot: Slot | null, agent: Agent): EffectiveRepoConfig {
  const agents: SavedAgents = config.agents;
  if (slot === null) return { ...config, agents: { ...agents, author: agent } };
  if (slot === 'reviewer') return { ...config, agents: { ...agents, reviewer: agent } };
  if (slot === 'lead') return { ...config, agents: { ...agents, leadReviewer: agent } };
  const extraReviewers = [...(agents.extraReviewers ?? [])];
  extraReviewers[extraIndex(slot)] = agent;
  const withExtras: SavedAgents = { ...agents, extraReviewers };
  return { ...config, agents: withExtras };
}

/** The role whose failover steps a slot takes: the extra reviewers take the reviewer's. */
export const failoverRoleOf = (slot: Slot | null): 'author' | 'reviewer' | 'leadReviewer' => (slot === null ? 'author' : slot === 'lead' ? 'leadReviewer' : 'reviewer');
