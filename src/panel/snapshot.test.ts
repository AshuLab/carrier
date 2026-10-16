import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { callerResults } from '../storage/caller-results.ts';
import { openDatabase, type Db } from '../storage/db.ts';
import { executions } from '../storage/executions.ts';
import { epics, epicStates } from '../storage/schema.ts';
import { renderPanel } from './render.ts';
import { buildSnapshot } from './snapshot.ts';

let dir: string;
let db: Db;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'carrier-snapshot-'));
  db = openDatabase(join(dir, 'carrier.db'));
});
afterEach(() => {
  db.$client.close();
  rmSync(dir, { recursive: true, force: true });
});

const add = (issue: number, status: (typeof epicStates)[number], extra: Partial<typeof epics.$inferInsert> = {}) =>
  db.insert(epics).values({ repo: 'acme/web', issue, status, ...extra }).returning().get();
const snapshot = (now = 100_000) => buildSnapshot(db, { now, maxConcurrentEpics: 3, maxReviews: 5 });

test('slots count the running epics, the queue lists the queued ones oldest first, and finished ones do not show', () => {
  add(5, 'queued');
  add(6, 'running');
  add(4, 'queued');
  for (const status of ['ready_for_test', 'merged', 'cancelled', 'repo_removed'] as const) add(10 + epicStates.indexOf(status), status);

  const s = snapshot();
  expect(s.slots).toEqual({ busy: 1, total: 3 });
  expect(s.queue).toEqual([{ repo: 'acme/web', issue: 5 }, { repo: 'acme/web', issue: 4 }]);
  expect(s.epics.map((e) => e.issue)).toEqual([6]);
});

test('an epic carries its stage, round, links, activity, error and the blockers of the last review that asked for changes', () => {
  const epic = add(12, 'running', {
    stage: 'fix', round: 2, prNumber: 50, startedAt: 1_000, stageStartedAt: 40_000, lastActivityAt: 90_000, lastError: 'the agent process ended with an error',
  });
  const base = { epicId: epic.id, stage: 'review' as const, resultPath: '/r', startedAt: 0 };
  const review = (executionId: string, outcome: string, result: object) => {
    db.insert(executions).values({ ...base, executionId }).run();
    db.insert(callerResults).values({ executionId, outcome, result: JSON.stringify(result) }).run();
  };
  review('r1', 'changes_requested', { blockers: [{ title: 'a' }, { title: 'b' }, { title: 'c' }] });
  review('r2', 'changes_requested', { blockers: [{ title: 'a' }, { title: 'b' }] });

  expect(snapshot().epics).toEqual([
    {
      repo: 'acme/web', issue: 12, status: 'running', stage: 'fix', round: 2, maxReviews: 5, blockers: 2, stageSince: 40_000, lastActivityAt: 90_000,
      issueUrl: 'https://github.com/acme/web/issues/12', prUrl: 'https://github.com/acme/web/pull/50',
      lastError: 'the agent process ended with an error', needsHumanReason: null,
    },
  ]);
});

test('before the first stage the epic counts from its start, has no PR and no activity; a needs_human epic shows its reason', () => {
  add(1, 'running', { startedAt: 7_000 });
  add(2, 'needs_human', { stage: 'review', round: 5, prNumber: 9, stageStartedAt: 8_000, needsHumanReason: 'review limit' });

  const [first, second] = snapshot().epics;
  expect(first).toMatchObject({ stage: null, stageSince: 7_000, prUrl: null, lastActivityAt: null, blockers: 0 });
  expect(second).toMatchObject({ status: 'needs_human', needsHumanReason: 'review limit', round: 5 });
});

test('renders through renderPanel: the stage duration and the activity age come from the stored instants', () => {
  add(3, 'running', { stage: 'review', round: 1, stageStartedAt: 40_000, lastActivityAt: 95_000 });
  const lines = renderPanel(snapshot()).join('\n');
  expect(lines).toContain('in stage 1m');
  expect(lines).toContain('activity 5s ago');
  expect(lines).toContain('slots 1/3');
});
