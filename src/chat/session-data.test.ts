import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { FakeClock } from '../orchestration/fake.ts';
import { openChatDatabase } from './db.ts';
import type { Git, GitResult } from './git.ts';
import { infoOf, pickPullRequest, pullRequestKey, type PullRequestInfo, type PullRequests } from './pull-requests.ts';
import { sessions } from './schema.ts';
import { createSessionData, DIFF_TTL_MS, DISCOVER_EVERY_MS, parseNumstat, STATE_TTL_MS, SWEEP_EVERY_MS } from './session-data.ts';

let dir: string;
beforeEach(() => void (dir = mkdtempSync(join(tmpdir(), 'sd-'))));
afterEach(() => rmSync(dir, { recursive: true, force: true }));

/** A git that answers the commands it was told about, by their arguments joined with a space, and fails the others as git does for "not set". */
function scriptedGit(answers: Record<string, string>) {
  const calls: { folder: string; command: string }[] = [];
  const git: Git = {
    // an alias of GitHub in the person's ssh config
    async sshHost(host) {
      return host === 'github.com-emu' ? 'github.com' : host;
    },
    async run(folder, args): Promise<GitResult> {
      const command = args.join(' ');
      calls.push({ folder, command });
      const found = Object.entries(answers).find(([key]) => command === key);
      return found === undefined ? { ok: false, code: 1, stderr: '' } : { ok: true, out: found[1] };
    },
  };
  return { git, calls };
}

class FakePulls implements PullRequests {
  found: Record<string, PullRequestInfo | null> = {};
  open: Record<string, PullRequestInfo> = {};
  finds: string[] = [];
  asked: string[][] = [];
  async find(repo: string, branch: string) {
    this.finds.push(`${repo}:${branch}`);
    return this.found[`${repo}:${branch}`] ?? null;
  }
  async states(refs: { repo: string; number: number }[]) {
    this.asked.push(refs.map((ref) => pullRequestKey(ref.repo, ref.number)));
    return new Map(refs.flatMap((ref) => (this.open[pullRequestKey(ref.repo, ref.number)] === undefined ? [] : [[pullRequestKey(ref.repo, ref.number), this.open[pullRequestKey(ref.repo, ref.number)]!] as const])));
  }
}

const pr = (number: number, state: PullRequestInfo['state'] = 'open', checks: PullRequestInfo['checks'] = null): PullRequestInfo => ({ number, url: `https://github.com/AshuLab/carrier/pull/${number}`, state, checks });
const ORIGIN = 'remote get-url origin';
const DEFAULT = 'symbolic-ref --short refs/remotes/origin/HEAD';

function setup(answers: Record<string, string>, extra: Partial<typeof sessions.$inferInsert> = {}) {
  const db = openChatDatabase(join(dir, 'chat.db'));
  const clock = new FakeClock();
  const { git, calls } = scriptedGit(answers);
  const pulls = new FakePulls();
  const data = createSessionData({ db, git, pulls, clock });
  const id = 's1';
  db.insert(sessions).values({ id, agent: 'claude', harness: 'claude', folder: '/work/app', createdAt: 0, lastActiveAt: 0, ...extra }).run();
  const row = () => db.select().from(sessions).where(eq(sessions.id, id)).get()!;
  return { db, clock, git, calls, pulls, data, id, row };
}

test('a numstat is counted, a binary file counts nothing and no change says nothing', () => {
  expect(parseNumstat('3\t1\ta.ts\n10\t0\tb.ts\n-\t-\timage.png\n')).toEqual({ added: 13, removed: 1 });
  expect(parseNumstat('')).toBeNull();
  expect(parseNumstat('-\t-\timage.png\n')).toBeNull();
});

test('a pull request node says its state and checks, and a closed one has no checks to show', () => {
  const node = (state: string, isDraft: boolean, rollup: string | null) => ({ number: 7, url: 'https://github.com/o/r/pull/7', state, isDraft, commits: { nodes: [{ commit: { statusCheckRollup: rollup === null ? null : { state: rollup } } }] } });
  expect(infoOf(node('OPEN', false, 'SUCCESS'))).toMatchObject({ state: 'open', checks: 'passing' });
  expect(infoOf(node('OPEN', true, 'PENDING'))).toMatchObject({ state: 'draft', checks: 'pending' });
  expect(infoOf(node('OPEN', false, 'FAILURE'))).toMatchObject({ checks: 'failing' });
  expect(infoOf(node('OPEN', false, null))).toMatchObject({ checks: null });
  expect(infoOf(node('MERGED', false, 'SUCCESS'))).toMatchObject({ state: 'merged', checks: null });
  expect(infoOf(node('CLOSED', false, 'FAILURE'))).toMatchObject({ state: 'closed', checks: null });
  expect(infoOf({ number: 'x' })).toBeNull();
});

