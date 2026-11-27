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
  expect(itemsOf(snap(), true).map((i) => i.key)).toEqual(['A/a#1', 'B/b#5', 'A/a#2', 'C/c#8']);
  expect(itemsOf(snap(), true).map((i) => i.url)).toEqual(['https://github.com/A/a/issues/1', 'https://github.com/B/b/issues/5', 'https://github.com/A/a/pull/9', 'https://github.com/C/c/pull/44']);
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
  expect(press({ ...initialUi, selected: 'A/a#1', mode: 'logs' }, 'c').action).toBeUndefined(); // the logs screen takes no other keys
});

test('c asks for a poll, p flips the pause using what the engine says, ? toggles the help', () => {
  expect(press(initialUi, 'c').action).toEqual({ type: 'poll' });
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
  expect(press(initialUi, 'c').action).toEqual({ type: 'poll' }); // Ctrl+C quits; a plain c checks GitHub
});

test('settle drops a selection that vanished, an expired toast, and logs of nothing', () => {
  const ui: UiState = { selected: 'A/a#1', mode: 'logs', toast: { text: 'x', until: now + 1 }, closedOpen: false };
  expect(settle(ui, snap(), now)).toEqual(ui);
  expect(settle(ui, snap({ epics: [], queue: [], done: [] }), now)).toEqual({ selected: null, mode: 'dashboard', toast: ui.toast, closedOpen: false });
  expect(settle({ ...ui, selected: null }, snap(), now).selected).toBe('A/a#1'); // something is always selected
  expect(settle({ ...ui, selected: 'gone#9' }, snap(), now).selected).toBe('A/a#1');
  expect(settle(ui, snap(), now + 1).toast).toBeNull();
});

test('finished rows are selectable after the ready ones, merged then cancelled, ten each, and act like a ready row', () => {
  const fin = (issue: number, status: 'merged' | 'cancelled', prNumber: number | null) => ({ repo: 'D/d', issue, title: null, labels: [], prNumber, finishedAt: 1, status, cancelReason: status === 'cancelled' ? 'x' : null, executionId: `exec-${issue}` });
  const s = snap({ epics: [], queue: [], finished: [...Array.from({ length: 11 }, (_, i) => fin(i + 1, 'merged', 50 + i)), fin(30, 'cancelled', null)] });
  const items = itemsOf(s, true);
  expect(items.map((i) => i.key)).toEqual(['C/c#8', 'closed', ...Array.from({ length: 10 }, (_, i) => `D/d#${i + 1}`), 'D/d#30']); // the eleventh is not listed, so not reachable
  expect(items.at(2)?.url).toBe('https://github.com/D/d/pull/50');
  expect(items.at(-1)?.url).toBe('https://github.com/D/d/issues/30'); // no PR: the issue
  const at = { ...initialUi, closedOpen: true, selected: 'D/d#1' };
  expect(press(at, 'return', s).action).toEqual({ type: 'open', url: 'https://github.com/D/d/pull/50' });
  expect(press(at, 'l', s).ui.mode).toBe('logs');
  expect(settle({ ...at, mode: 'logs' }, s, now).mode).toBe('logs');
});

// An epic that has not launched yet: no key of the panel asks for a choice, whatever accounts it has.
test('o and a do nothing on any row: there is no choice to make at the start of an epic', () => {
  const s = snap({ epics: [epic({ stage: null, executionId: null, options: { names: ['claude', 'codex'], author: 'claude', reviewer: 'codex' } }), epic({ issue: 2 })], queue: [], done: [] });
  for (const selected of ['A/a#1', 'A/a#2']) {
    const ui = { ...initialUi, selected };
    for (const name of ['o', 'a']) expect(onKey(ui, { name, sequence: name }, s, now)).toEqual({ ui });
  }
});

// --- the CLOSED section and dismissing ---

const fin = (issue: number, status: 'merged' | 'cancelled' = 'merged') => ({ repo: 'D/d', issue, title: null, labels: [], prNumber: status === 'merged' ? 50 + issue : null, finishedAt: 1, status, cancelReason: status === 'cancelled' ? 'x' : null, executionId: `exec-${issue}` });
const withClosed = (n = 3) => snap({ epics: [], queue: [], finished: Array.from({ length: n }, (_, i) => fin(i + 1)) });
const dismissable = { canDismiss: true };

