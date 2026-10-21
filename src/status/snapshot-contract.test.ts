import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics, type epicStates } from '../storage/schema.ts';
import { buildSnapshot } from './snapshot.ts';

// The contract with the macOS app: its tests decode this file (macos/Tests/CarrierCoreTests/SnapshotTests.swift).
const fixture = fileURLToPath(new URL('../../macos/Tests/Fixtures/snapshot.json', import.meta.url));

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-snapshot-contract-'));
  db = openDatabase(join(dir, 'carrier.db'));
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const add = (repo: string, issue: number, status: (typeof epicStates)[number], extra: Partial<typeof epics.$inferInsert> = {}) =>
  db.insert(epics).values({ repo, issue, status, ...extra }).returning().get();
const exec = (executionId: string, epicId: number, stage: 'ship' | 'review' | 'fix', startedAt: number) =>
  db.insert(executions).values({ executionId, epicId, stage, resultPath: '/r', startedAt }).run();

const agent = (harness: 'claude' | 'codex' | 'agy', model: string, provider?: 'ollama') => ({ profile: `${harness}-profile`, harness, model, provider });
const config = { name: 'acme', agents: { author: agent('claude', 'claude-sonnet-5-5'), reviewer: agent('codex', 'gpt-5', 'ollama') } };

// Every field of the snapshot has a value somewhere in this sample, so the app can be built against it.
test('the snapshot JSON equals macos/Tests/Fixtures/snapshot.json (UPDATE_FIXTURES=1 rewrites it)', () => {
  const inReview = add('acme/web', 12, 'running', { config, stage: 'review', round: 2, prNumber: 50, queuedAt: 500, startedAt: 1_000, stageStartedAt: 40_000, lastActivityAt: 90_000, lastError: 'the agent process ended with an error', workspace: '/work/acme/web-epic' });
  const inShip = add('acme/web', 13, 'running', { config, stage: 'ship', queuedAt: 600, startedAt: 7_000, stageStartedAt: 7_000, workspace: '/work/acme/web-13' });
  const waiting = add('acme/api', 4, 'needs_human', { config, stage: 'fix', round: 5, prNumber: 9, queuedAt: 700, startedAt: 2_000, stageStartedAt: 8_000, finishedAt: 60_000, needsHumanReason: 'review limit' });
  const otherKinds = (['agent_needs_human', 'retries_exhausted', 'timeout', 'auth', 'workspace', 'pr_invalid'] as const).map((kind, i) =>
    add('acme/api', 5 + i, 'needs_human', { config, stage: 'ship', queuedAt: 800 + i, startedAt: 3_000 + i, finishedAt: 61_000 + i, needsHumanReason: kind.replace('_', ' ') }));
  add('acme/web', 20, 'queued', { queuedAt: 20_000 });
  add('acme/api', 21, 'queued', { queuedAt: 21_000 });
  const shipped = add('acme/web', 30, 'ready_for_test', { prNumber: 77, finishedAt: 95_000 });
  add('acme/api', 31, 'ready_for_test', { finishedAt: 80_000 });
  exec('exec-ship-12', inReview.id, 'ship', 1_000);
  db.update(executions).set({ status: 'finished', finishedAt: 39_000 }).where(eq(executions.executionId, 'exec-ship-12')).run();
  exec('exec-review-12', inReview.id, 'review', 40_000);
  exec('exec-ship-13', inShip.id, 'ship', 7_000);
  exec('exec-fix-4', waiting.id, 'fix', 8_000);
  exec('exec-ship-30', shipped.id, 'ship', 2_000);
  db.insert(callerResults).values({ executionId: 'exec-review-12', outcome: 'changes_requested', result: JSON.stringify({ blockers: [{ title: 'a' }, { title: 'b' }] }) }).run();

  const kinds = ['review_limit', 'agent_needs_human', 'retries_exhausted', 'timeout', 'auth', 'workspace', 'pr_invalid'] as const;
  const needsHumanKind = new Map([waiting, ...otherKinds].map((e, i) => [`${e.repo}#${e.issue}`, kinds[i]!]));
  const snapshot = buildSnapshot(db, {
    now: 100_000, maxConcurrentEpics: 3, maxReviews: 5, startedAt: 40_000, repos: 2, nextCheckAt: 160_000, problem: 'GitHub is not answering', paused: true,
    slices: (repo, issue) => (repo === 'acme/web' && issue === 12 ? { done: 3, total: 5 } : null),
    version: '0.1.0', pollIntervalMs: 300_000,
    rateLimit: { remaining: 4_812, limit: 5_000, resetAt: 130_000, profile: 'orchestrator' },
    watched: [
      { repo: 'acme/web', lastCheckedAt: 98_000, ok: true, error: null, agents: { author: { harness: 'claude', model: 'claude-sonnet-5-5', provider: null }, reviewer: { harness: 'codex', model: 'gpt-5', provider: 'ollama' } } },
      { repo: 'acme/api', lastCheckedAt: 98_000, ok: false, error: 'GitHub answered 502', agents: { author: { harness: 'agy', model: 'gemini-3', provider: null }, reviewer: { harness: 'claude', model: 'claude-sonnet-5-5', provider: null } } },
    ],
    lastEvent: (id) => ({ 'exec-review-12': { kind: 'tool', text: 'Read src/auth/token.ts', at: 99_000 }, 'exec-ship-13': { kind: 'say', text: 'Writing the migration', at: 99_500 } })[id] ?? null,
    issueMeta: (repo, issue) => ({
      title: `Issue ${issue} of ${repo}`,
      labels: ['solve:epic', ...(repo === 'acme/web' && issue === 12 ? ['solve:epic:ready'] : [])],
      branch: `feat/issue-${issue}/epic`,
      ...(needsHumanKind.has(`${repo}#${issue}`) ? { needsHumanKind: needsHumanKind.get(`${repo}#${issue}`) } : {}),
    }),
  });
  const json = `${JSON.stringify(snapshot, null, 2)}\n`;

  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(fixture, json);
  expect(json).toBe(readFileSync(fixture, 'utf8'));
});
