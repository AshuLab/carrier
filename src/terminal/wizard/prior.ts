import { defaults, loadConfig } from '../../config/load.ts';
import { loadProviders } from '../../config/providers.ts';
import type { Config } from '../../config/schema.ts';
import type { AIProvider, Failover, Role } from './build-config.ts';
import { tilde } from './summary.ts';

/** What an existing config already says, to start from when editing it. */
export type Prior = { repos: string[]; providers: Record<string, AIProvider>; failover?: Failover; author: Role; reviewer: Role; leadReviewer?: Role };

/** `raw` is the parsed `config.json`, `rawProviders` the parsed `providers.json` (`{}` when there is none). */
export function priorFrom(raw: unknown, rawProviders: unknown): Prior | undefined {
  const accounts = loadProviders(rawProviders);
  if (!accounts.ok) return undefined;
  const loaded = loadConfig(defaults, raw, accounts.providers);
  if (!loaded.ok) return undefined;
  const { config } = loaded;
  const role = (r: Config['agents']['author']): Role => ({ identity: config.profiles[r.profile]!, provider: r.provider, model: r.model, ...(r.effort && { effort: r.effort }), ...(r.persona && { persona: r.persona }) });
  // The loader makes a folder absolute; written back with `~` it stays portable.
  const providers = Object.fromEntries(Object.entries(config.providers).map(([name, p]) => [name, p.configDir ? { ...p, configDir: tilde(p.configDir) } : p]));
  return {
    repos: config.repos.map((r) => r.name),
    providers,
    ...(config.failover && { failover: config.failover }),
    author: role(config.agents.author),
    reviewer: role(config.agents.reviewer),
    ...(config.agents.leadReviewer ? { leadReviewer: role(config.agents.leadReviewer) } : {}),
  };
}
