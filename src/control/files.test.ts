import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics } from '../storage/schema.ts';
import { cardsMemo, fact, fileDiff, filesOf, MAX_DIFF_ROWS, MAX_FACTS, MAX_FILES_PER_SECTION, MAX_LINE } from './files.ts';

// A real temporary repository, as the `epic` request's commit-list test does: the expectations are literals and git's own numbers.
const git = (cwd: string, ...args: string[]) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false', ...args], { cwd, encoding: 'utf8' }).trim();
const lines = (count: number, tag = 'x') => Array.from({ length: count }, (_, i) => `${tag}${i}`).join('\n') + '\n';
const BRANCH = 'feat/x/epic';
const config = { name: 'AshuLab/a', agents: { author: { profile: 'a', option: 'o', harness: 'claude' as const, model: 'm' }, reviewer: { profile: 'b', option: 'o', harness: 'codex' as const, model: 'r' } } };

let root: string;
let repos: string; // the engine's clones: <root>/repos
let db: Db;
let clone: string; // <root>/repos/AshuLab/a
let epic: string; // <root>/worktrees/a/x, on the epic branch
beforeEach(() => {
  root = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-files-')));
  db = openDatabase(join(root, 'carrier.db'));
  const origin = join(root, 'origin.git');
  execFileSync('git', ['init', '-q', '--bare', '-b', 'main', origin]);
  repos = join(root, 'repos');
  clone = join(repos, 'AshuLab', 'a');
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

test('sections come from git: two lanes with uncommitted work, three merged slices, a fix round and the total; a free lane has none', async () => {
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

  const reply = (await filesOf(db, repos, 'AshuLab/a', 1))!;
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
  expect((await filesOf(db, repos, 'AshuLab/a', 1, fixId))!.sections.map((s) => s.id)).toEqual([fixId]);
  expect((await filesOf(db, repos, 'AshuLab/a', 1, '00000000-0000-4000-8000-ffffffffffff'))!.sections).toEqual([]);
});

test('a file two working lanes touch names the other lane; a merged slice is never named; a rename counts as the old path leaving and the new one arriving', async () => {
  slice(101, 201, { 'shared.ts': lines(12, 'shared') }); // merged before the lanes fork
  const first = lane(1, 'feat/x/104-d');
  const second = lane(2, 'feat/x/105-e');
  const third = lane(3, 'feat/x/106-f');
  epicRow();
  // lane 1 renames base.ts and edits shared.ts; lane 2 edits the old name and shared.ts; lane 3 edits only the new name
  git(first, 'mv', 'base.ts', 'renamed.ts');
  writeFileSync(join(first, 'shared.ts'), lines(14, 'shared'));
  writeFileSync(join(second, 'base.ts'), lines(11, 'base'));
  writeFileSync(join(second, 'shared.ts'), lines(13, 'shared'));
  writeFileSync(join(third, 'renamed.ts'), lines(2, 'other'));

  const sections = Object.fromEntries((await filesOf(db, repos, 'AshuLab/a', 1))!.sections.map((s) => [s.id, s]));
  const also = (section: string) => Object.fromEntries(sections[section]!.files.map((f) => [f.path, f.alsoIn]));
  expect(also('lane-1')).toEqual({ 'base.ts': ['lane-2'], 'renamed.ts': ['lane-3'], 'shared.ts': ['lane-2'] });
  expect(also('lane-2')).toEqual({ 'base.ts': ['lane-1'], 'shared.ts': ['lane-1'] });
  expect(also('lane-3')).toEqual({ 'renamed.ts': ['lane-1'] });
  expect(also('slice-101')).toEqual({ 'shared.ts': [] }); // merged work is never flagged, and never named in a lane
});

test('an unknown epic is null; a missing, unset or unlisted worktree gives no sections and no error', async () => {
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toBeNull();
  const empty = { sections: [], total: null, truncated: false };
  const id = epicRow(join(root, 'worktrees', 'a', 'gone'));
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toEqual(empty);
  db.update(epics).set({ workspace: null }).run();
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toEqual(empty);
  // a real repository inside the engine's reach, but git does not list it for the clone: never inspected
  const unlisted = join(root, 'worktrees', 'a', 'unlisted');
  execFileSync('git', ['init', '-q', '-b', 'main', unlisted]);
  db.update(epics).set({ workspace: unlisted }).where(eq(epics.id, id)).run();
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toEqual(empty);
  // nor through a link that leads to it
  symlinkSync(unlisted, join(root, 'worktrees', 'a', 'link'));
  db.update(epics).set({ workspace: join(root, 'worktrees', 'a', 'link') }).where(eq(epics.id, id)).run();
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toEqual(empty);
  // a repo with no clone yet
  db.update(epics).set({ workspace: epic }).where(eq(epics.id, id)).run();
  expect(await filesOf(db, join(root, 'no-clones'), 'AshuLab/a', 1)).toEqual(empty);
});

test('a worktree git lists outside the engine folder is read, with its lanes and merged slices; a link is compared by its real path', async () => {
  const outside = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-outside-')));
  const listed = join(outside, 'x');
  git(clone, 'worktree', 'add', '-q', '-b', 'feat/y/epic', listed, 'main');
  const id = epicRow(listed);
  git(listed, 'checkout', '-q', '-b', 'feat/y/101-s');
  writeFileSync(join(listed, 'a.ts'), lines(2, 'a'));
  git(listed, 'add', '.');
  git(listed, 'commit', '-q', '-m', 'feat: s');
  git(listed, 'checkout', '-q', 'feat/y/epic');
  git(listed, 'merge', '-q', '--no-ff', '-m', 'Merge pull request #201 from AshuLab/feat/y/101-s', 'feat/y/101-s');
  const work = join(outside, 'x--lane-1');
  git(clone, 'worktree', 'add', '-q', '-b', 'feat/y/102-t', work, 'feat/y/epic');
  writeFileSync(join(work, 'b.ts'), lines(3, 'b'));

  const ids = async () => (await filesOf(db, repos, 'AshuLab/a', 1))!.sections.map((s) => s.id);
  expect(await ids()).toEqual(['lane-1', 'slice-101']);
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections[0]).toMatchObject({ added: 3, files: [{ path: 'b.ts' }] });
  // reached through a symlink whose real path is the listed one
  symlinkSync(listed, join(root, 'link'));
  db.update(epics).set({ workspace: join(root, 'link') }).where(eq(epics.id, id)).run();
  expect(await ids()).toEqual(['lane-1', 'slice-101']);
  // a link to a folder git does not list is refused, even when it is a worktree of the same repository on disk
  rmSync(join(root, 'link'));
  symlinkSync(outside, join(root, 'link'));
  expect(await ids()).toEqual([]);
  // a listed worktree deleted from disk answers none and does not fail
  db.update(epics).set({ workspace: listed }).where(eq(epics.id, id)).run();
  rmSync(outside, { recursive: true, force: true });
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toEqual({ sections: [], total: null, truncated: false });
});

test('a lane is only found beside the epic worktree, named after it', async () => {
  epicRow();
  const elsewhere = join(root, 'elsewhere--lane-1');
  git(clone, 'worktree', 'add', '-q', '-b', 'feat/x/106-f', elsewhere, BRANCH);
  writeFileSync(join(elsewhere, 'f.ts'), lines(2, 'f'));
  git(clone, 'worktree', 'add', '-q', '-b', 'feat/x/107-g', join(root, 'worktrees', 'a', 'x--lane-one'), BRANCH);
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections).toEqual([]);
});

