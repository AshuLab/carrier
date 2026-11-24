import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import type { EpicReply, EventsReply, FileDiffReply, FilesReply, SessionsReply } from './replies.ts';

// The contract with the macOS app: its tests decode these files (macos/Tests/CarrierCoreTests/RepliesTests.swift).
// UPDATE_FIXTURES=1 rewrites them. Each sample has a value for every field, in every variant the app must draw.
// `dev`: the copy in macos/DevFixtures, which the app run on fixtures reads, is written and checked too.
function golden(name: string, reply: object, dev = false) {
  for (const folder of dev ? ['Tests/Fixtures', 'DevFixtures'] : ['Tests/Fixtures']) {
    const file = fileURLToPath(new URL(`../../macos/${folder}/reply-${name}.json`, import.meta.url));
    const json = `${JSON.stringify(reply, null, 2)}\n`;
    if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
    expect(json).toBe(readFileSync(file, 'utf8'));
  }
}

const claude = { harness: 'claude', model: 'claude-sonnet-5-5', provider: null } as const;
const codex = { harness: 'codex', model: 'gpt-5', provider: 'ollama' } as const;

test('the sessions reply equals reply-sessions.json', () => {
  const sessions: SessionsReply = {
    sessions: [
      { executionId: '3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c', stage: 'fix', role: 'author', round: 2, agent: claude, profile: 'acme-author', status: 'running', startedAt: 90_000, finishedAt: null, resume: null, result: null, failure: null },
      {
        executionId: '9a7d1c52-0b3e-4f6a-8d2c-1e5f7a9b3c4d', stage: 'review', role: 'reviewer', reviewer: 'reviewer', round: 2, agent: codex, profile: 'acme-reviewer', status: 'finished', startedAt: 60_000, finishedAt: 85_000,
        resume: { harness: 'codex', sessionId: 'a1b2c3d4-0001-4000-8000-000000000002', cwd: '/work/acme/web-epic' },
        result: {
          outcome: 'completed', summary: 'Round 2 review of PR #12: no blockers. Review posted at https://github.com/acme/web-epic/pull/12#pullrequestreview-1.',
          verification: { ci: 'passed', evidence: 'CI run concluded success on the head commit.' }, reason: null,
        },
        failure: null,
      },
      {
        executionId: '7b1d4e90-3c2a-4f58-a6e1-9d0b2c4e6f13', stage: 'fix', role: 'author', round: 1, agent: claude, profile: 'acme-author', status: 'failed', startedAt: 45_000, finishedAt: 52_000,
        resume: { harness: 'claude', sessionId: 'c3e5a7b9-1d2f-4a6c-8e0b-5f7d9b1a3c42', cwd: '/work/acme/web-epic' },
        result: null,
        failure: { kind: 'usage_limit', detail: "You've hit your session limit · resets 12:40pm", exitCode: 1, signal: null, hostFreeMemMb: null, hostLoad: null },
      },
      {
        executionId: '1d6f3a90-2c8e-4b57-a4d1-7e9b0c2f5a31', stage: 'fix', role: 'author', round: 1, agent: claude, profile: 'acme-author', status: 'finished', startedAt: 44_500, finishedAt: 58_000,
        resume: { harness: 'claude', sessionId: 'b2c3d4e5-0001-4000-8000-000000000003', cwd: '/work/acme/web-epic' },
        result: { outcome: 'completed', summary: 'Answered the two blockers of round 1 and pushed the fixes.', verification: { ci: 'passed', evidence: 'CI run concluded success on the head commit.' }, reason: null },
        failure: null,
      },
      {
        executionId: '7e2a9d14-6b0c-4f83-9c5e-3a1d8b4f6c20', stage: 'review', role: 'reviewer', reviewer: 'reviewer', round: 1, agent: codex, profile: 'acme-reviewer', status: 'finished', startedAt: 39_000, finishedAt: 44_000,
        resume: { harness: 'codex', sessionId: 'a1b2c3d4-0001-4000-8000-000000000001', cwd: '/work/acme/web-epic' },
        result: { outcome: 'changes_requested', summary: 'Round 1 review of PR #12: two blockers.', verification: null, reason: null },
        failure: null,
      },
      {
        executionId: '5c0e8a14-7d2b-4a93-b6f1-2d8c4e6a0b97', stage: 'ship', role: 'author', round: null, agent: claude, profile: null, status: 'failed', startedAt: 1_000, finishedAt: 39_000,
        resume: { harness: 'claude', sessionId: '91d4be02-6a35-4c1e-9b7f-3e5a7c9d1f20', cwd: '/work/acme/web-epic', configDir: '/Users/dev/.claude-work' },
        result: { outcome: 'needs_human', summary: 'Stopped before opening a pull request.', verification: null, reason: 'The ticket asks for a migration the schema forbids; which of the two wins?' },
        failure: { kind: 'killed', detail: 'SIGKILL', exitCode: null, signal: 'SIGKILL', hostFreeMemMb: 812, hostLoad: 6.4 },
      },
      // a second reviewer of round 1, which gave no verdict (the sample's sessions are not all in order)
      { executionId: '6d3c7a21-8e4b-4c19-b0f2-5a9d1e3c7b84', stage: 'review', role: 'reviewer', reviewer: 'reviewer-2', round: 1, agent: claude, profile: 'acme-reviewer-2', status: 'finished', startedAt: 39_100, finishedAt: 44_000, resume: null, result: { outcome: 'needs_human', summary: 'Could not conclude.', verification: null, reason: 'cannot verify the migration' }, failure: null },
    ],
  };
  golden('sessions', sessions);
});

