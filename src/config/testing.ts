import { defaults, loadConfig } from './load.ts';

/** `loadConfig` over one object that still has `providers` in it: the accounts are split off, as they come from providers.json. */
export function loadWithProviders(config: Record<string, unknown>) {
  const { providers = {}, ...file } = config;
  return loadConfig(defaults, file, providers as Record<string, never>);
}
