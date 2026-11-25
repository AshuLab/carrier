import { defaults, loadConfig } from './load.ts';

/** `loadConfig` over one object that still has `providers` in it: the accounts are split off, as they come from providers.json. */
export function loadWithProviders(config: Record<string, unknown>) {
  const { providers = {}, ...file } = config;
  return loadConfig(defaults, file, providers as Record<string, never>);
}

/** An `engine.json` the engine accepts with no `providers.json` (the default accounts), as `carrier init` writes it: no default value is in it, and keys the person set by hand are. */
export const validEngineFile = {
  repos: [{ name: 'AshuLab/carrier', skills: { ship: 'ship' } }, { name: 'acme/web', agents: { author: { model: 'opus' } } }],
  profiles: { 'author-bot': { kind: 'forge', agent: 'artanis-agent' }, 'reviewer-bot': { kind: 'gh' } },
  agents: {
    author: { profile: 'author-bot', provider: 'claude', model: 'm' },
    reviewer: { profile: 'reviewer-bot', provider: 'codex', model: 'm' },
  },
  limits: { maxReviews: 7, maxLeadRounds: 2 },
  orchestratorProfile: 'reviewer-bot',
  failover: { triggers: ['usage_limit'] },
};
