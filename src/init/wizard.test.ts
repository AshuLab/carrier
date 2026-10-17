import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, expect, test } from 'vitest';
import type { Check } from '../doctor/doctor.ts';
import { buildConfig, parseIdentity, parseHarnessModel } from './build-config.ts';
import { readForgeAgents } from './forge-registry.ts';
import { Cancelled, runInit, type InitDeps, type Ui } from './wizard.ts';

const dir = mkdtempSync(join(tmpdir(), 'carrier-init-'));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const quietUi = (answers: Record<string, string | boolean> = {}) => {
  const asked: string[] = [];
  const listed: string[][] = [];
  const ui: Ui = {
    interactive: true,
    checkStart: () => {},
    checksEnd: (total, failed) => void asked.push(`checks:${total}/${failed}`),
    intro: () => {},
    outro: (m) => asked.push(`outro:${m}`),
    note: () => {},
    warn: (m) => asked.push(`warn:${m}`),
    check: () => {},
    text: async ({ message, defaultValue }) => {
      asked.push(message);
      const answer = answers[message];
      if (typeof answer === 'string') return answer;
      if (defaultValue !== undefined) return defaultValue;
      throw new Error(`unexpected question: ${message}`);
    },
    select: async ({ message, options, initialValue }) => {
      asked.push(message);
      const answer = answers[message];
      return (typeof answer === 'string' ? answer : (initialValue ?? options[0]!.value)) as never;
    },
    confirm: async (message) => {
      asked.push(message);
      const answer = answers[message];
      return typeof answer === 'boolean' ? answer : message === 'Save it?'; // the final recap is accepted unless a test declines it
    },
    multiselect: async ({ message, options, initialValues }) => {
      asked.push(message);
      const answer = answers[message];
      listed.push(Object.entries(options).map(([group, items]) => `${group}:${items.map((o) => o.label).join(',')}`));
      return typeof answer === 'string' ? answer.split(',') : (initialValues ?? []);
    },
  };
  return { ui, asked, listed };
};

const okCheck: Check = { name: 'x', status: 'ok' };
const fakeDeps = (over: Partial<InitDeps> = {}) => {
  const written: Record<string, string> = {};
  const deps: InitDeps = {
    which: () => true,
    forgeAgents: () => [{ name: 'artanis-agent', label: 'Artanis' }, { name: 'tassadar-agent' }],
    ghLogin: () => 'diego',
    listRepos: () => [],
    originRepo: () => 'AshuLab/carrier',
    codexModel: () => 'gpt-test',
    codexModels: () => [],
    agyModels: () => [],
    localModels: async () => Promise.reject(new Error('not running')),
    exists: () => false,
    write: (path, content) => (written[path] = content),
    doctor: async () => [okCheck],
    readConfig: () => ({}),
    forgeAdd: () => false,
    readyEpics: async () => ({}),
    ...over,
  };
  return { deps, written };
};

