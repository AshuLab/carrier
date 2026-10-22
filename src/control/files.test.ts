import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { filesOf, MAX_FILES_PER_SECTION } from './files.ts';

// A real temporary repository, as the `epic` request's commit-list test does: the expectations are literals and git's own numbers.
const git = (cwd: string, ...args: string[]) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false', ...args], { cwd, encoding: 'utf8' }).trim();
const lines = (count: number, tag = 'x') => Array.from({ length: count }, (_, i) => `${tag}${i}`).join('\n') + '\n';
const BRANCH = 'feat/x/epic';
const config = { name: 'AshuLab/a', agents: { author: { profile: 'a', harness: 'claude' as const, model: 'm' }, reviewer: { profile: 'b', harness: 'codex' as const, model: 'r' } } };

let root: string;
let db: Db;
let clone: string; // <root>/repos/AshuLab/a
let epic: string; // <root>/worktrees/a/x, on the epic branch
beforeEach(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-files-')));
  db = openDatabase(join(root, 'carrier.db'));
  const origin = join(root, 'origin.git');
  execFileSync('git', ['init', '-q', '--bare', '-b', 'main', origin]);
  clone = join(root, 'repos', 'AshuLab', 'a');
  mkdirSync(join(root, 'repos', 'AshuLab'), { recursive: true });
  execFileSync('git', ['clone', '-q', origin, clone]);
  writeFileSync(join(clone, 'base.ts'), lines(10, 'base'));
  writeFileSync(join(clone, 'shared.ts'), lines(10, 'shared'));
  git(clone, 'add', '.');
  git(clone, 'commit', '-q', '-m', 'chore: base');
  git(clone, 'push', '-q', '-u', 'origin', 'main');
  git(clone, 'remote', 'set-head', 'origin', 'main');
  mkdirSync(join(root, 'worktrees', 'a'), { recursive: true });
  epic = join(root, 'worktrees', 'a', 'x');
  git(clone, 'worktree', 'add', '-q', '-b', BRANCH, epic, 'main');
});
afterEach(() => {
  db.$client.close();
  rmSync(root, { recursive: true, force: true });
});

const epicRow = (workspace: string | null = epic) => db.insert(epics).values({ repo: 'AshuLab/a', issue: 1, status: 'running', config, queuedAt: 1, workspace }).returning({ id: epics.id }).get().id;
let n = 0;
function run(epicId: number, stage: 'ship' | 'review' | 'fix', headSha: string, round: number | null = null) {
  const executionId = `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`;
  db.insert(executions).values({ executionId, epicId, stage, status: 'finished', resultPath: '/r.json', startedAt: n, finishedAt: n + 1, round, harness: 'codex', model: 'r', provider: null, workspace: '/reviews' }).run();
  const result = { outcome: 'completed', pr: { number: 50, headSha } };
  db.insert(callerResults).values({ executionId, outcome: 'completed', result: JSON.stringify(result) }).run();
  return executionId;
}

/** A slice as GitHub merges it: its branch from the epic, a commit, then a merge commit with GitHub's subject. */
function slice(number: number, pr: number, files: Record<string, string>) {
  const branch = `feat/x/${number}-slice`;
  git(epic, 'checkout', '-q', '-b', branch);
  for (const [path, text] of Object.entries(files)) writeFileSync(join(epic, path), text);
  git(epic, 'add', '.');
  git(epic, 'commit', '-q', '-m', `feat: slice ${number}`);
  git(epic, 'checkout', '-q', BRANCH);
  git(epic, 'merge', '-q', '--no-ff', '-m', `Merge pull request #${pr} from AshuLab/${branch}`, branch);
}

function lane(number: number, branch: string | null) {
  const path = join(root, 'worktrees', 'a', `x--lane-${number}`);
  git(clone, 'worktree', 'add', '-q', ...(branch === null ? ['--detach', path, BRANCH] : ['-b', branch, path, BRANCH]));
  return path;
}

