import { EventEmitter } from 'node:events';
import { expect, test, vi } from 'vitest';
import type { PanelEpic, PanelSnapshot } from '../../../status/types.ts';
import { renderDashboard } from '../../dashboard/dashboard.ts';
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
    hello: { capabilities: ['sessions'] } as never,
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
  expect(requests.slice(1).filter(([cmd]) => cmd !== 'tail' && cmd !== 'sessions')).toEqual([['pause', undefined], ['checkNow', undefined]]);
  expect(hooks.open).toHaveBeenCalledWith('https://github.com/A/a/pull/9');
  setState(snapshotOf(true));
  await refresh();
  press('p');
  expect(requests.filter(([cmd]) => cmd !== 'tail' && cmd !== 'sessions').at(-1)).toEqual(['resume', undefined]);
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

// The stage detail: a running card per epic, drawn from the provider the panel is given, with the engine's `sessions` answered by a fake client.
const reply = (executionId: string) => ({
  sessions: [{ executionId, stage: 'ship', role: 'author', round: null, agent: {}, status: 'finished', startedAt: 0, finishedAt: 14 * 60_000, resume: null, result: { outcome: 'completed', summary: 's', verification: null, reason: null } }],
});
function stagePanel(capabilities: string[], answer: (issue: number) => unknown) {
  const sessionsAsked: number[] = [];
  const client = {
    hello: { capabilities } as never,
    request: vi.fn(async (cmd: string, fields?: Record<string, unknown>) => {
      if (cmd !== 'sessions') return null;
      sessionsAsked.push(fields!.issue as number);
      return answer(fields!.issue as number);
    }),
  };
  const { controls } = socketPanel(client, { open: vi.fn(), quit: vi.fn(), lost: vi.fn() });
  const draw = (...epics: PanelEpic[]) => renderDashboard({ ...snapshotOf(false), epics }, { color: false, detail: controls.detail }).join('\n');
  return { draw, sessionsAsked, client };
}
const flush = () => new Promise((resolve) => setImmediate(resolve));

test('stage lines appear at the redraw after the answer, and the epic is asked again only when its stage, round, status, blockers or execution change', async () => {
  const { draw, sessionsAsked } = stagePanel(['sessions'], () => reply('e1'));
  const first = draw(epic);
  expect(first).not.toContain('ship ✓'); // the answer is not here yet
  await flush();
  expect(draw(epic)).toContain('ship ✓ 14m 00s');
  draw(epic);
  draw(epic);
  expect(sessionsAsked).toEqual([1]);
  for (const change of [{ stage: 'review' as const }, { round: 2 }, { blockers: 3 }, { executionId: 'e9' }]) {
    sessionsAsked.length = 0;
    const changed = { ...epic, ...change };
    expect(draw(changed)).toContain('ship ✓'); // the last answer stays while the new one is on its way
    await flush();
    draw(changed);
    draw(changed);
    expect(sessionsAsked).toEqual([1]);
    draw(epic); // the reverse change is a change too
    await flush();
    draw(epic);
  }
});

test('an engine whose hello does not list sessions is never asked and its epics are drawn without detail', async () => {
  const { draw, client } = stagePanel([], () => reply('e1'));
  draw(epic);
  await flush();
  expect(draw(epic)).not.toContain('ship ✓');
  expect(client.request).not.toHaveBeenCalled();
});

test('a sessions request that errors leaves that epic without detail while the others show theirs', async () => {
  const { draw } = stagePanel(['sessions'], (issue) => {
    if (issue === 1) throw new Error('unknown epic');
    return reply('e2');
  });
  const two = { ...epic, issue: 2, repo: 'A/a' };
  draw(epic, two);
  await flush();
  const out = draw(epic, two);
  expect(out.match(/ship ✓/g)).toHaveLength(1);
  expect(out).toContain('A/a #1');
});

test('a sessions request that failed this time is asked again at the next draw, and an unknown epic is not', async () => {
  let failures = 1;
  const { draw, sessionsAsked } = stagePanel(['sessions'], (issue) => {
    if (issue === 2) throw new Error('unknown epic');
    if (failures-- > 0) throw new Error('internal error');
    return reply('e1');
  });
  const two = { ...epic, issue: 2 };
  draw(epic, two);
  await flush();
  expect(draw(epic, two)).not.toContain('ship ✓'); // the failure was not remembered...
  await flush();
  expect(draw(epic, two)).toContain('ship ✓ 14m 00s'); // ...so the next draw got the answer
  draw(epic, two);
  expect(sessionsAsked.filter((issue) => issue === 1)).toEqual([1, 1]);
  expect(sessionsAsked.filter((issue) => issue === 2)).toEqual([2]); // no detail to know: asked once
});