test('a diff of thousands of files is cut and says so, while the numbers still count every file', async () => {
  const files = Object.fromEntries(Array.from({ length: 3_000 }, (_, i) => [`f${i}.txt`, 'one\n']));
  slice(101, 201, files);
  epicRow();
  const reply = (await filesOf(db, repos, 'AshuLab/a', 1))!;
  expect(reply.truncated).toBe(true);
  expect(reply.sections).toHaveLength(1);
  expect(reply.sections[0]!.files).toHaveLength(MAX_FILES_PER_SECTION);
  expect(reply.sections[0]).toMatchObject({ added: 3_000, removed: 0 });
  expect(reply.total).toEqual({ files: 3_000, added: 3_000, removed: 0 });
  expect(JSON.stringify(reply).length).toBeLessThan(1024 * 1024);
});

/** A fix round on the epic branch: the review saw the head before, the fix left the head after `files` was committed. */
function fixRound(epicId: number, files: Record<string, string>) {
  const reviewed = git(epic, 'rev-parse', 'HEAD');
  for (const [path, text] of Object.entries(files)) writeFileSync(join(epic, path), text);
  git(epic, 'add', '.');
  git(epic, 'commit', '-q', '-m', 'fix: answer the review');
  run(epicId, 'review', reviewed, 1);
  return run(epicId, 'fix', git(epic, 'rev-parse', 'HEAD'), 1);
}
const diffOf = (section: string, path: string) => fileDiff(db, repos, 'AshuLab/a', 1, section, path);