test('the events reply equals reply-events.json', () => {
  const events: EventsReply = {
    events: [
      { id: 101, at: 1_000, kind: 'say', text: 'I will read the token module first.' },
      { id: 102, at: 1_100, kind: 'tool_start', callId: 'toolu_01', tool: 'Read', arg: 'src/auth/token.ts' },
      { id: 103, at: 1_180, kind: 'tool_end', callId: 'toolu_01', tool: 'Read', summary: '212 lines', status: 'ok', durationMs: 80, output: ['export function sign(', '}'] },
      { id: 104, at: 1_200, kind: 'tool_start', callId: 'toolu_02', tool: 'Edit', arg: 'src/auth/token.ts' },
      {
        id: 105, at: 1_300, kind: 'tool_end', callId: 'toolu_02', tool: 'Edit', summary: 'Edited 1 place', status: 'ok', durationMs: 100,
        diff: [{ sign: ' ', text: 'const ttl = 60;' }, { sign: '-', text: 'const alg = "HS256";' }, { sign: '+', text: 'const alg = "ES256";' }],
      },
      { id: 106, at: 1_400, kind: 'tool_start', callId: 'toolu_03', tool: 'Bash', arg: 'pnpm test' },
      { id: 107, at: 9_400, kind: 'tool_end', callId: 'toolu_03', tool: 'Bash', summary: '2 failed', status: 'err', durationMs: 8_000, output: ['FAIL src/auth/token.test.ts', 'Tests 2 failed'] },
      { id: 108, at: 9_500, kind: 'note', text: 'Output was cut: 4 KB of 90 KB shown.' },
      { id: 109, at: 9_600, kind: 'task', agentId: 'agent-7', text: 'Slice #121: migrate the signer' },
      { id: 110, at: 9_700, kind: 'say', agentId: 'agent-7', text: 'Migrating the signer.' },
      { id: 111, at: 9_800, kind: 'error', text: 'The agent process ended with an error.' },
      // three lanes, each a slice of the epic (the epic reply's closed ones); every lane ends ok after its work, at the end of the list
      { id: 112, at: 9_900, kind: 'tool_start', agentId: 'agent-7', callId: 'toolu_a7', tool: 'Bash', arg: 'cd /work/acme/web-epic--lane-1 && pnpm test' },
      { id: 113, at: 10_900, kind: 'tool_end', agentId: 'agent-7', callId: 'toolu_a7', tool: 'Bash', summary: 'ok', status: 'ok', durationMs: 1_000, output: ['Tests 12 passed'] },
      { id: 114, at: 11_000, kind: 'task', agentId: 'agent-8', text: 'Slice #127: rotate the keys' },
      { id: 115, at: 11_100, kind: 'tool_start', agentId: 'agent-8', callId: 'toolu_a8', tool: 'Edit', arg: '/work/acme/web-epic--lane-2/src/keys.ts' },
      {
        id: 116, at: 11_200, kind: 'tool_end', agentId: 'agent-8', callId: 'toolu_a8', tool: 'Edit', summary: 'Edited 1 place', status: 'ok', durationMs: 100,
        diff: [{ sign: '-', text: 'const keys = [];' }, { sign: '+', text: 'const keys = rotate();' }],
      },
      { id: 117, at: 11_300, kind: 'task', agentId: 'agent-9', text: 'Slice #128: tidy the docs' },
      { id: 118, at: 11_400, kind: 'tool_start', agentId: 'agent-9', callId: 'toolu_a9', tool: 'Read', arg: '/work/acme/web-epic--lane-3/README.md' },
      { id: 119, at: 11_480, kind: 'tool_end', agentId: 'agent-9', callId: 'toolu_a9', tool: 'Read', summary: '40 lines', status: 'ok', durationMs: 80 },
      { id: 120, at: 70_000, kind: 'task', agentId: 'agent-7', text: 'Slice #121: migrate the signer', status: 'ok' },
      { id: 121, at: 130_000, kind: 'task', agentId: 'agent-8', text: 'Slice #127: rotate the keys', status: 'ok' },
      { id: 122, at: 190_000, kind: 'task', agentId: 'agent-9', text: 'Slice #128: tidy the docs', status: 'ok' },
    ],
    next: 122,
    running: true,
    structured: true,
  };
  golden('events', events);
});

