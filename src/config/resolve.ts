import type { Config } from './schema.ts';

type Agent = Config['agents']['author'];

// Only profile names, never credentials: Agent Forge resolves those from the profile at run time.
export type EffectiveRepoConfig = { name: string; agents: { author: Agent; reviewer: Agent } };

// Each repo inherits the global value of every field it does not override.
export function resolveRepoConfig(config: Config, repo: Config['repos'][number]): EffectiveRepoConfig {
  return {
    name: repo.name,
    agents: {
      author: { ...config.agents.author, ...repo.agents?.author },
      reviewer: { ...config.agents.reviewer, ...repo.agents?.reviewer },
    },
  };
}
