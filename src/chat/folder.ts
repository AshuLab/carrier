import { realpathSync, statSync } from 'node:fs';
import { basename, dirname, isAbsolute, join, sep } from 'node:path';
import { ChatRefused } from './runner.ts';

// A session never works in the engine's shared clones, in an epic's worktree or in the engine's own state.
const engineFolders = ['repos', 'worktrees', 'orchestrator'];

const realOrSelf = (path: string) => {
  try {
    return realpathSync(path);
  } catch {
    return path;
  }
};

/** The real path of the folder a session may work in, or a `ChatRefused` saying why not. A symlink into an engine folder is refused too. */
export function checkFolder(folder: string, root: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('The folder must be an absolute path');
  let real: string;
  try {
    real = realpathSync(folder);
  } catch {
    throw new ChatRefused('That folder does not exist');
  }
  if (statSync(real).isDirectory() === false) throw new ChatRefused('That path is not a folder');
  refuseEngineFolder(real, root);
  return real;
}

function refuseEngineFolder(real: string, root: string) {
  const realRoot = realOrSelf(root);
  for (const name of engineFolders) {
    const engine = join(realRoot, name);
    if (real === engine || real.startsWith(engine + sep)) throw new ChatRefused(`That folder is inside Carrier's own ${name} folder; a chat never works there`);
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

/** The projects folder as the host will use it (it may not exist yet), or a `ChatRefused` saying why not. The engine-folder rule of `checkFolder`, with symlinks resolved. */
export function checkProjectsFolder(folder: string, root: string): string {
  if (isAbsolute(folder) === false) throw new ChatRefused('The projects folder must be an absolute path');
  const real = realOfNearest(folder);
  refuseEngineFolder(real, root);
  return folder;
}
