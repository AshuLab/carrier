import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { defaults, loadConfig } from '../../../config/load.ts';
import type { Ui } from '../../prompts/types.ts';
import { realDeps } from '../deps.ts';
import { fakeDeps, quietUi, twoOptions, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();
const home = join(dir, 'home');
const folders = { configFolders: (h: string) => (h === 'claude' ? ['/h/.claude', '/h/.claude-ashu-lab'] : ['/h/.codex']), loggedIn: async (_h: string, d?: string) => d !== '/h/.claude' };
const load = (written: string) => {
  const loaded = loadConfig(defaults, JSON.parse(written));
  expect(loaded.ok).toBe(true);
  return JSON.parse(written);
};

test('the folder is chosen among the ones found, each with its login state, plus the environment and a typed path', async () => {
  const { deps, written } = fakeDeps({ ...folders, which: (c) => c !== 'agy' });
  const seen: Record<string, { value: string; hint?: string }[]> = {};
  const { ui } = quietUi({ 'Config folder of this Claude Code option': '/h/.claude-ashu-lab', 'Add another agent option?': [true, false], 'Which agent CLI runs this option?': ['claude', 'claude'] });
  const spy: Ui = { ...ui, select: async (o) => ((seen[o.message] = o.options.map(({ value, hint }) => ({ value, hint }))), ui.select(o)) };
  const out = join(dir, 'f1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(seen['Config folder of this Claude Code option']).toEqual([
    { value: '/h/.claude', hint: 'not logged in' },
    { value: '/h/.claude-ashu-lab', hint: 'logged in' },
    { value: '\0inherit', hint: 'the login Carrier runs in: logged in' },
    { value: '\0path', hint: undefined },
  ]);
  const config = load(written[out]!);
  expect(config.agentOptions).toEqual({ 'claude-ashu-lab': { harness: 'claude', model: 'sonnet', configDir: '/h/.claude-ashu-lab' }, 'claude-ashu-lab-2': { harness: 'claude', model: 'sonnet', configDir: '/h/.claude-ashu-lab' } });
});

test('a typed path is validated, and a login that cannot be checked is said so', async () => {
  const { deps, written } = fakeDeps({ loggedIn: async () => Promise.reject(new Error('no cli')) });
  const { ui } = quietUi({ 'Config folder of this Claude Code option': '\0path' });
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
  expect(load(written[out]!).agentOptions).toEqual({ 'claude-x': { harness: 'claude', model: 'sonnet', configDir: '~/.claude-x' } });
});

test('the name is suggested from harness and folder, must be a lowercase word and unique, and the question repeats until it is', async () => {
  const { deps, written } = fakeDeps(folders);
  const { ui, asked } = quietUi({ 'Add another agent option?': [true, true, false], 'Which agent CLI runs this option?': ['claude', 'codex', 'codex'], 'Config folder of this Claude Code option': '/h/.claude', 'Config folder of this Codex option': '/h/.codex', 'Name of this option': [undefined as never, undefined as never, 'x'] });
  const names: Array<(string | undefined)[]> = [];
  const spy: Ui = { ...ui, text: async (o) => (o.message === 'Name of this option' ? (names.push([o.defaultValue, o.validate?.('Codex'), o.validate?.('1a'), o.validate?.('claude'), o.validate?.('ok-1')]), ui.text(o)) : ui.text(o)) };
  const out = join(dir, 'n1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(names.map(([suggested]) => suggested)).toEqual(['claude', 'codex', 'codex-2']); // `~/.claude` -> claude, `~/.codex` -> codex, and the third codex is not the first
  expect(names[1]!.slice(1).map((v) => v !== undefined)).toEqual([true, true, true, false]); // uppercase, digit first and the taken `claude` are refused; `ok-1` is fine
  expect(asked.filter((q) => q === 'Add another agent option?')).toHaveLength(3);
  expect(Object.keys(load(written[out]!).agentOptions)).toEqual(['claude', 'codex', 'x']);
});

test('each role asks one question, which option runs it, and the choices are the options created', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ 'Add another agent option?': [true, false], 'Which option runs the reviewer?': 'claude', 'Which option runs the author?': 'codex' });
  const choices: Record<string, string[]> = {};
  const spy: Ui = { ...ui, select: async (o) => ((choices[o.message] = o.options.map((x) => x.value)), ui.select(o)) };
  const out = join(dir, 'r1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(choices['Which option runs the author?']).toEqual(['claude', 'codex']);
  expect(asked.some((q) => q.startsWith('Which agent CLI runs the') || q.startsWith('Model for the'))).toBe(false);
  expect(load(written[out]!).agents).toMatchObject({ author: { option: 'codex' }, reviewer: { option: 'claude' } });
});