test('of the pull requests of a branch the newest open one is shown, else the newest, and a fork\'s is not the branch\'s', () => {
  const node = (number: number, state: string, from: string) => ({ number, url: `https://github.com/o/r/pull/${number}`, state, isDraft: false, headRepository: { nameWithOwner: from } });
  // newest first, as GitHub lists them
  expect(pickPullRequest('o/r', [node(9, 'MERGED', 'o/r'), node(8, 'OPEN', 'o/r'), node(7, 'CLOSED', 'o/r')])?.number).toBe(8);
  expect(pickPullRequest('o/r', [node(9, 'MERGED', 'o/r'), node(7, 'CLOSED', 'o/r')])?.number).toBe(9);
  expect(pickPullRequest('o/r', [node(10, 'OPEN', 'someone/r'), node(9, 'MERGED', 'O/R')])?.number).toBe(9);
  expect(pickPullRequest('o/r', [])).toBeNull();
});

test('the pull request is found when origin is an ssh alias of GitHub', async () => {
  const s = setup({ [ORIGIN]: 'git@github.com-emu:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main' });
  s.pulls.found['AshuLab/carrier:feat/x'] = pr(137, 'draft');
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).pr).toMatchObject({ repo: 'AshuLab/carrier', number: 137 });
});

test('a turn counts the lines of a worktree from where it was cut, and says nothing for a clean one', async () => {
  const s = setup(
    { [ORIGIN]: 'git@github.com:AshuLab/carrier.git', [DEFAULT]: 'origin/main', 'merge-base main HEAD': 'abc123\n', 'diff --numstat --no-ext-diff --no-textconv --no-renames abc123 --': '12\t3\ta.ts\n0\t4\tb.ts\n' },
    { folder: '/wt/fix', workspaceKind: 'worktree', worktreeBranch: 'carrier/fix', worktreeFrom: 'main', worktreeBase: '/work/app', worktreePath: '/wt/fix' },
  );
  expect(s.data.view(s.row()).diff).toBeNull(); // not read yet
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).diff).toEqual({ added: 12, removed: 7 });
  // read in the worktree; the repository and its default branch are asked of the base
  expect(s.calls.find((call) => call.command.startsWith('diff'))?.folder).toBe('/wt/fix');
  expect(s.calls.find((call) => call.command === ORIGIN)?.folder).toBe('/work/app');
});

const NUMSTAT = (base: string) => `diff --numstat --no-ext-diff --no-textconv --no-renames ${base} --`;
const WORKTREE = { folder: '/wt/fix', workspaceKind: 'worktree' as const, worktreeBranch: 'carrier/fix', worktreeBase: '/work/app', worktreePath: '/wt/fix' };

test('a worktree counts from the closest merge-base of the local and the remote copy of its start branch', async () => {
  const counted = async (answers: Record<string, string>, worktreeFrom: string) => {
    rmSync(join(dir, 'chat.db'), { force: true });
    const s = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', [DEFAULT]: 'origin/main', ...answers }, { ...WORKTREE, worktreeFrom });
    await s.data.afterTurn(s.id);
    return { diff: s.data.view(s.row()).diff, commands: s.calls.map((call) => call.command) };
  };
  // the local main is behind origin/main and the worktree is up to date with origin/main: an untouched session counts nothing
  const behind = await counted({ 'merge-base main HEAD': 'old\n', 'merge-base origin/main HEAD': 'new\n', 'merge-base --is-ancestor old new': '', [NUMSTAT('new')]: '' }, 'main');
  expect(behind.diff).toBeNull();
  expect(behind.commands).toContain(NUMSTAT('new'));
  // the local main is ahead (not pushed) and the worktree was cut from it: the local one
  const ahead = await counted({ 'merge-base main HEAD': 'local\n', 'merge-base origin/main HEAD': 'remote\n', 'merge-base --is-ancestor remote local': '', [NUMSTAT('local')]: '2\t0\ta\n' }, 'main');
  expect(ahead.diff).toEqual({ added: 2, removed: 0 });
  // the same commit on both sides, or only one copy of the branch
  expect((await counted({ 'merge-base main HEAD': 'same\n', 'merge-base origin/main HEAD': 'same\n', [NUMSTAT('same')]: '1\t1\ta\n' }, 'main')).diff).toEqual({ added: 1, removed: 1 });
  expect((await counted({ 'merge-base origin/main HEAD': 'remote\n', [NUMSTAT('remote')]: '3\t0\ta\n' }, 'main')).diff).toEqual({ added: 3, removed: 0 });
  expect((await counted({ 'merge-base main HEAD': 'local\n', [NUMSTAT('local')]: '4\t0\ta\n' }, 'main')).diff).toEqual({ added: 4, removed: 0 });
  // neither: what is committed
  expect((await counted({ [NUMSTAT('HEAD')]: '5\t0\ta\n' }, 'main')).diff).toEqual({ added: 5, removed: 0 });
});

