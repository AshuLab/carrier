import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { InitDeps } from '../deps.ts';
import { fakeDeps, quietUi, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();

const repoKey = 'Repos to watch';

test('the repo of the current folder is the suggested answer', async () => {
  const { deps, written } = fakeDeps();
  await runInit({ out: join(dir, 'c.json') }, quietUi().ui, deps); // the scripted ui takes the default
  expect(JSON.parse(written[join(dir, 'c.json')]!).repos).toEqual([{ name: 'AshuLab/carrier' }]);
});

test('with a list of repos they are picked, not typed; the current folder is first and preselected', async () => {
  const { deps, written } = fakeDeps({ listRepos: () => ({ names: ['AshuLab/skills', 'AshuLab/carrier', 'vemec/encaja'], hasMore: false }) });
  const { ui, listed } = quietUi();
  const out = join(dir, 'h.json');
  await runInit({ out }, ui, deps);
  expect(listed[0]).toEqual(['AshuLab:carrier,skills', 'vemec:encaja', 'Other:Other…']); // one section per owner, the folder's owner first
  expect(JSON.parse(written[out]!).repos).toEqual([{ name: 'AshuLab/carrier' }]);
});

test('with one owner the list is flat and shows full names', async () => {
  const { deps } = fakeDeps({ listRepos: () => ({ names: ['AshuLab/skills'], hasMore: false }), originRepo: () => undefined });
  const { ui, listed } = quietUi({ [repoKey]: 'AshuLab/skills' });
  await runInit({ out: join(dir, 'l.json') }, ui, deps);
  expect(listed[0]).toEqual(['AshuLab:AshuLab/skills,Other…']);
});

test('"Other" asks for the repos that are not on the list and joins them to the picked ones', async () => {
  const { deps, written } = fakeDeps({ listRepos: () => ({ names: ['AshuLab/skills'], hasMore: false }), originRepo: () => undefined });
  const { ui, asked } = quietUi({ [repoKey]: 'AshuLab/skills,\0other', 'Other repos (owner/name, comma separated)': 'x/y, AshuLab/skills' });
  const out = join(dir, 'i.json');
  await runInit({ out }, ui, deps);
  expect(asked).toContain('Other repos (owner/name, comma separated)');
  expect(JSON.parse(written[out]!).repos).toEqual([{ name: 'AshuLab/skills' }, { name: 'x/y' }]); // no duplicates
});

test('when the repos cannot be listed it says so and falls back to typing', async () => {
  const { deps, written } = fakeDeps({
    listRepos: () => {
      throw new Error('gh: not logged in\nmore');
    },
  });
  const { ui, asked } = quietUi();
  const out = join(dir, 'j.json');
  await runInit({ out }, ui, deps);
  expect(asked.find((a) => a.startsWith('warn:'))).toBe('warn:Could not list your repos (gh: not logged in); type them instead.');
  expect(JSON.parse(written[out]!).repos).toEqual([{ name: 'AshuLab/carrier' }]);
});

// The scripted ui answers the same each time it is asked; these tests answer the list once per round.
function rounds(answers: string[][]) {
  const { ui, asked } = quietUi();
  const lists: Record<string, { value: string; label: string }[]>[] = [];
  const initial: string[][] = [];
  ui.multiselect = (async ({ options, initialValues }: { options: Record<string, { value: string; label: string }[]>; initialValues?: string[] }) => {
    lists.push(options);
    initial.push(initialValues ?? []);
    return answers.shift()!;
  }) as typeof ui.multiselect;
  return { ui, asked, lists, initial };
}
const labels = (list: Record<string, { label: string }[]>) => Object.entries(list).map(([group, items]) => `${group}:${items.map((o) => o.label).join(',')}`);
const loadMoreEntry = 'Load more…';
const page = (names: string[], hasMore: boolean) => ({ names, hasMore });

test('"Load more…" reads the next page, keeps what was ticked and files the new repos under their owner', async () => {
  const pages: Record<number, ReturnType<typeof page>> = {
    1: page(['AshuLab/skills', 'vemec/encaja'], true),
    2: page(['AshuLab/tools', 'zed/new'], false),
  };
  const asked: number[] = [];
  const { deps, written } = fakeDeps({ listRepos: (n) => (asked.push(n), pages[n]!) });
  const { ui, lists, initial } = rounds([['AshuLab/skills', '\0more'], ['AshuLab/skills', 'zed/new']]);
  const out = join(dir, 'm.json');
  await runInit({ out }, ui, deps);
  expect(asked).toEqual([1, 2]);
  expect(labels(lists[0]!)).toEqual(['AshuLab:carrier,skills', 'vemec:encaja', `Other:${loadMoreEntry},Other…`]);
  expect(initial[1]).toEqual(['AshuLab/skills']); // the ticked one stays, the entry is not one of them
  expect(labels(lists[1]!)).toEqual(['AshuLab:carrier,skills,tools', 'vemec:encaja', 'zed:new', 'Other:Other…']); // no more pages: no entry
  expect(JSON.parse(written[out]!).repos).toEqual([{ name: 'AshuLab/skills' }, { name: 'zed/new' }]);
});

test('with one owner the entry sits next to "Other…" in the flat list', async () => {
  const { deps } = fakeDeps({ listRepos: () => page(['AshuLab/skills'], true) });
  const { ui, lists } = rounds([['AshuLab/skills']]);
  await runInit({ out: join(dir, 'n.json') }, ui, deps);
  expect(labels(lists[0]!)).toEqual([`AshuLab:AshuLab/carrier,AshuLab/skills,${loadMoreEntry},Other…`]);
});

test('a page that adds nothing keeps the entry while GitHub has more', async () => {
  const pages = [page(['AshuLab/skills'], true), page([], true), page(['AshuLab/tools'], false)];
  const { deps } = fakeDeps({ listRepos: (n) => pages[n - 1]! });
  const { ui, lists } = rounds([['\0more'], ['\0more'], ['AshuLab/tools']]);
  await runInit({ out: join(dir, 'o.json') }, ui, deps);
  expect(labels(lists[1]!)).toEqual(labels(lists[0]!));
  expect(labels(lists[1]!).join()).toContain(loadMoreEntry);
  expect(labels(lists[2]!).join()).not.toContain(loadMoreEntry);
});

test('a later page that cannot be read is said and the wizard goes on with what is loaded, "Other…" included', async () => {
  const listRepos: InitDeps['listRepos'] = (n) => {
    if (n === 1) return page(['AshuLab/skills'], true);
    throw new Error('gh: timed out\nmore');
  };
  const { deps, written } = fakeDeps({ listRepos });
  const { ui, asked, lists } = rounds([['\0more'], ['AshuLab/skills']]);
  const out = join(dir, 'p.json');
  await runInit({ out }, ui, deps);
  expect(asked).toContain('warn:Could not load more repos (gh: timed out); going on with the ones loaded.');
  expect(labels(lists[1]!)).toEqual([`AshuLab:AshuLab/carrier,AshuLab/skills,Other…`]);
  expect(JSON.parse(written[out]!).repos).toEqual([{ name: 'AshuLab/skills' }]);
});