test('the epic reply equals reply-epic.json', () => {
  const blocker = (id: string | null, title: string, mark: 'new' | 'carried' | 'fixed', approximate = false) => ({ id, title, url: id ? `https://github.com/acme/web/pull/50#discussion_${id}` : null, mark, approximate });
  const epic: EpicReply = {
    stages: [
      { stage: 'queued', startedAt: 500, endedAt: 1_000 },
      { stage: 'ship', startedAt: 1_000, endedAt: 39_000 },
      { stage: 'review', startedAt: 39_000, endedAt: 60_000, reviewers: ['reviewer', 'reviewer-2'] },
      { stage: 'fix', startedAt: 60_000, endedAt: null },
    ],
    rounds: [
      {
        round: 1, reviewer: codex, verdict: 'changes_requested', reviewMs: 21_000, fixMs: 30_000, reviewedSha: '1111111aaaaaaa', fixedSha: '2222222bbbbbbb',
        blockers: [blocker('b1', 'Token expiry is not checked', 'new'), blocker('b2', 'Missing test for refresh', 'new')],
        // a suggestion next to blockers, for the findings card (the engine lists observations only on an approved review)
        observations: [{ id: 'o0', title: 'Name the expiry constant', url: 'https://github.com/acme/web/pull/50#discussion_o0' }],
        commits: [{ sha: '2222222bbbbbbb', subject: 'fix(auth): check the expiry' }, { sha: '3333333ccccccc', subject: 'test(auth): cover refresh' }],
      },
      {
        round: 2, reviewer: codex, verdict: 'changes_requested', reviewMs: 25_000, fixMs: null, reviewedSha: '4444444ddddddd', fixedSha: null,
        blockers: [blocker('b1', 'Token expiry is not checked', 'fixed'), blocker(null, 'Missing test for refresh', 'carried', true), blocker('b3', 'Log line leaks the subject', 'new')],
        observations: [],
        commits: [],
      },
      {
        round: 3, reviewer: codex, verdict: 'approved', reviewMs: 18_000, fixMs: null, reviewedSha: '5555555eeeeeee', fixedSha: null,
        blockers: [],
        // one with its comment, one a reviewer gave no id or link
        observations: [{ id: 'o1', title: 'Rename the helper', url: 'https://github.com/acme/web/pull/50#discussion_o1' }, { id: null, title: 'Prefer a const here', url: null }],
        commits: [],
        // a round of two reviewers: the mandatory one's above, the other's here with its slot
        otherReviewers: [{ slot: 'reviewer-2', agent: claude, verdict: 'changes_requested', blockers: [blocker('B1', 'Use the shared helper', 'new')], observations: [{ id: null, title: 'Prefer a const here', url: null }] }],
      },
      {
        round: 5, reviewer: codex, verdict: 'limit_reached', reviewMs: 20_000, fixMs: null, reviewedSha: '6666666fffffff', fixedSha: null,
        blockers: [blocker('b3', 'Log line leaks the subject', 'carried')],
        observations: [],
        commits: [],
      },
    ],
    slices: [
      { number: 121, title: 'Request schemas', state: 'closed', blockedBy: [], prNumber: 130, prState: 'merged', prMergedAt: 49_000, closedAt: 50_000, readAt: 99_000 },
      { number: 122, title: 'Rejected idea', state: 'skipped', blockedBy: [], prNumber: null, prState: null, prMergedAt: null, closedAt: 51_000, readAt: 99_000 },
      { number: 123, title: 'Sessions request', state: 'in_progress', blockedBy: [], prNumber: 131, prState: 'draft', prMergedAt: null, closedAt: null, readAt: 99_000, lane: 1, activity: 'Edit /work/acme/web-epic--lane-1/src/control/sessions.ts' },
      { number: 124, title: 'Events request', state: 'waiting', blockedBy: [121, 123], prNumber: null, prState: null, prMergedAt: null, closedAt: null, readAt: 99_000 },
      { number: 125, title: 'Files request', state: 'ready', blockedBy: [], prNumber: null, prState: null, prMergedAt: null, closedAt: null, readAt: 99_000 },
      { number: 126, title: 'Watch request', state: 'waiting', blockedBy: [124], prNumber: null, prState: null, prMergedAt: null, closedAt: null, readAt: 99_000 },
      { number: 127, title: 'Key rotation', state: 'closed', blockedBy: [], prNumber: 132, prState: 'merged', prMergedAt: 52_000, closedAt: 53_000, readAt: 99_000 },
      { number: 128, title: 'Docs tidy', state: 'closed', blockedBy: [], prNumber: 133, prState: 'merged', prMergedAt: 54_000, closedAt: 55_000, readAt: 99_000 },
    ],
    slicesTruncated: false,
    threads: [
      { id: 'PRRT_kwDOexample01', path: 'src/control/server.ts', line: 42, resolved: false, outdated: false, author: 'reviewer-1', bot: false, firstLine: 'This should validate the repo name first.', commentCount: 3, url: 'https://github.com/acme/web/pull/50#discussion_r1001' },
      { id: 'PRRT_kwDOexample02', path: 'src/control/epic.ts', line: null, resolved: true, outdated: true, author: null, bot: true, firstLine: '', commentCount: 1, url: 'https://github.com/acme/web/pull/50#discussion_r1002' },
    ],
    threadsTruncated: false,
    worktrees: [
      { kind: 'epic', lane: null, path: '/work/acme/web-epic' },
      { kind: 'lane', lane: 1, path: '/work/acme/web-epic--lane-1' },
    ],
    branch: 'feat/issue-12/epic',
    unansweredObservations: { count: 2, reason: 'already_taken' },
    pr: { number: 50, url: 'https://github.com/acme/web/pull/50', draft: false, mergeState: 'CLEAN', reviewDecision: null, checks: { passing: 3, failing: 1, pending: 0 } },
  };
  golden('epic', epic);
});