test('a worktree cut from origin/main counts from its merge-base with origin/main, and origin/origin/main is never tried', async () => {
  const s = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', [DEFAULT]: 'origin/main', 'merge-base origin/main HEAD': 'remote\n', [NUMSTAT('remote')]: '6\t1\ta\n' }, { ...WORKTREE, worktreeFrom: 'origin/main' });
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).diff).toEqual({ added: 6, removed: 1 });
  expect(s.calls.map((call) => call.command).filter((command) => command.startsWith('merge-base'))).toEqual(['merge-base origin/main HEAD']);
});

test('the pull request of a worktree is looked for on the branch checked out now, not the one it was cut with', async () => {
  const s = setup(
    { [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'fix/renamed\n', [DEFAULT]: 'origin/main' },
    { folder: '/wt/fix', workspaceKind: 'worktree', worktreeBranch: 'carrier/fix', worktreeFrom: 'main', worktreeBase: '/work/app', worktreePath: '/wt/fix' },
  );
  s.pulls.found['AshuLab/carrier:fix/renamed'] = pr(1138);
  await s.data.afterTurn(s.id);
  expect(s.pulls.finds).toEqual(['AshuLab/carrier:fix/renamed']);
  expect(s.data.view(s.row()).pr).toMatchObject({ number: 1138 });
  expect(s.calls.find((call) => call.command === 'rev-parse --abbrev-ref HEAD')?.folder).toBe('/wt/fix');
});

test.each([
  ['detached', { 'rev-parse --abbrev-ref HEAD': 'HEAD\n' }],
  ['unreadable', {}],
])('a worktree whose branch is %s falls back to the one it was cut with', async (_case, head) => {
  const s = setup(
    { [ORIGIN]: 'git@github.com:AshuLab/carrier.git', ...head, [DEFAULT]: 'origin/main' },
    { folder: '/wt/fix', workspaceKind: 'worktree', worktreeBranch: 'carrier/fix', worktreeFrom: 'main', worktreeBase: '/work/app', worktreePath: '/wt/fix' },
  );
  s.pulls.found['AshuLab/carrier:carrier/fix'] = pr(7);
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).pr).toMatchObject({ number: 7 });
});

test('a folder on the default branch counts what is not committed, one on its own branch counts from where it left the default', async () => {
  const onMain = setup({ [ORIGIN]: 'https://github.com/AshuLab/carrier', 'rev-parse --abbrev-ref HEAD': 'main\n', [DEFAULT]: 'origin/main', 'diff --numstat --no-ext-diff --no-textconv --no-renames HEAD --': '1\t1\tx\n' });
  await onMain.data.afterTurn(onMain.id);
  expect(onMain.data.view(onMain.row()).diff).toEqual({ added: 1, removed: 1 });
  rmSync(join(dir, 'chat.db'));
  const onBranch = setup({ [ORIGIN]: 'https://github.com/AshuLab/carrier', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main', 'merge-base main HEAD': 'def456\n', 'diff --numstat --no-ext-diff --no-textconv --no-renames def456 --': '5\t0\ty\n' });
  await onBranch.data.afterTurn(onBranch.id);
  expect(onBranch.data.view(onBranch.row()).diff).toEqual({ added: 5, removed: 0 });
});

test('the pull request of the branch is looked for when a turn ends and kept: the link is stored and not asked for again', async () => {
  const s = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main' });
  s.pulls.found['AshuLab/carrier:feat/x'] = pr(983, 'draft');
  expect(s.data.view(s.row()).pr).toBeNull();
  await s.data.afterTurn(s.id);
  expect(s.pulls.finds).toEqual(['AshuLab/carrier:feat/x']);
  expect(s.data.view(s.row()).pr).toEqual({ repo: 'AshuLab/carrier', number: 983, url: 'https://github.com/AshuLab/carrier/pull/983', state: 'draft', checks: null });
  // linked and open: the next turn asks its state by number and does not look for it again
  s.pulls.open['ashulab/carrier#983'] = pr(983, 'open', 'passing');
  await s.data.afterTurn(s.id);
  expect(s.pulls.finds).toHaveLength(1);
  expect(s.pulls.asked).toEqual([['ashulab/carrier#983']]);
  expect(s.data.view(s.row()).pr).toMatchObject({ state: 'open', checks: 'passing' });
});

test('no pull request is looked for on the default branch, detached, or without a GitHub origin', async () => {
  const onMain = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'main\n', [DEFAULT]: 'origin/main' });
  await onMain.data.afterTurn(onMain.id);
  expect(onMain.pulls.finds).toEqual([]);
  rmSync(join(dir, 'chat.db'));
  const detached = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'HEAD\n' });
  await detached.data.afterTurn(detached.id);
  expect(detached.pulls.finds).toEqual([]);
  rmSync(join(dir, 'chat.db'));
  const local = setup({ [ORIGIN]: '/some/where/else.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n' });
  await local.data.afterTurn(local.id);
  expect(local.pulls.finds).toEqual([]);
});

