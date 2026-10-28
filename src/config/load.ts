import { configSchema, type Config } from './schema.ts';

export const defaults = {
  root: '~/.solve',
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

const movedKeys = ['harness', 'model', 'provider'];

export function loadConfig(base: unknown, user: unknown): LoadResult {
  const parsed = configSchema.safeParse(merge(base, user));
  if (parsed.success) return { ok: true, config: parsed.data };
  return {
    ok: false,
    errors: parsed.error.issues.flatMap((issue): ConfigError[] => {
      const path = issue.path.join('.') || '(root)';
      // The old shape: say where the fields went instead of calling them unknown.
      const moved = issue.code === 'unrecognized_keys' && issue.path.includes('agents') ? issue.keys.filter((key) => movedKeys.includes(key)) : [];
      if (moved.length === 0) return [{ path, message: issue.message }];
      return moved.map((key) => ({ path: `${path}.${key}`, message: `"${key}" moved to agentOptions: declare it in an agent option and point the role at it with "option" (see docs/configuration.md)` }));
    }),
  };
}
