import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, expect, test } from 'vitest';
import type { Check } from '../doctor/doctor.ts';
import { buildConfig, parseIdentity, parseProviderModel } from './build-config.ts';
import { readForgeAgents } from './forge-registry.ts';
import { runInit, type InitDeps, type Ui } from './wizard.ts';

const dir = mkdtempSync(join(tmpdir(), 'carrier-init-'));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

const quietUi = (answers: Record<string, string | boolean> = {}) => {
  const asked: string[] = [];
  const listed: string[][] = [];
  const ui: Ui = {
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
      return answers[message] === true;
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
    localModels: async () => Promise.reject(new Error('not running')),
    exists: () => false,
    write: (path, content) => (written[path] = content),
    doctor: async () => [okCheck],
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
      author: { profile: 'artanis-agent', provider: 'claude', model: 'sonnet' },
      reviewer: { profile: 'tassadar-agent', provider: 'codex', model: 'gpt-test' }, // author's bot is not offered again; codex default from ~/.codex
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
  expect(asked.filter((a) => !a.startsWith('outro'))).toEqual([]);
  expect(JSON.parse(written[out]!).agents).toEqual({
    author: { profile: 'artanis-agent', provider: 'codex', model: 'm1' },
    reviewer: { profile: 'gh', provider: 'claude', model: 'm2' },
  });
});

test('the repo of the current folder is the suggested answer', async () => {
  const { deps, written } = fakeDeps();
  await runInit({ out: join(dir, 'c.json') }, quietUi().ui, deps); // the scripted ui takes the default
  expect(JSON.parse(written[join(dir, 'c.json')]!).repos).toEqual([{ name: 'AshuLab/carrier' }]);
});

test('with no Forge agents the reviewer has nothing left, and the error says what to do', async () => {
  const { deps } = fakeDeps({ forgeAgents: () => [] });
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
    author: { identity: parseIdentity('gh'), ...parseProviderModel('claude:sonnet') },
    reviewer: { identity: parseIdentity('forge:bot'), ...parseProviderModel('codex:x:y') },
  });
  expect(config.profiles).toEqual({ gh: { kind: 'gh' }, bot: { kind: 'forge', agent: 'bot' } });
  expect(config.agents.reviewer).toEqual({ profile: 'bot', provider: 'codex', model: 'x:y' });
  expect(() => parseIdentity('forge')).toThrow('invalid identity');
  expect(() => parseProviderModel('gpt:4')).toThrow('invalid agent');
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
    'GitHub identity for the author', 'Which agent runs the author?', 'Model for the author',
    'GitHub identity for the reviewer', 'Which agent runs the reviewer?', 'Model for the reviewer',
  ]);
});

const running = { localModels: async (local: string) => (local === 'lmstudio' ? ['google/gemma-4-12b', 'qwen/qwen3.8-27b'] : Promise.reject(new Error('down'))) };

test('a local server that is running is offered next to Claude and Codex, and the choice sets `local`', async () => {
  const { deps, written } = fakeDeps(running);
  const selects: Record<string, string[]> = {};
  const { ui } = quietUi({ 'Which agent runs the reviewer?': 'local:lmstudio' });
  const spy: Ui = { ...ui, select: async (o) => ((selects[o.message] = o.options.map((x) => `${x.value}${x.disabled ? ' (disabled)' : ''}`)), ui.select(o)) };
  const out = join(dir, 'p.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(selects['Which agent runs the reviewer?']).toEqual(['claude', 'codex', 'local:lmstudio', 'local:ollama (disabled)']); // Ollama is there, but not running
  expect(JSON.parse(written[out]!).agents.reviewer).toEqual({ profile: 'tassadar-agent', provider: 'codex', model: 'google/gemma-4-12b', local: 'lmstudio' });
  expect(JSON.parse(written[out]!).agents.author).not.toHaveProperty('local');
});

test('--author-local goes with the flag form and an unknown server is refused', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 'q.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:qwen3:8b', authorLocal: 'ollama', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(JSON.parse(written[out]!).agents.author).toEqual({ profile: 'artanis-agent', provider: 'codex', model: 'qwen3:8b', local: 'ollama' });
  await expect(runInit({ repo: ['A/b'], author: 'codex:m', authorLocal: 'vllm', authorProfile: 'gh', reviewerProfile: 'forge:x', reviewer: 'claude:s', out }, quietUi().ui, deps)).rejects.toThrow('invalid local server');
});
