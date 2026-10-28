import type { HarnessName } from '../harnesses/names.ts';
import type { Config } from './schema.ts';

// What an agent runs with: the role (profile, persona, model) and the provider it points at (harness, configDir, local server).
export type Agent = {
  profile: string;
  harness: HarnessName;
  model: string;
  provider?: 'lmstudio' | 'ollama';
  configDir?: string;
  persona?: Config['agents']['author']['persona'];
  option?: string;
  providerName?: string;
};

// Only profile names, never credentials: Agent Forge resolves those from the profile at run time.
// `sharedIdentity` is saved with the epic so a later config change does not move it; absent on epics saved before it existed.
// `providers` is the directory of AI providers as it was when the epic was reserved, what a choice picks from.
// `failover` is saved too, for the same reason: a config edit moves no running epic.
export type EffectiveRepoConfig = {
  name: string;
  sharedIdentity?: boolean;
  providers?: Config['providers'];
  options?: Record<string, { harness: HarnessName; model?: string; configDir?: string; provider?: 'lmstudio' | 'ollama' }>;
  failover?: Config['failover'];
  agents: { author: Agent; reviewer: Agent; leadReviewer?: Agent };
};

// Two names can point at the same bot or at the same `gh` login: what matters is the account that posts.
export const sameAccount = (a: Config['profiles'][string], b: Config['profiles'][string]) => a.kind === b.kind && (a.kind === 'gh' || a.agent === (b as typeof a).agent);

/** Returns the failover order for a specific role: role-specific chain if configured, else default chain. */
export function failoverOrderFor(failover: Config['failover'], role: 'author' | 'reviewer' | 'leadReviewer'): string[] | undefined {
  if (!failover?.enabled) return undefined;
  return failover.roles?.[role] ?? failover.default ?? (failover as any).order;
}

// Each repo inherits the global value of every field it does not override.
export function resolveRepoConfig(config: Config, repo: Config['repos'][number]): EffectiveRepoConfig {
  const roleOf = (role: 'author' | 'reviewer' | 'leadReviewer') => {
    const base = config.agents[role];
    const repoAgent = repo.agents?.[role];
    if (!base && !repoAgent) return undefined;
    const merged = { ...(base ?? {}), ...(repoAgent ?? {}) };
    if (!merged.provider || !merged.profile || !merged.model) return undefined;
    const providerConfig = config.providers[merged.provider];
    if (!providerConfig) return undefined;
    return {
      profile: merged.profile,
      harness: providerConfig.harness,
      model: merged.model,
      ...(providerConfig.provider && { provider: providerConfig.provider }),
      ...(providerConfig.configDir && { configDir: providerConfig.configDir }),
      ...(merged.persona && { persona: merged.persona }),
      option: merged.provider,
      providerName: merged.provider,
    } as Agent;
  };
  const leadReviewer = roleOf('leadReviewer');
  const agents = { author: roleOf('author')!, reviewer: roleOf('reviewer')!, ...(leadReviewer ? { leadReviewer } : {}) };
  const [author, reviewer] = [config.profiles[agents.author?.profile], config.profiles[agents.reviewer?.profile]];
  return {
    name: repo.name,
    sharedIdentity: author !== undefined && reviewer !== undefined && sameAccount(author, reviewer),
    providers: config.providers,
    ...(config.failover && { failover: config.failover }),
    agents,
  };
}