test('the questions fill a config that has only what defaults lack, and the doctor runs on it', async () => {
  let doctored: unknown;
  const { deps, written } = fakeDeps({ doctor: async (config) => ((doctored = config), [okCheck]) });
  const { ui, asked } = quietUi({ 'Repos to watch (owner/name, comma separated)': 'AshuLab/a, AshuLab/b' });
  const out = join(dir, 'a.json');
  const result = await runInit({ out }, ui, deps);

  expect(JSON.parse(written[out]!)).toEqual({
    repos: [{ name: 'AshuLab/a' }, { name: 'AshuLab/b' }],
    profiles: { 'artanis-agent': { kind: 'forge', agent: 'artanis-agent' }, 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' } },
    orchestratorProfile: 'artanis-agent',
    agents: {
      author: { profile: 'artanis-agent', harness: 'claude', model: 'sonnet' },
      reviewer: { profile: 'tassadar-agent', harness: 'codex', model: 'gpt-test' }, // author's bot is not offered again; codex default from ~/.codex
    },
  });
  expect(doctored).toMatchObject({ pollIntervalMinutes: 5 }); // the doctor gets the merged config
  expect(result.checks).toEqual([okCheck]);
  expect(asked.at(-1)).toContain(`carrier --config ${out}`);
});

test('every flag skips its question', async () => {
  const { deps, written } = fakeDeps();
  const { ui, asked } = quietUi();
  const out = join(dir, 'b.json');
  await runInit({ repo: ['AshuLab/x'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:m1', reviewer: 'claude:m2', out, yes: true }, ui, deps);
  expect(asked.filter((a) => !a.startsWith('outro') && !a.startsWith('checks:'))).toEqual([]);
  expect(JSON.parse(written[out]!).agents).toEqual({
    author: { profile: 'artanis-agent', harness: 'codex', model: 'm1' },
    reviewer: { profile: 'gh', harness: 'claude', model: 'm2' },
  });
});

test('the repo of the current folder is the suggested answer', async () => {
  const { deps, written } = fakeDeps();
  await runInit({ out: join(dir, 'c.json') }, quietUi().ui, deps); // the scripted ui takes the default
  expect(JSON.parse(written[join(dir, 'c.json')]!).repos).toEqual([{ name: 'AshuLab/carrier' }]);
});

test('with no Forge agents the reviewer has nothing left, and the error says what to do', async () => {
  const { deps } = fakeDeps({ forgeAgents: () => [], which: (c) => c !== 'agent-forge' }); // and no way to add one from here
  await expect(runInit({ out: join(dir, 'd.json') }, quietUi().ui, deps)).rejects.toThrow('agent-forge add');
});

test('the same identity twice is refused before anything is written', async () => {
  const { deps, written } = fakeDeps();
  await expect(runInit({ repo: ['AshuLab/x'], authorProfile: 'gh', reviewerProfile: 'gh', out: join(dir, 'e.json') }, quietUi().ui, deps)).rejects.toThrow('must differ');
  expect(written).toEqual({});
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

test('failed checks are reported in the closing line', async () => {
  const { deps } = fakeDeps({ doctor: async () => [{ name: 'gh installed', status: 'fail' }] });
  const { ui, asked } = quietUi();
  await runInit({ out: join(dir, 'g.json') }, ui, deps);
  expect(asked.at(-1)).toContain('1 check failed');
  expect(asked.at(-1)).toContain('carrier doctor --config');
});

test('buildConfig names a forge profile after its agent and the login "gh"', () => {
  const config = buildConfig({
    repos: ['A/b'],
    author: { identity: parseIdentity('gh'), ...parseHarnessModel('claude:sonnet') },
    reviewer: { identity: parseIdentity('forge:bot'), ...parseHarnessModel('codex:x:y') },
  });
  expect(config.profiles).toEqual({ gh: { kind: 'gh' }, bot: { kind: 'forge', agent: 'bot' } });
  expect(config.agents.reviewer).toEqual({ profile: 'bot', harness: 'codex', model: 'x:y' });
  expect(() => parseIdentity('forge')).toThrow('invalid identity');
  expect(() => parseHarnessModel('gpt:4')).toThrow('invalid agent');
});

test('the Forge registry yields names and labels, and nothing when there is none', () => {
  const file = join(dir, 'agents.json');
  writeFileSync(file, JSON.stringify({ agents: [{ name: 'a', label: 'A', privateKeyPath: '/secret' }, { name: 'b' }, { nope: 1 }] }));
  expect(readForgeAgents(file)).toEqual([{ name: 'a', label: 'A' }, { name: 'b' }]);
  expect(readForgeAgents(join(dir, 'missing.json'))).toEqual([]);
  writeFileSync(file, '{');
  expect(() => readForgeAgents(file)).toThrow();
});

const repoKey = 'Repos to watch';

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

test('the model is picked from what the CLI offers; Codex starts on the model it already runs with', async () => {
  const { deps, written } = fakeDeps({ codexModels: () => [{ value: 'gpt-a', label: 'gpt-a' }, { value: 'gpt-test', label: 'gpt-test' }] });
  const { ui, asked } = quietUi();
  const out = join(dir, 'm.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked).toContain('Model for the author'); // a select, answered by its initial value
  expect(JSON.parse(written[out]!).agents).toMatchObject({ author: { model: 'sonnet' }, reviewer: { model: 'gpt-test' } });
});

test('"Other…" in the model list asks for the id', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'Model for the author': '\0other' });
  // the text prompt then answers with its default (none for a claude alias list), so give it one
  const withText: Ui = { ...ui, text: async (o) => (o.message === 'Model for the author' ? 'claude-x-1' : ui.text(o)) };
  const out = join(dir, 'n.json');
  await runInit({ repo: ['A/b'], out }, withText, deps);
  expect(JSON.parse(written[out]!).agents.author.model).toBe('claude-x-1');
});

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

test('each role gets its own box, and the author is fully asked before the reviewer', async () => {
  const notes: string[] = [];
  const order: string[] = [];
  const { ui } = quietUi();
  const spy: Ui = {
    ...ui,
    note: (_m, title) => notes.push(title),
    select: async (o) => (order.push(o.message), ui.select(o)),
    text: async (o) => (order.push(o.message), ui.text(o)),
  };
  await runInit({ repo: ['A/b'], out: join(dir, 'o.json') }, spy, fakeDeps().deps);
  expect(notes.filter((t) => t === 'Author' || t === 'Reviewer')).toEqual(['Author', 'Reviewer']);
  expect(order.filter((m) => /author|reviewer/.test(m))).toEqual([
    'GitHub identity for the author', 'Which agent CLI runs the author?', 'Model for the author',
    'GitHub identity for the reviewer', 'Which agent CLI runs the reviewer?', 'Model for the reviewer',
  ]);
});

const running = { localModels: async (local: string) => (local === 'lmstudio' ? ['google/gemma-4-12b', 'qwen/qwen3.8-27b'] : Promise.reject(new Error('down'))) };

test('three questions, each with one meaning: harness, then provider (only when there is a choice), then that provider\'s models', async () => {
  const { deps, written } = fakeDeps(running);
  const selects: Record<string, string[]> = {};
  const { ui } = quietUi({ 'Which provider serves the reviewer\'s model?': 'lmstudio' });
  const spy: Ui = { ...ui, select: async (o) => ((selects[o.message] = o.options.map((x) => `${x.value}${x.disabled ? ' (disabled)' : ''}`)), ui.select(o)) };
  const out = join(dir, 'p.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(selects['Which agent CLI runs the reviewer?']).toEqual(['claude', 'codex', 'agy']); // only harnesses
  expect(selects['Which provider serves the reviewer\'s model?']).toEqual(['\0native', 'lmstudio', 'ollama (disabled)']); // Ollama is there, not running
  expect(selects['Model for the reviewer']).toEqual(['google/gemma-4-12b', 'qwen/qwen3.8-27b', '\0other']); // only LM Studio's models, no cloud ones
  expect(JSON.parse(written[out]!).agents.reviewer).toEqual({ profile: 'tassadar-agent', harness: 'codex', model: 'google/gemma-4-12b', provider: 'lmstudio' });
  expect(JSON.parse(written[out]!).agents.author).not.toHaveProperty('provider');
});

test('with no local server running there is no provider question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'p2.json') }, ui, deps);
  expect(asked.some((q) => q.startsWith('Which provider'))).toBe(false);
});

test('a local model id with a colon (Ollama) keeps it whole', async () => {
  const { deps, written } = fakeDeps({ localModels: async (local) => (local === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))) });
  const { ui } = quietUi({ 'Which provider serves the author\'s model?': 'ollama', 'Model for the author': 'qwen3:8b' });
  const out = join(dir, 'r.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(JSON.parse(written[out]!).agents.author).toMatchObject({ model: 'qwen3:8b', provider: 'ollama' });
});

test('--author-provider goes with the flag form and an unknown server is refused', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 'q.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:qwen3:8b', authorProvider: 'ollama', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(JSON.parse(written[out]!).agents.author).toEqual({ profile: 'artanis-agent', harness: 'codex', model: 'qwen3:8b', provider: 'ollama' });
  await expect(runInit({ repo: ['A/b'], author: 'codex:m', authorProvider: 'vllm', authorProfile: 'gh', reviewerProfile: 'forge:x', reviewer: 'claude:s', out }, quietUi().ui, deps)).rejects.toThrow('invalid provider');
});

test('Antigravity: its own models, and no provider question even with a local server running (it cannot use one)', async () => {
  const { deps, written } = fakeDeps({ ...running, agyModels: () => [{ value: 'gemini-3.8-flash-low', label: 'gemini-3.8-flash-low', hint: 'Gemini 3.8 Flash (Low)' }] });
  const { ui, asked } = quietUi({ 'Which agent CLI runs the author?': 'agy' });
  const out = join(dir, 's.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked).not.toContain("Which provider serves the author's model?");
  expect(JSON.parse(written[out]!).agents.author).toEqual({ profile: 'artanis-agent', harness: 'agy', model: 'gemini-3.8-flash-low' });
});

test('--author agy:<model> is a valid flag form, and a provider on it is refused by the config', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 't.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'agy:gemini-3.8-flash-low', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(JSON.parse(written[out]!).agents.author.harness).toBe('agy');
  await expect(runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'agy:m', authorProvider: 'lmstudio', reviewer: 'claude:sonnet', out }, quietUi().ui, deps)).rejects.toThrow('agy cannot use the provider "lmstudio"');
});

