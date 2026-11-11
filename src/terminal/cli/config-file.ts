import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { carrierHome, defaultConfigPath } from '../../config/default-path.ts';
import { defaults, loadConfig } from '../../config/load.ts';
import { providersProblem, readProvidersFile } from '../../config/providers.ts';
import type { Config } from '../../config/schema.ts';
import { CliError } from './cli-error.ts';

/** The explicit `--config` wins; otherwise the global file `carrier init` writes, if it is there. */
export const configPathFor = (explicit: unknown) => (typeof explicit === 'string' ? explicit : existsSync(defaultConfigPath()) ? defaultConfigPath() : undefined);

/** When there is no config to use: what to do about it. */
export const noConfig = (...first: string[]) => new CliError(2, ...first, `No config at ${defaultConfigPath()}: run "carrier init" to create one.`);

/** Reads, merges over the defaults and validates; every problem is reported at once, with its field. The accounts come from `providers.json` in the Carrier folder, wherever `path` is. */
export function loadConfigFile(path: string, folder = carrierHome()): Config {
  const file = resolve(path);
  let user: unknown;
  try {
    user = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    throw new CliError(1, `Cannot read config ${file}: ${error instanceof Error ? error.message : String(error)}`);
  }
  const accounts = readProvidersFile(folder);
  if (!accounts.ok) throw new CliError(1, ...providersProblem(folder, accounts.errors).split('\n'));
  const result = loadConfig(defaults, user, accounts.providers);
  if (!result.ok) throw new CliError(1, `Invalid config ${file}:`, ...result.errors.map((e) => `  ${e.path}: ${e.message}`));
  return result.config;
}
