import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readFileSync, realpathSync } from 'node:fs';
import { basename, dirname, join } from 'node:path';
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
const numstat = (card: Pick<Card, 'cwd' | 'range' | 'guard'>) => {
  const out = git(card.cwd, [...card.guard, 'diff', '--numstat', ...SAFE_DIFF, '-z', ...card.range, '--']);
  return out === null ? null : parseNumstat(out);
};

/**
 * `-c` options that keep a worktree's own code from running while it is read: diffing a worktree hashes its edited files through
 * the clean filter (or the long-running `process`) its attributes name, and refreshes through the fsmonitor hook. Every filter the
 * config defines is emptied and not required, so git reads the bytes as they are.
 */
function guardOf(cwd: string): string[] {
  const keys = (git(cwd, ['config', '--list', '--name-only']) ?? '').split('\n');
  const filters = new Set(keys.flatMap((key) => (/^filter\.(.+)\.(?:clean|smudge|process|required)$/i.exec(key)?.[1] ?? [])));
  return ['-c', 'core.fsmonitor=false', ...[...filters].flatMap((name) => ['clean=', 'smudge=', 'process=', 'required=false'].flatMap((set) => ['-c', `filter.${name}.${set}`]))];
}

/** An untracked file as `files` counts it: its text, or why it has none. A symlink is not followed: it could point anywhere. */
function readUntracked(cwd: string, path: string): string | 'binary' | 'too-big' | 'gone' {
  try {
    const file = join(cwd, path);
    const stat = lstatSync(file);
    if (stat.isFile() === false) return 'binary';
    if (stat.size > MAX_UNTRACKED_BYTES) return 'too-big';
    const bytes = readFileSync(file);
    return bytes.includes(0) ? 'binary' : bytes.toString('utf8');
  } catch {
    return 'gone'; // between the listing and the read: the agent is working
  }
}
const lineCount = (text: string) => text.split('\n').length - 1 + (text.length > 0 && text.endsWith('\n') === false ? 1 : 0);
const untrackedPaths = (card: Card) => (git(card.cwd, [...card.guard, 'ls-files', '--others', '--exclude-standard', '-z']) ?? '').split('\0').filter(Boolean).slice(0, MAX_FILES);

