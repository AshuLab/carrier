import { accessSync, constants, existsSync, readFileSync, realpathSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { chatPlacesOf, enginePlacesOf } from '../config/places.ts';
import { ChatRefused } from './runner.ts';

// A session never works in the engine's folder (ADR 0034); the projects folder also stays out of the chat's own state, logs, worktrees, pending and sessions.
const engineFolders = (home: string) => [enginePlacesOf(home).dir];
const chatOwnFolders = (home: string) => [...engineFolders(home), chatPlacesOf(home).state, chatPlacesOf(home).logs, chatPlacesOf(home).worktrees, chatPlacesOf(home).pending, chatPlacesOf(home).sessions];

// The real path of a path that may not exist yet: its nearest existing ancestor, resolved, plus the rest.
export const realOfNearest = (path: string): string => {
  try {
    return realpathSync(path);
  } catch {
    const parent = dirname(path);
    return parent === path ? path : join(realOfNearest(parent), basename(path));
  }
};

/** The real path of the folder a session may work in, or a `ChatRefused` saying why not. A symlink into an engine folder is refused too. */
export function checkFolder(folder: string, home: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('folder.notAbsolute', 'The folder must be an absolute path');
  let real: string;
  try {
    real = realpathSync(folder);
  } catch {
    throw new ChatRefused('folder.missing', 'That folder does not exist');
  }
  if (statSync(real).isDirectory() === false) throw new ChatRefused('folder.notDirectory', 'That path is not a folder');
  const inside = insideCarrier(real, home, engineFolders);
  if (inside !== undefined) throw new ChatRefused('folder.insideCarrier', `That folder is inside Carrier's own ${inside} folder; a chat never works there`, { folder: inside });
  return real;
}

/** The Carrier folder (relative to the home) that `real` lies in, if any. */
function insideCarrier(real: string, home: string, folders: (home: string) => string[]): string | undefined {
  const realHome = realOfNearest(home);
  const refused = folders(realHome).find((folder) => real === folder || real.startsWith(folder + sep));
  return refused === undefined ? undefined : relative(realHome, refused);
}

/** Whether `folder` (an existing, readable real path) is inside a git worktree linked to another repository. */
function isLinkedWorktree(folder: string): boolean {
  let dir = folder;
  for (;;) {
    const dotGit = join(dir, '.git');
    try {
      const stat = statSync(dotGit);
      if (stat.isDirectory()) return false;
      if (stat.isFile() === false) return false;
      const line = readFileSync(dotGit, 'utf8')
        .split(/\r?\n/)
        .find((entry) => entry.startsWith('gitdir:'));
      if (line === undefined) return false;
      const target = line.slice('gitdir:'.length).trim();
      if (target === '') return false;
      const gitDir = resolve(dir, target);
      const commondir = join(gitDir, 'commondir');
      if (existsSync(commondir) === false) return false;
      return resolve(gitDir, readFileSync(commondir, 'utf8').trim()) !== gitDir;
    } catch {
      // `.git` does not exist here or could not be read; keep walking up unless we hit the root.
    }
    const parent = dirname(dir);
    if (parent === dir) return false;
    dir = parent;
  }
}

/**
 * The real path of a folder that can be added as a project, or a `ChatRefused` saying why not.
 * Refuses relative paths, missing paths, files, unreadable folders, Carrier's own folders (symlinks resolved), and worktrees linked to another project.
 */
export function checkProjectFolder(folder: string, home: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('folder.notAbsolute', 'The folder must be an absolute path');
  let real: string;
  try {
    real = realpathSync(folder);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    throw code === 'EACCES' || code === 'EPERM' ? new ChatRefused('folder.unreadable', 'That folder cannot be read') : new ChatRefused('folder.missing', 'That folder does not exist');
  }
  if (statSync(real).isDirectory() === false) throw new ChatRefused('folder.notDirectory', 'That path is not a folder');
  try {
    accessSync(real, constants.R_OK | constants.X_OK);
  } catch {
    throw new ChatRefused('folder.unreadable', 'That folder cannot be read');
  }
  const inside = insideCarrier(real, home, chatOwnFolders);
  if (inside !== undefined) throw new ChatRefused('folder.projectInsideCarrier', `That folder is inside Carrier's own ${inside} folder; a project cannot live there`, { folder: inside });
  if (isLinkedWorktree(real)) throw new ChatRefused('folder.linkedWorktree', 'That folder is a worktree linked to another project');
  return real;
}

/** The projects folder as the host will use it (it may not exist yet), or a `ChatRefused` saying why not. The engine-folder rule of `checkFolder` plus the chat's own state, logs and worktrees, with symlinks resolved. */
export function checkProjectsFolder(folder: string, home: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('folder.projectsNotAbsolute', 'The projects folder must be an absolute path');
  const real = realOfNearest(folder);
  const inside = insideCarrier(real, home, chatOwnFolders);
  if (inside !== undefined) throw new ChatRefused('folder.insideCarrier', `That folder is inside Carrier's own ${inside} folder; a chat never works there`, { folder: inside });
  return folder;
}
