import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readFileSync, realpathSync } from 'node:fs';
import { basename, dirname, join, sep } from 'node:path';
import { and, eq, sql } from 'drizzle-orm';
import type { CallerResult } from '../execution/caller-result.ts';
import type { Db } from '../storage/db.ts';
import { callerResults } from '../storage/caller-results.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { redact } from '../logging/redact.ts';
import { git } from './epic.ts';
import type { FileDiffReply, FilesReply } from './replies.ts';

// The reply is bounded: with these it weighs at most about 400 KB, far under the client's 8 MiB line, and says so when it cut.
export const MAX_FILES_PER_SECTION = 500;
export const MAX_FILES = 2_000;
const MAX_SLICES = 100;
const MAX_PATH = 500;
const MAX_UNTRACKED_BYTES = 1024 * 1024;
// a file's diff: past these bytes it is not read, and the rows are cut at the same caps the app draws with
const MAX_DIFF_BYTES = 4 * 1024 * 1024;
export const MAX_DIFF_ROWS = 1_000;
export const MAX_LINE = 2_000;

type Row = { path: string; added: number; removed: number };

/** `git diff --numstat --no-renames -z`: `added<TAB>removed<TAB>path` per record; a binary file counts `-`, taken as 0. */
function parseNumstat(out: string): Row[] {
  return out.split('\0').flatMap((record) => {
    const [, added, removed, path] = /^(\d+|-)\t(\d+|-)\t(.+)$/s.exec(record) ?? [];
    return path === undefined ? [] : [{ path, added: Number(added) || 0, removed: Number(removed) || 0 }];
  });
}

