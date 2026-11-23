import { randomUUID } from 'node:crypto';
import { mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { z } from 'zod';
import { carrierHome, projectsPathOf } from './places.ts';

// `projects.json` (ADR 0041): the person's projects, read by the app and the chat host and written by both.
// `macos/Sources/CarrierCore/ProjectsFile.swift` checks the same rules; `projects.test.ts` writes the fixture its contract test reads.

const text = z.string().regex(/\S/, 'must not be blank');
const nonEmpty = z.string().min(1, 'must not be empty');

/** One command a project runs as a step of a preparation (ADR 0039). */
const action = z.strictObject({
  name: text,
  command: text,
  when: z.enum(['newWorktree', 'afterClone']),
  on: z.boolean().optional(),
  onFail: z.enum(['warn', 'stop']).optional(),
});

/** One project, identified by its folder. Only what the person sets: the remote, branch, worktrees and sizes are derived. */
export const projectEntry = z.strictObject({
  /** Absolute or `~`; the identity, never repeated in the file. */
  path: z.string().refine((path) => /^(\/|~(\/|$))/.test(path), 'must be an absolute path or start with ~/'),
  /** The folder's name when absent. */
  name: text.optional(),
  origin: z.enum(['cloned', 'created', 'added']),
  pinned: z.boolean().optional(),
  hidden: z.boolean().optional(),
  /** Trimmed, lower case, no repeats. */
  tags: z.array(text.refine((tag) => tag === tag.trim().toLowerCase(), 'must be trimmed and lower case')).refine((tags) => new Set(tags).size === tags.length, 'must not repeat a tag').optional(),
  /** `image` is a file name in the app's project-icons folder. */
  icon: z.strictObject({ color: nonEmpty.optional(), mark: nonEmpty.optional(), image: nonEmpty.optional() }).optional(),
  /** Absent means the same as everywhere. */
  defaults: z.strictObject({ agent: nonEmpty.optional(), model: nonEmpty.optional(), effort: nonEmpty.optional(), access: z.record(nonEmpty, nonEmpty).optional(), workIn: z.enum(['baseFolder', 'worktree']).optional(), baseBranch: nonEmpty.optional() }).optional(),
  actions: z.array(action).optional(),
});
export type ProjectEntry = z.infer<typeof projectEntry>;

const projectsFileSchema = z.strictObject({ projects: z.array(projectEntry).default([]) });

export type ProjectsError = { path: string; message: string };
export type ProjectsResult = { ok: true; projects: ProjectEntry[] } | { ok: false; errors: ProjectsError[] };

/** The entries from the parsed contents of `projects.json` (`{}` is no projects). Each problem names its field; an unknown key is named as a field of its own. */
export function loadProjects(json: unknown): ProjectsResult {
  const parsed = projectsFileSchema.safeParse(json);
  if (!parsed.success) {
    const errors = parsed.error.issues.flatMap((issue) =>
      issue.code === 'unrecognized_keys'
        ? issue.keys.map((key) => ({ path: [...issue.path, key].join('.'), message: 'is not a key of projects.json' }))
        : [{ path: issue.path.join('.') || '(root)', message: issue.message }]);
    return { ok: false, errors };
  }
  // ponytail: exact string compare, so `~/x` and its absolute form count as two projects; resolve both if that ever bites.
  const seen = new Set<string>();
  const repeated = parsed.data.projects.flatMap((entry, index) => (seen.size === seen.add(entry.path).size ? [{ path: `projects.${index}.path`, message: `repeats the path of an earlier project (${entry.path})` }] : []));
  return repeated.length > 0 ? { ok: false, errors: repeated } : { ok: true, projects: parsed.data.projects };
}

/** `projects.json` as the folder has it; no file is no projects, one that cannot be read or does not match is an error naming the field. */
export function readProjectsFile(folder = carrierHome()): ProjectsResult {
  let json: unknown = {};
  try {
    json = JSON.parse(readFileSync(projectsPathOf(folder), 'utf8'));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') return { ok: false, errors: [{ path: '(file)', message: error instanceof SyntaxError ? `is not valid JSON: ${error.message}` : 'cannot be read' }] };
  }
  return loadProjects(json);
}

/**
 * Changes the projects: reads the file again now, gives `change` what is there, checks what it returns and writes the whole file through a temporary
 * file and a rename. A file that does not match, or a result that would not, is refused with the field named and nothing is written.
 * The window between the read and the rename is the one the app's writer has too (docs/specs/projects.md, Who writes what).
 */
export function updateProjectsFile(change: (current: ProjectEntry[]) => ProjectEntry[], folder = carrierHome()): ProjectsResult {
  const current = readProjectsFile(folder);
  if (!current.ok) return current;
  const next = loadProjects({ projects: change(current.projects) });
  if (!next.ok) return next;
  const file = projectsPathOf(folder);
  const temporary = `${file}.${process.pid}.${randomUUID()}.tmp`;
  mkdirSync(dirname(file), { recursive: true });
  try {
    writeFileSync(temporary, `${JSON.stringify({ projects: next.projects }, null, 2)}\n`);
    renameSync(temporary, file);
  } catch (error) {
    rmSync(temporary, { force: true });
    throw error;
  }
  return next;
}
