import { expect, test } from 'vitest';
import type { PanelEpic, PanelSnapshot } from '../../status/types.ts';
import { initialUi, itemsOf, onKey, settle, type Key, type UiState } from './ui-state.ts';

const now = 1_000_000;
const epic = (over: Partial<PanelEpic> = {}): PanelEpic => ({
  repo: 'A/a', issue: 1, status: 'running', stage: 'ship', round: null, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: null,
  issueUrl: 'https://github.com/A/a/issues/1', prUrl: null, lastError: null, needsHumanReason: null, slices: null, executionId: 'exec-1', ...over,
});
const snap = (over: Partial<PanelSnapshot> = {}): PanelSnapshot => ({
  now, slots: { busy: 1, total: 3 }, queue: [{ repo: 'B/b', issue: 5 }], startedAt: 0, repos: 2, nextCheckAt: null, problem: null, paused: false,
  epics: [epic(), epic({ issue: 2, status: 'needs_human', issueUrl: 'https://github.com/A/a/issues/2', prUrl: 'https://github.com/A/a/pull/9', executionId: null })],
  done: [{ repo: 'C/c', issue: 8, prNumber: 44, finishedAt: 1, executionId: 'exec-8' }],
  ...over,
});
const press = (ui: UiState, name: string, s = snap(), extra: Partial<Key> = {}) => onKey(ui, { name, sequence: name, ...extra }, s, now);

test('the selectable rows are in the order the dashboard shows them: running, queued, needs you, ready', () => {
  expect(itemsOf(snap()).map((i) => i.key)).toEqual(['A/a#1', 'B/b#5', 'A/a#2', 'C/c#8']);
  expect(itemsOf(snap()).map((i) => i.url)).toEqual(['https://github.com/A/a/issues/1', 'https://github.com/B/b/issues/5', 'https://github.com/A/a/pull/9', 'https://github.com/C/c/pull/44']);
});

test('arrows move the selection and stop at the ends', () => {
  let ui = initialUi;
  ui = press(ui, 'down').ui;
  expect(ui.selected).toBe('A/a#1');
  ui = press(press(ui, 'down').ui, 'down').ui;
  expect(ui.selected).toBe('A/a#2');
  for (let i = 0; i < 5; i += 1) ui = press(ui, 'down').ui;
  expect(ui.selected).toBe('C/c#8');
  for (let i = 0; i < 9; i += 1) ui = press(ui, 'up').ui;
  expect(ui.selected).toBe('A/a#1');
  expect(press(initialUi, 'down', snap({ epics: [], queue: [], done: [] })).ui.selected).toBeNull(); // nothing to select
});

test('enter opens the selected row, and without a selection it says what to do', () => {
  const selected = { ...initialUi, selected: 'A/a#2' };
  expect(press(selected, 'return').action).toEqual({ type: 'open', url: 'https://github.com/A/a/pull/9' });
  const none = press(initialUi, 'return');
  expect(none.action).toBeUndefined();
  expect(none.ui.toast?.text).toBe('Select an epic first (↑/↓)');
});

test('l shows the agent output only of a row that has some', () => {
  expect(press({ ...initialUi, selected: 'A/a#1' }, 'l').ui.mode).toBe('logs');
  const without = press({ ...initialUi, selected: 'A/a#2' }, 'l'); // needs-you epic with no execution
  expect(without.ui.mode).toBe('dashboard');
  expect(without.ui.toast?.text).toBe('That one has no agent output yet');
  const back = press({ ...initialUi, selected: 'A/a#1', mode: 'logs' }, 'escape');
  expect(back.ui.mode).toBe('dashboard');
  expect(press({ ...initialUi, selected: 'A/a#1', mode: 'logs' }, 'r').action).toBeUndefined(); // the logs screen takes no other keys
});

test('r asks for a poll, p flips the pause using what the engine says, ? toggles the help', () => {
  expect(press(initialUi, 'r').action).toEqual({ type: 'poll' });
  expect(press(initialUi, 'p').action).toEqual({ type: 'pause', paused: true });
  expect(press(initialUi, 'p', snap({ paused: true })).action).toEqual({ type: 'pause', paused: false });
  const help = onKey(initialUi, { sequence: '?' }, snap(), now);
  expect(help.ui.mode).toBe('help');
  expect(onKey(help.ui, { sequence: '?' }, snap(), now).ui.mode).toBe('dashboard');
  expect(press(help.ui, 'down').ui.selected).toBeNull(); // the help screen takes no navigation
});

test('q and Ctrl+C quit, from any screen', () => {
  for (const mode of ['dashboard', 'logs', 'help'] as const) {
    expect(press({ ...initialUi, mode }, 'q').action).toEqual({ type: 'quit' });
    expect(press({ ...initialUi, mode }, 'c', snap(), { ctrl: true }).action).toEqual({ type: 'quit' });
  }
  expect(press(initialUi, 'c').action).toBeUndefined(); // a plain c is just a c
});

test('settle drops a selection that vanished, an expired toast, and logs of nothing', () => {
  const ui: UiState = { selected: 'A/a#1', mode: 'logs', toast: { text: 'x', until: now + 1 } };
  expect(settle(ui, snap(), now)).toEqual(ui);
  expect(settle(ui, snap({ epics: [], queue: [], done: [] }), now)).toEqual({ selected: null, mode: 'dashboard', toast: ui.toast });
  expect(settle({ ...ui, selected: null }, snap(), now).selected).toBe('A/a#1'); // something is always selected
  expect(settle({ ...ui, selected: 'gone#9' }, snap(), now).selected).toBe('A/a#1');
  expect(settle(ui, snap(), now + 1).toast).toBeNull();
});
