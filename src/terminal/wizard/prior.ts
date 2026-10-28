import { defaults, loadConfig } from '../../config/load.ts';
import type { Config } from '../../config/schema.ts';
import type { AgentOption, AIProvider, Failover, Identities, Role } from './build-config.ts';
import { tilde } from './summary.ts';

/** What an existing config already says, to start from when editing it. */
export type Prior = { repos: string[]; identities: Identities; providers?: Record<string, AIProvider>; options: Record<string, AgentOption>; failover?: Failover; author: Role; reviewer: Role; leadReviewer?: Role };

export function priorFrom(raw: unknown): Prior | undefined {
  const loaded = loadConfig(defaults, raw);
  if (!loaded.ok) return undefined;
  const { config } = loaded;
  const role = (r: Config['agents']['author']): Role => ({ identity: config.profiles[r.profile]!, option: r.option, ...(r.persona && { persona: r.persona }) });
  // The loader makes a folder absolute; written back with `~` it stays portable.
  const options = Object.fromEntries(Object.entries(config.agentOptions).map(([name, o]) => [name, o.configDir ? { ...o, configDir: tilde(o.configDir) } : o]));
  const providers = config.providers ? Object.fromEntries(Object.entries(config.providers).map(([name, p]) => [name, p.configDir ? { ...p, configDir: tilde(p.configDir) } : p])) : undefined;
  return {
    repos: config.repos.map((r) => r.name),
    identities: config.identities,
    providers,
    options,
    ...(config.failover && { failover: config.failover }),
    author: role(config.agents.author),
    reviewer: role(config.agents.reviewer),
    ...(config.agents.leadReviewer ? { leadReviewer: role(config.agents.leadReviewer) } : {}),
  };
}
