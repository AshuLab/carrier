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
  };
  return { ui, asked };
};

const okCheck: Check = { name: 'x', status: 'ok' };
const fakeDeps = (over: Partial<InitDeps> = {}) => {
  const written: Record<string, string> = {};
  const deps: InitDeps = {
    which: () => true,
    forgeAgents: () => [{ name: 'artanis-agent', label: 'Artanis' }, { name: 'tassadar-agent' }],
    ghLogin: () => 'diego',
    originRepo: () => 'AshuLab/carrier',
    codexModel: () => 'gpt-test',
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
