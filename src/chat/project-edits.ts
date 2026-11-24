import { basename, resolve } from 'node:path';
import { carrierHome, expandHome } from '../config/places.ts';
import { readProjectsFile, updateProjectsFile, type ProjectEntry, type ProjectsError } from '../config/projects.ts';
import { editChatSettings } from './config.ts';
import { checkProjectsFolder, realOfNearest } from './folder.ts';
import { ChatRefused } from './runner.ts';

// The changes to `projects.json` (and `projectsFolder` of `chat.json`) the `config` capability answers (ADR 0053): each takes what the Swift function it replaced took,
// reads the file again now, checks the whole result with the file's schema and writes it through `updateProjectsFile`; nothing is written when it refuses.
// The chat host answers them on its socket and `carrier config` runs them when no host answers, so both write the same bytes.

type Entry = Record<string, unknown>;

/** The refusal for a field the file's schema refuses (or a file that does not match): the key path and the kind, with the words the app showed. */
const refusal = ({ path, message, problem }: ProjectsError) => new ChatRefused('config.problem', path === '(file)' || path === '(root)' ? `projects.json ${message}` : `projects.json: ${path} ${message}`, { path, problem });

/** The same folder written two ways: `~` expanded, symlinks resolved, no trailing slash. */
const sameFolder = (a: string, b: string) => realOfNearest(resolve(expandHome(a))) === realOfNearest(resolve(expandHome(b)));

/** Writes what `change` makes of the entries; a refusal of the schema is thrown as a `ChatRefused` and the file stays as it was. */
function write(folder: string, change: (entries: ProjectEntry[]) => ProjectEntry[]): ProjectEntry[] {
  const result = updateProjectsFile(change, folder);
  if (result.ok === false) throw refusal(result.errors[0]!);
  return result.projects;
}

/** Changes the entry at `path` (exact) and answers it as the file has it now. */
function editEntry(path: string, folder: string, change: (entry: Entry, entries: ProjectEntry[]) => Entry): { saved: ProjectEntry } {
  let index = -1;
  const projects = write(folder, (entries) => {
    index = entries.findIndex((entry) => entry.path === path);
    if (index < 0) throw new ChatRefused('project.missing', `No project has the path ${path}`, { path });
    return entries.map((entry, at) => (at === index ? (change({ ...entry }, entries) as ProjectEntry) : entry));
  });
  return { saved: projects[index]! };
}

/** `entry[key]` set to `value`, or taken out when it is null. */
function set(entry: Entry, key: string, value: unknown): Entry {
  if (value === null) delete entry[key];
  else entry[key] = value;
  return entry;
}

/** The sub-keys in `changes` set or removed (null removes), and the object removed when none remain. Every other key of it stays. */
function setIn(entry: Entry, object: string, changes: Record<string, unknown>): Entry {
  const inner: Entry = { ...(entry[object] as Entry | undefined) };
  for (const [key, value] of Object.entries(changes)) if (value !== undefined) set(inner, key, value);
  return set(entry, object, Object.keys(inner).length === 0 ? null : inner);
}

const tag = (text: string) => text.trim().toLowerCase();
/** Trimmed, lower case, no blanks, no repeats, in order. */
const normalizedTags = (tags: string[]) => [...new Set(tags.map(tag).filter((text) => text !== ''))];

/** What a new action is written as: `on: true` and `onFail: warn` are the defaults, so they are left out. */
const encodedAction = ({ on, onFail, ...action }: Entry) => ({ ...action, ...(on !== undefined && on !== true && { on }), ...(onFail !== undefined && onFail !== 'warn' && { onFail }) });

export const projectEdits = {
  /** Adds `folder` as a project of origin `added`, named after it; one already there (the same folder written any way) is not written again. */
  addProject({ folder }: { folder: string }, home = carrierHome()): { added: boolean; saved: ProjectEntry } {
    const current = readProjectsFile(home);
    if (current.ok === false) throw refusal(current.errors[0]!);
    const known = current.projects.find((entry) => sameFolder(entry.path, folder));
    if (known !== undefined) return { added: false, saved: known };
    const added: ProjectEntry = { path: folder, name: basename(folder), origin: 'added' };
    write(home, (entries) => [...entries, added]);
    return { added: true, saved: added };
  },

  /** Takes the entry out; the folder, the worktrees and the sessions are not this file's. */
  removeProject({ path }: { path: string }, home = carrierHome()): { removed: string } {
    write(home, (entries) => {
      if (entries.some((entry) => entry.path === path) === false) throw new ChatRefused('project.missing', `No project has the path ${path}`, { path });
      return entries.filter((entry) => entry.path !== path);
    });
    return { removed: path };
  },

  /** Sets one key of the entry (`name`, `pinned` or `hidden`), or takes it out when `value` is null. */
  editProject({ path, key, value }: { path: string; key: 'name' | 'pinned' | 'hidden'; value: string | boolean | null }, home = carrierHome()) {
    return editEntry(path, home, (entry) => set(entry, key, value));
  },

  /** Points the entry at `folder`; a folder that is another project's, written any way, is refused. Every other key stays. */
  moveProject({ path, folder }: { path: string; folder: string }, home = carrierHome()) {
    return editEntry(path, home, (entry, entries) => {
      const other = entries.findIndex((candidate) => candidate.path !== path && sameFolder(candidate.path, folder));
      if (other >= 0) throw refusal({ path: `projects.${other}.path`, message: "is already another project's folder", problem: 'custom' });
      return set(entry, 'path', folder);
    });
  },

  /** Sets or removes (null) keys of `icon`; `icon` goes when none remains. */
  editProjectIcon({ path, changes }: { path: string; changes: Record<string, unknown> }, home = carrierHome()) {
    return editEntry(path, home, (entry) => setIn(entry, 'icon', changes));
  },

  /** Sets or removes (null) keys of `defaults`; `defaults` goes when none remains. */
  editProjectDefaults({ path, changes }: { path: string; changes: Record<string, unknown> }, home = carrierHome()) {
    return editEntry(path, home, (entry) => setIn(entry, 'defaults', changes));
  },

  /** Takes `remove` out of the tags and puts `add` in, normalized and deduplicated; `tags` goes when none remains. */
  editProjectTags({ path, add, remove }: { path: string; add: string[]; remove: string[] }, home = carrierHome()) {
    const removed = new Set(remove.map(tag));
    return editEntry(path, home, (entry) => {
      const next = normalizedTags([...((entry.tags as string[] | undefined) ?? []).filter((text) => removed.has(text) === false), ...add]);
      return set(entry, 'tags', next.length === 0 ? null : next);
    });
  },

  /** Replaces the actions; one with a blank name or command is refused by the schema, and `actions` goes when none is given. */
  setProjectActions({ path, actions }: { path: string; actions: Entry[] }, home = carrierHome()) {
    return editEntry(path, home, (entry) => set(entry, 'actions', actions.length === 0 ? null : actions.map(encodedAction)));
  },

  /** Writes `projectsFolder` of `chat.json` through its writing code, after refusing a folder inside Carrier's own folders. */
  setProjectsFolder({ folder }: { folder: string }, home = carrierHome()) {
    checkProjectsFolder(folder, home);
    return editChatSettings({ projectsFolder: folder }, home);
  },
};