test('fileDiff answers the hunks of a merged slice and of a fix round, with an @ row before each and three lines of context', async () => {
  slice(101, 201, { 'shared.ts': lines(10, 'shared').replace('shared1\n', 'one\n').replace('shared9\n', 'nine\nten\n'), 'a.ts': lines(2, 'a') });
  const id = epicRow();
  const fixId = fixRound(id, { 'base.ts': lines(10, 'base').replace('base5\n', '') });

  const ctx = (...names: string[]) => names.map((text) => ({ sign: ' ', text }));
  expect(await diffOf('slice-101', 'shared.ts')).toEqual({
    rows: [
      { sign: '@', text: '@@ -1,5 +1,5 @@' }, ...ctx('shared0'), { sign: '-', text: 'shared1' }, { sign: '+', text: 'one' }, ...ctx('shared2', 'shared3', 'shared4'),
      { sign: '@', text: '@@ -7,4 +7,5 @@' }, ...ctx('shared6', 'shared7', 'shared8'), { sign: '-', text: 'shared9' }, { sign: '+', text: 'nine' }, { sign: '+', text: 'ten' },
    ],
    truncated: false,
    note: null,
  });
  expect(await diffOf('slice-101', 'a.ts')).toEqual({ rows: [{ sign: '@', text: '@@ -0,0 +1,2 @@' }, { sign: '+', text: 'a0' }, { sign: '+', text: 'a1' }], truncated: false, note: null });
  expect(await diffOf(fixId, 'base.ts')).toEqual({ rows: [{ sign: '@', text: '@@ -3,7 +3,6 @@' }, ...ctx('base2', 'base3', 'base4'), { sign: '-', text: 'base5' }, ...ctx('base6', 'base7', 'base8')], truncated: false, note: null });

  // the rows add up to the numbers `files` reports for the same card and file
  for (const section of (await filesOf(db, repos, 'AshuLab/a', 1))!.sections) {
    for (const file of section.files) {
      const rows = (await diffOf(section.id, file.path))!.rows;
      expect([rows.filter((r) => r.sign === '+').length, rows.filter((r) => r.sign === '-').length]).toEqual([file.added, file.removed]);
    }
  }
});

test('a binary file, a diff past the byte cap, and a diff past the row caps', async () => {
  slice(101, 201, {
    'image.png': 'PNG\0\x01\x02',
    'big.txt': `${'y'.repeat(99)}\n`.repeat(50_000), // 5 MB
    'long.txt': lines(1_200, 'l'),
    'wide.txt': `${'w'.repeat(MAX_LINE + 50)}\n`,
  });
  epicRow();
  expect(await diffOf('slice-101', 'image.png')).toEqual({ rows: [], truncated: false, note: 'binary' });
  // a tracked diff past the byte cap opens at its first rows and says it was cut
  const big = (await diffOf('slice-101', 'big.txt'))!;
  expect(big).toMatchObject({ truncated: true, note: null });
  expect(big.rows).toHaveLength(MAX_DIFF_ROWS);
  expect(big.rows[0]).toEqual({ sign: '@', text: '@@ -0,0 +1,50000 @@' });
  expect(big.rows[1]).toEqual({ sign: '+', text: 'y'.repeat(99) });
  const long = (await diffOf('slice-101', 'long.txt'))!;
  expect(long).toMatchObject({ truncated: true, note: null });
  expect(long.rows).toHaveLength(MAX_DIFF_ROWS);
  const wide = (await diffOf('slice-101', 'wide.txt'))!;
  expect(wide).toMatchObject({ truncated: true, note: null });
  expect(wide.rows[1]!.text).toHaveLength(MAX_LINE);
});

test('a file whose diff over the range is empty says it has no changes', async () => {
  const id = epicRow();
  const reviewed = git(epic, 'rev-parse', 'HEAD');
  chmodSync(join(epic, 'base.ts'), 0o755);
  git(epic, 'commit', '-q', '-am', 'fix: executable');
  run(id, 'review', reviewed, 1);
  const fixId = run(id, 'fix', git(epic, 'rev-parse', 'HEAD'), 1);
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections[0]!.files).toEqual([{ path: 'base.ts', added: 0, removed: 0, alsoIn: [] }]);
  expect(await diffOf(fixId, 'base.ts')).toEqual({ rows: [], truncated: false, note: 'no-changes' });
});

