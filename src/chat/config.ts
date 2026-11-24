import { randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, isAbsolute } from 'node:path';
import { LogLevel } from '@ashulab/universal-logger';
import { z } from 'zod';
import { carrierHome, chatConfigPathOf, chatPlacesOf, expandHome } from '../config/places.ts';
import { ChatRefused } from './runner.ts';

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

// The chat's own configuration level (ADR 0034): `<folder>/chat.json`, every key optional, strict like the engine's config.
const chatConfigSchema = z.strictObject({
  agents: z.record(z.string().regex(chatAgentName, 'a chat agent name is lowercase letters, digits and hyphens, starting with a letter'), chatAgent).optional(),
  projectsFolder: z.string().min(1).transform(expandHome).refine(isAbsolute, 'must be an absolute path, or start with ~/').optional(),
  githubCallTimeoutSeconds: z.int().positive().optional(),
  logLevel: z.enum(LogLevel).optional(),
  /** A session left alone this long is archived by the host's clock pass. */
  archiveAfterDays: days.default(15),
  /** An archived session left alone this long is deleted by the same pass, unless its worktree holds unsaved work; it must be greater than `archiveAfterDays` when both are numbers. */
  deleteAfterDays: days.default(30),
  /** Which copy of a branch a new worktree is cut from when the plan does not say (ADR 0037). */
  worktreeStart: z.enum(['remote', 'local']).default('remote'),
  /** Minutes an idle session that no request names stays open before its agent is closed; it wakes with the next message. */
  idleCloseMinutes: z.union([z.literal(10), z.literal(30), z.literal(60)], { error: 'must be 10, 30 or 60 (minutes)' }).default(10),
  /** When the clock's pass removes a session's worktree folder, keeping its branch (ADR 0035, 0042): once its PR is merged, and once the session is archived and untouched for `afterInactiveDays` (14 by default); `"never"` and false turn each off. */
  worktreeCleanup: z.strictObject({ afterPrMerged: z.boolean().default(true), afterInactiveDays: days.default(14) }).default({ afterPrMerged: true, afterInactiveDays: 14 }),
}).refine((c) => typeof c.archiveAfterDays !== 'number' || typeof c.deleteAfterDays !== 'number' || c.deleteAfterDays > c.archiveAfterDays, {
  path: ['deleteAfterDays'],
  when: (payload) => payload.issues.length === 0, // a value already refused is not also reported against the other
  error: 'must be greater than archiveAfterDays',
});

/** The chat's settings once the defaults are in. */
/** `agents` is undefined when `chat.json` lists none: the agents are then the accounts of `providers.json` (see `chatAgentsOf`). */
export type ChatSettings = { agents: ChatAgent[] | undefined; projectsFolder: string; githubCallTimeoutSeconds: number; logLevel: LogLevel; archiveAfterDays: number | 'never'; deleteAfterDays: number | 'never'; worktreeStart: 'remote' | 'local'; idleCloseMinutes: 10 | 30 | 60; worktreeCleanup: WorktreeCleanup };
export type WorktreeCleanup = { afterPrMerged: boolean; afterInactiveDays: number | 'never' };
export type ChatConfigError = { path: string; message: string };
export type ChatConfigResult = { ok: true; settings: ChatSettings } | { ok: false; errors: ChatConfigError[] };

/** The chat's settings from the parsed contents of `chat.json` (`{}` when there is no file), with the defaults for what it leaves out. */
export function loadChatConfig(user: unknown, folder = carrierHome()): ChatConfigResult {
  const parsed = chatConfigSchema.safeParse(user);
  if (parsed.success === false) return { ok: false, errors: parsed.error.issues.map((issue) => ({ path: issue.path.join('.') || '(root)', message: issue.message })) };
  const { agents, projectsFolder = chatPlacesOf(folder).projects, githubCallTimeoutSeconds = 30, logLevel = LogLevel.INFO, archiveAfterDays, deleteAfterDays, worktreeStart, idleCloseMinutes, worktreeCleanup } = parsed.data;
  return { ok: true, settings: { agents: agents && Object.entries(agents).map(([name, agent]) => ({ name, ...agent })), projectsFolder, githubCallTimeoutSeconds, logLevel, archiveAfterDays, deleteAfterDays, worktreeStart, idleCloseMinutes, worktreeCleanup } };
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

/** The keys `editChatSettings` may change: the two ages of the session clock, where a worktree starts and when an idle session sleeps. */
export const chatSettingKeys = ['archiveAfterDays', 'deleteAfterDays', 'worktreeStart', 'idleCloseMinutes'] as const;

/**
 * Changes keys of `chat.json` (ADR 0053): reads the raw file again now (a file that is not there is `{}`), sets each key of `changes` (null removes it, every other key stays as the person wrote it),
 * validates the whole result with the file's strict schema and writes it through a temporary file and a rename. Answers the saved part: the keys of `changes` as the file now has them.
 * A file that is not a JSON object, or a result the schema refuses, is a `ChatRefused` (`config.problem`: the key path and the kind, the schema's issue code, as parameters) and the file is left as it was.
 */
export function editChatSettings(changes: Partial<Record<(typeof chatSettingKeys)[number], unknown>>, folder = carrierHome()): { saved: Record<string, unknown> } {
  const file = chatConfigPathOf(folder);
  let current: unknown = {};
  try {
    current = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    if (error instanceof SyntaxError) throw new ChatRefused('config.problem', `${file} is not valid JSON, so it was not changed`, { path: '(file)', problem: 'notJson' });
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
  }
  if (typeof current !== 'object' || current === null || Array.isArray(current)) throw new ChatRefused('config.problem', `${file} is not a JSON object, so it was not changed`, { path: '(file)', problem: 'notAnObject' });
  const next: Record<string, unknown> = { ...current };
  for (const [key, value] of Object.entries(changes)) {
    if (value === null) delete next[key];
    else if (value !== undefined) next[key] = value;
  }
  const checked = chatConfigSchema.safeParse(next);
  if (checked.success === false) {
    const issue = checked.error.issues[0]!;
    const path = issue.path.join('.') || '(root)';
    throw new ChatRefused('config.problem', `${path}: ${issue.message}`, { path, problem: issue.code });
  }
  const temporary = `${file}.${process.pid}.${randomUUID()}.tmp`;
  mkdirSync(dirname(file), { recursive: true });
  try {
    writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`);
    renameSync(temporary, file);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
  return { saved: Object.fromEntries(Object.keys(changes).filter((key) => key in next).map((key) => [key, next[key]])) };
}
