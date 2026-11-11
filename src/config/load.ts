import type { Providers } from './providers.ts';
import { configSchema, type Config } from './schema.ts';

export const defaults = {
  pollIntervalMinutes: 5,
  finishedWindowDays: 15,
  logLevel: 'info',
  identities: 'separate',
  limits: {
    maxConcurrentEpics: 3,
    maxReviews: 5,
    maxExecutionRetries: 3,
    maxExecutionHours: 4,
    githubCallTimeoutSeconds: 30,
    optionChoiceSeconds: 60,
  },
};

export type ConfigError = { path: string; message: string };
export type LoadResult = { ok: true; config: Config } | { ok: false; errors: ConfigError[] };

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

// Objects merge per field; anything else (scalars, arrays, mismatched types) is replaced as-is
// and left for the schema to reject.
function merge(base: unknown, override: unknown): unknown {
  if (!isObject(base) || !isObject(override)) return override;
  const result: Record<string, unknown> = { ...base };
  for (const [key, value] of Object.entries(override)) result[key] = merge(base[key], value);
  return result;
}

const movedKeys = ['option'];

/** The config from the user's file merged over `base`, with the accounts `providers.json` declares (read by `loadProviders`; none without the file) where `config.providers` is. */
export function loadConfig(base: unknown, user: unknown, providers: Providers = {}): LoadResult {
  if (isObject(user) && 'providers' in user) {
    return { ok: false, errors: [{ path: 'providers', message: `accounts moved out of config.json into providers.json in the Carrier folder (see docs/configuration.md)` }] };
  }
  const merged = merge(base, user);
  const parsed = configSchema.safeParse(isObject(merged) ? { ...merged, providers } : merged);
  if (parsed.success) return { ok: true, config: parsed.data };
  return {
    ok: false,
    errors: parsed.error.issues.flatMap((issue): ConfigError[] => {
      const path = issue.path.join('.') || '(root)';
      if (issue.code === 'unrecognized_keys' && issue.path.includes('agents')) {
        const moved = issue.keys.filter((key) => movedKeys.includes(key));
        if (moved.length > 0) {
          return moved.map((key) => ({
            path: `${path}.${key}`,
            message: `"${key}" was replaced by "provider" and "model" directly on the agent (see docs/configuration.md)`,
          }));
        }
      }
      return [{ path, message: issue.message }];
    }),
  };
}
