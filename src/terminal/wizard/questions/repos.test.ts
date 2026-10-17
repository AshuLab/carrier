import { join } from 'node:path';
import { expect, test } from 'vitest';
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
  const { deps, written } = fakeDeps({ listRepos: () => ['AshuLab/skills', 'AshuLab/carrier', 'vemec/encaja'] });
  const { ui, listed } = quietUi();
  const out = join(dir, 'h.json');
  await runInit({ out }, ui, deps);
  expect(listed[0]).toEqual(['AshuLab:carrier,skills', 'vemec:encaja', 'Other:Other…']); // one section per owner, the folder's owner first
  expect(JSON.parse(written[out]!).repos).toEqual([{ name: 'AshuLab/carrier' }]);
});

test('with one owner the list is flat and shows full names', async () => {
  const { deps } = fakeDeps({ listRepos: () => ['AshuLab/skills'], originRepo: () => undefined });
  const { ui, listed } = quietUi({ [repoKey]: 'AshuLab/skills' });
  await runInit({ out: join(dir, 'l.json') }, ui, deps);
  expect(listed[0]).toEqual(['AshuLab:AshuLab/skills,Other…']);
});

test('"Other" asks for the repos that are not on the list and joins them to the picked ones', async () => {
  const { deps, written } = fakeDeps({ listRepos: () => ['AshuLab/skills'], originRepo: () => undefined });
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
