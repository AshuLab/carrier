import { EventEmitter } from 'node:events';
import { expect, test, vi } from 'vitest';
import type { PanelEpic, PanelSnapshot } from '../../../status/types.ts';
import { startInteractivePanel } from '../../dashboard/interactive.ts';
import { ControlUnreachable } from '../control-client.ts';
import { socketPanel } from './watch.ts';

const epic: PanelEpic = {
  repo: 'A/a', issue: 1, status: 'running', stage: 'ship', round: null, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: null,
  issueUrl: 'https://github.com/A/a/issues/1', prUrl: 'https://github.com/A/a/pull/9', lastError: null, needsHumanReason: null, slices: null, executionId: '0b9d7a52-6d0e-4a52-8f8e-0f3a6d3c1a11',
};
const snapshotOf = (paused: boolean): PanelSnapshot => ({ now: 5000, slots: { busy: 1, total: 3 }, queue: [], epics: [epic], startedAt: 0, repos: 1, nextCheckAt: null, problem: null, paused, done: [] });

/** The keys of the foreground panel, drawn from a fake client instead of an engine. */
async function setup(paused = false) {
  let state = snapshotOf(paused);
  const requests: Array<[string, unknown]> = [];
  const client = {
    request: vi.fn(async (cmd: string, fields?: Record<string, unknown>) => {
      requests.push([cmd, fields]);
      if (cmd === 'snapshot') return state;
      if (cmd === 'tail') return ['one', '▸ Bash ls', 'last'];
      return null;
    }),
  };
  const hooks = { open: vi.fn(), quit: vi.fn(), lost: vi.fn() };
  const panel = socketPanel(client, hooks);
  await panel.refresh();
  const stdin = Object.assign(new EventEmitter(), { isTTY: true, setRawMode: vi.fn(), resume: vi.fn(), pause: vi.fn() });
  const writes: string[] = [];
  const stop = startInteractivePanel({ snapshot: panel.snapshot, out: { isTTY: true, write: (t) => writes.push(t) }, stdin: stdin as never, controls: panel.controls, now: () => 5000, intervalMs: 3_600_000, quit: 'leave' });
  const press = (name: string) => stdin.emit('keypress', name, { name });
  return { client, hooks, requests, writes, stop, press, setState: (s: PanelSnapshot) => (state = s), refresh: panel.refresh };
}

test('p, r and enter go through the socket as pause or resume by the current state, checkNow and the PR to open; q only leaves', async () => {
  const { requests, hooks, press, stop, setState, refresh } = await setup();
  press('p');
  press('r');
  press('return');
  expect(requests.slice(1).filter(([cmd]) => cmd !== 'tail')).toEqual([['pause', undefined], ['checkNow', undefined]]);
  expect(hooks.open).toHaveBeenCalledWith('https://github.com/A/a/pull/9');
  setState(snapshotOf(true));
  await refresh();
  press('p');
  expect(requests.filter(([cmd]) => cmd !== 'tail').at(-1)).toEqual(['resume', undefined]);
  press('q');
  expect(hooks.quit).toHaveBeenCalledTimes(1);
  expect(requests.map(([cmd]) => cmd)).not.toContain('stop');
  stop();
});

test('l asks the socket for the tail of the selected epic and shows the last answer', async () => {
  const { requests, writes, press, stop } = await setup();
  press('l');
  await vi.waitFor(() => expect(requests.filter(([cmd]) => cmd === 'tail').length).toBeGreaterThan(0));
  expect(requests.find(([cmd]) => cmd === 'tail')![1]).toEqual({ executionId: epic.executionId, lines: 18 });
  press('r'); // any redraw: the answer has arrived by now
  expect(writes.at(-1)).toContain('▸ Bash ls');
  stop();
});

test('a socket that stops answering calls lost; a refused request does not', async () => {
  const { client, hooks, press, stop } = await setup();
  client.request.mockRejectedValueOnce(new Error('nope'));
  press('r');
  await Promise.resolve();
  expect(hooks.lost).not.toHaveBeenCalled();
  client.request.mockRejectedValueOnce(new ControlUnreachable('no-answer'));
  press('r');
  await vi.waitFor(() => expect(hooks.lost).toHaveBeenCalledTimes(1));
  stop();
});
