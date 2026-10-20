import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
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

test('the snapshot JSON equals macos/Tests/Fixtures/snapshot.json (UPDATE_FIXTURES=1 rewrites it)', () => {
  const running = add('acme/web', 12, 'running', { stage: 'review', round: 2, prNumber: 50, startedAt: 1_000, stageStartedAt: 40_000, lastActivityAt: 90_000, lastError: 'the agent process ended with an error' });
  add('acme/web', 13, 'running', { startedAt: 7_000 });
  const waiting = add('acme/api', 4, 'needs_human', { stage: 'fix', round: 5, prNumber: 9, stageStartedAt: 8_000, needsHumanReason: 'review limit' });
  add('acme/web', 20, 'queued');
  add('acme/api', 21, 'queued');
  const shipped = add('acme/web', 30, 'ready_for_test', { prNumber: 77, finishedAt: 95_000 });
  add('acme/api', 31, 'ready_for_test', { finishedAt: 80_000 });
  exec('exec-ship-12', running.id, 'ship', 1_000);
  exec('exec-review-12', running.id, 'review', 40_000);
  exec('exec-fix-4', waiting.id, 'fix', 8_000);
  exec('exec-ship-30', shipped.id, 'ship', 2_000);
  db.insert(callerResults).values({ executionId: 'exec-review-12', outcome: 'changes_requested', result: JSON.stringify({ blockers: [{ title: 'a' }, { title: 'b' }] }) }).run();

  const snapshot = buildSnapshot(db, {
    now: 100_000, maxConcurrentEpics: 3, maxReviews: 5, startedAt: 40_000, repos: 2, nextCheckAt: 160_000, problem: 'GitHub is not answering', paused: true,
    slices: (repo, issue) => (repo === 'acme/web' && issue === 12 ? { done: 3, total: 5 } : null),
  });
  const json = `${JSON.stringify(snapshot, null, 2)}\n`;

  if (process.env.UPDATE_FIXTURES === '1') writeFileSync(fixture, json);
  expect(json).toBe(readFileSync(fixture, 'utf8'));
});