test('the closed epics start folded: the arrows reach the CLOSED heading, not the rows, and f opens the section', () => {
  expect(initialUi.closedOpen).toBe(false);
  const s = withClosed();
  expect(itemsOf(s, false).map((i) => i.key)).toEqual(['C/c#8', 'closed']); // the ready one and the heading
  expect(itemsOf(s, true).map((i) => i.key)).toEqual(['C/c#8', 'closed', 'D/d#1', 'D/d#2', 'D/d#3']);
  expect(itemsOf(s, true).map((i) => i.closed)).toEqual([false, false, true, true, true]);
  expect(itemsOf(snap({ done: [], epics: [], queue: [], finished: [] }), true).map((i) => i.key)).toEqual([]); // no closed epics, no heading
  expect(press(initialUi, 'f', s).ui.closedOpen).toBe(true);
  expect(press({ ...initialUi, closedOpen: true }, 'f', s).ui.closedOpen).toBe(false);
  expect(press(initialUi, 'f', s).action).toBeUndefined();
});

test('down reaches the CLOSED heading and stops there while it is folded; once open it goes on to the rows', () => {
  const s = withClosed();
  expect(press({ ...initialUi, selected: 'C/c#8' }, 'down', s).ui.selected).toBe('closed');
  expect(press({ ...initialUi, selected: 'closed' }, 'down', s).ui.selected).toBe('closed');
  expect(press({ ...initialUi, selected: 'closed', closedOpen: true }, 'down', s).ui.selected).toBe('D/d#1');
  expect(press({ ...initialUi, selected: 'D/d#1', closedOpen: true }, 'up', s).ui.selected).toBe('closed');
});

test('enter on the CLOSED heading opens and folds it, → opens, ← folds, and none of them opens a URL', () => {
  const s = withClosed();
  const head = { ...initialUi, selected: 'closed' };
  expect(press(head, 'return', s)).toEqual({ ui: { ...head, closedOpen: true } });
  expect(press({ ...head, closedOpen: true }, 'return', s)).toEqual({ ui: { ...head, closedOpen: false } });
  expect(press(head, 'right', s).ui.closedOpen).toBe(true);
  expect(press({ ...head, closedOpen: true }, 'left', s).ui.closedOpen).toBe(false);
  expect(press({ ...head, closedOpen: true }, 'right', s).ui.closedOpen).toBe(true);
  expect(press({ ...initialUi, selected: 'C/c#8', closedOpen: true }, 'left', s).ui).toEqual({ ...initialUi, selected: 'C/c#8', closedOpen: true }); // ← elsewhere does nothing
  const row = press({ ...initialUi, selected: 'D/d#2', closedOpen: true }, 'left', s).ui;
  expect(row).toMatchObject({ closedOpen: false, selected: 'closed' }); // folding from a row lands on the heading
});

test('with no closed epics f says so and changes nothing; folding the section over the selection moves it to the heading', () => {
  const none = press(initialUi, 'f', snap({ done: [], finished: [] }));
  expect(none.ui.closedOpen).toBe(false);
  expect(none.ui.toast?.text).toBe('No closed epics');
  const s = withClosed();
  const folded = press({ ...initialUi, closedOpen: true, selected: 'D/d#2' }, 'f', s).ui;
  expect(folded).toMatchObject({ closedOpen: false, selected: 'closed' });
  expect(settle(folded, s, now).selected).toBe('closed');
  expect(press({ ...initialUi, closedOpen: true, selected: 'C/c#8' }, 'f', s).ui.selected).toBe('C/c#8'); // not on a closed row: stays
});

test('settle keeps the section open or folded, and a selection on a row of a section that folded goes to the first row', () => {
  const s = withClosed();
  expect(settle({ ...initialUi, closedOpen: true, selected: 'D/d#1' }, s, now)).toMatchObject({ closedOpen: true, selected: 'D/d#1' });
  expect(settle({ ...initialUi, selected: 'D/d#1' }, s, now)).toMatchObject({ closedOpen: false, selected: 'C/c#8' });
});

test('d dismisses the selected closed row and moves the selection to its neighbour, the next one first', () => {
  const s = withClosed();
  const at = (selected: string) => ({ ...initialUi, closedOpen: true, selected });
  expect(press(at('D/d#1'), 'd', s).action).toBeUndefined(); // without the option the key is not offered
  const second = onKey(at('D/d#2'), { name: 'd', sequence: 'd' }, s, now, dismissable);
  expect(second.action).toEqual({ type: 'dismiss', repo: 'D/d', issue: 2 });
  expect(second.ui.selected).toBe('D/d#3');
  const last = onKey(at('D/d#3'), { name: 'd', sequence: 'd' }, s, now, dismissable);
  expect(last.action).toEqual({ type: 'dismiss', repo: 'D/d', issue: 3 });
  expect(last.ui.selected).toBe('D/d#2'); // the last one: the one before it
  const only = onKey({ ...initialUi, closedOpen: true, selected: 'D/d#1' }, { name: 'd', sequence: 'd' }, snap({ done: [], epics: [], queue: [], finished: [fin(1)] }), now, dismissable);
  expect(only.action).toEqual({ type: 'dismiss', repo: 'D/d', issue: 1 });
  expect(only.ui.selected).toBe('closed'); // nothing below it: the heading above
});

