import { EventEmitter } from 'node:events';
import { expect, test, vi } from 'vitest';
import { startInteractivePanel, type Controls } from './interactive.ts';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';

const epic: PanelEpic = {
  repo: 'A/a', issue: 1, status: 'running', stage: 'ship', round: null, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: null,
  issueUrl: 'https://github.com/A/a/issues/1', prUrl: 'https://github.com/A/a/pull/9', lastError: null, needsHumanReason: null, slices: null, executionId: 'exec-1',
};
let paused = false;
const snapshot = (): PanelSnapshot => ({ now: 5000, slots: { busy: 1, total: 3 }, queue: [], epics: [epic], startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused, done: [] });

function setup() {
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const writes: string[] = [];
  const controls = { poll: vi.fn(), setPaused: vi.fn(), open: vi.fn(), quit: vi.fn(), logs: vi.fn(() => ['▸ Bash ls']) } satisfies Controls;
  const stop = startInteractivePanel({ snapshot, out: { isTTY: true, write: (t) => writes.push(t) }, stdin: stdin as never, controls, now: () => 5000, intervalMs: 3_600_000 });
  const press = (name: string, extra: object = {}) => stdin.emit('keypress', extra['sequence' as keyof typeof extra] ?? name, { name, ...extra });
  return { stdin, writes, controls, stop, press };
}

