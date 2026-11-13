import { readFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { LogLevel } from '@ashulab/universal-logger';
import { z } from 'zod';
import { carrierHome, expandHome } from '../config/default-path.ts';

const movedToAccount = (key: string) => z.never({ error: `${key} is declared by the account in providers.json now; name it with "account"` }).optional();

/** An agent a chat can start with: an account of `providers.json` (ADR 0020), which sets its harness, login and binary. An Antigravity account is refused when a session opens. */
export const chatAgent = z.strictObject({
  account: z.string().min(1),
  harness: movedToAccount('harness'),
  command: movedToAccount('command'),
  model: z.string().min(1).optional(),
  /** Default options of the provider, by the provider's own option id. */
  options: z.record(z.string(), z.string()).optional(),
});
export const chatAgentName = /^[a-z][a-z0-9-]*$/;
export type ChatAgent = Omit<z.infer<typeof chatAgent>, 'harness' | 'command'> & { name: string };

/** Days of no activity before the session lifecycle acts (ADR 0019): a whole number, or `"never"` to turn that step off. */
const days = z.union([z.int().positive(), z.literal('never')]);

// The chat's own configuration level (ADR 0016): `<folder>/chat/chat.json`, every key optional, strict like the engine's config.
const chatConfigSchema = z.strictObject({
  agents: z.record(z.string().regex(chatAgentName, 'a chat agent name is lowercase letters, digits and hyphens, starting with a letter'), chatAgent).optional(),
  projectsFolder: z.string().min(1).transform(expandHome).refine(isAbsolute, 'must be an absolute path, or start with ~/').optional(),
  githubCallTimeoutSeconds: z.int().positive().optional(),
  logLevel: z.enum(LogLevel).optional(),
  /** A session left alone this long is archived by the host's clock pass. */
  archiveAfterDays: days.default(15),
  /** An archived session left alone this long is deleted by the same pass, unless its worktree holds unsaved work; it must be greater than `archiveAfterDays` when both are numbers. */
  deleteAfterDays: days.default(30),
}).refine((c) => typeof c.archiveAfterDays !== 'number' || typeof c.deleteAfterDays !== 'number' || c.deleteAfterDays > c.archiveAfterDays, {
  path: ['deleteAfterDays'],
  when: (payload) => payload.issues.length === 0, // a value already refused is not also reported against the other
  error: 'must be greater than archiveAfterDays',
});

/** The chat's settings once the defaults are in. */
/** `agents` is undefined when `chat.json` lists none: the agents are then the accounts of `providers.json` (see `chatAgentsOf`). */
export type ChatSettings = { agents: ChatAgent[] | undefined; projectsFolder: string; githubCallTimeoutSeconds: number; logLevel: LogLevel; archiveAfterDays: number | 'never'; deleteAfterDays: number | 'never' };
export type ChatConfigError = { path: string; message: string };
export type ChatConfigResult = { ok: true; settings: ChatSettings } | { ok: false; errors: ChatConfigError[] };

/** Where the chat keeps what it owns, inside the Carrier folder. */
export const chatDirOf = (folder = carrierHome()) => join(folder, 'chat');
export const chatStateOf = (folder = carrierHome()) => join(chatDirOf(folder), 'state');
export const chatLogsOf = (folder = carrierHome()) => join(chatDirOf(folder), 'logs');
export const chatSocketOf = (folder = carrierHome()) => join(chatStateOf(folder), 'chat.sock');
export const chatConfigPathOf = (folder = carrierHome()) => join(chatDirOf(folder), 'chat.json');

/** The chat's settings from the parsed contents of `chat.json` (`{}` when there is no file), with the defaults for what it leaves out. */
export function loadChatConfig(user: unknown, folder = carrierHome()): ChatConfigResult {
  const parsed = chatConfigSchema.safeParse(user);
  if (parsed.success === false) return { ok: false, errors: parsed.error.issues.map((issue) => ({ path: issue.path.join('.') || '(root)', message: issue.message })) };
  const { agents, projectsFolder = join(chatDirOf(folder), 'projects'), githubCallTimeoutSeconds = 30, logLevel = LogLevel.INFO, archiveAfterDays, deleteAfterDays } = parsed.data;
  return { ok: true, settings: { agents: agents && Object.entries(agents).map(([name, agent]) => ({ name, ...agent })), projectsFolder, githubCallTimeoutSeconds, logLevel, archiveAfterDays, deleteAfterDays } };
}

/** `chat.json` read and validated; a file that is not there is the defaults, one that cannot be read or does not match is an error naming the key. */
export function readChatConfig(folder = carrierHome()): ChatConfigResult {
  let user: unknown = {};
  try {
    user = JSON.parse(readFileSync(chatConfigPathOf(folder), 'utf8'));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') return { ok: false, errors: [{ path: '(file)', message: error instanceof SyntaxError ? `is not valid JSON: ${error.message}` : 'cannot be read' }] };
  }
  return loadChatConfig(user, folder);
}

/** The error a person sees when `chat.json` is wrong: the file and each key with what is wrong with it. */
export const chatConfigProblem = (folder: string, errors: ChatConfigError[]) => `Invalid chat config ${chatConfigPathOf(folder)}:\n${errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`;