test('sections come from git: two lanes with uncommitted work, three merged slices, a fix round and the total; a free lane has none', () => {
  slice(101, 201, { 'a.ts': lines(5, 'a'), 'shared.ts': lines(12, 'shared') }); // +5 a.ts, +2 shared.ts
  slice(102, 202, { 'b.ts': lines(3, 'b') });
  const first = lane(1, 'feat/x/104-d');
  const second = lane(2, 'feat/x/105-e');
  lane(3, null); // free
  slice(103, 203, { 'c.ts': lines(7, 'c'), 'base.ts': lines(4, 'base') }); // after the lanes forked: epic progress is not the lanes' work
  git(epic, 'worktree', 'add', '-q', '--detach', join(root, 'worktrees', 'a', 'y--lane-1')); // another epic's lane

  // lane 1: a commit (+4 d.ts), an uncommitted edit (shared.ts +2 -1), a new untracked file of 3 lines
  writeFileSync(join(first, 'd.ts'), lines(4, 'd'));
  git(first, 'add', '.');
  git(first, 'commit', '-q', '-m', 'feat: d');
  writeFileSync(join(first, 'shared.ts'), lines(12, 'shared').replace('shared0', 'changed0') + 'extra\n');
  writeFileSync(join(first, 'new.ts'), lines(3, 'n'));
  // lane 2: touches the same shared.ts, uncommitted only
  writeFileSync(join(second, 'shared.ts'), lines(9, 'shared')); // -3

  // the fix round: the review saw one head, the fix left another
  const id = epicRow();
  const reviewed = git(epic, 'rev-parse', 'HEAD');
  writeFileSync(join(epic, 'fix.ts'), lines(6, 'fix'));
  git(epic, 'add', '.');
  git(epic, 'commit', '-q', '-m', 'fix: answer the review');
  const fixed = git(epic, 'rev-parse', 'HEAD');
  run(id, 'ship', reviewed);
  run(id, 'review', reviewed, 1);
  const fixId = run(id, 'fix', fixed, 1);

  const reply = filesOf(db, root, 'AshuLab/a', 1)!;
  const byId = Object.fromEntries(reply.sections.map((s) => [s.id, s]));
  expect(reply.sections.map((s) => s.id)).toEqual(['lane-1', 'lane-2', 'slice-103', 'slice-102', 'slice-101', fixId]);
  expect(reply.truncated).toBe(false);

  const file = (section: string, path: string) => byId[section]!.files.find((f) => f.path === path);
  expect(byId['lane-1']).toMatchObject({ kind: 'lane', title: 'Lane 1', added: 4 + 2 + 3, removed: 1 });
  expect(file('lane-1', 'd.ts')).toEqual({ path: 'd.ts', added: 4, removed: 0, alsoIn: [] });
  expect(file('lane-1', 'shared.ts')).toEqual({ path: 'shared.ts', added: 2, removed: 1, alsoIn: ['lane-2'] });
  expect(file('lane-1', 'new.ts')).toEqual({ path: 'new.ts', added: 3, removed: 0, alsoIn: [] });
  expect(byId['lane-2']).toMatchObject({ kind: 'lane', added: 0, removed: 3 });
  expect(byId['lane-2']!.files).toEqual([{ path: 'shared.ts', added: 0, removed: 3, alsoIn: ['lane-1'] }]);

  expect(byId['slice-101']).toMatchObject({ kind: 'merged', title: 'Slice #101 (PR #201)', added: 7, removed: 0 });
  expect(byId['slice-102']!.files).toEqual([{ path: 'b.ts', added: 3, removed: 0, alsoIn: [] }]);
  expect(byId['slice-103']).toMatchObject({ added: 7, removed: 6 });
  expect(byId[fixId]).toMatchObject({ kind: 'session', title: 'Fix, round 1', added: 6, removed: 0, files: [{ path: 'fix.ts', added: 6, removed: 0, alsoIn: [] }] });

  // every section against git itself
  const gitRows = (cwd: string, ...range: string[]) => git(cwd, 'diff', '--numstat', '--no-renames', ...range).split('\n').filter(Boolean).map((l) => l.split('\t'));
  const merges = git(epic, 'log', '--first-parent', '--merges', '--format=%H', 'origin/main..HEAD').split('\n');
  expect(merges).toHaveLength(3);
  for (const [i, number] of [103, 102, 101].entries()) {
    const expected = gitRows(epic, `${merges[i]}^1`, merges[i]!);
    expect(byId[`slice-${number}`]!.files.map((f) => [String(f.added), String(f.removed), f.path])).toEqual(expected);
  }
  const forkOf = (cwd: string) => git(cwd, 'merge-base', BRANCH, 'HEAD');
  expect(byId['lane-1']!.files.filter((f) => f.path !== 'new.ts').map((f) => [String(f.added), String(f.removed), f.path])).toEqual(gitRows(first, forkOf(first)));
  expect(byId['lane-2']!.files.map((f) => [String(f.added), String(f.removed), f.path])).toEqual(gitRows(second, forkOf(second)));
  expect(byId[fixId]!.files.map((f) => [String(f.added), String(f.removed), f.path])).toEqual(gitRows(epic, reviewed, fixed));

  // the total before any pull request: the epic branch against the default branch
  const all = gitRows(epic, `origin/main...${BRANCH}`);
  expect(reply.total).toEqual({ files: all.length, added: all.reduce((s, r) => s + Number(r[0]), 0), removed: all.reduce((s, r) => s + Number(r[1]), 0) });
  expect(reply.total).toEqual({ files: 6, added: 7 + 3 + 7 + 6, removed: 6 });

  // a fix round asked for by itself
  expect(filesOf(db, root, 'AshuLab/a', 1, fixId)!.sections.map((s) => s.id)).toEqual([fixId]);
  expect(filesOf(db, root, 'AshuLab/a', 1, '00000000-0000-4000-8000-ffffffffffff')!.sections).toEqual([]);
});

