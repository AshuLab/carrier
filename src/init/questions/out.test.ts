import { join } from 'node:path';
import { expect, test } from 'vitest';
import { fakeDeps, quietUi, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();

test('the default place is the global ~/.carrier/config.json, and the closing line then needs no --config', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  process.env.CARRIER_HOME = join(dir, 'home');
  try {
    await runInit({ repo: ['A/b'] }, ui, deps); // the scripted ui takes the default for "Where to write the config"
  } finally {
    delete process.env.CARRIER_HOME;
  }
  expect(Object.keys(written)).toEqual([join(dir, 'home', 'config.json')]);
  expect(asked.at(-1)).toMatch(/^outro:Ready\. Start it with: carrier\n/);
});

test('"Somewhere else…" asks for the path, and the closing line then points at it with --config', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ 'Where should the config be saved?': '\0path', 'Path of the config file': join(dir, 'elsewhere.json') });
  await runInit({ repo: ['A/b'] }, ui, deps);
  expect(Object.keys(written)).toEqual([join(dir, 'elsewhere.json')]);
  expect(asked.at(-1)).toContain(`carrier --config ${join(dir, 'elsewhere.json')}`);
});

test('an existing file is overwritten only when confirmed or with --yes', async () => {
  const out = join(dir, 'f.json');
  const base = { repo: ['AshuLab/x'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'forge:tassadar-agent', author: 'claude:m', reviewer: 'codex:m', out };
  const refused = fakeDeps({ exists: () => true });
  await expect(runInit(base, quietUi().ui, refused.deps)).rejects.toThrow('already exists');
  expect(refused.written).toEqual({});
  const confirmed = fakeDeps({ exists: () => true });
  await runInit(base, quietUi({ [`${out} exists. Overwrite it?`]: true }).ui, confirmed.deps);
  expect(Object.keys(confirmed.written)).toEqual([out]);
  const forced = fakeDeps({ exists: () => true });
  await runInit({ ...base, yes: true }, quietUi().ui, forced.deps);
  expect(Object.keys(forced.written)).toEqual([out]);
});
