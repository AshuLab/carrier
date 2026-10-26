import type { Config } from './schema.ts';

type Agent = Config['agents']['author'];

// Only profile names, never credentials: Agent Forge resolves those from the profile at run time.
// `sharedIdentity` is saved with the epic so a later config change does not move it; absent on epics saved before it existed.
export type EffectiveRepoConfig = { name: string; sharedIdentity?: boolean; agents: { author: Agent; reviewer: Agent } };

// Two names can point at the same bot or at the same `gh` login: what matters is the account that posts.
export const sameAccount = (a: Config['profiles'][string], b: Config['profiles'][string]) => a.kind === b.kind && (a.kind === 'gh' || a.agent === (b as typeof a).agent);

// Each repo inherits the global value of every field it does not override.
export function resolveRepoConfig(config: Config, repo: Config['repos'][number]): EffectiveRepoConfig {
  const agents = {
    author: { ...config.agents.author, ...repo.agents?.author },
    reviewer: { ...config.agents.reviewer, ...repo.agents?.reviewer },
  };
  // Validation resolves repos before it has checked that every profile is declared.
  const [author, reviewer] = [config.profiles[agents.author.profile], config.profiles[agents.reviewer.profile]];
  return { name: repo.name, sharedIdentity: author !== undefined && reviewer !== undefined && sameAccount(author, reviewer), agents };
}
