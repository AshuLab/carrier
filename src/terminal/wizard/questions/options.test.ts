import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../../config/load.ts';
import type { Ui } from '../../prompts/types.ts';
import { realDeps } from '../deps.ts';
import { asFiles, fakeDeps, fakeMachine, providersWritten, quietUi, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';
import { normalizeOptionName } from './options.ts';

const dir = useTempDir();
const home = join(dir, 'home');
const folders = { configFolders: (h: string) => (h === 'claude' ? ['/h/.claude', '/h/.claude-ashu-lab'] : ['/h/.codex']), loggedIn: async (_h: string, d?: string) => d !== '/h/.claude' };
/** The config written to `out` with the accounts written to providers.json, after checking that both load together. */
const load = (written: Record<string, string>, out: string, folder?: string) => {
  const config = JSON.parse(written[out]!);
  const providers = providersWritten(written, folder);
  expect(loadConfig(defaults, config, providers as never).ok).toBe(true);
  return { ...config, providers };
};

test('the folder is chosen among the ones found, each with its login state, plus the environment and a typed path', async () => {
  const { deps, written } = fakeDeps(folders);
  const seen: Record<string, { value: string; hint?: string }[]> = {};
  const { ui } = quietUi({ 'Config folder of this Claude Code provider': '/h/.claude-ashu-lab', 'Add another AI provider?': [true, false], 'Which agent CLI runs this provider?': 'claude' });
  const spy: Ui = { ...ui, select: async (o) => ((seen[o.message] = o.options.map(({ value, hint }) => ({ value, hint }))), ui.select(o)) };
  const out = join(dir, 'f1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(seen['Config folder of this Claude Code provider']).toEqual([
    { value: '/h/.claude', hint: 'not logged in' },
    { value: '/h/.claude-ashu-lab', hint: 'logged in' },
    { value: '\0inherit', hint: 'the login Carrier runs in: logged in' },
    { value: '\0path', hint: undefined },
  ]);
  const config = load(written, out);
  expect(config.providers).toEqual({ claude: { harness: 'claude', enabled: false }, codex: { harness: 'codex', enabled: false }, 'claude-ashu-lab': { harness: 'claude', configDir: '/h/.claude-ashu-lab' } }); // what was found, then the extra
});

