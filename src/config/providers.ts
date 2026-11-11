import { readFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { z } from 'zod';
import { harnessNames, localProvidersOf } from '../harnesses/names.ts';
import { carrierHome, expandHome } from './default-path.ts';

/** The key of an account: stored and shown as is. */
export const optionNamePattern = /^[a-z][a-z0-9-]{0,39}$/;

/** An account: one login of an agent CLI, or a local server through one. */
export const account = z.strictObject({
  harness: z.enum(harnessNames),
  /** What the app shows instead of the key: a single line of at most 60 characters. */
  displayName: z.string().trim().min(1).max(60).regex(/^[^\r\n]*$/, 'must be a single line').optional(),
  /** Optional default model for this account. */
  model: z.string().min(1).optional(),
  /** Run on a local server through the harness's CLI instead of the cloud. */
  provider: z.enum(['lmstudio', 'ollama']).optional(),
  /** `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. Absolute once `~` is expanded. */
  configDir: z.string().min(1).transform(expandHome).optional(),
  /** Whether the account is offered when an epic's agent option is chosen; true when absent. A role, a failover list or a chat agent may name it either way. */
  enabled: z.boolean().optional(),
});

/** The accounts by name, each one checked on its own and against its harness. */
export const accounts = z.record(z.string(), account).superRefine((all, ctx) => {
  for (const [name, p] of Object.entries(all)) {
    const where = `providers.${name}`;
    if (!optionNamePattern.test(name)) {
      ctx.addIssue({ code: 'custom', path: [name], message: `${where}: a provider name is a lowercase word: letters, digits and hyphens, starting with a letter, up to 40 characters` });
    }
    if (p.provider !== undefined && !(localProvidersOf[p.harness] as readonly string[]).includes(p.provider)) {
      ctx.addIssue({ code: 'custom', path: [name, 'provider'], message: `${where}: ${p.harness} cannot use the provider "${p.provider}"` });
    }
    if (p.configDir !== undefined && p.harness === 'agy') {
      ctx.addIssue({ code: 'custom', path: [name, 'configDir'], message: `${where}: agy has no config folder setting, so it cannot have a configDir` });
    } else if (p.configDir !== undefined && p.configDir !== '' && !isAbsolute(p.configDir)) {
      ctx.addIssue({ code: 'custom', path: [name, 'configDir'], message: `${where}: configDir must be an absolute path, or start with ~/ (got "${p.configDir}")` });
    }
  }
});
export type Providers = z.infer<typeof accounts>;

/** Without `providers.json`: one account per harness, named after it, with this Mac's own login, offered to nobody. */
const defaultAccounts: Providers = Object.fromEntries(harnessNames.map((harness) => [harness, { harness, enabled: false }]));

const providersFileSchema = z.strictObject({ providers: accounts.default(defaultAccounts) });

/** The names of the accounts offered for an epic's choice, which is also what the choice wait counts: the enabled ones. */
export const offeredNames = (directory: Record<string, { harness: string; enabled?: boolean }> | undefined) => Object.entries(directory ?? {}).filter(([, a]) => a.enabled !== false).map(([name]) => name);

export type ProvidersError = { path: string; message: string };
export type ProvidersResult = { ok: true; providers: Providers } | { ok: false; errors: ProvidersError[] };

/** Where the accounts live: `providers.json` in the Carrier folder, wherever the engine's `--config` points (ADR 0020). */
export const providersPathOf = (folder = carrierHome()) => join(folder, 'providers.json');

/** The accounts from the parsed contents of `providers.json` (`{}` when there is no file: the default accounts). */
export function loadProviders(json: unknown): ProvidersResult {
  const parsed = providersFileSchema.safeParse(json);
  if (parsed.success) return { ok: true, providers: parsed.data.providers };
  return { ok: false, errors: parsed.error.issues.map((issue) => ({ path: issue.path.join('.') || '(root)', message: issue.message })) };
}

/** `providers.json` read and validated; a file that is not there declares no account, one that cannot be read or does not match is an error naming the key. */
export function readProvidersFile(folder = carrierHome()): ProvidersResult {
  let json: unknown = {};
  try {
    json = JSON.parse(readFileSync(providersPathOf(folder), 'utf8'));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') return { ok: false, errors: [{ path: '(file)', message: error instanceof SyntaxError ? `is not valid JSON: ${error.message}` : 'cannot be read' }] };
  }
  return loadProviders(json);
}

/** The error a person sees when `providers.json` is wrong: the file and each key with what is wrong with it. */
export const providersProblem = (folder: string, errors: ProvidersError[]) => `Invalid providers file ${providersPathOf(folder)}:\n${errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`;