test('a merged pull request is final and gives way only to a newer open one on the same branch', async () => {
  const s = setup(
    { [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main' },
    { prRepo: 'AshuLab/carrier', prNumber: 900, prUrl: 'https://github.com/AshuLab/carrier/pull/900', prState: 'merged', prCheckedAt: 1 },
  );
  s.pulls.found['AshuLab/carrier:feat/x'] = pr(900, 'merged');
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).pr?.number).toBe(900);
  expect(s.pulls.asked).toEqual([]); // a merged one is not asked for
  s.pulls.found['AshuLab/carrier:feat/x'] = pr(950, 'open');
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).pr).toMatchObject({ number: 950, state: 'open' });
  // an open link is never replaced by a find
  s.pulls.found['AshuLab/carrier:feat/x'] = pr(960, 'open');
  await s.data.afterTurn(s.id);
  expect(s.data.view(s.row()).pr?.number).toBe(950);
});

test('a list starts one sweep at most every fifteen seconds, reads a diff again after a minute and asks the open pull requests together', async () => {
  const s = setup(
    { [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main', 'merge-base main HEAD': 'abc\n', 'diff --numstat --no-ext-diff --no-textconv --no-renames abc --': '2\t1\ta\n' },
    { prRepo: 'AshuLab/carrier', prNumber: 5, prUrl: 'https://github.com/AshuLab/carrier/pull/5', prState: 'open', prCheckedAt: 0 },
  );
  s.clock.time = STATE_TTL_MS;
  s.pulls.open['ashulab/carrier#5'] = pr(5, 'open', 'failing');
  const settle = () => new Promise((resolve) => setTimeout(resolve, 5));
  s.data.kick([s.row()]);
  await settle();
  expect(s.data.view(s.row()).diff).toEqual({ added: 2, removed: 1 });
  expect(s.pulls.asked).toEqual([['ashulab/carrier#5']]);
  expect(s.data.view(s.row()).pr).toMatchObject({ checks: 'failing' });
  // asked again at once: nothing runs, and later but inside the interval: nothing either
  s.clock.time += SWEEP_EVERY_MS - 1;
  s.data.kick([s.row()]);
  await settle();
  expect(s.pulls.asked).toHaveLength(1);
  // past the interval but inside the minute: the diff and the state are believed
  s.clock.time += 2;
  s.data.kick([s.row()]);
  await settle();
  expect(s.pulls.asked).toHaveLength(1);
  expect(s.calls.filter((call) => call.command.startsWith('diff'))).toHaveLength(1);
  // a minute after: both are read again
  s.clock.time += DIFF_TTL_MS;
  s.data.kick([s.row()]);
  await settle();
  expect(s.pulls.asked).toHaveLength(2);
  expect(s.calls.filter((call) => call.command.startsWith('diff'))).toHaveLength(2);
});

test('a session with no pull request is looked for again after three minutes and not before', async () => {
  const s = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main' });
  const settle = () => new Promise((resolve) => setTimeout(resolve, 5));
  s.data.kick([s.row()]);
  await settle();
  expect(s.pulls.finds).toHaveLength(1);
  s.clock.time = SWEEP_EVERY_MS + 1;
  s.data.kick([s.row()]);
  await settle();
  expect(s.pulls.finds).toHaveLength(1);
  s.clock.time = DISCOVER_EVERY_MS + 1;
  s.data.kick([s.row()]);
  await settle();
  expect(s.pulls.finds).toHaveLength(2);
});

test('a list with no sessions does not use up the window of the sweep: the first one that has some starts it', async () => {
  const s = setup({ [ORIGIN]: 'git@github.com:AshuLab/carrier.git', 'rev-parse --abbrev-ref HEAD': 'feat/x\n', [DEFAULT]: 'origin/main' });
  s.pulls.found['AshuLab/carrier:feat/x'] = pr(7, 'open');
  const settle = () => new Promise((resolve) => setTimeout(resolve, 5));
  s.data.kick([]);
  s.clock.time = 1_000; // still inside the window the empty list would have taken
  s.data.kick([s.row()]);
  await settle();
  expect(s.data.view(s.row()).pr?.number).toBe(7);
});