test('the diff is redacted as a whole before it is split into rows: no secret survives, a key block across lines included', async () => {
  const secrets = [
    'ghp_abcdefghijklmnopqrstuvwxyz0123456789',
    'github_pat_11ABCDEFG0123456789_abcdefghijklmnop',
    'sk-ant-api03-abcdefghijklmnopqrstuv',
    'sk_live_abcdefghijklmnop1234',
    'AKIAABCDEFGHIJKLMNOP',
    'AIzaSyA-abcdefghijklmnopqrstuvwxyz012345',
    'xoxb-1234567890-abcdefghij',
    'glpat-abcdefghijklmnopqrstu',
    'npm_abcdefghijklmnopqrstuvwxyz0123456789',
    'hf_abcdefghijklmnopqrstuvwxyz01234567',
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop',
    'hunter2-database-password',
    'bearer-value-0123456789',
    'MIIEowIBAAKCAQEAsecretkeybody',
    'secondlineofthekeybody',
  ];
  const text = [
    ...secrets.slice(0, 11).map((s, i) => `const t${i} = '${s}';`),
    `DATABASE_PASSWORD=${secrets[11]}`,
    `Authorization: Bearer ${secrets[12]}`,
    '-----BEGIN RSA PRIVATE KEY-----', secrets[13], secrets[14], '-----END RSA PRIVATE KEY-----',
    'after',
  ].join('\n') + '\n';
  slice(101, 201, { 'secrets.txt': text });
  epicRow();
  const reply = (await diffOf('slice-101', 'secrets.txt'))!;
  const all = JSON.stringify(reply);
  for (const secret of secrets) expect(all).not.toContain(secret);
  expect(reply.rows.at(-1)).toEqual({ sign: '+', text: 'after' });
  expect(reply.rows.some((r) => r.text === '[redacted]')).toBe(true);
});

test('a lane answers its own range, uncommitted work and untracked files included: the rows add up to what files counts, and a file two lanes edit answers each lane\'s own lines', async () => {
  const first = lane(1, 'feat/x/104-d');
  const second = lane(2, 'feat/x/105-e');
  epicRow();
  // lane 1: a commit (d.ts), an uncommitted edit of shared.ts, an untracked file; lane 2: another edit of shared.ts, uncommitted
  writeFileSync(join(first, 'd.ts'), lines(2, 'd'));
  git(first, 'add', '.');
  git(first, 'commit', '-q', '-m', 'feat: d');
  writeFileSync(join(first, 'shared.ts'), lines(10, 'shared').replace('shared1\n', 'one\n'));
  writeFileSync(join(first, 'new.ts'), 'n0\nn1\nn2'); // no newline at the end
  writeFileSync(join(second, 'shared.ts'), lines(10, 'shared').replace('shared8\n', ''));
  // untracked, and counted 0: a symlink (never followed), a file over 1 MB, a NUL byte
  symlinkSync(join(root, 'carrier.db'), join(first, 'link.ts'));
  writeFileSync(join(first, 'huge.txt'), `${'h'.repeat(99)}\n`.repeat(11_000));
  writeFileSync(join(first, 'nul.bin'), 'a\0b\n');

  const ctx = (...names: string[]) => names.map((text) => ({ sign: ' ', text }));
  expect(await diffOf('lane-1', 'shared.ts')).toEqual({ rows: [{ sign: '@', text: '@@ -1,5 +1,5 @@' }, ...ctx('shared0'), { sign: '-', text: 'shared1' }, { sign: '+', text: 'one' }, ...ctx('shared2', 'shared3', 'shared4')], truncated: false, note: null });
  expect(await diffOf('lane-2', 'shared.ts')).toEqual({ rows: [{ sign: '@', text: '@@ -6,5 +6,4 @@' }, ...ctx('shared5', 'shared6', 'shared7'), { sign: '-', text: 'shared8' }, ...ctx('shared9')], truncated: false, note: null });
  expect((await diffOf('lane-1', 'd.ts'))!.rows).toEqual([{ sign: '@', text: '@@ -0,0 +1,2 @@' }, { sign: '+', text: 'd0' }, { sign: '+', text: 'd1' }]);
  expect(await diffOf('lane-1', 'new.ts')).toEqual({ rows: [{ sign: '@', text: '@@ -0,0 +1,3 @@' }, { sign: '+', text: 'n0' }, { sign: '+', text: 'n1' }, { sign: '+', text: 'n2' }], truncated: false, note: null });
  expect(await diffOf('lane-1', 'link.ts')).toEqual({ rows: [], truncated: false, note: 'binary' });
  expect(await diffOf('lane-1', 'huge.txt')).toEqual({ rows: [], truncated: false, note: 'too-big' });
  expect(await diffOf('lane-1', 'nul.bin')).toEqual({ rows: [], truncated: false, note: 'binary' });
  expect(await diffOf('lane-2', 'new.ts')).toBeNull(); // another lane's file

  const sections = (await filesOf(db, repos, 'AshuLab/a', 1))!.sections;
  expect(sections.map((s) => [s.id, s.files.map((f) => f.path).sort()])).toEqual([['lane-1', ['d.ts', 'huge.txt', 'link.ts', 'new.ts', 'nul.bin', 'shared.ts']], ['lane-2', ['shared.ts']]]);
  for (const section of sections) {
    for (const file of section.files) {
      const rows = (await diffOf(section.id, file.path))!.rows;
      expect([rows.filter((r) => r.sign === '+').length, rows.filter((r) => r.sign === '-').length]).toEqual([file.added, file.removed]);
    }
  }
});