test('select, open, check now, pause and quit reach the program, and every key redraws at once', () => {
  const { writes, controls, stop, press } = setup();
  const drawn = writes.length;
  press('down');
  expect(writes.length).toBe(drawn + 1); // redrawn by the key, not by the timer
  expect(writes.at(-1)!.replace(/\x1b\[[0-9;]*m/g, '')).toContain('› A/a #1');
  press('return');
  expect(controls.open).toHaveBeenCalledWith('https://github.com/A/a/pull/9');
  press('c');
  expect(controls.poll).toHaveBeenCalledTimes(1);
  press('p');
  expect(controls.setPaused).toHaveBeenCalledWith(true);
  press('q');
  expect(controls.quit).toHaveBeenCalledTimes(1);
  stop();
});

test('Ctrl+C is a quit (raw mode swallows the signal), and l shows what controls.logs gives', () => {
  const { writes, controls, stop, press } = setup();
  press('down');
  press('l');
  expect(controls.logs).toHaveBeenCalledWith('exec-1', 18);
  expect(writes.at(-1)).toContain('▸ Bash ls');
  press('escape');
  expect(writes.at(-1)).not.toContain('AGENT OUTPUT');
  press('c', { ctrl: true });
  expect(controls.quit).toHaveBeenCalledTimes(1);
  stop();
});

test('raw mode is on while it runs and given back on stop, with the cursor', () => {
  const { stdin, writes, stop } = setup();
  expect(stdin.setRawMode).toHaveBeenLastCalledWith(true);
  expect(stdin.resume).toHaveBeenCalled();
  stop();
  expect(stdin.setRawMode).toHaveBeenLastCalledWith(false);
  expect(stdin.pause).toHaveBeenCalled();
  expect(writes.at(-1)).toBe('\x1b[?25h');
  expect(stdin.listenerCount('keypress')).toBe(0);
});

test('without a terminal on stdin the keys are not read at all', () => {
  const stdin = Object.assign(new EventEmitter(), { isTTY: false, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const stop = startInteractivePanel({ snapshot, out: { isTTY: true, write: () => {} }, stdin: stdin as never, controls: { poll() {}, setPaused() {}, open() {}, quit() {}, logs: () => [] }, intervalMs: 3_600_000 });
  expect(stdin.setRawMode).not.toHaveBeenCalled();
  stop();
});

test('in watch, q and Ctrl+C leave through quit and the screens say so', () => {
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const writes: string[] = [];
  const controls = { poll: vi.fn(), setPaused: vi.fn(), open: vi.fn(), quit: vi.fn(), logs: vi.fn(() => []) } satisfies Controls;
  const stop = startInteractivePanel({ snapshot, out: { isTTY: true, write: (t) => writes.push(t) }, stdin: stdin as never, controls, now: () => 5000, intervalMs: 3_600_000, quit: 'leave' });
  expect(writes.at(-1)).toContain('q leave');
  stdin.emit('keypress', '?', {});
  expect(writes.at(-1)).toContain('leave (Carrier keeps running)');
  stdin.emit('keypress', 'q', { name: 'q' });
  expect(controls.quit).toHaveBeenCalledTimes(1);
  stop();
  expect(writes.at(-1)).toBe('\x1b[?25h'); // the cursor is given back
});

// An epic that has not launched yet: the panel offers no choice for it, in its hints or in the help.
test('o and a do nothing, and the hints and the help do not offer them', () => {
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const writes: string[] = [];
  const starting: PanelEpic = { ...epic, stage: null, executionId: null, options: { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex' } };
  const controls = { poll: vi.fn(), setPaused: vi.fn(), open: vi.fn(), quit: vi.fn(), logs: vi.fn(() => []) } satisfies Controls;
  const stop = startInteractivePanel({ snapshot: () => ({ ...snapshot(), epics: [starting] }), out: { isTTY: true, write: (t) => writes.push(t) }, stdin: stdin as never, controls, now: () => 5000, intervalMs: 3_600_000 });
  const press = (name: string) => stdin.emit('keypress', name, { name });
  const screen = () => writes.at(-1)!.replace(/\x1b\[[0-9;]*m/g, '');
  expect(screen()).not.toContain('o options');
  press('o');
  press('a');
  expect(screen()).not.toContain('‹');
  expect(screen()).not.toContain('Starting');
  press('?');
  expect(screen()).not.toContain('choose the options');
  stop();
});

// --- closed epics: folded by default, opened with f, hidden for good with x ---

const closedEpic = { repo: 'D/d', issue: 3, title: 'Old', labels: [], prNumber: 40, finishedAt: 1000, status: 'merged' as const, cancelReason: null, executionId: null };
const withClosed = (): PanelSnapshot => ({ ...snapshot(), epics: [], finished: [closedEpic, { ...closedEpic, issue: 4 }] });

function setupClosed(dismiss?: Controls['dismiss']) {
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const writes: string[] = [];
  const controls: Controls = { poll: vi.fn(), setPaused: vi.fn(), open: vi.fn(), quit: vi.fn(), logs: vi.fn(() => []), ...(dismiss && { dismiss }) };
  const stop = startInteractivePanel({ snapshot: withClosed, out: { isTTY: true, write: (t) => writes.push(t) }, stdin: stdin as never, controls, now: () => 5000, intervalMs: 3_600_000 });
  const press = (name: string) => stdin.emit('keypress', name, { name });
  const screen = () => writes.at(-1)!.replace(/\x1b\[[0-9;]*m/g, '');
  return { controls, stop, press, screen, writes };
}

test('closed epics start folded: the heading is selected, enter opens it, ↓ reaches the rows, and ← folds it again', () => {
  const { stop, press, screen } = setupClosed();
  expect(screen()).toContain('› CLOSED 2 ▸'); // the arrows reach the heading, so it carries the pointer
  expect(screen()).not.toContain('D/d #3');
  press('return');
  expect(screen()).toContain('› CLOSED 2 ▾');
  expect(screen()).toContain('D/d #3');
  press('down');
  expect(screen()).toContain('› D/d #3');
  press('down');
  expect(screen()).toContain('› D/d #4');
  press('left'); // from a row: folds and lands on the heading
  expect(screen()).toContain('› CLOSED 2 ▸');
  press('f'); // f flips it too
  expect(screen()).toContain('CLOSED 2 ▾');
  stop();
});

test('x on a closed row asks the program to dismiss it, says so when it did, and moves to the next row', async () => {
  const dismiss = vi.fn(async () => ({ ok: true as const }));
  const { controls, stop, press, screen } = setupClosed(dismiss);
  press('f');
  expect(screen()).not.toContain('d dismiss'); // the heading is selected: nothing to dismiss
  press('down');
  expect(screen()).toContain('d dismiss'); // the first row is selected
  press('d');
  expect(controls.dismiss).toHaveBeenCalledWith('D/d', 3);
  expect(screen()).toContain('› D/d #4'); // the selection has moved on
  await Promise.resolve();
  await Promise.resolve();
  expect(screen()).toContain('Dismissed D/d#3');
  stop();
});

test('a refusal or a failed request shows as the toast, and a reply after the panel stopped draws nothing', async () => {
  const { stop, press, screen, writes } = setupClosed(async () => ({ ok: false as const, reason: 'Carrier says no' }));
  press('f');
  press('down');
  press('d');
  await new Promise((r) => setTimeout(r, 0));
  expect(screen()).toContain('Carrier says no');
  stop();

  const failing = setupClosed(() => Promise.reject(new Error('socket closed')));
  failing.press('f');
  failing.press('down');
  failing.press('d');
  await new Promise((r) => setTimeout(r, 0));
  expect(failing.screen()).toContain('Could not dismiss D/d#3: socket closed');
  failing.stop();

  let answer!: (r: { ok: true }) => void;
  const late = setupClosed(() => new Promise((r) => (answer = r)));
  late.press('f');
  late.press('down');
  late.press('d');
  late.stop();
  const drawn = late.writes.length;
  answer({ ok: true });
  await new Promise((r) => setTimeout(r, 0));
  expect(late.writes).toHaveLength(drawn);
  expect(writes.at(-1)).not.toBe(undefined);
});

test('without controls.dismiss the key is neither offered nor listed, and x does nothing', () => {
  const { stop, press, screen } = setupClosed();
  press('f');
  expect(screen()).not.toContain('d dismiss');
  const frame = () => screen().replace(/^\x1b\[\d+A/, '');
  const before = frame();
  press('d');
  expect(frame()).toBe(before);
  press('?');
  expect(screen()).not.toContain('dismiss');
  stop();
});

// --- resuming a stopped epic: R, R ---

const stoppedEpic: PanelEpic = { ...epic, issue: 9, status: 'needs_human', needsHumanReason: 'the review limit', executionId: null, prUrl: null };

function setupResume(resume?: Controls['resume']) {
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const writes: string[] = [];
  let at = 5000;
  const controls: Controls = { poll: vi.fn(), setPaused: vi.fn(), open: vi.fn(), quit: vi.fn(), logs: vi.fn(() => []), ...(resume && { resume }) };
  const stop = startInteractivePanel({ snapshot: () => ({ ...snapshot(), epics: [stoppedEpic] }), out: { isTTY: true, write: (t) => writes.push(t) }, stdin: stdin as never, controls, now: () => at, intervalMs: 3_600_000 });
  const press = (name: string, sequence = name) => stdin.emit('keypress', sequence, { name, shift: sequence !== name });
  const screen = () => writes.at(-1)!.replace(/\x1b\[[0-9;]*m/g, '');
  return { controls, stop, press, screen, writes, later: (ms: number) => (at += ms) };
}

test('r twice resumes the selected stopped epic, says it is under way and then that it started', async () => {
  let answer!: (r: { ok: true }) => void;
  const resume = vi.fn(() => new Promise<{ ok: true }>((r) => (answer = r)));
  const { stop, press, screen } = setupResume(resume);
  expect(screen()).toContain('r resume'); // the stopped row is selected from the start
  press('r');
  expect(screen()).toContain('Resume A/a#9? It starts again from ship');
  expect(resume).not.toHaveBeenCalled();
  press('r');
  expect(resume).toHaveBeenCalledWith('A/a', 9);
  expect(screen()).toContain('Resuming A/a#9…');
  press('r'); press('r'); // while it has not answered a second one is not sent
  expect(resume).toHaveBeenCalledTimes(1);
  answer({ ok: true });
  await new Promise((r) => setTimeout(r, 0));
  expect(screen()).toContain('Resumed A/a#9');
  stop();
});

test('a refused or failed resume shows the engine’s words, and a key between the two Rs withdraws the first', async () => {
  const refused = setupResume(async () => ({ ok: false as const, reason: 'A/a#9 is not stopped, so there is nothing to restart.' }));
  refused.press('r');
  refused.press('r');
  await new Promise((r) => setTimeout(r, 0));
  expect(refused.screen()).toContain('is not stopped, so there is nothing to restart.');
  refused.stop();

  const failing = setupResume(() => Promise.reject(new Error('socket closed')));
  failing.press('r');
  failing.press('r');
  await new Promise((r) => setTimeout(r, 0));
  expect(failing.screen()).toContain('Could not resume A/a#9: socket closed');
  failing.stop();

  const withdrawn = setupResume(vi.fn(async () => ({ ok: true as const })));
  withdrawn.press('r');
  withdrawn.press('escape');
  expect(withdrawn.screen()).not.toContain('r confirms');
  withdrawn.press('r'); // asks again, does not send
  expect(withdrawn.controls.resume).not.toHaveBeenCalled();
  withdrawn.stop();
});

test('without controls.resume the key is neither offered nor listed, and R does nothing', () => {
  const { stop, press, screen } = setupResume();
  expect(screen()).not.toContain('r resume');
  press('r');
  expect(screen()).not.toContain('r confirms');
  press('?');
  expect(screen()).not.toMatch(/resume the selected/);
  stop();
});
