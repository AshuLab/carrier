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

/** A role of a written config with the option it points at spread in, to assert on harness, model and provider. */
export function roleOf(written: string, role: 'author' | 'reviewer') {
  const config = JSON.parse(written);
  const agent = config.agents[role];
  return { ...agent, ...config.agentOptions[agent.option] };
}

/** An answer by question; a list answers the same question again and again, in order, and what is left unanswered takes the default. */
type Answers = Record<string, string | boolean | (string | boolean)[]>;

export const quietUi = (scripted: Answers = {}) => {
  const answers: Record<string, string | boolean | undefined> = {};
  for (const message of Object.keys(scripted)) {
    const answer = scripted[message]!;
    const list = Array.isArray(answer) ? [...answer] : undefined;
    Object.defineProperty(answers, message, { get: () => (list ? list.shift() : answer) });
  }
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