test('a lane\'s worktree is read without the clean filter or the fsmonitor hook the repository configures', async () => {
  const marker = join(root, 'marker');
  const tool = join(root, 'tool.sh');
  writeFileSync(tool, `#!/bin/sh\ntouch '${marker}'\ncat\n`);
  chmodSync(tool, 0o755);
  const work = lane(1, 'feat/x/104-d');
  git(work, 'config', 'filter.evil.clean', tool);
  git(work, 'config', 'filter.evil.required', 'true');
  git(work, 'config', 'filter.odd.name.process', tool);
  git(work, 'config', 'core.fsmonitor', tool);
  writeFileSync(join(git(work, 'rev-parse', '--git-common-dir'), 'info', 'attributes'), '* filter=evil\n*.ts filter=odd.name\n');
  epicRow();
  writeFileSync(join(work, 'base.ts'), lines(11, 'base'));
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections[0]!.files.map((f) => f.path)).toEqual(['base.ts']);
  expect((await diffOf('lane-1', 'base.ts'))!.rows.filter((r) => r.sign === '+')).toEqual([{ sign: '+', text: 'base10' }]);
  expect(existsSync(marker)).toBe(false);
});

test('an unknown epic, card, or a path not in the card\'s own list is null, a pathspec or a .. or a NUL byte included', async () => {
  slice(101, 201, { 'a.ts': lines(2, 'a'), ':(glob)x': 'odd\n' });
  expect(await diffOf('slice-101', 'a.ts')).toBeNull(); // no epic row yet
  epicRow();
  const work = lane(1, 'feat/x/104-d');
  writeFileSync(join(work, 'a.ts'), lines(3, 'a'));
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections.map((s) => s.id)).toEqual(['lane-1', 'slice-101']);
  expect((await diffOf('lane-1', 'a.ts'))!.rows.filter((r) => r.sign === '+')).toEqual([{ sign: '+', text: 'a2' }]);
  for (const path of ['base.ts', ':(glob)*', '*', 'b/../a.ts', '../a.ts', 'a.ts\0', ':(top)a.ts']) expect(await diffOf('lane-1', path)).toBeNull();
  expect(await diffOf('slice-999', 'a.ts')).toBeNull();
  for (const path of ['base.ts', ':(glob)*', '*', 'b/../a.ts', '../a.ts', 'a.ts\0', '\0', ':(top)a.ts', 'A.TS']) expect(await diffOf('slice-101', path)).toBeNull();
  // a file whose name looks like a pathspec is itself in the list, and is read literally
  expect((await diffOf('slice-101', ':(glob)x'))!.rows).toEqual([{ sign: '@', text: '@@ -0,0 +1 @@' }, { sign: '+', text: 'odd' }]);
});