test('d on a row that is not closed says so and asks for nothing, and without the option it does nothing at all', () => {
  const s = withClosed();
  for (const selected of ['C/c#8']) {
    const r = onKey({ ...initialUi, closedOpen: true, selected }, { name: 'd', sequence: 'd' }, s, now, dismissable);
    expect(r.action).toBeUndefined();
    expect(r.ui.toast?.text).toBe('Only closed epics can be dismissed');
  }
  const running = onKey({ ...initialUi, selected: 'A/a#1' }, { name: 'd', sequence: 'd' }, snap(), now, dismissable);
  expect(running.action).toBeUndefined();
  expect(running.ui.toast?.text).toBe('Only closed epics can be dismissed');
  expect(onKey(initialUi, { name: 'd', sequence: 'd' }, snap(), now, dismissable).ui.toast?.text).toBe('Only closed epics can be dismissed'); // nothing selected
  const off = onKey({ ...initialUi, closedOpen: true, selected: 'D/d#1' }, { name: 'd', sequence: 'd' }, s, now);
  expect(off).toEqual({ ui: { ...initialUi, closedOpen: true, selected: 'D/d#1' } });
  expect(onKey({ ...initialUi, mode: 'help', closedOpen: true, selected: 'D/d#1' }, { name: 'd', sequence: 'd' }, s, now, dismissable).action).toBeUndefined(); // the help takes no other keys
});

// --- resuming a stopped epic: R twice ---

const R = (ui: UiState, s = snap(), options: { canResume?: boolean } = { canResume: true }) => onKey(ui, { name: 'r', sequence: 'r' }, s, now, options);
const stopped = { ...initialUi, selected: 'A/a#2' };

test('r on a stopped epic asks first, and a second r resumes it with a toast that says so', () => {
  const first = R(stopped);
  expect(first.action).toBeUndefined();
  expect(first.ui.confirm).toBe('A/a#2');
  const second = R(first.ui);
  expect(second.action).toEqual({ type: 'resume', repo: 'A/a', issue: 2 });
  expect(second.ui.confirm).toBeUndefined();
  expect(second.ui.toast?.text).toBe('Resuming A/a#2…');
  expect(second.ui.toast!.until).toBeGreaterThan(now + 30_000); // the engine takes up to 30 seconds to answer
});

test('any other key withdraws the first r, and the key still does what it does', () => {
  const asked = R(stopped).ui;
  const moved = press(asked, 'down');
  expect(moved.ui.confirm).toBeUndefined();
  expect(moved.ui.selected).toBe('C/c#8');
  expect(R(moved.ui).action).toBeUndefined(); // a new R on another row only asks again
  expect(press(asked, 'escape').ui.confirm).toBeUndefined();
  expect(press(asked, 'c').action).toEqual({ type: 'poll' }); // c is check now, and does not confirm
  expect(R(press(asked, 'c').ui).action).toBeUndefined();
});

test('r does nothing without the control, and on a row that is not stopped it says what can be resumed', () => {
  expect(R(stopped, snap(), {})).toEqual({ ui: stopped });
  const running = R({ ...initialUi, selected: 'A/a#1' });
  expect(running.action).toBeUndefined();
  expect(running.ui.toast?.text).toBe('Only a stopped epic (NEEDS YOU) can be resumed · c checks GitHub now');
  expect(R({ ...initialUi, selected: 'C/c#8' }).ui.toast?.text).toBe('Only a stopped epic (NEEDS YOU) can be resumed · c checks GitHub now');
});

test('a stopped row says whether it stopped on its quota, and settle drops a confirmation whose row moved or is no longer stopped', () => {
  const s = snap({ epics: [epic(), epic({ issue: 2, status: 'needs_human', needsHumanCode: 'epic.stop.usageLimit', executionId: null })] });
  expect(itemsOf(s, false).find((i) => i.key === 'A/a#2')).toMatchObject({ stopped: true, usage: true });
  expect(itemsOf(snap(), false).find((i) => i.key === 'A/a#2')).toMatchObject({ stopped: true });
  expect(itemsOf(snap(), false).find((i) => i.key === 'A/a#2')?.usage).toBeUndefined();
  expect(itemsOf(snap(), false).find((i) => i.key === 'A/a#1')?.stopped).toBeUndefined();
  const asked = { ...stopped, confirm: 'A/a#2' };
  expect(settle(asked, snap(), now).confirm).toBe('A/a#2');
  expect(settle({ ...asked, selected: 'A/a#1' }, snap(), now).confirm).toBeUndefined(); // the selection left
  expect(settle(asked, snap({ epics: [epic()] }), now).confirm).toBeUndefined(); // it started again
});