test('a typed path is validated, and a login that cannot be checked is said so', async () => {
  const { deps, written } = fakeDeps({ loggedIn: async () => Promise.reject(new Error('no cli')) });
  const { ui } = quietUi({ 'Add another AI provider?': [true, false], 'Config folder of this Claude Code provider': '\0path' });
  let hint: string | undefined;
  const refused: Array<string | undefined> = [];
  const spy: Ui = {
    ...ui,
    select: async (o) => (o.message.startsWith('Config folder') && (hint = o.options.find((x) => x.value === '\0inherit')?.hint), ui.select(o)),
    text: async (o) => (o.message.startsWith('Config folder') ? (refused.push(o.validate?.('relative/dir'), o.validate?.('~/.claude-x'), o.validate?.('/abs')), '  ~/.claude-x ') : ui.text(o)),
  };
  const out = join(dir, 'f2.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(hint).toBe('the login Carrier runs in: could not check the login');
  expect(refused[0]).toBeDefined();
  expect([refused[1], refused[2]]).toEqual([undefined, undefined]);
  expect(load(written, out).providers['claude-x']).toEqual({ harness: 'claude', configDir: '~/.claude-x' });
});

test('the name is suggested from harness and folder, is normalized to a lowercase slug, and must be unique', async () => {
  const { deps, written } = fakeDeps(folders);
  const { ui, asked } = quietUi({ 'Add another AI provider?': [true, true, true, false], 'Which agent CLI runs this provider?': ['claude', 'codex', 'codex'], 'Config folder of this Claude Code provider': '/h/.claude', 'Config folder of this Codex provider': '/h/.codex', 'Name of this provider': [undefined as never, undefined as never, '  Teams 2  '] });
  const names: Array<(string | undefined)[]> = [];
  const spy: Ui = { ...ui, text: async (o) => (o.message === 'Name of this provider' ? (names.push([o.defaultValue, o.validate?.('Codex'), o.validate?.('1a'), o.validate?.('claude'), o.validate?.('Claude'), o.validate?.('ok-1')]), ui.text(o)) : ui.text(o)) };
  const out = join(dir, 'n1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(names.map(([suggested]) => suggested)).toEqual(['claude-2', 'codex-2', 'codex-3']); // `~/.claude` -> claude and `~/.codex` -> codex, which the detected accounts already have
  expect(names[1]!.slice(1).map((v) => v !== undefined)).toEqual([true, true, true, true, false]); // codex is taken (and so is Codex, once normalized), a digit first is refused, claude is taken; ok-1 is fine
  expect(asked.filter((q) => q === 'Add another AI provider?')).toHaveLength(4);
  expect(Object.keys(load(written, out).providers)).toEqual(['claude', 'codex', 'claude-2', 'codex-2', 'teams-2']);
});

test('normalizeOptionName turns human names into kebab-case slugs', () => {
  expect(normalizeOptionName('Teams')).toBe('teams');
  expect(normalizeOptionName('Teams 2')).toBe('teams-2');
  expect(normalizeOptionName('Claude_Ashu_Lab')).toBe('claude-ashu-lab');
  expect(normalizeOptionName('  --My  Custom--Option--  ')).toBe('my-custom-option');
  expect(normalizeOptionName('1a')).toBe('1a');
  expect(normalizeOptionName('!!!')).toBe('');
  expect(normalizeOptionName('a'.repeat(50))).toBe('a'.repeat(40));
});

test('each role asks one question, which option runs it, and the choices are the options created', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ 'Which AI provider runs the reviewer?': 'claude', 'Which AI provider runs the author?': 'codex' });
  const choices: Record<string, string[]> = {};
  const spy: Ui = { ...ui, select: async (o) => ((choices[o.message] = o.options.map((x) => x.value)), ui.select(o)) };
  const out = join(dir, 'r1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(choices['Which AI provider runs the author?']).toEqual(['claude', 'codex']);
  expect(asked.some((q) => q.startsWith('Which agent CLI runs the'))).toBe(false);
  expect(load(written, out).agents).toMatchObject({ author: { provider: 'codex' }, reviewer: { provider: 'claude' } });
});

