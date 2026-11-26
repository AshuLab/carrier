import { failoverStepsFor, type Agent, type EffectiveRepoConfig, type ExtraReviewer } from '../config/resolve.ts';
import { savedSkills, type ResolvedSkills } from '../config/skills.ts';
import type { Slot } from '../storage/executions.ts';

// The extra reviewers live in the epic's saved configuration (`agents.extraReviewers`, as the config's schema names them), which an epic saved before them lacks.
// Read here as agents: what each also keeps (its review skills, its failover steps) is only carried along.
type SavedAgents = { author: Agent; reviewer: Agent; leadReviewer?: Agent; extraReviewers?: (Agent & Pick<ExtraReviewer, 'key' | 'name' | 'type'>)[] };
const withAgents = (config: EffectiveRepoConfig, agents: SavedAgents): EffectiveRepoConfig => ({ ...config, agents: agents as EffectiveRepoConfig['agents'] });

/** Whether the slot is an extra reviewer's: its key, as the epic's saved configuration carries it. */
export const isExtraSlot = (slot: Slot | null) => slot !== null && slot !== 'reviewer' && slot !== 'lead';

/** The agent a slot runs with in the epic's saved configuration (null: the author); undefined when the epic saved none for it. */
export function agentOfSlot(config: EffectiveRepoConfig, slot: Slot | null): Agent | undefined {
  const agents = config.agents as SavedAgents;
  if (slot === null) return agents.author;
  if (slot === 'reviewer') return agents.reviewer;
  if (slot === 'lead') return agents.leadReviewer;
  return agents.extraReviewers?.find((extra) => extra.key === slot);
}

/** What a lead or an extra reviewer keeps besides its agent: carried over when the agent is replaced, never the agent's own fields. */
const besidesAgent = (entry: (Agent & Partial<ExtraReviewer>) | undefined) => ({
  ...(entry?.skills && { skills: entry.skills }),
  ...(entry?.failover && { failover: entry.failover }),
  ...(entry?.sharedIdentity && { sharedIdentity: entry.sharedIdentity }),
});

/** The saved configuration with the slot's agent replaced: where a failover leaves the option the slot runs on. */
export function withAgentOfSlot(config: EffectiveRepoConfig, slot: Slot | null, agent: Agent): EffectiveRepoConfig {
  const agents = config.agents as SavedAgents;
  if (slot === null) return withAgents(config, { ...agents, author: agent });
  if (slot === 'reviewer') return withAgents(config, { ...agents, reviewer: agent });
  // The agent replaces the previous one whole, so a field the new option leaves unset (provider, configDir, command, effort...) does not survive from the old option.
  if (slot === 'lead') return withAgents(config, { ...agents, leadReviewer: { ...agent, ...besidesAgent(agents.leadReviewer) } });
  // The key, name and type are the entry's, not the agent's: they stay where the entry is.
  const extraReviewers = (agents.extraReviewers ?? []).map((extra) => (extra.key === slot ? { ...agent, ...besidesAgent(extra), key: extra.key, name: extra.name, type: extra.type } : extra));
  return withAgents(config, { ...agents, extraReviewers });
}

/** The role whose failover steps a slot takes: the extra reviewers take the reviewer's. */
const failoverRoleOf = (slot: Slot | null): 'author' | 'reviewer' | 'leadReviewer' => (slot === null ? 'author' : slot === 'lead' ? 'leadReviewer' : 'reviewer');

/** The failover steps of a slot: an extra reviewer's own when it declares any, else its role's (the extra reviewers take the reviewer's). */
export const failoverStepsOfSlot = (config: EffectiveRepoConfig | null, slot: Slot | null) =>
  (slot === null || config === null ? undefined : (agentOfSlot(config, slot) as Partial<ExtraReviewer> | undefined)?.failover) ?? failoverStepsFor(config?.failover, failoverRoleOf(slot));

/** The slots that review a round, the mandatory reviewer first and then the extra ones in the order of the epic's saved configuration: an epic saved before the extra reviewers has one. A saved extra reviewer with no key (saved before the names) is no slot. */
export const roundSlots = (config: EffectiveRepoConfig | null): Slot[] => ['reviewer', ...(config?.agents.extraReviewers ?? []).flatMap((extra) => (typeof extra.key === 'string' ? [extra.key] : []))];

/** The skills a slot invokes: an extra reviewer's own review skills replace the epic's. */
export function skillsOfSlot(config: EffectiveRepoConfig, slot: Slot | null): ResolvedSkills {
  const own = slot === null ? undefined : (agentOfSlot(config, slot) as Partial<ExtraReviewer> | undefined)?.skills;
  return own ? { ...savedSkills(config), review: own } : savedSkills(config);
}