const withHome = async <T>(run: () => Promise<T>) => {
  process.env.CARRIER_HOME = join(dir, 'home');
  try {
    return await run();
  } finally {
    delete process.env.CARRIER_HOME;
  }
};
const existingKey = `A config already exists at ${join(dir, 'home', 'config.json')}`;
const existing = {
  repos: [{ name: 'X/y' }, { name: 'X/z' }],
  profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
  orchestratorProfile: 'tassadar-agent',
  agents: { author: { profile: 'tassadar-agent', harness: 'claude', model: 'opus' }, reviewer: { profile: 'gh', harness: 'codex', model: 'gpt-test' } },
};

test('the recap lists what will be saved, and declining it writes nothing', async () => {
  const { deps, written } = fakeDeps();
  const notes: Record<string, string> = {};
  const { ui } = quietUi({ 'Save it?': false });
  const spy: Ui = { ...ui, note: (m, title) => void (notes[title] = m) };
  await expect(runInit({ repo: ['A/b'], out: join(dir, 'u.json') }, spy, deps)).rejects.toBeInstanceOf(Cancelled);
  expect(written).toEqual({});
  expect(notes['This is what will be saved']).toMatch(/Repos {5}A\/b\nAuthor {4}artanis-agent · Claude Code · sonnet\nReviewer {2}tassadar-agent · Codex · gpt-test\nSaved to {2}/);
});

