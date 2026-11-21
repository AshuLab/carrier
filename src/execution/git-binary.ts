import { execFile } from 'node:child_process';
import { accessSync, constants, existsSync } from 'node:fs';
import { join } from 'node:path';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

/** What finding the binary needs from the machine; the tests give their own. */
export type Machine = { platform: string; path: string; executable: (file: string) => boolean; exists: (file: string) => boolean; developerDir: () => Promise<string> };

const machine: Machine = {
  platform: process.platform,
  get path() {
    return process.env.PATH ?? '';
  },
  executable: (file) => {
    try {
      accessSync(file, constants.X_OK);
      return true;
    } catch {
      return false;
    }
  },
  exists: existsSync,
  developerDir: async () => (await execFileAsync('/usr/bin/xcode-select', ['-p'], { encoding: 'utf8', timeout: 2_000 })).stdout.trim(),
};

/**
 * The `git` to start. On a Mac `/usr/bin/git` is not git but a shim that finds the real one through `xcode-select` on every start: about
 * 6 ms more than the real one, for each of the dozens of processes a request makes. When that shim is the `git` the PATH reaches, the real
 * binary of the selected developer folder is the same git without the detour; otherwise (another PATH, another system, no developer
 * folder, anything failing) it is plain `git`, as before.
 */
export async function findGit(on: Machine): Promise<string> {
  if (on.platform !== 'darwin') return 'git';
  try {
    const first = on.path.split(':').filter(Boolean).map((dir) => join(dir, 'git')).find(on.executable);
    if (first !== '/usr/bin/git') return 'git';
    const real = join(await on.developerDir(), 'usr', 'bin', 'git');
    return on.executable(real) ? real : 'git';
  } catch {
    return 'git';
  }
}

/** The runner of a machine: asks `findGit` once, and if the binary it found goes away later (Xcode updated or removed), uses plain `git` from then on. */
export function gitRunner(on: Machine) {
  let found: Promise<string> | undefined;
  return async function withGit<T>(start: (binary: string) => Promise<T>): Promise<T> {
    found ??= findGit(on);
    const binary = await found;
    try {
      return await start(binary);
    } catch (error) {
      if (binary === 'git' || (error as NodeJS.ErrnoException).code !== 'ENOENT' || on.exists(binary)) throw error; // ENOENT also says the folder it ran in is gone
      found = Promise.resolve('git');
      return start('git');
    }
  };
}

/** `start(binary)` with the `git` of this machine: the engine's reads of git and the chat host's `realGit` go through it. */
export const withGit = gitRunner(machine);
