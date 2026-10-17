import { expect, test } from 'vitest';
import { renderPanel, type PanelEpic, type PanelSnapshot } from './render.ts';

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
  ...over,
});
const snapshot = (over: Partial<PanelSnapshot> = {}): PanelSnapshot => ({ now, slots: { busy: 0, total: 3 }, queue: [], epics: [], startedAt: 0, repos: 1, nextCheckAt: null, problem: null, done: [], ...over });

test('the agent\'s reason and error are shown without control characters', () => {
  const lines = renderPanel(snapshot({ slots: { busy: 1, total: 1 }, epics: [epic({ needsHumanReason: 'a\x1b[2Jb', lastError: 'c\r\nd\x07' })] })).join('\n');
  expect(lines).toContain('reason: a [2Jb');
  expect(lines).toContain('error: c  d ');
  expect(lines).not.toMatch(/[\x07\x1b\r]/);
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