test('a diff driver or textconv the repository configures never runs', async () => {
  const marker = join(root, 'marker');
  const tool = join(root, 'tool.sh');
  writeFileSync(tool, `#!/bin/sh\ntouch '${marker}'\ncat "$1" 2>/dev/null\n`);
  chmodSync(tool, 0o755);
  git(epic, 'config', 'diff.evil.textconv', tool);
  git(epic, 'config', 'diff.evil.command', tool);
  git(epic, 'config', 'diff.external', tool);
  slice(101, 201, { '.gitattributes': '* diff=evil\n', 'a.ts': lines(2, 'a') });
  epicRow();
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections[0]!.files.map((f) => f.path)).toEqual(['.gitattributes', 'a.ts']);
  expect((await diffOf('slice-101', 'a.ts'))!.rows).toHaveLength(3);
  expect(existsSync(marker)).toBe(false);
});

test('the event loop turns while files and a diff wait for git', async () => {
  for (const [n, pr] of [[101, 201], [102, 202], [103, 203]] as const) slice(n, pr, { [`s${n}.ts`]: lines(5, 's') });
  epicRow();
  // the turns counted at the moment the answer arrives: a synchronous git answers before any timer had its turn
  let turns = 0;
  const tick = setInterval(() => turns++, 0);
  const turnsDuring = async <T>(work: Promise<T>) => {
    turns = 0;
    const value = await work;
    return { value, turns };
  };
  const files = await turnsDuring(filesOf(db, repos, 'AshuLab/a', 1));
  const diff = await turnsDuring(diffOf('slice-101', 's101.ts'));
  clearInterval(tick);
  expect(files.value!.sections).toHaveLength(3);
  expect(files.turns).toBeGreaterThan(0);
  expect(diff.value!.rows.length).toBeGreaterThan(0);
  expect(diff.turns).toBeGreaterThan(0);
});

test('the cards of an epic are read once inside the memo window, once for two requests at once, and again after it', async () => {
  let now = 1_000;
  const memo = cardsMemo(() => now);
  slice(101, 201, { 'a.ts': lines(2, 'a') });
  epicRow();
  const ids = async () => (await filesOf(db, repos, 'AshuLab/a', 1, undefined, memo))!.sections.map((s) => s.id);
  expect(await ids()).toEqual(['slice-101']);
  slice(102, 202, { 'b.ts': lines(2, 'b') });
  expect(await ids()).toEqual(['slice-101']); // the memo still has the cards of the first read
  expect((await fileDiff(db, repos, 'AshuLab/a', 1, 'slice-101', 'a.ts', memo))!.rows).toHaveLength(3);
  now += 5_000;
  expect(await ids()).toEqual(['slice-102', 'slice-101']);
  // without a memo, every request reads again
  slice(103, 203, { 'c.ts': lines(2, 'c') });
  expect(await filesOf(db, repos, 'AshuLab/a', 1).then((r) => r!.sections.map((s) => s.id))).toEqual(['slice-103', 'slice-102', 'slice-101']);
});

test('cardsMemo: one read for two at once, a read apart per key, and a failed read is not kept', async () => {
  let now = 0;
  const memo = cardsMemo(() => now);
  let reads = 0;
  const read = async () => ++reads;
  expect(await Promise.all([memo('a', read), memo('a', read)])).toEqual([1, 1]);
  expect(await memo('b', read)).toBe(2);
  now = 4_999;
  expect(await memo('a', read)).toBe(1);
  now = 5_000;
  expect(await memo('a', read)).toBe(3);
  await expect(memo('f', () => Promise.reject(new Error('git failed')))).rejects.toThrow('git failed');
  expect(await memo('f', read)).toBe(4);
});

test('a filter the repository configures after the cards were remembered is still not run', async () => {
  const marker = join(root, 'marker');
  const tool = join(root, 'tool.sh');
  writeFileSync(tool, `#!/bin/sh\ntouch '${marker}'\ncat\n`);
  chmodSync(tool, 0o755);
  const work = lane(1, 'feat/x/104-d');
  epicRow();
  let now = 0;
  const memo = cardsMemo(() => now);
  writeFileSync(join(work, 'base.ts'), lines(11, 'base'));
  expect((await filesOf(db, repos, 'AshuLab/a', 1, undefined, memo))!.sections[0]!.files.map((f) => f.path)).toEqual(['base.ts']);
  // the agent's worktree gets a filter while the memo still holds the lane: the guard is worked out again for every request
  git(work, 'config', 'filter.evil.clean', tool);
  git(work, 'config', 'filter.evil.required', 'true');
  writeFileSync(join(git(work, 'rev-parse', '--git-common-dir'), 'info', 'attributes'), '* filter=evil\n');
  writeFileSync(join(work, 'base.ts'), lines(12, 'base'));
  expect((await fileDiff(db, repos, 'AshuLab/a', 1, 'lane-1', 'base.ts', memo))!.rows.filter((r) => r.sign === '+')).toEqual([{ sign: '+', text: 'base10' }, { sign: '+', text: 'base11' }]);
  expect((await filesOf(db, repos, 'AshuLab/a', 1, undefined, memo))!.sections[0]!.files.map((f) => f.path)).toEqual(['base.ts']);
  expect(existsSync(marker)).toBe(false);
});