test('with one option the roles are not asked, and neither is failover', async () => {
  const { deps, written } = fakeDeps({ machine: fakeMachine({ resolveBinary: (name) => { if (name === 'claude') return '/opt/bin/claude'; throw new Error('not found'); } }) }); // only Claude is on this Mac
  const { ui, asked } = quietUi();
  const out = join(dir, 'r2.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.some((q) => q.startsWith('Which AI provider runs') || q.startsWith('Turn failover'))).toBe(false);
  const config = load(written, out);
  expect(config.agents).toMatchObject({ author: { provider: 'claude' }, reviewer: { provider: 'claude' } });
  expect(config).not.toHaveProperty('failover');
});

test('with two or more options failover is asked, and "yes" asks the order until the person is done', async () => {
  const three = { 'Add another AI provider?': [true, false], 'Which agent CLI runs this provider?': 'claude', 'Config folder of this Claude Code provider': '/h/.claude-ashu-lab' }; // the found claude and codex, and the extra
  const { deps, written } = fakeDeps(folders);
  const { ui } = quietUi({ ...three, 'Turn failover on? A role that runs out of credits then moves to the next provider you list, so its code can reach another provider.': true, 'Failover order: which provider goes first?': 'codex', 'Failover order: which provider goes next?': ['claude', '\0done'] });
  const picks: Record<string, string[]> = {};
  const spy: Ui = { ...ui, select: async (o) => ((picks[o.message] = o.options.map((x) => x.value)), ui.select(o)) };
  const out = join(dir, 'fo1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(picks['Failover order: which provider goes first?']).toEqual(['claude', 'codex', 'claude-ashu-lab']);
  expect(picks['Failover order: which provider goes next?']).toEqual(['claude-ashu-lab', '\0done']); // codex and claude are already in; the person ends it here
  expect(load(written, out).failover).toEqual({
    triggers: ['usage_limit', 'rate_limit', 'service_down'],
    roles: { author: [{ provider: 'codex' }, { provider: 'claude' }], reviewer: [{ provider: 'codex' }, { provider: 'claude' }] },
  });

  const off = fakeDeps();
  const no = quietUi();
  const outOff = join(dir, 'fo2.json');
  await runInit({ repo: ['A/b'], out: outOff }, no.ui, off.deps);
  expect(no.asked.some((q) => q.startsWith('Turn failover'))).toBe(true); // asked, and declined
  expect(load(off.written, outOff)).not.toHaveProperty('failover');
});

test('running again on an existing config keeps its options and failover, adds more, and preselects each role\'s option', async () => {
  const existing = {
    repos: [{ name: 'X/y' }],
    profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
    orchestratorProfile: 'tassadar-agent',
    providers: { work: { harness: 'claude', configDir: '~/.claude-work' }, codex: { harness: 'codex' } },
    failover: { roles: { author: [{ provider: 'codex', model: 'gpt-x' }] } },
    agents: { author: { profile: 'tassadar-agent', provider: 'codex', model: 'gpt-test' }, reviewer: { profile: 'gh', provider: 'work', model: 'opus' } },
  };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: asFiles(existing) });
  const { ui, asked } = quietUi({ 'Add another AI provider?': [true, false], 'Which agent CLI runs this provider?': 'agy' });
  const initial: Record<string, unknown> = {};
  const spy: Ui = { ...ui, select: async (o) => ((initial[o.message] = o.initialValue), ui.select(o)) };
  process.env.CARRIER_HOME = home;
  try {
    await runInit({}, spy, deps);
  } finally {
    delete process.env.CARRIER_HOME;
  }
  expect(initial['Which AI provider runs the author?']).toBe('codex');
  expect(initial['Which AI provider runs the reviewer?']).toBe('work');
  expect(asked).not.toContain('Where should the config be saved?');
  expect(asked.some((q) => q.startsWith('Turn failover'))).toBe(false);
  const config = load(written, join(home, 'config.json'), home);
  expect(config.providers).toEqual({ ...existing.providers, agy: { harness: 'agy' } });
  expect(config.failover).toEqual(existing.failover);
  expect(config.agents).toMatchObject(existing.agents);
});

test('the flags declare the options and skip the section, the failover question and the role question', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'u1.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'claude:m1', reviewer: 'claude:m2', out, yes: true }, ui, deps);
  expect(asked.filter((q) => !q.startsWith('outro') && !q.startsWith('checks:'))).toEqual([]);
  const config = load(written, out);
  expect(config.providers).toEqual({ claude: { harness: 'claude', enabled: false }, codex: { harness: 'codex', enabled: false } }); // the flags name what was found
  expect(config.agents).toMatchObject({
    author: { provider: 'claude', model: 'm1' },
    reviewer: { provider: 'claude', model: 'm2' },
  });
  expect(config).not.toHaveProperty('failover');
});

test('one flag declares one option; the section then offers more and the other role picks among them', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ 'Add another AI provider?': [true, false] });
  const out = join(dir, 'u2.json');
  await runInit({ repo: ['A/b'], author: 'claude:m1', out }, ui, deps);
  expect(asked).not.toContain('Which AI provider runs the author?');
  expect(asked).toContain('Which AI provider runs the reviewer?');
  expect(load(written, out).agents).toMatchObject({ author: { provider: 'claude', model: 'm1' }, reviewer: { provider: 'codex', model: 'gpt-test' } });
});

test('the real search finds ~/.claude, ~/.claude-* and ~/.codex as folders, and nothing else', () => {
  const fakeHome = join(dir, 'search');
  for (const name of ['.claude', '.claude-work', '.claudeish', '.codex', '.codex-old']) mkdirSync(join(fakeHome, name), { recursive: true });
  writeFileSync(join(fakeHome, '.claude.json'), '{}');
  writeFileSync(join(fakeHome, '.claude-file'), '');
  const before = process.env.HOME;
  process.env.HOME = fakeHome;
  try {
    expect(realDeps.configFolders('claude')).toEqual([join(fakeHome, '.claude'), join(fakeHome, '.claude-work')]);
    expect(realDeps.configFolders('codex')).toEqual([join(fakeHome, '.codex')]);
  } finally {
    process.env.HOME = before;
  }
});
