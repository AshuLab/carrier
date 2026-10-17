import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { Ui } from '../../prompts/types.ts';
import { fakeDeps, quietUi, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();

test('with no Forge agents the reviewer has nothing left, and the error says what to do', async () => {
  const { deps } = fakeDeps({ forgeAgents: () => [], which: (c) => c !== 'agent-forge' }); // and no way to add one from here
  await expect(runInit({ out: join(dir, 'd.json') }, quietUi().ui, deps)).rejects.toThrow('agent-forge add');
});

test('the same identity twice is refused before anything is written', async () => {
  const { deps, written } = fakeDeps();
  await expect(runInit({ repo: ['AshuLab/x'], authorProfile: 'gh', reviewerProfile: 'gh', out: join(dir, 'e.json') }, quietUi().ui, deps)).rejects.toThrow('must differ');
  expect(written).toEqual({});
});

test('when the reviewer has no identity left, a bot can be added right there and the list is read again', async () => {
  let added = 0;
  let registry = [{ name: 'artanis-agent' }];
  const { deps, written } = fakeDeps({
    forgeAgents: () => registry,
    forgeAdd: () => {
      added += 1;
      registry = [...registry, { name: 'new-bot' }];
      return true;
    },
  });
  const answers: string[] = ['forge:artanis-agent', 'gh', '\0add', 'forge:new-bot']; // author, then the reviewer tries "gh"... scripted below
  const { ui } = quietUi();
  let reviewerAsks = 0;
  const scripted: Ui = {
    ...ui,
    select: async (o) => {
      if (o.message === 'GitHub identity for the author') return 'forge:artanis-agent' as never;
      if (o.message === 'GitHub identity for the reviewer') return ((reviewerAsks += 1) === 1 ? '\0add' : 'forge:new-bot') as never;
      return ui.select(o);
    },
  };
  void answers;
  const out = join(dir, 'w.json');
  await runInit({ repo: ['A/b'], out }, scripted, deps);
  expect(added).toBe(1);
  expect(JSON.parse(written[out]!).agents.reviewer.profile).toBe('new-bot');
});

test('a failed `agent-forge add` warns and asks again; without a terminal it is not offered', async () => {
  const offered: string[][] = [];
  const { deps } = fakeDeps({ forgeAdd: () => false });
  const { ui, asked } = quietUi();
  let n = 0;
  const spy: Ui = { ...ui, select: async (o) => (o.message === 'GitHub identity for the reviewer' ? (offered.push(o.options.map((x) => x.value)), ((n += 1) === 1 ? '\0add' : 'gh') as never) : ui.select(o)) };
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', author: 'claude:sonnet', out: join(dir, 'x.json') }, spy, deps);
  expect(asked.some((q) => q.startsWith('warn:agent-forge add did not finish'))).toBe(true);
  expect(offered.length).toBe(2);
  const withYes: string[][] = [];
  const quiet = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'y.json'), yes: true }, { ...quiet.ui, select: async (o) => (o.message.startsWith('GitHub identity') && withYes.push(o.options.map((x) => x.value)), quiet.ui.select(o)) }, fakeDeps().deps);
  expect(withYes.flat()).not.toContain('\0add'); // --yes: no "add a bot" option in the way
});