test('an epic whose worktree git did not list is not remembered as having none', async () => {
  const memo = cardsMemo(() => 0);
  slice(101, 201, { 'a.ts': lines(2, 'a') });
  const id = epicRow(null);
  expect(await filesOf(db, repos, 'AshuLab/a', 1, undefined, memo)).toEqual({ sections: [], total: null, truncated: false });
  db.update(epics).set({ workspace: epic }).where(eq(epics.id, id)).run();
  expect((await filesOf(db, repos, 'AshuLab/a', 1, undefined, memo))!.sections.map((s) => s.id)).toEqual(['slice-101']);
});

test('cardsMemo keeps only what the caller says is worth keeping', async () => {
  const memo = cardsMemo(() => 0);
  let reads = 0;
  const read = async () => (++reads < 2 ? null : reads);
  expect(await memo('k', read, (value) => value !== null)).toBeNull();
  expect(await memo('k', read, (value) => value !== null)).toBe(2);
  expect(await memo('k', read, (value) => value !== null)).toBe(2);
  expect(reads).toBe(2);
});

/** How many git processes `work` starts: git's own trace logs one `start` event for each. */
async function spawnsOf(work: () => Promise<unknown>) {
  const trace = join(root, 'trace.json');
  writeFileSync(trace, '');
  process.env.GIT_TRACE2_EVENT = trace;
  try {
    await work();
  } finally {
    delete process.env.GIT_TRACE2_EVENT;
  }
  return readFileSync(trace, 'utf8').split('\n').filter((line) => line.includes('"event":"start"')).length;
}

/** Two lanes with work in them, three merged slices and a fix round: the epic of the first test, with nothing asked twice. */
function busyEpic() {
  slice(101, 201, { 'a.ts': lines(5, 'a') });
  slice(102, 202, { 'b.ts': lines(3, 'b') });
  slice(103, 203, { 'c.ts': lines(7, 'c') });
  const id = epicRow();
  fixRound(id, { 'fix.ts': lines(6, 'fix') });
  const first = lane(1, 'feat/x/104-d');
  const second = lane(2, 'feat/x/105-e');
  writeFileSync(join(first, 'd.ts'), lines(4, 'd'));
  writeFileSync(join(second, 'e.ts'), lines(2, 'e'));
  return { id, first, second };
}

test('files starts 16 git processes the first time and 8 the second: what two commits fix is asked once, a worktree is read every time', async () => {
  busyEpic();
  // first: the worktree list and the refs, the merges and a fork point per lane, per lane its config, numbers and new files,
  // then a card's numbers for each of three slices and one round, and the total
  expect(await spawnsOf(() => filesOf(db, repos, 'AshuLab/a', 1))).toBe(16);
  // second: the list and the refs, and the three of each lane
  expect(await spawnsOf(() => filesOf(db, repos, 'AshuLab/a', 1))).toBe(8);
});

test('what an epic and its lanes did after the first read is read again: a new slice, a lane commit and an edit are never served from what was asked before', async () => {
  const { first } = busyEpic();
  const before = (await filesOf(db, repos, 'AshuLab/a', 1))!;
  expect(before.sections.map((s) => s.id)).toHaveLength(6);
  expect(before.total).toEqual({ files: 4, added: 5 + 3 + 7 + 6, removed: 0 });

  slice(104, 204, { 'g.ts': lines(2, 'g') }); // a new head for the epic
  git(first, 'add', '.');
  git(first, 'commit', '-q', '-m', 'feat: d'); // a new head for the lane
  writeFileSync(join(first, 'd.ts'), lines(9, 'd')); // and an edit
  const after = (await filesOf(db, repos, 'AshuLab/a', 1))!;
  expect(after.sections.map((s) => s.id).slice(0, 3)).toEqual(['lane-1', 'lane-2', 'slice-104']);
  expect(after.sections[0]).toMatchObject({ added: 9, files: [{ path: 'd.ts', added: 9 }] });
  expect(after.total).toEqual({ files: 5, added: 5 + 3 + 7 + 6 + 2, removed: 0 });

  // a lane put back on an older commit has another fork point with the same epic head
  git(first, 'reset', '-q', '--hard', 'main');
  const reset = (await filesOf(db, repos, 'AshuLab/a', 1))!;
  expect(reset.sections[0]).toMatchObject({ id: 'lane-1', added: 0, removed: 0, files: [] });
});