test('the files reply equals reply-files.json', () => {
  const files: FilesReply = {
    sections: [
      {
        id: 'lane-1', kind: 'lane', title: 'Lane 1', added: 41, removed: 6,
        files: [
          { path: 'src/auth/token.ts', added: 30, removed: 6, alsoIn: ['lane-2'] },
          { path: 'src/auth/token.test.ts', added: 11, removed: 0, alsoIn: [] },
        ],
      },
      { id: 'lane-2', kind: 'lane', title: 'Lane 2', added: 4, removed: 1, files: [{ path: 'src/auth/token.ts', added: 4, removed: 1, alsoIn: ['lane-1'] }] },
      { id: 'merged', kind: 'merged', title: 'Merged slices', added: 120, removed: 12, files: [{ path: 'src/control/server.ts', added: 120, removed: 12, alsoIn: [] }] },
      { id: '3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c', kind: 'session', title: 'Fix, round 2', added: 0, removed: 0, files: [] },
    ],
    total: { files: 3, added: 165, removed: 19 },
    truncated: false,
  };
  golden('files', files);
});

test('the fileDiff replies equal reply-filediff.json: one with hunks, one with a note', () => {
  const hunks: FileDiffReply = {
    rows: [
      { sign: '@', text: '@@ -1,4 +1,5 @@' },
      { sign: ' ', text: "import { sign } from './sign.ts';" },
      { sign: '-', text: 'const alg = "HS256";' },
      { sign: '+', text: 'const alg = "ES256";' },
      { sign: '+', text: 'const ttl = 60;' },
      { sign: ' ', text: '' },
      { sign: ' ', text: 'export function token() {' },
      { sign: '@', text: '@@ -40,3 +41,3 @@' },
      { sign: ' ', text: '  const claims = read();' },
      { sign: '-', text: '  return sign(claims);' },
      { sign: '+', text: '  return sign(claims, alg);' },
      { sign: ' ', text: '}' },
    ],
    truncated: true,
    note: null,
  };
  const binary: FileDiffReply = { rows: [], truncated: false, note: 'binary' };
  golden('filediff', [hunks, binary], true);
});
