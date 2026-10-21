import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, test } from 'vitest';
import type { EpicReply, EventsReply, FilesReply, SessionsReply } from './replies.ts';

// The contract with the macOS app: its tests decode these files (macos/Tests/CarrierCoreTests/RepliesTests.swift).
// UPDATE_FIXTURES=1 rewrites them. Each sample has a value for every field, in every variant the app must draw.
function golden(name: string, reply: object) {
  const file = fileURLToPath(new URL(`../../macos/Tests/Fixtures/reply-${name}.json`, import.meta.url));
  const json = `${JSON.stringify(reply, null, 2)}\n`;
  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(file, json);
  expect(json).toBe(readFileSync(file, 'utf8'));
}

const claude = { harness: 'claude', model: 'claude-sonnet-5-5', provider: null } as const;
const codex = { harness: 'codex', model: 'gpt-5', provider: 'ollama' } as const;

test('the sessions reply equals reply-sessions.json', () => {
  const sessions: SessionsReply = {
    sessions: [
      { executionId: '3f2b8c1e-5a4d-4e8b-9c1a-0d2e4f6a8b1c', stage: 'fix', role: 'author', round: 2, agent: claude, status: 'running', startedAt: 90_000, finishedAt: null, resume: null },
      {
        executionId: '9a7d1c52-0b3e-4f6a-8d2c-1e5f7a9b3c4d', stage: 'review', role: 'reviewer', round: 2, agent: codex, status: 'finished', startedAt: 60_000, finishedAt: 85_000,
        resume: { harness: 'codex', sessionId: 'a1b2c3d4-0001-4000-8000-000000000002', cwd: '/work/acme/web-epic' },
      },
      {
        executionId: '5c0e8a14-7d2b-4a93-b6f1-2d8c4e6a0b97', stage: 'ship', role: 'author', round: null, agent: claude, status: 'failed', startedAt: 1_000, finishedAt: 39_000,
        resume: { harness: 'claude', sessionId: '91d4be02-6a35-4c1e-9b7f-3e5a7c9d1f20', cwd: '/work/acme/web-epic', configDir: '/Users/dev/.claude-work' },
      },
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
      { id: 109, at: 9_600, kind: 'task', agentId: 'agent-7', text: 'Slice #123: migrate the signer' },
      { id: 110, at: 9_700, kind: 'say', agentId: 'agent-7', text: 'Migrating the signer.' },
      { id: 111, at: 9_800, kind: 'error', text: 'The agent process ended with an error.' },
      // three lanes: a slice and a lane, the same, and a lane with no slice in its description
      { id: 112, at: 9_900, kind: 'tool_start', agentId: 'agent-7', callId: 'toolu_a7', tool: 'Bash', arg: 'cd /work/acme/web-epic--lane-1 && pnpm test' },
      { id: 113, at: 10_900, kind: 'tool_end', agentId: 'agent-7', callId: 'toolu_a7', tool: 'Bash', summary: 'ok', status: 'ok', durationMs: 1_000, output: ['Tests 12 passed'] },
      { id: 114, at: 11_000, kind: 'task', agentId: 'agent-8', text: 'Slice #124: rotate the keys' },
      { id: 115, at: 11_100, kind: 'tool_start', agentId: 'agent-8', callId: 'toolu_a8', tool: 'Edit', arg: '/work/acme/web-epic--lane-2/src/keys.ts' },
      {
        id: 116, at: 11_200, kind: 'tool_end', agentId: 'agent-8', callId: 'toolu_a8', tool: 'Edit', summary: 'Edited 1 place', status: 'ok', durationMs: 100,
        diff: [{ sign: '-', text: 'const keys = [];' }, { sign: '+', text: 'const keys = rotate();' }],
      },
      { id: 117, at: 11_300, kind: 'task', agentId: 'agent-9', text: 'Tidy the docs' },
      { id: 118, at: 11_400, kind: 'tool_start', agentId: 'agent-9', callId: 'toolu_a9', tool: 'Read', arg: '/work/acme/web-epic--lane-3/README.md' },
      { id: 119, at: 11_480, kind: 'tool_end', agentId: 'agent-9', callId: 'toolu_a9', tool: 'Read', summary: '40 lines', status: 'ok', durationMs: 80 },
    ],
    next: 119,
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
      { stage: 'review', startedAt: 39_000, endedAt: 60_000 },
      { stage: 'fix', startedAt: 60_000, endedAt: null },
    ],
    rounds: [
      {
        round: 1, reviewer: codex, verdict: 'changes_requested', reviewMs: 21_000, fixMs: 30_000, reviewedSha: '1111111aaaaaaa', fixedSha: '2222222bbbbbbb',
        blockers: [blocker('b1', 'Token expiry is not checked', 'new'), blocker('b2', 'Missing test for refresh', 'new')],
        commits: [{ sha: '2222222bbbbbbb', subject: 'fix(auth): check the expiry' }, { sha: '3333333ccccccc', subject: 'test(auth): cover refresh' }],
      },
      {
        round: 2, reviewer: codex, verdict: 'changes_requested', reviewMs: 25_000, fixMs: null, reviewedSha: '4444444ddddddd', fixedSha: null,
        blockers: [blocker('b1', 'Token expiry is not checked', 'fixed'), blocker(null, 'Missing test for refresh', 'carried', true), blocker('b3', 'Log line leaks the subject', 'new')],
        commits: [],
      },
      {
        round: 3, reviewer: codex, verdict: 'approved', reviewMs: 18_000, fixMs: null, reviewedSha: '5555555eeeeeee', fixedSha: null,
        blockers: [],
        commits: [],
      },
      {
        round: 5, reviewer: codex, verdict: 'limit_reached', reviewMs: 20_000, fixMs: null, reviewedSha: '6666666fffffff', fixedSha: null,
        blockers: [blocker('b3', 'Log line leaks the subject', 'carried')],
        commits: [],
      },
    ],
    slices: [
      { number: 121, title: 'Request schemas', state: 'closed', blockedBy: [], prNumber: 130, closedAt: 50_000, readAt: 99_000 },
      { number: 122, title: 'Rejected idea', state: 'skipped', blockedBy: [], prNumber: null, closedAt: 51_000, readAt: 99_000 },
      { number: 123, title: 'Sessions request', state: 'in_progress', blockedBy: [], prNumber: 131, closedAt: null, readAt: 99_000 },
      { number: 124, title: 'Events request', state: 'waiting', blockedBy: [121, 123], prNumber: null, closedAt: null, readAt: 99_000 },
      { number: 125, title: 'Files request', state: 'ready', blockedBy: [], prNumber: null, closedAt: null, readAt: 99_000 },
    ],
    worktrees: [
      { kind: 'epic', lane: null, path: '/work/acme/web-epic' },
      { kind: 'lane', lane: 1, path: '/work/acme/web-epic--lane-1' },
    ],
    branch: 'feat/issue-12/epic',
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
  };
  golden('files', files);
});
