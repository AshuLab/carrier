import { readFileSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { z } from 'zod';
import { harnessNames, localProvidersOf } from '../harnesses/names.ts';
import { carrierHome, expandHome, providersPathOf } from './places.ts';
import { refusedLaunchArg } from './launch-args.ts';

/** The key of an account: stored and shown as is. */
export const optionNamePattern = /^[a-z][a-z0-9-]{0,39}$/;

/** The icons an app may draw for an account; absent means the tool's own mark. The hello's `accountPalette` says a host knows all of them: the first twelve are the ones `accountIdentity` hosts know. */
export const accountIcons = [
  'bolt', 'star', 'briefcase', 'person', 'people', 'code', 'flask', 'leaf', 'moon', 'heart', 'cube', 'letter',
  'flame', 'sparkles', 'paperplane', 'globe', 'shield', 'key', 'house', 'book', 'hammer', 'cloud', 'bell',
] as const;
/** The colors an app may give an account; absent means none. The first eight are the ones `accountIdentity` hosts know. */
export const accountColors = ['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'purple', 'pink', 'mint', 'cyan', 'indigo', 'brown', 'gray'] as const;

/** An account: one login of an agent CLI, or a local server through one. */
export const account = z.strictObject({
  harness: z.enum(harnessNames),
  /** What the app shows instead of the key: a single line of at most 60 characters. */
  displayName: z.string().trim().min(1).max(60).regex(/^[^\r\n]*$/, 'must be a single line').optional(),
  /** A short tag an app shows beside the account: a single line of 1 to 12 characters. */
  label: z.string().trim().min(1).max(12).regex(/^[^\r\n]*$/, 'must be a single line').optional(),
  icon: z.enum(accountIcons).optional(),
  color: z.enum(accountColors).optional(),
  /** Optional default model for this account. */
  model: z.string().min(1).optional(),
  /** Run on a local server through the harness's CLI instead of the cloud. */
  provider: z.enum(['lmstudio', 'ollama']).optional(),
  /** `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. Absolute once `~` is expanded. */
  configDir: z.string().min(1).transform(expandHome).optional(),
  /** The binary to run instead of the harness's name on the PATH. Absolute once `~` is expanded. */
  command: z.string().min(1).transform(expandHome).optional(),
  /** Claude: `"auto"` or 100000 to 1000000 tokens (`--autocompact`). Codex: a positive token count (`model_auto_compact_token_limit`). */
  autoCompact: z.union([z.literal('auto'), z.int().positive()]).optional(),
  /** Claude only: passed per run as `--settings '{"idleCompaction":…}'`; absent passes nothing. */
  idleCompaction: z.boolean().optional(),
  /** Appended to the arguments Carrier passes; the flags Carrier sets itself are refused. */
  launchArgs: z.array(z.string().min(1)).optional(),
}, { error: (issue) => (issue.code === 'unrecognized_keys' && issue.keys.includes('enabled') ? 'enabled is gone: an epic starts at once on its roles and no choice is held, so there is nothing to switch off. Remove it' : undefined) });

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
    if (p.command !== undefined && !isAbsolute(p.command)) {
      ctx.addIssue({ code: 'custom', path: [name, 'command'], message: `${where}: command must be an absolute path, or start with ~/ (got "${p.command}")` });
    }
    if (p.harness === 'agy') {
      for (const key of ['autoCompact', 'idleCompaction'] as const) {
        if (p[key] !== undefined) ctx.addIssue({ code: 'custom', path: [name, key], message: `${where}: agy has no ${key} setting` });
      }
    } else if (p.autoCompact !== undefined && p.autoCompact !== 'auto' && p.harness === 'claude' && (p.autoCompact < 100_000 || p.autoCompact > 1_000_000)) {
      ctx.addIssue({ code: 'custom', path: [name, 'autoCompact'], message: `${where}: autoCompact for claude is "auto" or a token count from 100000 to 1000000 (got ${p.autoCompact})` });
    } else if (p.autoCompact === 'auto' && p.harness === 'codex') {
      ctx.addIssue({ code: 'custom', path: [name, 'autoCompact'], message: `${where}: autoCompact for codex is a token count, not "auto"` });
    }
    if (p.idleCompaction !== undefined && p.harness === 'codex') {
      ctx.addIssue({ code: 'custom', path: [name, 'idleCompaction'], message: `${where}: codex has no idleCompaction setting` });
    }
    const refused = p.launchArgs && refusedLaunchArg(p.harness, p.launchArgs);
    if (refused) {
      ctx.addIssue({ code: 'custom', path: [name, 'launchArgs', refused.index], message: `${where}: launchArgs cannot repeat ${refused.what}, Carrier sets it` });
    }
  }
});
export type Providers = z.infer<typeof accounts>;
export type Account = z.infer<typeof account>;

/** How an account's CLI runs: what reaches the process the engine starts. */
export type AccountRuntime = Pick<Account, 'command' | 'autoCompact' | 'idleCompaction' | 'launchArgs'>;
export const runtimeOf = ({ command, autoCompact, idleCompaction, launchArgs }: Account): AccountRuntime => ({
  ...(command !== undefined && { command }),
  ...(autoCompact !== undefined && { autoCompact }),
  ...(idleCompaction !== undefined && { idleCompaction }),
  ...(launchArgs !== undefined && { launchArgs }),
});

/** Without `providers.json`: one account per harness, named after it, with this Mac's own login. */
export const defaultAccounts: Providers = Object.fromEntries(harnessNames.map((harness) => [harness, { harness }]));

/** The servers a text generator can be: the local ones, called on their default port on this Mac. */
export const textGeneratorKinds = ['lmstudio', 'ollama'] as const;
/** A text generator: a model that turns text into text with no tools, on a local server. */
const textGenerator = z.strictObject({ kind: z.enum(textGeneratorKinds), model: z.string().trim().min(1) });
export type TextGenerator = z.infer<typeof textGenerator>;

const providersFileSchema = z.strictObject({
  providers: accounts.default(defaultAccounts),
  textGenerators: z.record(z.string(), textGenerator).default({}),
  /** The name of the generator in use. */
  textGenerator: z.string().optional(),
}).superRefine((file, ctx) => {
  for (const name of Object.keys(file.textGenerators)) {
    if (!optionNamePattern.test(name)) {
      ctx.addIssue({ code: 'custom', path: ['textGenerators', name], message: `textGenerators.${name}: a text generator name is a lowercase word: letters, digits and hyphens, starting with a letter, up to 40 characters` });
    }
  }
  if (file.textGenerator !== undefined && Object.hasOwn(file.textGenerators, file.textGenerator) === false) {
    ctx.addIssue({ code: 'custom', path: ['textGenerator'], message: `textGenerator: "${file.textGenerator}" is not declared in textGenerators` });
  }
});

export type ProvidersError = { path: string; message: string };
/** `textGenerator` is the one in use, when the file names one. */
export type ProvidersResult = { ok: true; providers: Providers; textGenerator?: TextGenerator & { name: string } } | { ok: false; errors: ProvidersError[] };

/** The accounts and the text generator in use from the parsed contents of `providers.json` (`{}` when there is no file: the default accounts, no generator). */
export function loadProviders(json: unknown): ProvidersResult {
  const parsed = providersFileSchema.safeParse(json);
  if (parsed.success) {
    const { providers, textGenerators, textGenerator: name } = parsed.data;
    return { ok: true, providers, ...(name !== undefined && { textGenerator: { name, ...textGenerators[name]! } }) };
  }
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
