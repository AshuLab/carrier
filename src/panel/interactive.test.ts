import { EventEmitter } from 'node:events';
import { expect, test, vi } from 'vitest';
import { startInteractivePanel, type Controls } from './interactive.ts';
import type { PanelEpic, PanelSnapshot } from './render.ts';

const epic: PanelEpic = {
  repo: 'A/a', issue: 1, status: 'running', stage: 'ship', round: null, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: null,
  issueUrl: 'https://github.com/A/a/issues/1', prUrl: 'https://github.com/A/a/pull/9', lastError: null, needsHumanReason: null, executionId: 'exec-1',
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
  press('r');
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
