import { randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { TextParams } from '../orchestration/text-params.ts';
import { defaults, loadConfig } from './load.ts';
import { configProblem } from './problems.ts';
import { providersProblem, readProvidersFile } from './providers.ts';
import { repoNamePattern } from './schema.ts';

// The writes of `engine.json` the app and the CLI ask for (ADR 0053): the file's raw JSON is read again just now, changed, checked whole with the engine's own schema and
// written through a temporary file and a rename. `macos/Sources/CarrierCore` no longer writes these parts of the file; the words are the ones its checks used.

/** Why a change to a config file was not made: its words, a text code and the key path and kind of problem as parameters ([ADR 0055](../../docs/adr/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). */
export class ConfigRefused extends Error {
  code: string;
  params: TextParams;

  // Node strips types: `pnpm typecheck` is what refuses a refusal without its code.
  constructor(code: string, message: string, params: TextParams = {}) {
    super(message);
    this.code = code;
    this.params = params;
  }
}

export const refuse = (path: string, kind: string, words: string) => new ConfigRefused('config.problem', words, { path, problem: kind });

export const isObject = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null && !Array.isArray(value);

/** The file as the person has it; one that is not there, is not JSON or is not an object is refused and left as it is: the app never makes the engine's config. */
export function readObject(file: string): Record<string, unknown> {
  let current: unknown;
  try {
    current = JSON.parse(readFileSync(file, 'utf8'));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') throw refuse('(file)', 'notFound', `${file} is not there, so it was not changed`);
    if (error instanceof SyntaxError) throw refuse('(file)', 'notJson', `${file} is not valid JSON, so it was not changed`);
    throw error;
  }
  if (isObject(current) === false) throw refuse('(file)', 'notAnObject', `${file} is not a JSON object, so it was not changed`);
  return current as Record<string, unknown>;
}

/** Checks the whole result as the engine loads it (the defaults under it, the accounts of `providers.json`), then writes it; nothing is written when it is refused. */
export function write(file: string, next: Record<string, unknown>, folder: string) {
  const accounts = readProvidersFile(folder);
  if (accounts.ok === false) throw refuse('(providers.json)', 'invalid', providersProblem(folder, accounts.errors));
  const checked = loadConfig(defaults, next, accounts.providers);
  if (checked.ok === false) {
    const first = checked.errors[0]!;
    const problem = configProblem(first);
    const words = `${first.path}: ${first.message}`;
    throw problem ? new ConfigRefused(problem.code, words, problem.params) : new ConfigRefused('config.problem', words, { path: first.path, problem: 'invalid' });
  }
  const temporary = `${file}.${process.pid}.${randomUUID()}.tmp`;
  try {
    writeFileSync(temporary, `${JSON.stringify(next, null, 2)}\n`);
    renameSync(temporary, file);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
}

/** `carrier init` makes the whole file: the folder it goes in is made when it is not there, then it is checked and written like every other write of `engine.json`. */
export function saveEngineConfig(config: Record<string, unknown>, file: string, folder: string) {
  mkdirSync(dirname(file), { recursive: true });
  write(file, config, folder);
}

const folderOf = (name: string) => name.split('/').pop()!.toLowerCase();

/** The first thing the engine would refuse in the list, in list order; an empty list is fine (nothing is watched yet). */
function reposProblem(names: string[]) {
  names.forEach((name, index) => {
    const path = `repos[${index}]`;
    const earlier = names.slice(0, index);
    if (repoNamePattern.test(name) === false) throw refuse(path, 'notARepo', `${name} must be owner/name`);
    if (earlier.some((other) => other.toLowerCase() === name.toLowerCase())) throw refuse(path, 'alreadyWatched', `${name} is already watched`);
    const clash = earlier.find((other) => folderOf(other) === folderOf(name));
    if (clash !== undefined) throw refuse(path, 'sameFolderName', `${name} has the same folder name as ${clash}; Solve's worktree paths have no owner`);
  });
}

/** The watched repos, as `engine.json` names them. */
export function setWatchedRepos(repos: string[], file: string, folder: string): { saved: { repos: unknown[] } } {
  reposProblem(repos);
  const current = readObject(file);
  const kept = Array.isArray(current.repos) ? current.repos.filter(isObject) : [];
  // a repo that was there keeps its entry as it is; a new one is `{ "name": ... }`
  const next = { ...current, repos: repos.map((name) => kept.find((entry) => entry.name === name) ?? { name }) };
  write(file, next, folder);
  return { saved: { repos: next.repos } };
}

/** The eight values Behavior edits, named as in the file; a value left out is not changed. */
export type BehaviorChanges = {
  pollIntervalMinutes?: number;
  logLevel?: string;
  finishedWindowDays?: number;
  limits?: { maxConcurrentEpics?: number; maxReviews?: number; maxExecutionRetries?: number; maxExecutionHours?: number | 'unlimited'; githubCallTimeoutSeconds?: number };
};

const logLevels = ['debug', 'info', 'warn', 'error'];

function behaviorProblem({ limits = {}, ...top }: BehaviorChanges) {
  const whole = (path: string, value: number | undefined, least: number, words: string) => {
    if (value === undefined) return;
    if (Number.isInteger(value) === false) throw refuse(path, 'notWhole', 'Must be a whole number');
    if (value < least) throw refuse(path, 'tooSmall', words);
  };
  if (top.pollIntervalMinutes !== undefined && top.pollIntervalMinutes <= 0) throw refuse('pollIntervalMinutes', 'tooSmall', 'Must be more than 0');
  if (top.logLevel !== undefined && logLevels.includes(top.logLevel) === false) throw refuse('logLevel', 'notOneOf', `Must be one of ${logLevels.join(', ')}`);
  whole('limits.maxConcurrentEpics', limits.maxConcurrentEpics, 1, 'Must be 1 or more');
  whole('limits.maxReviews', limits.maxReviews, 1, 'Must be 1 or more');
  whole('limits.maxExecutionRetries', limits.maxExecutionRetries, 0, 'Must be 0 or more');
  if (limits.maxExecutionHours !== 'unlimited') whole('limits.maxExecutionHours', limits.maxExecutionHours, 1, 'Must be 1 or more, or unlimited');
  whole('limits.githubCallTimeoutSeconds', limits.githubCallTimeoutSeconds, 1, 'Must be 1 or more');
  if (top.finishedWindowDays !== undefined && (Number.isInteger(top.finishedWindowDays) === false || top.finishedWindowDays < 1 || top.finishedWindowDays > 30)) {
    throw refuse('finishedWindowDays', 'outOfRange', 'Must be a whole number from 1 to 30');
  }
}

/** Sets each value in `object`, or takes it out when it equals the engine's default, so the file does not pin what the engine may change later. */
function put(object: Record<string, unknown>, values: Record<string, unknown>, fallback: Record<string, unknown>) {
  for (const [key, value] of Object.entries(values)) {
    if (value === undefined) continue;
    if (value === fallback[key]) delete object[key];
    else object[key] = value;
  }
}

/** The Behavior values; a value equal to the engine's default is taken out of the file, and an emptied `limits` goes with them. */
export function editBehavior(changes: BehaviorChanges, file: string, folder: string): { saved: Record<string, unknown> } {
  behaviorProblem(changes);
  const next = { ...readObject(file) };
  const { limits, ...top } = changes;
  put(next, top, defaults);
  if (limits !== undefined) {
    const own = { ...(isObject(next.limits) ? next.limits : {}) };
    put(own, limits, defaults.limits);
    if (Object.keys(own).length === 0) delete next.limits;
    else next.limits = own;
  }
  write(file, next, folder);
  const asked = (from: Record<string, unknown>, keys: string[]) => Object.fromEntries(keys.filter((key) => key in from).map((key) => [key, from[key]]));
  const kept = isObject(next.limits) ? asked(next.limits, Object.keys(limits ?? {})) : {};
  return { saved: { ...asked(next, Object.keys(top)), ...(Object.keys(kept).length > 0 && { limits: kept }) } };
}
