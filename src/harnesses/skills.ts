import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import { readdir, readFile, stat } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { configDirVariable, type HarnessName } from './names.ts';

/** `cannot-tell` is never a reason to stop anything: it means the check could not read somewhere the skill might be. */
export type SkillAnswer = 'present' | 'absent' | 'cannot-tell';

export interface Skills {
  /** Whether the harness, run as the account of `configDir`, finds the skill `name`. `folder` is the repo folder the role will work in, or the repo's clone while its worktree does not exist. */
  has(harness: HarnessName, configDir: string | undefined, folder: string, name: string): Promise<SkillAnswer>;
}

/** What the readers need from the machine, replaceable by a test. */
export interface SkillsDeps {
  /** The user's home; `~/.claude` and `~/.codex` are the account's folder when it has no `configDir`. */
  home: string;
  /** The output of `claude plugin list --json` run with `CLAUDE_CONFIG_DIR` set to `configDir` (the process environment when none); rejects when it fails. */
  pluginList: (configDir: string | undefined, folder: string) => Promise<string>;
  /** The output of `agy plugin list --json` run in `folder`; rejects when it fails. */
  agyPluginList: (folder: string) => Promise<string>;
  /** The folder Codex reads for every user of the machine. */
  codexSystemSkills: string;
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

/** The names in a folder; a folder that is not there has none. */
async function entriesOf(dir: string): Promise<string[]> {
  try {
    return await readdir(dir);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === 'ENOENT' || code === 'ENOTDIR') return [];
    throw error;
  }
}

