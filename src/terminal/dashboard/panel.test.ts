import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { startPanel, type PanelOutput } from './panel.ts';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';

const epic: PanelEpic = {
  repo: 'acme/web',
  issue: 12,
  status: 'running',
  stage: 'ship',
  round: null,
  maxReviews: 5,
  blockers: 0,
  stageSince: 0,
  lastActivityAt: null,
  issueUrl: 'https://github.com/acme/web/issues/12',
  prUrl: null,
  lastError: null,
  needsHumanReason: null,
  slices: null,
  executionId: null,
};

let state: PanelSnapshot;
const output = (isTTY: boolean) => {
  const writes: string[] = [];
  const out: PanelOutput = { isTTY, write: (t) => writes.push(t) };
  return { out, writes };
};

beforeEach(() => {
  vi.useFakeTimers({ now: 0 });
  state = { now: 0, slots: { busy: 1, total: 2 }, queue: [], epics: [{ ...epic }], startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused: false, done: [] };
});
afterEach(() => vi.useRealTimers());

const snapshot = () => ({ ...state, now: Date.now() });

test('on a terminal it redraws in place with ANSI every second', () => {
  const { out, writes } = output(true);
  const stop = startPanel(snapshot, out);
  expect(writes).toHaveLength(1);
  expect(writes[0]).not.toContain('\x1b[1A'); // first draw: nothing to overwrite
  vi.advanceTimersByTime(1000);
  expect(writes).toHaveLength(2);
  expect(writes[1]).toContain(`\x1b[${writes[0]!.split('\n').length - 1}A`); // back over every line drawn before
  expect(writes[1]).toContain('\x1b[2K');
  expect(writes[1]).toContain('1s in stage');
  vi.advanceTimersByTime(2000);
  expect(writes).toHaveLength(4);
  stop();
  expect(writes.at(-1)).toBe('\x1b[?25h'); // the cursor comes back
  vi.advanceTimersByTime(5000);
  expect(writes).toHaveLength(5); // and nothing is drawn after stop
});

test('without a terminal it writes one plain line per state change, no ANSI', () => {
  const { out, writes } = output(false);
  const stop = startPanel(snapshot, out);
  expect(writes).toHaveLength(2); // the slots/queue line and the epic
  vi.advanceTimersByTime(5000);
  expect(writes).toHaveLength(2); // time passing is not a state change
  state.epics = [{ ...epic, stage: 'review', round: 1 }];
  vi.advanceTimersByTime(1000);
  expect(writes).toHaveLength(3);
  expect(writes[2]).toContain('acme/web#12  review  round 1/5');
  state.queue = [{ repo: 'acme/api', issue: 7 }];
  vi.advanceTimersByTime(1000);
  expect(writes).toHaveLength(4);
  expect(writes[3]).toContain('queue 1: acme/api#7');
  stop();
  for (const line of writes) {
    expect(line).not.toContain('\x1b');
    expect(line.endsWith('\n')).toBe(true);
    expect(line.trimEnd()).not.toContain('\n');
  }
});

test('the panel has no controls: it never reads stdin', () => {
  const before = process.stdin.listenerCount('data') + process.stdin.listenerCount('keypress') + process.stdin.listenerCount('readable');
  const stop = startPanel(snapshot, output(true).out);
  expect(process.stdin.listenerCount('data') + process.stdin.listenerCount('keypress') + process.stdin.listenerCount('readable')).toBe(before);
  expect(process.stdin.isRaw).toBeFalsy();
  stop();
});

test('the cursor is hidden by the first draw, returned on stop and also if the process exits without it', () => {
  const { out, writes } = output(true);
  const before = process.listenerCount('exit');
  const stop = startPanel(snapshot, out);
  expect(writes[0]!.startsWith('\x1b[?25l')).toBe(true);
  expect(writes[1]).toBeUndefined();
  expect(process.listenerCount('exit')).toBe(before + 1);
  process.emit('exit', 0); // what Node does on the way out, however the process ended
  expect(writes.at(-1)).toBe('\x1b[?25h');
  stop();
  expect(process.listenerCount('exit')).toBe(before);

  const plain = output(false);
  const stopPlain = startPanel(snapshot, plain.out);
  stopPlain();
  expect(plain.writes.join('')).not.toContain('\x1b[?25'); // a pipe never gets cursor codes
});
