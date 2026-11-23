import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { configDirVariable, type HarnessName } from './names.ts';

/** `cannot-tell` is never a reason to stop anything: it means the check could not read somewhere the skill might be. */
export type SkillAnswer = 'present' | 'absent' | 'cannot-tell';

export interface Skills {
  /** Whether the harness, run as the account of `configDir`, finds the skill `name`. `folder` is the repo folder the role will work in, or the repo's clone while its worktree does not exist. */
  has(harness: HarnessName, configDir: string | undefined, folder: string, name: string): Promise<SkillAnswer>;
}

/** What the Claude reader needs from the machine, replaceable by a test. */
export interface ClaudeSkillsDeps {
  /** The user's home; `~/.claude` is the account's folder when it has no `configDir`. */
  home: string;
  /** The output of `claude plugin list --json` run with `CLAUDE_CONFIG_DIR` set to `configDir` (the process environment when none); rejects when it fails. */
  pluginList: (configDir: string | undefined, folder: string) => Promise<string>;
}

const log = createScopedLogger('skills');

/** A file or folder that is not there is a no; any other failure (permissions, for one) means the place was not read. */
async function exists(path: string): Promise<boolean> {
  try {
    await stat(path);
    return true;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === 'ENOENT' || code === 'ENOTDIR') return false;
    throw error;
  }
}

/** The folder and each parent up to the first one that holds `.git` (a folder, or the file of a linked worktree); only the folder itself when none does. */
function folderAndParents(folder: string): string[] {
  const found: string[] = [];
  for (let dir = folder; ; dir = dirname(dir)) {
    found.push(dir);
    if (existsSync(join(dir, '.git'))) return found;
    if (dirname(dir) === dir) return [folder];
  }
}

/** The plugins `claude plugin list --json` reports as available: enabled ones, or enabled by the repo. Throws on anything it cannot read. */
function pluginsOf(output: string): { plugin: string; installPath: string }[] {
  const list: unknown = JSON.parse(output);
  if (!Array.isArray(list)) throw new Error('the plugin list is not an array');
  return list.flatMap((entry: { id?: unknown; installPath?: unknown; enabled?: unknown; projectEnabled?: unknown }) => {
    if (entry.enabled === false && entry.projectEnabled !== true) return [];
    if (typeof entry.id !== 'string' || typeof entry.installPath !== 'string') throw new Error('a plugin has no id or no install path');
    return [{ plugin: entry.id.split('@')[0]!, installPath: entry.installPath }];
  });
}

async function claudeHas(deps: ClaudeSkillsDeps, configDir: string | undefined, folder: string, name: string): Promise<SkillAnswer> {
  try {
    const user = configDir ?? join(deps.home, '.claude');
    const places = [join(user, 'skills', name, 'SKILL.md'), join(user, 'commands', `${name}.md`), ...folderAndParents(folder).map((dir) => join(dir, '.claude', 'skills', name, 'SKILL.md'))];
    for (const place of places) if (await exists(place)) return 'present';
    // `a:b` is the skill `b` of the plugin `a`; a bare name is the skill of any plugin.
    const [plugin, skill] = name.includes(':') ? [name.slice(0, name.indexOf(':')), name.slice(name.indexOf(':') + 1)] : [undefined, name];
    for (const found of pluginsOf(await deps.pluginList(configDir, folder))) {
      if (plugin !== undefined && plugin !== found.plugin) continue;
      if (await exists(join(found.installPath, 'skills', skill, 'SKILL.md'))) return 'present';
    }
    return 'absent';
  } catch (error) {
    log.warn('could not read everywhere Claude Code looks for a skill', { skill: name, error: error instanceof Error ? error.message : String(error) });
    return 'cannot-tell';
  }
}

/** The Claude reader; Codex and Antigravity have none yet and always cannot tell, so nothing is ever reported absent for them. */
export function createSkills(deps: ClaudeSkillsDeps = realClaudeDeps): Skills {
  return {
    has: async (harness, configDir, folder, name) => {
      if (harness === 'claude') return claudeHas(deps, configDir, folder, name);
      log.debug('no reader of skills for this harness yet: cannot tell', { harness, skill: name });
      return 'cannot-tell';
    },
  };
}

const realClaudeDeps: ClaudeSkillsDeps = {
  home: homedir(),
  pluginList: (configDir, folder) =>
    new Promise((resolve, reject) => {
      const env = configDir ? { ...process.env, [configDirVariable.claude]: configDir } : process.env;
      // The folder decides which plugins the repo enables; the clone may not exist yet, and then the process runs where it is.
      const cwd = existsSync(folder) ? folder : undefined;
      execFile('claude', ['plugin', 'list', '--json'], { env, cwd, timeout: 20_000, maxBuffer: 10 * 1024 * 1024 }, (error, stdout) => (error ? reject(error) : resolve(stdout)));
    }),
};
