import { lstatSync, realpathSync } from 'node:fs';
import { basename, join, sep } from 'node:path';
import { chatPlacesOf, expandHome } from '../config/places.ts';
import type { Git } from './git.ts';
import { ChatRefused } from './runner.ts';
import { adjectives, places, units } from './words.ts';
import { inspectFolder, type WorkspaceInfo } from './workspace.ts';

/** The answer to `checkName`. */
export type NameCheck = { valid: boolean; free: boolean; reason?: string };

/** Every worktree branch is `carrier/<name>`; a name is the part after this prefix. */
export const BRANCH_PREFIX = 'carrier/';
const MAX_NAME = 60;
const ROLLS = 50;

/** Why `name` cannot be one, in words, or null when it can: lowercase letters, digits, `-`, `_` and `.`, starting with a letter or a digit, at most 60 characters, and a valid git ref name. */
export function invalidReason(name: string): string | null {
  if (name === '') return 'The name is empty';
  if (name.length > MAX_NAME) return `The name is longer than ${MAX_NAME} characters`;
  if (/^[a-z0-9]/.test(name) === false) return 'The name must start with a lowercase letter or a digit';
  if (/^[a-z0-9._-]+$/.test(name) === false) return 'The name may only have lowercase letters, digits, hyphens, underscores and dots';
  if (name.includes('..')) return 'The name cannot have two dots in a row';
  if (name.endsWith('.')) return 'The name cannot end with a dot';
  if (name.endsWith('.lock')) return 'The name cannot end with .lock';
  return null;
}

/** `<adjective>-<unit>-<place>`, each word picked with `random` (a number in [0, 1), `Math.random` by default). */
export function generateName(random: () => number = Math.random): string {
  const pick = (words: string[]) => words[Math.floor(random() * words.length)]!;
  return `${pick(adjectives)}-${pick(units)}-${pick(places)}`;
}

/** Where every session worktree lives. */
export const worktreesDir = () => chatPlacesOf().worktrees;

/** The folder of `worktrees/` a repository's worktrees live in: `<owner>/<repo>`, or `local/<folder name>` without a GitHub origin. */
export const worktreeDirectory = (info: WorkspaceInfo) => (info.repo === null ? join('local', basename(info.folder)) : join(info.repo.owner, info.repo.name));

/** Where a worktree called `name` of this repository lives: `<CARRIER_HOME>/chat/worktrees/<owner>/<repo>/<name>`, or `local/<folder name>` without a GitHub origin. A path that would lie anywhere else is refused. */
export function worktreePath(info: WorkspaceInfo, name: string): string {
  const path = join(worktreesDir(), worktreeDirectory(info), name);
  if (path.startsWith(worktreesDir() + sep) === false) throw new ChatRefused('That worktree would not be inside Carrier\'s worktrees folder');
  return path;
}

const real = (path: string) => {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
};

/**
 * Refuses `folder` (already checked, a real path) as a project when its worktree directory (`worktreeDirectory`, the one `worktreePath` makes) is the one of
 * another of `projects`, naming it (ADR 0041). Compared without regard to case, as the disk may. A project whose folder git cannot read is skipped.
 */
export async function checkWorktreeClash(git: Git, folder: string, projects: { path: string; name?: string }[]): Promise<void> {
  const mine = worktreeDirectory(await inspectFolder(git, folder)).toLowerCase();
  for (const project of projects) {
    const path = real(expandHome(project.path));
    if (path === folder) continue; // already a project, not a clash
    const other = await inspectFolder(git, path).catch(() => null);
    if (other !== null && worktreeDirectory(other).toLowerCase() === mine) throw new ChatRefused(`The worktrees of ${project.name ?? basename(path)} already use the folder ${worktreeDirectory(other)}; two projects cannot share it`);
  }
}

/** Whether something is at `path`. Only a path that cannot exist answers false; any other error is not a free name. */
const exists = (path: string) => {
  try {
    lstatSync(path);
    return true;
  } catch (error) {
    if (['ENOENT', 'ENOTDIR'].includes((error as NodeJS.ErrnoException).code ?? '')) return false;
    throw error;
  }
};

/** What a name is up against in a repository: the three places where `carrier/<name>` must not exist yet. */
export async function repository(git: Git, folder: string) {
  const info = await inspectFolder(git, folder);
  if (info.git === false) throw new ChatRefused('Worktrees need a git repository');
  if (info.bare) throw new ChatRefused('Worktrees need a git repository with a working folder, and this one is bare');
  const has = (branch: string) => info.branches.some((candidate) => candidate.name === branch);
  /** Why a valid name is taken, in words, or null when it is free. */
  const takenBecause = (name: string) => {
    if (has(`${BRANCH_PREFIX}${name}`)) return `A branch called ${BRANCH_PREFIX}${name} already exists`;
    if (has(`origin/${BRANCH_PREFIX}${name}`)) return `The remote already has a branch called ${BRANCH_PREFIX}${name}`;
    if (exists(worktreePath(info, name))) return 'A folder for that worktree already exists';
    return null;
  };
  /** A generated name that is free, rolled again while it is taken and never numbered. */
  const freeName = (random: () => number = Math.random) => {
    for (let roll = 0; roll < ROLLS; roll++) {
      const name = generateName(random);
      if (takenBecause(name) === null) return name;
    }
    throw new ChatRefused(`Every name that was tried (${ROLLS}) is already taken; type one instead`);
  };
  return { info, takenBecause, freeName };
}

/** A free name for a worktree of `folder` (already checked, a real path). */
export async function suggestName(git: Git, folder: string, random?: () => number): Promise<{ name: string }> {
  return { name: (await repository(git, folder)).freeName(random) };
}

/** Whether a name typed for a worktree of `folder` (already checked, a real path) is valid and free, and why not when it is not. */
export async function checkName(git: Git, folder: string, name: string): Promise<NameCheck> {
  const { takenBecause } = await repository(git, folder);
  const invalid = invalidReason(name);
  if (invalid !== null) return { valid: false, free: false, reason: invalid };
  const taken = takenBecause(name);
  return taken === null ? { valid: true, free: true } : { valid: true, free: false, reason: taken };
}