test('an unknown epic is null; a missing, unset or foreign worktree gives no sections and no error', () => {
  expect(filesOf(db, root, 'AshuLab/a', 1)).toBeNull();
  const empty = { sections: [], total: null, truncated: false };
  const id = epicRow(join(root, 'worktrees', 'a', 'gone'));
  expect(filesOf(db, root, 'AshuLab/a', 1)).toEqual(empty);
  db.update(epics).set({ workspace: null }).run();
  expect(filesOf(db, root, 'AshuLab/a', 1)).toEqual(empty);
  // a real repository, but not under the shared root: never inspected
  const outside = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-outside-')));
  execFileSync('git', ['init', '-q', '-b', 'main', outside]);
  db.update(epics).set({ workspace: outside }).where(eq(epics.id, id)).run();
  expect(filesOf(db, root, 'AshuLab/a', 1)).toEqual(empty);
  // nor through a link that leads out of it
  symlinkSync(outside, join(root, 'worktrees', 'a', 'link'));
  db.update(epics).set({ workspace: join(root, 'worktrees', 'a', 'link') }).where(eq(epics.id, id)).run();
  expect(filesOf(db, root, 'AshuLab/a', 1)).toEqual(empty);
  rmSync(outside, { recursive: true, force: true });
});

test('a lane is only found beside the epic worktree, named after it', () => {
  epicRow();
  const elsewhere = join(root, 'elsewhere--lane-1');
  git(clone, 'worktree', 'add', '-q', '-b', 'feat/x/106-f', elsewhere, BRANCH);
  writeFileSync(join(elsewhere, 'f.ts'), lines(2, 'f'));
  git(clone, 'worktree', 'add', '-q', '-b', 'feat/x/107-g', join(root, 'worktrees', 'a', 'x--lane-one'), BRANCH);
  expect(filesOf(db, root, 'AshuLab/a', 1)!.sections).toEqual([]);
});

test('a diff of thousands of files is cut and says so, while the numbers still count every file', () => {
  const files = Object.fromEntries(Array.from({ length: 3_000 }, (_, i) => [`f${i}.txt`, 'one\n']));
  slice(101, 201, files);
  epicRow();
  const reply = filesOf(db, root, 'AshuLab/a', 1)!;
  expect(reply.truncated).toBe(true);
  expect(reply.sections).toHaveLength(1);
  expect(reply.sections[0]!.files).toHaveLength(MAX_FILES_PER_SECTION);
  expect(reply.sections[0]).toMatchObject({ added: 3_000, removed: 0 });
  expect(reply.total).toEqual({ files: 3_000, added: 3_000, removed: 0 });
  expect(JSON.stringify(reply).length).toBeLessThan(1024 * 1024);
});