// a driver or a textconv the repository configures never runs: it is the repository's code, and it would skew the numbers
const SAFE_DIFF = ['--no-color', '--no-ext-diff', '--no-textconv', '--no-renames'];
const numstat = (cwd: string, ...range: string[]) => {
  const out = git(cwd, ['diff', '--numstat', ...SAFE_DIFF, '-z', ...range, '--']);
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

type Card = { id: string; kind: FilesReply['sections'][number]['kind']; title: string; cwd: string; range: string[] };

/**
 * Every card of an epic and where git is asked over which range: a lane's worktree against its fork point, the epic worktree
 * over `<sha>^1..<sha>` of a merged slice, and over the two heads of a fix round. `filesOf` counts over it and `fileDiff` diffs over it,
 * so the two cannot drift apart. null for an unknown epic, 'none' for one without a worktree under the shared root.
 */
function cardsOf(db: Db, root: string, repo: string, issue: number, executionId?: string): { workspace: string; head: string; base: string | null; cards: Card[] } | 'none' | null {
  const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const workspace = epic.workspace === null ? null : real(epic.workspace);
  const shared = real(root);
  // the folder comes from the database, but it is only read when it really sits under the shared root
  if (workspace === null || shared === null || workspace.startsWith(shared + sep) === false) return 'none';
  const branch = git(workspace, ['symbolic-ref', '--short', 'HEAD'])?.trim();
  if (branch === undefined || branch === '') return 'none';
  const head = `refs/heads/${branch}`;
  const base = defaultBase(workspace);
  const cards: Card[] = [];

  const runs = db
    .select({ run: executions, result: callerResults.result })
    .from(executions)
    .leftJoin(callerResults, eq(callerResults.executionId, executions.executionId))
    .where(eq(executions.epicId, epic.id))
    .orderBy(sql`executions.rowid`)
    .all();
  const rounds: Card[] = [];
  let reviewed: string | null = null;
  for (const { run, result } of runs) {
    if (result === null || run.stage === 'ship') continue;
    const parsed = JSON.parse(result) as CallerResult;
    if (run.stage === 'review') reviewed = parsed.outcome === 'needs_human' ? null : parsed.pr.headSha;
    else if (parsed.outcome === 'completed' && reviewed !== null && (executionId === undefined || executionId === run.executionId)) {
      rounds.unshift({ id: run.executionId, kind: 'session', title: `Fix, round ${run.round ?? '?'}`, cwd: workspace, range: [reviewed, parsed.pr.headSha] });
    }
  }

  if (executionId === undefined) {
    for (const { lane, path } of lanes(workspace)) {
      const fork = git(path, ['merge-base', head, 'HEAD'])?.trim();
      if (fork) cards.push({ id: `lane-${lane}`, kind: 'lane', title: `Lane ${lane}`, cwd: path, range: [fork] });
    }
    if (base !== null) {
      const merges = git(workspace, ['log', '--first-parent', '--merges', `--max-count=${MAX_SLICES}`, '--format=%H%x00%s', `${base}..${head}`]) ?? '';
      for (const line of merges.split('\n')) {
        const [sha = '', subject = ''] = line.split('\0');
        // GitHub's own merge subject: `Merge pull request #<pr> from <owner>/<namespace>/<slice number>-<slug>`
        const [, pr, slice] = /^Merge pull request #(\d+) from [^/]+\/.+\/(\d+)-[^/]+$/.exec(subject) ?? [];
        if (slice !== undefined) cards.push({ id: `slice-${slice}`, kind: 'merged', title: `Slice #${slice} (PR #${pr})`, cwd: workspace, range: [`${sha}^1`, sha] });
      }
    }
  }
  cards.push(...rounds);
  return { workspace, head, base, cards };
}

/**
 * The files an epic changed, from git and never from GitHub: the lanes' work so far (against the fork point, uncommitted work included),
 * each merged slice (the first-parent merge commits on the epic branch), each fix round (between the heads of its review and its fix),
 * and the epic branch against the default branch as `total`. An epic without a worktree here has nothing to show: empty, not an error.
 * With `executionId`, only that fix round.
 * ponytail: nothing is cached, git is asked on every request (tens of ms); cache a few seconds if the app ever polls faster.
 */
export function filesOf(db: Db, root: string, repo: string, issue: number, executionId?: string): FilesReply | null {
  const found = cardsOf(db, root, repo, issue, executionId);
  if (found === null) return null;
  if (found === 'none') return { sections: [], total: null, truncated: false };
  const { workspace, head, base } = found;
  const drafts = found.cards.flatMap((card) => {
    const rows = numstat(card.cwd, ...card.range);
    return rows === null ? [] : [{ ...card, rows: card.kind === 'lane' ? [...rows, ...untracked(card.cwd)] : rows }];
  });

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

/** The diff text of one file over a range; 'too-big' past the cap. Nothing the repository configures runs: no driver, no textconv. */
function diffText(cwd: string, range: string[], path: string): string | 'too-big' {
  try {
    return execFileSync('git', ['diff', ...SAFE_DIFF, '-U3', ...range, '--', `:(literal)${path}`], { cwd, encoding: 'utf8', timeout: 5_000, maxBuffer: MAX_DIFF_BYTES, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' }, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOBUFS') return 'too-big';
    throw new Error('git diff failed in an epic worktree', { cause: error }); // the server logs it and answers `internal error`
  }
}

/**
 * The edited fragments of one file of a card: the hunks with three lines of context, an '@' row with git's header before each.
 * null for an unknown epic or card, a lane (a later slice), or a path that is not in the card's own file list: that list is the
 * allowlist, so a pathspec, a `..` or a NUL byte never reaches git. Redacted as a whole, then cut at MAX_DIFF_ROWS and MAX_LINE.
 */
export function fileDiff(db: Db, root: string, repo: string, issue: number, section: string, path: string): FileDiffReply | null {
  const found = cardsOf(db, root, repo, issue);
  const card = found === null || found === 'none' ? undefined : found.cards.find((c) => c.id === section);
  if (card === undefined || card.kind === 'lane') return null;
  if (path.length > MAX_PATH || numstat(card.cwd, ...card.range)?.some((r) => r.path === path) !== true) return null;
  const out = diffText(card.cwd, card.range, path);
  if (out === 'too-big') return { rows: [], truncated: false, note: 'too-big' };
  const all = redact(out).split('\n');
  const first = all.findIndex((line) => line.startsWith('@@'));
  if (first < 0) return { rows: [], truncated: false, note: /^Binary files /m.test(out) ? 'binary' : 'no-changes' };
  let truncated = false;
  const rows = all.slice(first).flatMap((line): FileDiffReply['rows'] => {
    const hunk = /^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@/.exec(line);
    if (hunk !== null) return [{ sign: '@', text: hunk[0] }];
    const sign = line[0];
    if (sign !== '+' && sign !== '-' && sign !== ' ') return []; // `\ No newline at end of file`, and the last empty line
    truncated ||= line.length - 1 > MAX_LINE;
    return [{ sign, text: line.slice(1, MAX_LINE + 1) }];
  });
  truncated ||= rows.length > MAX_DIFF_ROWS;
  return { rows: rows.slice(0, MAX_DIFF_ROWS), truncated, note: null };
}
