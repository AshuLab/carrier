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

test('without a terminal a new retry time of an api_error is a state change: each backoff line is written', () => {
  const { out, writes } = output(false);
  state.epics = [{ ...epic, lastError: 'HTTP 529', retryAt: 30_000 }];
  const stop = startPanel(snapshot, out);
  const before = writes.length;
  vi.advanceTimersByTime(5000);
  expect(writes).toHaveLength(before); // the countdown ticking is not a change
  state.epics = [{ ...epic, lastError: 'HTTP 529', retryAt: 150_000 }]; // the second retry, same error
  vi.advanceTimersByTime(1000);
  expect(writes).toHaveLength(before + 1);
  expect(writes.at(-1)).toContain('retries: in');
  stop();
});

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

test('without a terminal the finished epics are written once, and again only when the set changes', () => {
  const { out, writes } = output(false);
  state = { ...state, epics: [], finished: [{ repo: 'acme/web', issue: 3, title: 'T', labels: [], prNumber: 9, finishedAt: 0, status: 'merged', cancelReason: null, executionId: null }] };
  const stop = startPanel(snapshot, out);
  vi.advanceTimersByTime(3000);
  expect(writes.filter((w) => w.includes('done  acme/web#3  PR #9')).length).toBe(1);
  state = { ...state, finished: [] };
  vi.advanceTimersByTime(1000);
  expect(writes.filter((w) => w.includes('done  acme/web#3')).length).toBe(1);
  stop();
});

test('the renderer is told the size of the terminal, and a frame that does not fit is cut to leave the last row free', () => {
  const sizes: unknown[] = [];
  const writes: string[] = [];
  const out: PanelOutput = { isTTY: true, columns: 70, rows: 6, write: (t) => writes.push(t) };
  const stop = startPanel(snapshot, out, 1000, (_, columns, rows) => (sizes.push([columns, rows]), Array.from({ length: 9 }, (_, i) => `line ${i}`)));
  expect(sizes).toEqual([[70, 6]]);
  expect(writes[0]!.match(/line \d/g)).toHaveLength(5); // rows - 1: the cursor-up of the next frame can reach the top
  vi.advanceTimersByTime(1000);
  expect(writes[1]).toContain('\x1b[5A');
  stop();

  const tall: PanelOutput = { isTTY: true, write: (t) => writes.push(t) }; // no rows (a pipe, a test): nothing is cut
  writes.length = 0;
  startPanel(snapshot, tall, 1000, () => Array.from({ length: 9 }, (_, i) => `line ${i}`))();
  expect(writes[0]!.match(/line \d/g)).toHaveLength(9);
});

test('the default dashboard fits the terminal it is drawn on', () => {
  const writes: string[] = [];
  state.epics = Array.from({ length: 6 }, (_, i) => ({ ...epic, issue: i + 1 }));
  const stop = startPanel(snapshot, { isTTY: true, columns: 80, rows: 15, write: (t) => writes.push(t) });
  expect(writes[0]!.split('\n').length - 1).toBeLessThanOrEqual(14);
  stop();
});

test('a terminal that changes size is cleared and drawn again at once, not at the next tick, and the listener goes with the panel', () => {
  const writes: string[] = [];
  const listeners: Array<() => void> = [];
  const out: PanelOutput = { isTTY: true, columns: 80, rows: 30, write: (t) => writes.push(t), on: (_, l) => listeners.push(l), off: (_, l) => listeners.splice(listeners.indexOf(l), 1) };
  const stop = startPanel(snapshot, out, 1000, () => ['a', 'b']);
  expect(listeners).toHaveLength(1);
  const drawn = writes.length;
  listeners[0]!(); // the window was resized
  expect(writes.slice(drawn).join('')).toBe('\x1b[2J\x1b[H\x1b[?25l\r\x1b[2Ka\n\r\x1b[2Kb\n\x1b[J'); // cleared, then a whole frame from the corner: no cursor-up count of the old size
  stop();
  expect(listeners).toHaveLength(0);
  // not a terminal: nothing is listened to
  const plain: PanelOutput = { isTTY: false, write: () => {}, on: () => listeners.push(() => {}) };
  startPanel(snapshot, plain, 1000)();
  expect(listeners).toHaveLength(0);
});
