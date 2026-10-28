import { realpathSync, statSync } from 'node:fs';
import { isAbsolute, join, sep } from 'node:path';
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
  const realRoot = realOrSelf(root);
  for (const name of engineFolders) {
    const engine = join(realRoot, name);
    if (real === engine || real.startsWith(engine + sep)) throw new ChatRefused(`That folder is inside Carrier's own ${name} folder; a chat never works there`);
  }
  return real;
}
