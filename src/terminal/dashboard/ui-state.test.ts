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
  done: [{ repo: 'C/c', issue: 8, title: null, labels: [], prNumber: 44, finishedAt: 1, executionId: 'exec-8' }],
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

test('finished rows are selectable after the ready ones, merged then cancelled, ten each, and act like a ready row', () => {
  const fin = (issue: number, status: 'merged' | 'cancelled', prNumber: number | null) => ({ repo: 'D/d', issue, title: null, labels: [], prNumber, finishedAt: 1, status, cancelReason: status === 'cancelled' ? 'x' : null, executionId: `exec-${issue}` });
  const s = snap({ epics: [], queue: [], finished: [...Array.from({ length: 11 }, (_, i) => fin(i + 1, 'merged', 50 + i)), fin(30, 'cancelled', null)] });
  const items = itemsOf(s);
  expect(items.map((i) => i.key)).toEqual(['C/c#8', ...Array.from({ length: 10 }, (_, i) => `D/d#${i + 1}`), 'D/d#30']); // the eleventh is not listed, so not reachable
  expect(items.at(1)?.url).toBe('https://github.com/D/d/pull/50');
  expect(items.at(-1)?.url).toBe('https://github.com/D/d/issues/30'); // no PR: the issue
  const at = { ...initialUi, selected: 'D/d#1' };
  expect(press(at, 'return', s).action).toEqual({ type: 'open', url: 'https://github.com/D/d/pull/50' });
  expect(press(at, 'l', s).ui.mode).toBe('logs');
  expect(settle({ ...at, mode: 'logs' }, s, now).mode).toBe('logs');
});

// An epic waiting for its option choice: running, no stage yet, with a deadline; the roles would start on claude and codex.
const waiting = (over: Partial<PanelEpic> = {}) => epic({ stage: null, executionId: null, options: { names: ['claude', 'codex', 'agy'], author: 'claude', reviewer: 'codex', choiceDeadline: now + 40_000 }, ...over });
const waitingSnap = (over: Partial<PanelSnapshot> = {}) => snap({ epics: [waiting(), epic({ issue: 2 })], queue: [], done: [], ...over });
const at = { ...initialUi, selected: 'A/a#1' };
const choose = (ui: UiState, name: string, s = waitingSnap()) => onKey(ui, { name, sequence: name }, s, now, true);

test('o on a waiting epic enters the choice mode on the options it would start on; enter sends what is shown', () => {
  const entered = choose(at, 'o');
  expect(entered.ui.mode).toBe('choose');
  expect(entered.ui.choice).toEqual({ role: 'author', author: 'claude', reviewer: 'codex' });
  expect(entered.action).toBeUndefined();
  const sent = choose(entered.ui, 'return');
  expect(sent.action).toEqual({ type: 'choose', repo: 'A/a', issue: 1, author: 'claude', reviewer: 'codex' });
  expect(sent.ui.mode).toBe('dashboard');
  expect(sent.ui.toast?.text).toBe('Starting A/a#1 on claude and codex');
});

test('a choice still open when the wait ends says the time ran out; a plain dashboard says nothing', () => {
  const entered = choose(at, 'o').ui;
  expect(settle(entered, snap(), now)).toMatchObject({ mode: 'dashboard', toast: { text: 'Time ran out: started on its defaults' } });
  expect(settle(at, snap(), now).toast).toBeNull();
});

test('in the choice mode up and down move between the two roles, left and right change the option of the role and wrap', () => {
  let ui = choose(at, 'o').ui;
  ui = choose(ui, 'right').ui;
  expect(ui.choice).toEqual({ role: 'author', author: 'codex', reviewer: 'codex' });
  ui = choose(choose(ui, 'right').ui, 'right').ui; // agy, then around to claude
  expect(ui.choice?.author).toBe('claude');
  ui = choose(ui, 'left').ui; // back to agy
  expect(ui.choice?.author).toBe('agy');
  ui = choose(ui, 'down').ui;
  expect(ui.choice?.role).toBe('reviewer');
  ui = choose(ui, 'left').ui;
  expect(ui.choice).toEqual({ role: 'reviewer', author: 'agy', reviewer: 'claude' });
  ui = choose(ui, 'up').ui;
  expect(ui.choice?.role).toBe('author');
  expect(choose(ui, 'return').action).toEqual({ type: 'choose', repo: 'A/a', issue: 1, author: 'agy', reviewer: 'claude' });
});

test('esc leaves the choice mode without sending, and the mode takes no other key but q', () => {
  const ui = choose(at, 'o').ui;
  const left = choose(ui, 'escape');
  expect(left.ui.mode).toBe('dashboard');
  expect(left.action).toBeUndefined();
  for (const name of ['r', 'p', 'l', 'o', 'a']) expect(choose(ui, name).action).toBeUndefined();
  expect(choose(ui, 'r').ui.mode).toBe('choose');
  expect(onKey(ui, { sequence: '?' }, waitingSnap(), now, true).ui.mode).toBe('choose');
  expect(choose(ui, 'q').action).toEqual({ type: 'quit' });
});

test('a sends the choice with no role, which starts the epic on the defaults', () => {
  const sent = choose(at, 'a');
  expect(sent.action).toEqual({ type: 'choose', repo: 'A/a', issue: 1 });
  expect(sent.ui.mode).toBe('dashboard');
});

test('o and a do nothing on an epic that is not waiting, and against an engine without agentOptions', () => {
  const other = { ...initialUi, selected: 'A/a#2' };
  for (const name of ['o', 'a']) {
    expect(choose(other, name)).toEqual({ ui: other });
    expect(choose({ ...initialUi, selected: 'B/b#5' }, name, snap({ queue: [{ repo: 'B/b', issue: 5 }] }))).toEqual({ ui: { ...initialUi, selected: 'B/b#5' } }); // a queued row
    expect(onKey(at, { name, sequence: name }, waitingSnap(), now)).toEqual({ ui: at }); // canChoose off
  }
  const started = waitingSnap({ epics: [waiting({ options: { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex', choiceDeadline: null } })] });
  expect(choose(at, 'a', started).action).toBeUndefined();
  const oneOption = waitingSnap({ epics: [waiting({ options: { names: ['claude'], author: 'claude', reviewer: 'claude', choiceDeadline: now + 1 } })] });
  expect(choose(at, 'o', oneOption).ui.mode).toBe('dashboard');
});

test('settle leaves the choice mode when the epic is no longer waiting, and keeps it while it is', () => {
  const ui = choose(at, 'o').ui;
  expect(settle(ui, waitingSnap(), now)).toEqual({ ...ui, selected: 'A/a#1', toast: null });
  const started = waitingSnap({ epics: [waiting({ options: { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex', choiceDeadline: null } })] });
  expect(settle(ui, started, now).mode).toBe('dashboard');
  expect(settle(ui, started, now).choice).toBeUndefined();
});