/** `a:b` is the skill `b` of the plugin `a`; a bare name is the skill of any plugin. */
function splitName(name: string): { plugin: string | undefined; skill: string } {
  const colon = name.indexOf(':');
  return colon < 0 ? { plugin: undefined, skill: name } : { plugin: name.slice(0, colon), skill: name.slice(colon + 1) };
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

async function claudeHas(deps: SkillsDeps, configDir: string | undefined, folder: string, name: string): Promise<SkillAnswer> {
  try {
    const user = configDir ?? join(deps.home, '.claude');
    const places = [join(user, 'skills', name, 'SKILL.md'), join(user, 'commands', `${name}.md`), ...folderAndParents(folder).map((dir) => join(dir, '.claude', 'skills', name, 'SKILL.md'))];
    for (const place of places) if (await exists(place)) return 'present';
    const { plugin, skill } = splitName(name);
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

async function codexHas(deps: SkillsDeps, configDir: string | undefined, folder: string, name: string): Promise<SkillAnswer> {
  try {
    // It does not run `codex debug prompt-input`: that is a debug command that may change, so only the folders are read.
    const user = configDir ?? join(deps.home, '.codex');
    const skills = [join(user, 'skills'), join(user, 'skills', '.system'), join(deps.home, '.agents', 'skills'), ...folderAndParents(folder).map((dir) => join(dir, '.agents', 'skills')), deps.codexSystemSkills];
    for (const place of skills) if (await exists(join(place, name, 'SKILL.md'))) return 'present';
    // <marketplace>/<plugin>/<version>/skills/<name>/SKILL.md
    const { plugin, skill } = splitName(name);
    const cache = join(user, 'plugins', 'cache');
    for (const market of await entriesOf(cache)) {
      for (const found of await entriesOf(join(cache, market))) {
        if (plugin !== undefined && plugin !== found) continue;
        for (const version of await entriesOf(join(cache, market, found))) {
          if (await exists(join(cache, market, found, version, 'skills', skill, 'SKILL.md'))) return 'present';
        }
      }
    }
    return 'absent';
  } catch (error) {
    log.warn('could not read everywhere Codex looks for a skill', { skill: name, error: error instanceof Error ? error.message : String(error) });
    return 'cannot-tell';
  }
}

/** The `entries` of a `skills.json` that point inside `inside` (anywhere when none), and whether it filters skills with `include_only` or `exclude`. Throws when it cannot be read; a manifest that is not there has none. */
async function manifestOf(file: string, base: string, inside?: string): Promise<{ places: string[]; filters: boolean }> {
  let text: string;
  try {
    text = await readFile(file, 'utf8');
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return { places: [], filters: false };
    throw error;
  }
  const manifest: { entries?: unknown; include_only?: unknown; exclude?: unknown } = JSON.parse(text);
  const entries = manifest.entries ?? [];
  if (!Array.isArray(entries)) throw new Error(`${file} has no list of entries`);
  const places: string[] = [];
  let filters = manifest.include_only !== undefined || manifest.exclude !== undefined;
  for (const entry of entries as { path?: unknown; include_only?: unknown; exclude?: unknown }[]) {
    if (typeof entry.path !== 'string') throw new Error(`an entry of ${file} has no path`);
    filters ||= entry.include_only !== undefined || entry.exclude !== undefined;
    const place = resolve(base, entry.path);
    const path = inside === undefined ? '' : relative(inside, place);
    if (!path.startsWith('..') && !isAbsolute(path)) places.push(place);
  }
  return { places, filters };
}

async function agyHas(deps: SkillsDeps, folder: string, name: string): Promise<SkillAnswer> {
  let sure = true;
  // A place that cannot be read leaves the answer open, but a later place may still have the skill.
  const attempt = async (what: string, read: () => Promise<boolean>) => {
    try {
      return await read();
    } catch (error) {
      sure = false;
      log.warn('could not read where Antigravity looks for a skill', { skill: name, where: what, error: error instanceof Error ? error.message : String(error) });
      return false;
    }
  };
  const gemini = join(deps.home, '.gemini');
  const inFolders = async (places: string[]) => {
    for (const place of places) if (await exists(join(place, name, 'SKILL.md'))) return true;
    return false;
  };
  const inManifest = (file: string, base: string, inside?: string) => async () => {
    const { places, filters } = await manifestOf(file, base, inside);
    // A filter may hide a skill that is on disk, so what the manifest points at proves nothing: the answer stays open unless another place has it.
    if (filters) {
      sure = false;
      return false;
    }
    return inFolders(places);
  };
  const folders = [join(folder, '.agents', 'skills'), join(folder, '.agent', 'skills'), join(gemini, 'config', 'skills'), join(gemini, 'antigravity-cli', 'skills'), join(gemini, 'skills'), join(gemini, 'antigravity', 'builtin', 'skills')];
  if (await attempt('folders', () => inFolders(folders))) return 'present';
  if (await attempt('the manifest of the folder', inManifest(join(folder, '.agents', 'skills.json'), folder, folder))) return 'present';
  if (await attempt('the manifest of the user', inManifest(join(gemini, 'config', 'skills.json'), gemini))) return 'present';
  const { plugin, skill } = splitName(name);
  const inPlugins = async () => {
    const list: unknown = JSON.parse(await deps.agyPluginList(folder));
    if (!Array.isArray(list)) throw new Error('the plugin list is not an array');
    for (const entry of list as { name?: unknown; path?: unknown; enabled?: unknown }[]) {
      if (entry.enabled === false) continue;
      if (typeof entry.name !== 'string' || typeof entry.path !== 'string') throw new Error('a plugin has no name or no path');
      if (plugin !== undefined && plugin !== entry.name) continue;
      if (await exists(join(entry.path, 'skills', skill, 'SKILL.md'))) return true;
    }
    return false;
  };
  if (await attempt('the plugin list', inPlugins)) return 'present';
  return sure ? 'absent' : 'cannot-tell';
}

/** The readers of the three harnesses; each answers absent only when it read every place its harness reads. */
export function createSkills(deps: SkillsDeps = realDeps): Skills {
  return {
    has: async (harness, configDir, folder, name) => {
      if (harness === 'claude') return claudeHas(deps, configDir, folder, name);
      if (harness === 'codex') return codexHas(deps, configDir, folder, name);
      return agyHas(deps, folder, name);
    },
  };
}

const realDeps: SkillsDeps = {
  home: homedir(),
  codexSystemSkills: '/etc/codex/skills',
  agyPluginList: (folder) =>
    new Promise((resolve, reject) => {
      const cwd = existsSync(folder) ? folder : undefined;
      execFile('agy', ['plugin', 'list', '--json'], { cwd, timeout: 20_000, maxBuffer: 10 * 1024 * 1024 }, (error, stdout) => (error ? reject(error) : resolve(stdout)));
    }),
  pluginList: (configDir, folder) =>
    new Promise((resolve, reject) => {
      const env = configDir ? { ...process.env, [configDirVariable.claude]: configDir } : process.env;
      // The folder decides which plugins the repo enables; the clone may not exist yet, and then the process runs where it is.
      const cwd = existsSync(folder) ? folder : undefined;
      execFile('claude', ['plugin', 'list', '--json'], { env, cwd, timeout: 20_000, maxBuffer: 10 * 1024 * 1024 }, (error, stdout) => (error ? reject(error) : resolve(stdout)));
    }),
};
