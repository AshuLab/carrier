import { expect, test } from 'vitest';
import { renderPanel } from './plain.ts';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';

const now = 1_000_000_000;
const epic = (over: Partial<PanelEpic> = {}): PanelEpic => ({
  repo: 'acme/web',
  issue: 12,
  status: 'running',
  stage: 'ship',
  round: null,
  maxReviews: 5,
  blockers: 0,
  stageSince: now - 185_000,
  lastActivityAt: now - 12_000,
  issueUrl: 'https://github.com/acme/web/issues/12',
  prUrl: null,
  lastError: null,
  needsHumanReason: null,
  slices: null,
  executionId: null,
  ...over,
});
const snapshot = (over: Partial<PanelSnapshot> = {}): PanelSnapshot => ({ now, slots: { busy: 0, total: 3 }, queue: [], epics: [], startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, done: [], ...over });

test('the agent\'s reason and error are shown without control characters', () => {
  const lines = renderPanel(snapshot({ slots: { busy: 1, total: 1 }, epics: [epic({ needsHumanReason: 'a\x1b[2Jb', lastError: 'c\r\nd\x07' })] })).join('\n');
  expect(lines).toContain('reason: a [2Jb');
  expect(lines).toContain('error: c  d ');
  expect(lines).not.toMatch(/[\x07\x1b\r]/);
});

test('slices show next to the round when GitHub reports some, and nothing when it sends none or the epic has no sub-issues', () => {
  const line = (slices: PanelEpic['slices']) => renderPanel(snapshot({ epics: [epic({ round: 2, slices })] }))[1];
  expect(line({ done: 3, total: 5 })).toContain('round 2/5  slices 3/5  blockers 0');
  expect(line(null)).not.toContain('slices');
  expect(line({ done: 0, total: 0 })).not.toContain('slices');
});

test('an epic waiting for its choice says so with the seconds left, and an epic whose deadline is gone is starting', () => {
  const waiting = (choiceDeadline: number | null) => renderPanel(snapshot({ epics: [epic({ stage: null, options: { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex', choiceDeadline } })] }))[1];
  expect(waiting(now + 42_500)).toContain('acme/web#12  waiting for its choice (42s left)  blockers 0');
  expect(waiting(now - 1)).toContain('acme/web#12  waiting for its choice (0s left)');
  expect(waiting(null)).toContain('acme/web#12  starting  ');
});

test('empty queue', () => {
  expect(renderPanel(snapshot()).join('\n')).toMatchInlineSnapshot(`"carrier  slots 0/3  queue 0"`);
});

test('queued epics in order next to the busy slots', () => {
  const lines = renderPanel(
    snapshot({
      slots: { busy: 1, total: 3 },
      queue: [
        { repo: 'acme/api', issue: 7 },
        { repo: 'acme/web', issue: 30 },
      ],
      epics: [epic()],
    }),
  );
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 1/3  queue 2: acme/api#7, acme/web#30
    acme/web#12  ship  blockers 0  in stage 3m 05s  activity 12s ago
      issue https://github.com/acme/web/issues/12"
  `);
});

test('epic in review with blockers, round, PR link and no output yet', () => {
  const lines = renderPanel(
    snapshot({
      slots: { busy: 1, total: 1 },
      epics: [epic({ stage: 'review', round: 2, blockers: 3, prUrl: 'https://github.com/acme/web/pull/40', lastActivityAt: null, stageSince: now - 7_380_000 })],
    }),
  );
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 1/1  queue 0
    acme/web#12  review  round 2/5  blockers 3  in stage 2h 03m  no activity
      issue https://github.com/acme/web/issues/12  PR https://github.com/acme/web/pull/40"
  `);
});

test('needs_human shows the reason', () => {
  const lines = renderPanel(
    snapshot({ epics: [epic({ status: 'needs_human', stage: 'review', round: 5, blockers: 2, needsHumanReason: 'review limit: round 5 of 5 still has requested changes' })] }),
  );
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 0/3  queue 0
    acme/web#12  NEEDS HUMAN  round 5/5  blockers 2  in stage 3m 05s  activity 12s ago
      issue https://github.com/acme/web/issues/12
      reason: review limit: round 5 of 5 still has requested changes"
  `);
});

test('epic with a last error', () => {
  const lines = renderPanel(snapshot({ epics: [epic({ lastError: 'the agent process ended with an error' })] }));
  expect(lines.join('\n')).toMatchInlineSnapshot(`
    "carrier  slots 0/3  queue 0
    acme/web#12  ship  blockers 0  in stage 3m 05s  activity 12s ago
      issue https://github.com/acme/web/issues/12
      error: the agent process ended with an error"
  `);
});

const fin = (issue: number, over: Partial<NonNullable<PanelSnapshot['finished']>[number]> = {}): NonNullable<PanelSnapshot['finished']>[number] => ({
  repo: 'acme/web', issue, title: `Epic ${issue}`, labels: [], prNumber: 100 + issue, finishedAt: now - 3_600_000 * issue, status: 'merged', cancelReason: null, executionId: null, ...over,
});

test('finished epics are listed after the live ones: merged, then cancelled with the reason, ten each and a count of the rest', () => {
  const lines = renderPanel(snapshot({ finished: [...Array.from({ length: 11 }, (_, i) => fin(i + 1)), fin(20, { status: 'cancelled', prNumber: null, cancelReason: 'final PR closed' })] }));
  expect(lines[1]).toBe('done  acme/web#1  PR #101  1h 00m ago  Epic 1');
  expect(lines).toContain('done  acme/web#10  PR #110  10h 00m ago  Epic 10');
  expect(lines.some((l) => l.includes('#11 '))).toBe(false);
  expect(lines[11]).toBe('done  +1 more');
  expect(lines[12]).toBe('cancelled  acme/web#20  20h 00m ago  Epic 20  reason: final PR closed');
  expect(lines).toHaveLength(13);
});

test('no finished epics, or an engine that sends none, adds no lines', () => {
  expect(renderPanel(snapshot({ finished: [] }))).toHaveLength(1);
  expect(renderPanel(snapshot())).toHaveLength(1);
});