test('with one option the roles are not asked, and neither is failover', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'r2.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.some((q) => q.startsWith('Which option runs') || q.startsWith('Turn failover'))).toBe(false);
  const config = load(written[out]!);
  expect(config.agents).toMatchObject({ author: { option: 'claude' }, reviewer: { option: 'claude' } });
  expect(config).not.toHaveProperty('failover');
});

test('with two or more options failover is asked, and "yes" asks the order until the person is done', async () => {
  const three = { 'Add another agent option?': [true, true, false], 'Which agent CLI runs this option?': ['claude', 'claude', 'codex'], 'Config folder of this Claude Code option': ['/h/.claude', '/h/.claude-ashu-lab'] };
  const { deps, written } = fakeDeps(folders);
  const { ui } = quietUi({ ...three, 'Turn failover on? A role that runs out of credits then moves to the next option you list, so its code can reach another provider.': true, 'Failover order: which option goes first?': 'codex', 'Failover order: which option goes next?': ['claude', '\0done'] });
  const picks: Record<string, string[]> = {};
  const spy: Ui = { ...ui, select: async (o) => ((picks[o.message] = o.options.map((x) => x.value)), ui.select(o)) };
  const out = join(dir, 'fo1.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(picks['Failover order: which option goes first?']).toEqual(['claude', 'claude-ashu-lab', 'codex']);
  expect(picks['Failover order: which option goes next?']).toEqual(['claude-ashu-lab', '\0done']); // codex and claude are already in; the person ends it here
  expect(load(written[out]!).failover).toEqual({ enabled: true, order: ['codex', 'claude'] });

  const off = fakeDeps();
  const no = quietUi(twoOptions);
  const outOff = join(dir, 'fo2.json');
  await runInit({ repo: ['A/b'], out: outOff }, no.ui, off.deps);
  expect(no.asked.some((q) => q.startsWith('Turn failover'))).toBe(true); // asked, and declined
  expect(load(off.written[outOff]!)).not.toHaveProperty('failover');
});

test('running again on an existing config keeps its options and failover, adds more, and preselects each role\'s option', async () => {
  const existing = {
    repos: [{ name: 'X/y' }],
    profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
    orchestratorProfile: 'tassadar-agent',
    agentOptions: { work: { harness: 'claude', model: 'opus', configDir: '~/.claude-work' }, codex: { harness: 'codex', model: 'gpt-test' } },
    failover: { enabled: true, order: ['codex'] },
    agents: { author: { profile: 'tassadar-agent', option: 'codex' }, reviewer: { profile: 'gh', option: 'work' } },
  };
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => existing });
  const { ui, asked } = quietUi({ 'Add another agent option?': [true, false], 'Which agent CLI runs this option?': 'agy', 'Model of this option': 'gemini-x' });
  const initial: Record<string, unknown> = {};
  const spy: Ui = { ...ui, select: async (o) => ((initial[o.message] = o.initialValue), ui.select(o)), text: async (o) => (o.message === 'Model of this option' ? 'gemini-x' : ui.text(o)) };
  process.env.CARRIER_HOME = home;
  try {
    await runInit({}, spy, deps);
  } finally {
    delete process.env.CARRIER_HOME;
  }
  expect(initial['Which option runs the author?']).toBe('codex');
  expect(initial['Which option runs the reviewer?']).toBe('work');
  expect(asked).not.toContain('Where should the config be saved?');
  expect(asked.some((q) => q.startsWith('Turn failover'))).toBe(false);
  const config = load(written[join(home, 'config.json')]!);
  expect(config.agentOptions).toEqual({ ...existing.agentOptions, agy: { harness: 'agy', model: 'gemini-x' } });
  expect(config.failover).toEqual(existing.failover);
  expect(config.agents).toEqual(existing.agents);
});

test('the flags declare the options and skip the section, the failover question and the role question', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'u1.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'claude:m1', reviewer: 'claude:m2', out, yes: true }, ui, deps);
  expect(asked.filter((q) => !q.startsWith('outro') && !q.startsWith('checks:'))).toEqual([]);
  const config = load(written[out]!);
  expect(config.agentOptions).toEqual({ claude: { harness: 'claude', model: 'm1' }, 'claude-reviewer': { harness: 'claude', model: 'm2' } });
  expect(config).not.toHaveProperty('failover');
});

test('one flag declares one option; the section then offers more and the other role picks among them', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi({ 'Add another agent option?': [true, false] });
  const out = join(dir, 'u2.json');
  await runInit({ repo: ['A/b'], author: 'claude:m1', out }, ui, deps);
  expect(asked).not.toContain('Which option runs the author?');
  expect(asked).toContain('Which option runs the reviewer?');
  expect(load(written[out]!).agents).toMatchObject({ author: { option: 'claude' }, reviewer: { option: 'codex' } });
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