test('--yes skips the recap and the start question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'v.json'), yes: true }, ui, deps);
  expect(asked).not.toContain('Save it?');
  expect(asked.some((q) => q.startsWith('Start Carrier'))).toBe(false);
});

test('an existing config can be edited: its answers are the starting points and no question about the file is asked', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => existing });
  const { ui, asked } = quietUi();
  await withHome(() => runInit({}, ui, deps));
  const [path] = Object.keys(written);
  expect(path).toBe(join(dir, 'home', 'config.json'));
  expect(JSON.parse(written[path!]!)).toEqual({
    repos: [{ name: 'X/y' }, { name: 'X/z' }],
    profiles: { 'tassadar-agent': { kind: 'forge', agent: 'tassadar-agent' }, gh: { kind: 'gh' } },
    orchestratorProfile: 'tassadar-agent',
    agents: { author: { profile: 'tassadar-agent', harness: 'claude', model: 'opus' }, reviewer: { profile: 'gh', harness: 'codex', model: 'gpt-test' } },
  });
  expect(asked).not.toContain('Where should the config be saved?');
  expect(asked.some((q) => q.endsWith('exists. Overwrite it?'))).toBe(false);
});

test('"Start over" ignores the old answers but still replaces that file without asking again', async () => {
  const { deps, written } = fakeDeps({ exists: () => true, readConfig: () => existing });
  const { ui } = quietUi({ [existingKey]: 'fresh' });
  await withHome(() => runInit({}, ui, deps));
  expect(JSON.parse(written[join(dir, 'home', 'config.json')]!).repos).toEqual([{ name: 'AshuLab/carrier' }]); // the origin suggestion, not the old repos
});