test('a card whose commits git could not read is asked again, not remembered as empty', async () => {
  const id = epicRow();
  const reviewed = git(epic, 'rev-parse', 'HEAD');
  // a fix that is in another clone only: this one cannot read its range yet
  const other = join(root, 'other');
  git(root, 'clone', '-q', clone, other);
  git(other, 'checkout', '-q', '-b', 'fixed', `origin/${BRANCH}`);
  writeFileSync(join(other, 'fix.ts'), lines(4, 'fix'));
  git(other, 'add', '.');
  git(other, 'commit', '-q', '-m', 'fix: answer the review');
  const fixed = git(other, 'rev-parse', 'HEAD');
  run(id, 'review', reviewed, 1);
  const fixId = run(id, 'fix', fixed, 1);
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections).toEqual([]);
  git(clone, 'fetch', '-q', other, 'fixed');
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections.map((s) => [s.id, s.added])).toEqual([[fixId, 4]]);
});

test('an epic worktree on a detached head has nothing to show', async () => {
  epicRow();
  git(epic, 'checkout', '-q', '--detach');
  expect(await filesOf(db, repos, 'AshuLab/a', 1)).toEqual({ sections: [], total: null, truncated: false });
});

test('the numbers of a slice of hundreds of files are not remembered', async () => {
  slice(101, 201, Object.fromEntries(Array.from({ length: 201 }, (_, i) => [`f${i}.txt`, 'one\n'])));
  epicRow();
  const first = await spawnsOf(() => filesOf(db, repos, 'AshuLab/a', 1));
  // the merges are remembered, the numbers of the slice and the total are asked again
  expect(await spawnsOf(() => filesOf(db, repos, 'AshuLab/a', 1))).toBe(first - 1);
});

test('fact: one read for two at once, kept for the same key, a failure or null forgotten, the least recently asked dropped past the cap', async () => {
  const key = (name: string) => `${root}\0${name}`;
  let reads = 0;
  const read = async () => ++reads;
  expect(await Promise.all([fact(key('a'), read), fact(key('a'), read)])).toEqual([1, 1]);
  expect(await fact(key('a'), read)).toBe(1);
  await expect(fact(key('f'), () => Promise.reject(new Error('git failed')))).rejects.toThrow('git failed');
  expect(await fact(key('f'), read)).toBe(2);
  expect(await fact(key('n'), async () => null)).toBeNull();
  expect(await fact(key('n'), read)).toBe(3);
  for (let i = 0; i < MAX_FACTS - 3; i++) await fact(key(`fill${i}`), async () => i); // a, f and n are in: the memory is full
  await fact(key('a'), read); // a is the newest again
  await fact(key('one more'), read); // the oldest is out
  expect(await fact(key('a'), read)).toBe(1);
  expect(await fact(key('f'), read)).toBe(5); // dropped, read again (4 was `one more`)
});

test('a later slice that changes how git reads an earlier one (an attribute) is counted again', async () => {
  slice(101, 201, { 'f.lock': lines(2, 'l') });
  epicRow();
  expect((await filesOf(db, repos, 'AshuLab/a', 1))!.sections[0]!.files).toEqual([{ path: 'f.lock', added: 2, removed: 0, alsoIn: [] }]);
  slice(102, 202, { '.gitattributes': '*.lock -diff\n' }); // from now on git reads f.lock as binary, in any range
  const sections = (await filesOf(db, repos, 'AshuLab/a', 1))!.sections;
  expect(sections.map((s) => s.id)).toEqual(['slice-102', 'slice-101']);
  expect(sections[1]!.files).toEqual([{ path: 'f.lock', added: 0, removed: 0, alsoIn: [] }]);
});
