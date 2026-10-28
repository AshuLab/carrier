import type { Config } from './schema.ts';

// What an agent runs with: the role (profile, persona) and the option it points at. `option` and `configDir` are absent from the config of an epic reserved before options existed; harness, model and provider are what it saved.
type Agent = Omit<Config['agents']['author'], 'option'> & Partial<Pick<Config['agents']['author'], 'option'>> & Config['agentOptions'][string];

// Only profile names, never credentials: Agent Forge resolves those from the profile at run time.
// `sharedIdentity` is saved with the epic so a later config change does not move it; absent on epics saved before it existed.
// `options` is the directory of options as it was when the epic was reserved, what a choice picks from; absent on an epic saved before the choice existed.
// `failover` is saved too, for the same reason: a config edit moves no running epic.
export type EffectiveRepoConfig = { name: string; sharedIdentity?: boolean; options?: Config['agentOptions']; failover?: Config['failover']; agents: { author: Agent; reviewer: Agent; leadReviewer?: Agent } };

// Two names can point at the same bot or at the same `gh` login: what matters is the account that posts.
export const sameAccount = (a: Config['profiles'][string], b: Config['profiles'][string]) => a.kind === b.kind && (a.kind === 'gh' || a.agent === (b as typeof a).agent);

/** Returns the failover order for a specific role: role-specific chain if configured, else default chain. */
export function failoverOrderFor(failover: Config['failover'], role: 'author' | 'reviewer' | 'leadReviewer'): string[] | undefined {
  if (!failover?.enabled) return undefined;
  return failover.roles?.[role] ?? failover.default ?? failover.order;
}

// Each repo inherits the global value of every field it does not override.
export function resolveRepoConfig(config: Config, repo: Config['repos'][number]): EffectiveRepoConfig {
  // Validation resolves repos before it has checked that every option is declared.
  const roleOf = (role: 'author' | 'reviewer' | 'leadReviewer') => {
    const base = config.agents[role];
    const repoAgent = repo.agents?.[role];
    if (!base && !repoAgent) return undefined;
    const agent = { ...(base ?? {}), ...(repoAgent ?? {}) };
    if (!agent.option) return undefined;
    return { ...agent, ...config.agentOptions[agent.option] } as Agent;
  };
  const leadReviewer = roleOf('leadReviewer');
  const agents = { author: roleOf('author')!, reviewer: roleOf('reviewer')!, ...(leadReviewer ? { leadReviewer } : {}) };
  // Validation resolves repos before it has checked that every profile is declared.
  const [author, reviewer] = [config.profiles[agents.author.profile], config.profiles[agents.reviewer.profile]];
  return { name: repo.name, sharedIdentity: author !== undefined && reviewer !== undefined && sameAccount(author, reviewer), options: config.agentOptions, ...(config.failover && { failover: config.failover }), agents };
}
