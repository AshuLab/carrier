import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll } from 'vitest';
import type { Check } from '../../doctor/doctor.ts';
import type { Ui } from '../prompts/types.ts';
import type { InitDeps } from './deps.ts';

// What the init tests share: a scripted terminal, a machine with fakes in every seam, and a folder to write into.

/** A temporary folder, removed when the test file is done. */
export function useTempDir() {
  const dir = mkdtempSync(join(tmpdir(), 'carrier-init-'));
  afterAll(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

/** A role of a written config with the provider it points at spread in, to assert on harness, model and provider. */
export function roleOf(written: string, role: 'author' | 'reviewer' | 'leadReviewer') {
  const config = JSON.parse(written);
  const agent = config.agents[role];
  const provider = config.providers?.[agent.provider];
  return {
    profile: agent.profile,
    harness: provider?.harness,
    model: agent.model,
    ...(provider?.provider && { provider: provider.provider }),
    ...(provider?.configDir && { configDir: provider.configDir }),
    ...(agent.persona && { persona: agent.persona }),
  };
}

/** An answer by question; a list answers the same question again and again, in order, and what is left unanswered takes the default. */
type Answers = Record<string, string | boolean | (string | boolean)[]>;

const questionAliases: Record<string, string[]> = {
  'Add another AI provider?': ['Add another agent option?'],
  'Which agent CLI runs this provider?': ['Which agent CLI runs this option?'],
  'Where does this provider run?': ['Which provider serves the model of this option?'],
  'Config folder of this Claude Code provider': ['Config folder of this Claude Code option'],
  'Config folder of this Codex provider': ['Config folder of this Codex option'],
  'Name of this provider': ['Name of this option'],
  'Which AI provider runs the author?': ['Which option runs the author?'],
  'Which AI provider runs the reviewer?': ['Which option runs the reviewer?'],
  'Model for the author': ['Model of this option'],
  'Model for the reviewer': ['Model of this option'],
};

export const quietUi = (scripted: Answers = {}) => {
  const lists: Record<string, (string | boolean)[]> = {};
  const values: Record<string, string | boolean> = {};
  for (const [k, v] of Object.entries(scripted)) {
    if (Array.isArray(v)) lists[k] = [...v];
    else values[k] = v;
  }
  const take = (k: string) => {
    if (lists[k] && lists[k].length > 0) return lists[k].shift();
    return values[k];
  };
  const getAnswer = (message: string) => {
    const direct = take(message);
    if (direct !== undefined) return direct;
    for (const alias of questionAliases[message] ?? []) {
      const fromAlias = take(alias);
      if (fromAlias !== undefined) return fromAlias;
    }
    return undefined;
  };
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
      const answer = getAnswer(message);
      if (typeof answer === 'string') return answer;
      if (defaultValue !== undefined) return defaultValue;
      throw new Error(`unexpected question: ${message}`);
    },
    select: async ({ message, options, initialValue }) => {
      asked.push(message);
      const answer = getAnswer(message);
      return (typeof answer === 'string' ? answer : (initialValue ?? options[0]!.value)) as never;
    },
    confirm: async (message) => {
      asked.push(message);
      const answer = getAnswer(message);
      return typeof answer === 'boolean' ? answer : message === 'Save it?'; // the final recap is accepted unless a test declines it
    },
    multiselect: async ({ message, options, initialValues }) => {
      asked.push(message);
      const answer = getAnswer(message);
      listed.push(Object.entries(options).map(([group, items]) => `${group}:${items.map((o) => o.label).join(',')}`));
      return typeof answer === 'string' ? answer.split(',') : (initialValues ?? []);
    },
  };
  return { ui, asked, listed };
};

/** Adds a second option (the machine's other CLI, on its defaults) to the first, then stops: Claude on sonnet and Codex on the model it runs with. */
export const twoOptions = { 'Add another agent option?': [true, false] };

export const okCheck: Check = { name: 'x', status: 'ok' };
export const fakeDeps = (over: Partial<InitDeps> = {}) => {
  const written: Record<string, string> = {};
  const deps: InitDeps = {
    which: () => true,
    forgeAgents: () => [{ name: 'artanis-agent', label: 'Artanis' }, { name: 'tassadar-agent' }],
    ghLogin: () => 'diego',
    listRepos: () => ({ names: [], hasMore: false }),
    originRepo: () => 'AshuLab/carrier',
    codexModel: () => 'gpt-test',
    codexModels: () => [],
    agyModels: () => [],
    localModels: async () => Promise.reject(new Error('not running')),
    configFolders: () => [],
    loggedIn: async () => true,
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
