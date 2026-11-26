import { defaults, loadConfig } from '../../config/load.ts';
import { loadProviders } from '../../config/providers.ts';
import type { Config } from '../../config/schema.ts';
import type { AIProvider, Extra, Failover, Identity, Role } from './build-config.ts';
import { tilde } from './summary.ts';

/** What an existing config already says, to start from when editing it. */
export type Prior = { repos: string[]; providers: Record<string, AIProvider>; failover?: Failover; orchestrator?: Identity; author: Role; reviewer: Role; extraReviewers?: Extra[]; leadReviewer?: Role };

/** `raw` is the parsed `engine.json`, `rawProviders` the parsed `providers.json` (`{}` when there is none). A file that does not validate gives its first error, with its path. */
export function priorFrom(raw: unknown, rawProviders: unknown): Prior | { error: string } {
  const accounts = loadProviders(rawProviders);
  if (!accounts.ok) return { error: `providers.json ${accounts.errors[0]!.path}: ${accounts.errors[0]!.message}` };
  const loaded = loadConfig(defaults, raw, accounts.providers);
  if (!loaded.ok) return { error: `${loaded.errors[0]!.path}: ${loaded.errors[0]!.message}` };
  const { config } = loaded;
  const role = (r: Omit<Config['agents']['author'], 'skills'>): Role => ({ identity: config.profiles[r.profile]!, provider: r.provider, model: r.model, ...(r.effort && { effort: r.effort }), ...(r.persona && { persona: r.persona }) });
  // The loader makes a folder absolute; written back with `~` it stays portable.
  const providers = Object.fromEntries(Object.entries(config.providers).map(([name, p]) => [name, p.configDir ? { ...p, configDir: tilde(p.configDir) } : p]));
  return {
    repos: config.repos.map((r) => r.name),
    providers,
    ...(config.failover && { failover: config.failover }),
    orchestrator: config.profiles[config.orchestratorProfile]!,
    author: role(config.agents.author),
    reviewer: role(config.agents.reviewer),
    ...(config.agents.extraReviewers && { extraReviewers: config.agents.extraReviewers.map((extra) => ({ role: role(extra), ...(extra.failover && { failover: extra.failover }) })) }),
    ...(config.agents.leadReviewer ? { leadReviewer: role(config.agents.leadReviewer) } : {}),
  };
}
