import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { Ui } from '../../prompts/types.ts';
import { fakeDeps, quietUi, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();

test('with no Forge agents both roles are the gh login: it is accepted, and the recap says it will show', async () => {
  const { deps, written } = fakeDeps({ forgeAgents: () => [], which: (c) => c !== 'agent-forge' }); // and no way to add one from here
  const { ui } = quietUi();
  const notes: Record<string, string> = {};
  const out = join(dir, 'd.json');
  await runInit({ out }, { ...ui, note: (m, t) => void (notes[t] = m) }, deps);
  const config = JSON.parse(written[out]!);
  expect(config.profiles).toEqual({ gh: { kind: 'gh' } });
  expect(config.agents.author.profile).toBe('gh');
  expect(config.agents.reviewer.profile).toBe('gh');
  expect(notes['This is what will be saved']).toContain('Identity      shared: author and reviewer are the same account, and the signature in what they publish will show it');
});

test('picking the same identity for the author and the reviewer is accepted without a word of protest', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 'e.json');
  await runInit({ repo: ['AshuLab/x'], authorProfile: 'gh', reviewerProfile: 'gh', out }, quietUi().ui, deps);
  expect(JSON.parse(written[out]!).agents).toMatchObject({ author: { profile: 'gh' }, reviewer: { profile: 'gh' } });
});

test('the reviewer starts on an identity the author does not have, and no question is about sharing', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'e2.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.some((q) => /shared|identities/i.test(q))).toBe(false);
  expect(JSON.parse(written[out]!).agents).toMatchObject({ author: { profile: 'artanis-agent' }, reviewer: { profile: 'tassadar-agent' } });
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