/** New files a lane has not added yet: no diff exists for them, so lines are counted; a binary or big file counts 0. */
function untracked(card: Card): Row[] {
  return untrackedPaths(card).map((path) => {
    const text = readUntracked(card.cwd, path);
    return { path, added: text === 'binary' || text === 'too-big' || text === 'gone' ? 0 : lineCount(text), removed: 0 };
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

/** Whether `list` (`git worktree list --porcelain` of the engine's clone) lists `workspace` (a real path), both sides compared by real path. */
function listedByGit(list: string, workspace: string): boolean {
  return list.split('\n').some((line) => line.startsWith('worktree ') && real(line.slice('worktree '.length)) === workspace);
}

/**
 * The lanes of an epic: `git worktree list` entries named `<epic worktree>--lane-<N>` beside it, with a slice branch checked out
 * (a detached one is a free lane and has no work). Nothing outside the epic's own folder is inspected.
 */
function lanes(list: string, workspace: string): { lane: number; path: string }[] {
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

/** `guard` goes before every git command run in `cwd` (`guardOf`); empty where git only reads commits. */
type Card = { id: string; kind: FilesReply['sections'][number]['kind']; title: string; cwd: string; range: string[]; guard: string[] };

/**
 * Every card of an epic and where git is asked over which range: a lane's worktree against its fork point, the epic worktree
 * over `<sha>^1..<sha>` of a merged slice, and over the two heads of a fix round. `filesOf` counts over it and `fileDiff` diffs over it,
 * so the two cannot drift apart. null for an unknown epic, 'none' for one whose worktree git does not list for the engine's clone.
 */
function cardsOf(db: Db, reposDir: string, repo: string, issue: number, executionId?: string): { workspace: string; head: string; base: string | null; cards: Card[] } | 'none' | null {
  const epic = db.select().from(epics).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).get();
  if (epic === undefined) return null;
  const workspace = epic.workspace === null ? null : real(epic.workspace);
  // the folder comes from the database, but it is only read when git lists it for the engine's clone of the repo; asked once per request
  if (workspace === null) return 'none';
  const list = git(join(reposDir, repo), ['worktree', 'list', '--porcelain']); // null: no clone yet
  if (list === null || listedByGit(list, workspace) === false) return 'none';
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
      rounds.unshift({ id: run.executionId, kind: 'session', title: `Fix, round ${run.round ?? '?'}`, cwd: workspace, range: [reviewed, parsed.pr.headSha], guard: [] });
    }
  }

  if (executionId === undefined) {
    for (const { lane, path } of lanes(list, workspace)) {
      const fork = git(path, ['merge-base', head, 'HEAD'])?.trim();
      if (fork) cards.push({ id: `lane-${lane}`, kind: 'lane', title: `Lane ${lane}`, cwd: path, range: [fork], guard: guardOf(path) });
    }
    if (base !== null) {
      const merges = git(workspace, ['log', '--first-parent', '--merges', `--max-count=${MAX_SLICES}`, '--format=%H%x00%s', `${base}..${head}`]) ?? '';
      for (const line of merges.split('\n')) {
        const [sha = '', subject = ''] = line.split('\0');
        // GitHub's own merge subject: `Merge pull request #<pr> from <owner>/<namespace>/<slice number>-<slug>`
        const [, pr, slice] = /^Merge pull request #(\d+) from [^/]+\/.+\/(\d+)-[^/]+$/.exec(subject) ?? [];
        if (slice !== undefined) cards.push({ id: `slice-${slice}`, kind: 'merged', title: `Slice #${slice} (PR #${pr})`, cwd: workspace, range: [`${sha}^1`, sha], guard: [] });
      }
    }
  }
  cards.push(...rounds);
  return { workspace, head, base, cards };
}

/**
 * The files an epic changed, from git and never from GitHub: the lanes' work so far (against the fork point, uncommitted work included),
 * each merged slice (the first-parent merge commits on the epic branch), each fix round (between the heads of its review and its fix),
 * and the epic branch against the default branch as `total`. An epic without a worktree git lists has nothing to show: empty, not an error.
 * With `executionId`, only that fix round.
 * ponytail: nothing is cached, git is asked on every request (tens of ms); cache a few seconds if the app ever polls faster.
 */
export function filesOf(db: Db, reposDir: string, repo: string, issue: number, executionId?: string): FilesReply | null {
  const found = cardsOf(db, reposDir, repo, issue, executionId);
  if (found === null) return null;
  if (found === 'none') return { sections: [], total: null, truncated: false };
  const { workspace, head, base } = found;
  const drafts = found.cards.flatMap((card) => {
    const rows = numstat(card);
    return rows === null ? [] : [{ ...card, rows: card.kind === 'lane' ? [...rows, ...untracked(card)] : rows }];
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

  const all = base === null ? null : numstat({ cwd: workspace, range: [`${base}...${head}`], guard: [] });
  const total = all === null ? null : { files: all.length, added: all.reduce((sum, r) => sum + r.added, 0), removed: all.reduce((sum, r) => sum + r.removed, 0) };
  return { sections, total, truncated };
}

/** The diff text of one file over a range; past the byte cap, the whole lines read so far and `cut`. Nothing the repository configures runs: no driver, no textconv. */
function diffText({ cwd, range, guard }: Card, path: string): { text: string; cut: boolean } {
  try {
    const text = execFileSync('git', [...guard, 'diff', ...SAFE_DIFF, '-U3', ...range, '--', `:(literal)${path}`], { cwd, encoding: 'utf8', timeout: 5_000, maxBuffer: MAX_DIFF_BYTES, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' }, stdio: ['ignore', 'pipe', 'pipe'] });
    return { text, cut: false };
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOBUFS') {
      const partial = String((error as { stdout?: string }).stdout ?? '');
      return { text: partial.slice(0, partial.lastIndexOf('\n') + 1), cut: true }; // the last line may be half read
    }
    throw new Error('git diff failed in an epic worktree', { cause: error }); // the server logs it and answers `internal error`
  }
}

/**
 * The edited fragments of one file of a card: the hunks with three lines of context, an '@' row with git's header before each.
 * null for an unknown epic or card, or a path that is not in the card's own file list: that list is the allowlist, so a pathspec,
 * a `..` or a NUL byte never reaches git. A lane's untracked file is read as `files` counts it, every line a '+'.
 * Redacted as a whole, then cut at MAX_DIFF_ROWS and MAX_LINE.
 */
export function fileDiff(db: Db, reposDir: string, repo: string, issue: number, section: string, path: string): FileDiffReply | null {
  const found = cardsOf(db, reposDir, repo, issue);
  const card = found === null || found === 'none' ? undefined : found.cards.find((c) => c.id === section);
  if (card === undefined || path.length > MAX_PATH) return null;
  let out: string;
  let cut = false;
  if (numstat(card)?.some((r) => r.path === path) === true) {
    ({ text: out, cut } = diffText(card, path));
  } else if (card.kind === 'lane' && untrackedPaths(card).includes(path)) {
    const text = readUntracked(card.cwd, path);
    if (text === 'binary' || text === 'too-big') return { rows: [], truncated: false, note: text };
    const count = text === 'gone' ? 0 : lineCount(text);
    if (text === 'gone' || count === 0) return { rows: [], truncated: false, note: 'no-changes' };
    // the diff git would show once the file is added
    out = `@@ -0,0 +1${count === 1 ? '' : `,${count}`} @@\n` + text.split('\n').slice(0, count).map((line) => `+${line}`).join('\n') + '\n';
  } else {
    return null;
  }
  const all = redact(out).split('\n');
  const first = all.findIndex((line) => line.startsWith('@@'));
  if (first < 0) return { rows: [], truncated: false, note: /^Binary files /m.test(out) ? 'binary' : 'no-changes' };
  let truncated = cut;
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
