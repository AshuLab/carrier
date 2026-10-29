import { realpathSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, sep } from 'node:path';
import { ChatRefused } from './runner.ts';

// A session never works in the engine's folder (ADR 0016); the projects folder also stays out of the chat's own state, logs and worktrees.
const engineFolders = ['engine'];
const chatOwnFolders = [...engineFolders, join('chat', 'state'), join('chat', 'logs'), join('chat', 'worktrees')];

const realOrSelf = (path: string) => {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
};

/** The real path of the folder a session may work in, or a `ChatRefused` saying why not. A symlink into an engine folder is refused too. */
export function checkFolder(folder: string, home: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('The folder must be an absolute path');
  let real: string;
  try {
    real = realpathSync(folder);
  } catch {
    throw new ChatRefused('That folder does not exist');
  }
  if (statSync(real).isDirectory() === false) throw new ChatRefused('That path is not a folder');
  refuseInside(real, home, engineFolders);
  return real;
}

function refuseInside(real: string, home: string, names: string[]) {
  const realHome = realOrSelf(home);
  for (const name of names) {
    const refused = join(realHome, name);
    if (real === refused || real.startsWith(refused + sep)) throw new ChatRefused(`That folder is inside Carrier's own ${name} folder; a chat never works there`);
  }
}

// The real path of a path that may not exist yet: its nearest existing ancestor, resolved, plus the rest.
const realOfNearest = (path: string): string => {
  try {
    return realpathSync(path);
  } catch {
    const parent = dirname(path);
    return parent === path ? path : join(realOfNearest(parent), basename(path));
  }
};

/** The projects folder as the host will use it (it may not exist yet), or a `ChatRefused` saying why not. The engine-folder rule of `checkFolder` plus the chat's own state, logs and worktrees, with symlinks resolved. */
export function checkProjectsFolder(folder: string, home: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('The projects folder must be an absolute path');
  const real = realOfNearest(folder);
  refuseInside(real, home, chatOwnFolders);
  return folder;
}
