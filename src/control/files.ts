import { existsSync, lstatSync, readFileSync, realpathSync } from 'node:fs';
import { basename, dirname, join, sep } from 'node:path';
import { and, eq, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import type { Db } from '../storage/db.ts';
import { callerResults } from '../storage/caller-results.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { git } from './epic.ts';
import type { FilesReply } from './replies.ts';

// The reply is bounded: with these it weighs at most about 400 KB, far under the client's 8 MiB line, and says so when it cut.
export const MAX_FILES_PER_SECTION = 500;
export const MAX_FILES = 2_000;
const MAX_SLICES = 100;
const MAX_PATH = 500;
const MAX_UNTRACKED_BYTES = 1024 * 1024;

type Row = { path: string; added: number; removed: number };

/** `git diff --numstat --no-renames -z`: `added<TAB>removed<TAB>path` per record; a binary file counts `-`, taken as 0. */
function parseNumstat(out: string): Row[] {
  return out.split('\0').flatMap((record) => {
    const [, added, removed, path] = /^(\d+|-)\t(\d+|-)\t(.+)$/s.exec(record) ?? [];
    return path === undefined ? [] : [{ path, added: Number(added) || 0, removed: Number(removed) || 0 }];
  });
}

const numstat = (cwd: string, ...range: string[]) => {
  const out = git(cwd, ['diff', '--numstat', '--no-renames', '-z', ...range, '--']);
  return out === null ? null : parseNumstat(out);
};

/** New files a lane has not added yet: no diff exists for them, so lines are counted; a binary or big file counts 0. */
function untracked(cwd: string): Row[] {
  const out = git(cwd, ['ls-files', '--others', '--exclude-standard', '-z']);
  return (out ?? '').split('\0').filter(Boolean).slice(0, MAX_FILES).map((path) => {
    try {
      const file = join(cwd, path);
      const stat = lstatSync(file); // a symlink is not followed: it could point anywhere
      if (stat.isFile() === false || stat.size > MAX_UNTRACKED_BYTES) return { path, added: 0, removed: 0 };
      const text = readFileSync(file);
      if (text.includes(0)) return { path, added: 0, removed: 0 };
      const lines = text.toString('utf8').split('\n').length - 1 + (text.length > 0 && text.at(-1) !== 0x0a ? 1 : 0);
      return { path, added: lines, removed: 0 };
    } catch {
      return { path, added: 0, removed: 0 }; // gone between the listing and the read: the agent is working
    }
  });
}

/** The base the pull request will have: the remote's HEAD, then the usual names; null when the clone has none of them. */
function defaultBase(cwd: string): string | null {
  const refs = new Set((git(cwd, ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin', 'refs/heads/main', 'refs/heads/master']) ?? '').split('\n'));
  return ['refs/remotes/origin/HEAD', 'refs/remotes/origin/main', 'refs/remotes/origin/master', 'refs/heads/main', 'refs/heads/master'].find((ref) => refs.has(ref)) ?? null;
}

/** A folder resolved through symlinks, or null when it is gone. */
function real(path: string): string | null {
  try {
    return realpathSync(path);
  } catch {
    return null;
  }
}

/**
 * The lanes of an epic: `git worktree list` entries named `<epic worktree>--lane-<N>` beside it, with a slice branch checked out
 * (a detached one is a free lane and has no work). Nothing outside the epic's own folder is inspected.
 */
function lanes(workspace: string): { lane: number; path: string }[] {
  const list = git(workspace, ['worktree', 'list', '--porcelain']);
  if (list === null) return [];
  const parent = real(dirname(workspace));
  const prefix = `${basename(workspace)}--lane-`;
  return list.split('\n\n').flatMap((block) => {
    const lines = block.split('\n');
    const path = lines.find((l) => l.startsWith('worktree '))?.slice('worktree '.length);
    const number = path === undefined ? '' : basename(path).slice(prefix.length);
    if (path === undefined || basename(path).startsWith(prefix) === false || /^\d{1,2}$/.test(number) === false) return [];
    if (lines.some((l) => l.startsWith('branch refs/heads/')) === false || existsSync(path) === false) return [];
    return real(dirname(path)) === parent ? [{ lane: Number(number), path }] : [];
  }).sort((a, b) => a.lane - b.lane);
}

/**
 * The files an epic changed, from git and never from GitHub: the lanes' work so far (against the fork point, uncommitted work included),
 * each merged slice (the first-parent merge commits on the epic branch), each fix round (between the heads of its review and its fix),
 * and the epic branch against the default branch as `total`. An epic without a worktree here has nothing to show: empty, not an error.
 * With `executionId`, only that fix round.
 * ponytail: nothing is cached, git is asked on every request (tens of ms); cache a few seconds if the app ever polls faster.
 */
export function filesOf(db: Db, root: string, repo: string, issue: number, executionId?: string): FilesReply | null {
  const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const empty: FilesReply = { sections: [], total: null, truncated: false };
  const workspace = epic.workspace === null ? null : real(epic.workspace);
  const shared = real(root);
  // the folder comes from the database, but it is only read when it really sits under the shared root
  if (workspace === null || shared === null || workspace.startsWith(shared + sep) === false) return empty;
  const branch = git(workspace, ['symbolic-ref', '--short', 'HEAD'])?.trim();
  if (branch === undefined || branch === '') return empty;
  const head = `refs/heads/${branch}`;
  const base = defaultBase(workspace);

  type Draft = { id: string; kind: FilesReply['sections'][number]['kind']; title: string; rows: Row[] };
  const drafts: Draft[] = [];

  const runs = db
    .select({ run: executions, result: callerResults.result })
    .from(executions)
    .leftJoin(callerResults, eq(callerResults.executionId, executions.executionId))
    .where(eq(executions.epicId, epic.id))
    .orderBy(sql`executions.rowid`)
    .all();
  const rounds: Draft[] = [];
  let reviewed: string | null = null;
  for (const { run, result } of runs) {
    if (result === null || run.stage === 'ship') continue;
    const parsed = JSON.parse(result) as CallerResult;
    if (run.stage === 'review') reviewed = parsed.outcome === 'needs_human' ? null : parsed.pr.headSha;
    else if (parsed.outcome === 'completed' && reviewed !== null && (executionId === undefined || executionId === run.executionId)) {
      const rows = numstat(workspace, reviewed, parsed.pr.headSha);
      if (rows !== null) rounds.unshift({ id: run.executionId, kind: 'session', title: `Fix, round ${run.round ?? '?'}`, rows });
    }
  }

  if (executionId === undefined) {
    for (const { lane, path } of lanes(workspace)) {
      const fork = git(path, ['merge-base', head, 'HEAD'])?.trim();
      const tracked = fork ? numstat(path, fork) : null;
      if (tracked !== null) drafts.push({ id: `lane-${lane}`, kind: 'lane', title: `Lane ${lane}`, rows: [...tracked, ...untracked(path)] });
    }
    if (base !== null) {
      const merges = git(workspace, ['log', '--first-parent', '--merges', `--max-count=${MAX_SLICES}`, '--format=%H%x00%s', `${base}..${head}`]) ?? '';
      for (const line of merges.split('\n')) {
        const [sha = '', subject = ''] = line.split('\0');
        // GitHub's own merge subject: `Merge pull request #<pr> from <owner>/<namespace>/<slice number>-<slug>`
        const [, pr, slice] = /^Merge pull request #(\d+) from [^/]+\/.+\/(\d+)-[^/]+$/.exec(subject) ?? [];
        const rows = slice === undefined ? null : numstat(workspace, `${sha}^1`, sha);
        if (rows !== null) drafts.push({ id: `slice-${slice}`, kind: 'merged', title: `Slice #${slice} (PR #${pr})`, rows });
      }
    }
  }
  drafts.push(...rounds);

  // a file two lanes touch says so in both
  const laneFiles = new Map(drafts.filter((d) => d.kind === 'lane').map((d) => [d.id, new Set(d.rows.map((r) => r.path))]));
  let left = MAX_FILES;
  let truncated = false;
  const sections = drafts.map(({ id, kind, title, rows }): FilesReply['sections'][number] => {
    const kept = rows.filter((r) => r.path.length <= MAX_PATH).slice(0, Math.min(MAX_FILES_PER_SECTION, left));
    left -= kept.length;
    truncated ||= kept.length < rows.length;
    return {
      id, kind, title,
      added: rows.reduce((sum, r) => sum + r.added, 0),
      removed: rows.reduce((sum, r) => sum + r.removed, 0),
      files: kept.map(({ path, added, removed }) => ({ path, added, removed, alsoIn: kind === 'lane' ? [...laneFiles].filter(([other, set]) => other !== id && set.has(path)).map(([other]) => other) : [] })),
    };
  });

  const all = base === null ? null : numstat(workspace, `${base}...${head}`);
  const total = all === null ? null : { files: all.length, added: all.reduce((sum, r) => sum + r.added, 0), removed: all.reduce((sum, r) => sum + r.removed, 0) };
  return { sections, total, truncated };
}
