import { defaults, loadConfig } from '../../config/load.ts';
import type { Config } from '../../config/schema.ts';
import type { AgentOption, Failover, Identities, Role } from './build-config.ts';
import { tilde } from './summary.ts';

/** What an existing config already says, to start from when editing it. */
export type Prior = { repos: string[]; identities: Identities; options: Record<string, AgentOption>; failover?: Failover; author: Role; reviewer: Role };

export function priorFrom(raw: unknown): Prior | undefined {
  const loaded = loadConfig(defaults, raw);
  if (!loaded.ok) return undefined;
  const { config } = loaded;
  const role = (r: Config['agents']['author']): Role => ({ identity: config.profiles[r.profile]!, option: r.option, ...(r.persona && { persona: r.persona }) });
  // The loader makes a folder absolute; written back with `~` it stays portable.
  const options = Object.fromEntries(Object.entries(config.agentOptions).map(([name, o]) => [name, o.configDir ? { ...o, configDir: tilde(o.configDir) } : o]));
  return { repos: config.repos.map((r) => r.name), identities: config.identities, options, ...(config.failover && { failover: config.failover }), author: role(config.agents.author), reviewer: role(config.agents.reviewer) };
}
