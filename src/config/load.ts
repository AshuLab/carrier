import { configSchema, type Config } from './schema.ts';

export const defaults = {
  root: '~/.solve',
  pollIntervalMinutes: 5,
  logLevel: 'info',
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

export function loadConfig(base: unknown, user: unknown): LoadResult {
  const parsed = configSchema.safeParse(merge(base, user));
  if (parsed.success) return { ok: true, config: parsed.data };
  return {
    ok: false,
    errors: parsed.error.issues.map((issue) => ({
      path: issue.path.join('.') || '(root)',
      message: issue.message,
    })),
  };
}