test('"Leave it as it is" cancels, and an unreadable config is said so instead of crashing', async () => {
  const left = fakeDeps({ exists: () => true });
  await expect(withHome(() => runInit({}, quietUi({ [existingKey]: 'cancel' }).ui, left.deps))).rejects.toBeInstanceOf(Cancelled);
  expect(left.written).toEqual({});
  const broken = fakeDeps({ exists: () => true, readConfig: () => ({ nope: 1 }) });
  const { ui, asked } = quietUi();
  await withHome(() => runInit({}, ui, broken.deps));
  expect(asked.some((q) => q.startsWith('warn:') && q.includes('is not a valid config'))).toBe(true);
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

test('after good checks it shows what is waiting and offers to start; with failed checks it does neither', async () => {
  const notes: Record<string, string> = {};
  const good = fakeDeps({ readyEpics: async () => ({ 'AshuLab/carrier': 2, 'AshuLab/x': undefined }) });
  const { ui } = quietUi({ 'Start Carrier now? (Ctrl+C stops it)': true });
  const result = await runInit({ repo: ['A/b'], out: join(dir, 'z.json') }, { ...ui, note: (m, t) => void (notes[t] = m) }, good.deps);
  expect(result.start).toBe(true);
  expect(notes['Waiting for Carrier']).toBe('AshuLab/carrier: 2 epics marked ready\nAshuLab/x: could not read');

  let asked = 0;
  const bad = fakeDeps({ doctor: async () => [{ name: 'gh installed', status: 'fail' }], readyEpics: async () => (asked += 1, {}) });
  const failed = await runInit({ repo: ['A/b'], out: join(dir, 'z2.json') }, quietUi().ui, bad.deps);
  expect([failed.start, asked]).toEqual([false, 0]);
});

test('a machine that is fine shows nothing about itself, and the checks end with one count', async () => {
  const notes: string[] = [];
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'm1.json') }, { ...ui, note: (_m, t) => void notes.push(t) }, fakeDeps().deps);
  expect(notes).not.toContain('This machine');
  expect(asked).toContain('checks:1/0'); // the fake doctor ran one check
  expect(asked.some((q) => q.startsWith('warn:'))).toBe(false);
});

test('what cannot work at all stops before any question, each with how to fix it', async () => {
  const { ui, asked } = quietUi();
  await expect(runInit({ repo: ['A/b'] }, ui, fakeDeps({ which: (c) => c !== 'gh' }).deps)).rejects.toThrow(/Carrier needs these before it can run:\n {2}gh: install the GitHub CLI/);
  await expect(runInit({ repo: ['A/b'] }, ui, fakeDeps({ which: (c) => c === 'git' || c === 'gh' }).deps)).rejects.toThrow(/an agent CLI, any of these:\n {4}claude: install Claude Code .*\n {4}codex: .*\n {4}agy: /);
  expect(asked).toEqual([]); // nothing was asked
});

test('gh without a login is a warning, not a stop', async () => {
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'm2.json') }, ui, fakeDeps({ ghLogin: () => undefined }).deps);
  expect(asked.find((q) => q.startsWith('warn:gh is not logged in'))).toContain('gh auth login');
});
