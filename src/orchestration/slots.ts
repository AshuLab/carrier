import type { Agent, EffectiveRepoConfig } from '../config/resolve.ts';
import type { Slot } from '../storage/executions.ts';

// The extra reviewers live in the epic's saved configuration (`agents.extraReviewers`, as the config's schema names them), which an epic saved before them lacks.
// Read here as agents: what each also keeps (its review skills, its failover steps) is only carried along.
type SavedAgents = { author: Agent; reviewer: Agent; leadReviewer?: Agent; extraReviewers?: Agent[] };
const withAgents = (config: EffectiveRepoConfig, agents: SavedAgents): EffectiveRepoConfig => ({ ...config, agents: agents as EffectiveRepoConfig['agents'] });

// `reviewer-2` is the first of the extra ones.
const extraIndex = (slot: Slot) => Number(slot.slice(-1)) - 2;

/** The agent a slot runs with in the epic's saved configuration (null: the author); undefined when the epic saved none for it. */
export function agentOfSlot(config: EffectiveRepoConfig, slot: Slot | null): Agent | undefined {
  const agents = config.agents as SavedAgents;
  if (slot === null) return agents.author;
  if (slot === 'reviewer') return agents.reviewer;
  if (slot === 'lead') return agents.leadReviewer;
  return agents.extraReviewers?.[extraIndex(slot)];
}

/** The saved configuration with the slot's agent replaced: where a failover leaves the option the slot runs on. */
export function withAgentOfSlot(config: EffectiveRepoConfig, slot: Slot | null, agent: Agent): EffectiveRepoConfig {
  const agents = config.agents as SavedAgents;
  if (slot === null) return withAgents(config, { ...agents, author: agent });
  if (slot === 'reviewer') return withAgents(config, { ...agents, reviewer: agent });
  if (slot === 'lead') return withAgents(config, { ...agents, leadReviewer: agent });
  const extraReviewers = [...(agents.extraReviewers ?? [])];
  extraReviewers[extraIndex(slot)] = { ...extraReviewers[extraIndex(slot)], ...agent }; // keeps what the extra reviewer has besides an agent
  return withAgents(config, { ...agents, extraReviewers });
}

/** The role whose failover steps a slot takes: the extra reviewers take the reviewer's. */
export const failoverRoleOf = (slot: Slot | null): 'author' | 'reviewer' | 'leadReviewer' => (slot === null ? 'author' : slot === 'lead' ? 'leadReviewer' : 'reviewer');
