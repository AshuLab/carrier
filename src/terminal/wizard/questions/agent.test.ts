import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { Ui } from '../../prompts/types.ts';
import { antigravityModel, defaultsFor } from './agent.ts';
import { fakeDeps, fakeMachine, quietUi, roleOf, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();

const running = { machine: fakeMachine({ localModels: async (local: string) => (local === 'lmstudio' ? ['google/gemma-4-12b', 'qwen/qwen3.8-27b'] : Promise.reject(new Error('down'))) }) };

const found = (...binaries: string[]) => ({ machine: fakeMachine({ resolveBinary: (name) => (binaries.includes(name) ? `/opt/bin/${name}` : Promise.reject(new Error('not found')) as never) }) });
const agy = (listed: string[]) => ({ ...found('claude', 'codex', 'agy'), agyModels: () => listed.map((value) => ({ value, label: value })) });
const effortOf = (written: Record<string, string>, out: string, role: 'author' | 'reviewer') => JSON.parse(written[out]!).agents[role].effort;

test('defaults: Claude starts on sonnet at high, Codex on the model its own config.toml has, at high', async () => {
  const { deps, written } = fakeDeps({ codexModels: () => [{ value: 'gpt-a', label: 'gpt-a' }, { value: 'gpt-test', label: 'gpt-test' }] });
  const { ui, asked } = quietUi();
  const out = join(dir, 'm.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.filter((q) => q.startsWith('Model for the') || q.startsWith('Effort for the'))).toEqual([]); // nothing to answer: Enter kept the defaults
  expect(roleOf(written, out, 'author')).toMatchObject({ model: 'sonnet' });
  expect(roleOf(written, out, 'reviewer')).toMatchObject({ model: 'gpt-test' });
  expect([effortOf(written, out, 'author'), effortOf(written, out, 'reviewer')]).toEqual(['high', 'high']);
});

test('defaults: with no model in Codex\'s config.toml the first one it lists, and no model id of Codex is in the code', async () => {
  const { deps, written } = fakeDeps({ codexModel: () => undefined, codexModels: () => [{ value: 'gpt-a', label: 'gpt-a' }, { value: 'gpt-b', label: 'gpt-b' }] });
  const out = join(dir, 'm2.json');
  await runInit({ repo: ['A/b'], out }, quietUi().ui, deps);
  expect(roleOf(written, out, 'reviewer')).toMatchObject({ harness: 'codex', model: 'gpt-a' });
  expect(readFileSync(join(import.meta.dirname, 'agent.ts'), 'utf8')).not.toMatch(/gpt-\d|codex-\w+-\d/);
});

test('defaults: Antigravity starts on gemini-4-hydrogen-high with no effort, else on the first model `agy models` lists', async () => {
  for (const [listed, expected] of [[['gemini-3.8-flash-low', antigravityModel], antigravityModel], [['gemini-3.8-flash-low', 'x'], 'gemini-3.8-flash-low'], [[], antigravityModel]] as const) {
    const { deps, written } = fakeDeps(agy([...listed]));
    const out = join(dir, `a-${expected}-${listed.length}.json`);
    await runInit({ repo: ['A/b'], out }, quietUi({ 'Which account runs the author?': 'agy' }).ui, deps);
    expect(roleOf(written, out, 'author')).toMatchObject({ harness: 'agy', model: expected });
    expect(JSON.parse(written[out]!).agents.author).not.toHaveProperty('effort');
  }
});

test('defaultsFor gives the model and effort a harness starts on, and none when a local server offers no model', async () => {
  const { deps } = fakeDeps({ codexModel: () => undefined, codexModels: () => [] });
  expect(await defaultsFor(quietUi().ui, 'claude', undefined, {}, deps)).toEqual({ model: 'sonnet', effort: 'high' });
  expect(await defaultsFor(quietUi().ui, 'codex', undefined, {}, deps)).toEqual({ effort: 'high' }); // nothing to start from: the model is typed
  expect(await defaultsFor(quietUi().ui, 'codex', 'ollama', { ollama: ['qwen3:8b', 'x'] }, deps)).toEqual({ model: 'qwen3:8b', effort: 'high' });
  expect(await defaultsFor(quietUi().ui, 'agy', undefined, {}, deps)).toEqual({ model: antigravityModel });
});

test('"Change them?" opens the model and then the effort, starting from the defaults', async () => {
  const { deps, written } = fakeDeps({ codexModels: () => [{ value: 'gpt-a', label: 'gpt-a' }, { value: 'gpt-test', label: 'gpt-test' }] });
  const initial: Record<string, unknown> = {};
  const { ui, asked } = quietUi({ 'Model and effort: sonnet at high, change them?': true, 'Model for the author': 'opus', 'Effort for the author': 'low' });
  const out = join(dir, 'm3.json');
  await runInit({ repo: ['A/b'], out }, { ...ui, select: async (o) => ((initial[o.message] = o.initialValue), ui.select(o)) }, deps);
  expect(asked.indexOf('Model for the author')).toBeLessThan(asked.indexOf('Effort for the author'));
  expect(initial).toMatchObject({ 'Model for the author': 'sonnet', 'Effort for the author': 'high' });
  expect(roleOf(written, out, 'author').model).toBe('opus');
  expect(effortOf(written, out, 'author')).toBe('low');
});

test('"Other…" in the model list asks for the id', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'Model and effort: sonnet at high, change them?': true, 'Model for the author': '\0other' });
  const withText: Ui = { ...ui, text: async (o) => (o.message === 'Model for the author' ? 'claude-x-1' : ui.text(o)) };
  const out = join(dir, 'n.json');
  await runInit({ repo: ['A/b'], out }, withText, deps);
  expect(roleOf(written, out, 'author').model).toBe('claude-x-1');
});

test('each question has one meaning: harness, then provider (only when there is a choice), then that provider\'s models, then the folder', async () => {
  const { deps, written } = fakeDeps({ ...running, configFolders: (h) => (h === 'codex' ? ['/home/d/.codex'] : []) });
  const selects: Record<string, string[]> = {};
  const { ui } = quietUi({ 'Add another account?': [true, false], 'Which agent CLI runs this account?': 'codex', 'Where does this account run?': 'lmstudio', 'Which account runs the reviewer?': 'codex-2', 'Model and effort: google/gemma-4-12b at high, change them?': true });
  const spy: Ui = { ...ui, select: async (o) => ((selects[o.message] = o.options.map((x) => `${x.value}${x.disabled ? ' (disabled)' : ''}`)), ui.select(o)) };
  const out = join(dir, 'p.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(selects['Which agent CLI runs this account?']).toEqual(['claude', 'codex']); // only the harnesses found, and only harnesses
  expect(selects['Where does this account run?']).toEqual(['\0native', 'lmstudio', 'ollama (disabled)']); // Ollama is there, not running
  expect(selects['Model for the reviewer']).toEqual(['google/gemma-4-12b', 'qwen/qwen3.8-27b', '\0other']); // only LM Studio's models, no cloud ones (the last one asked)
  expect(selects['Config folder of this Codex account']).toEqual(['/home/d/.codex', '\0inherit', '\0path']);
  expect(roleOf(written, out, 'reviewer')).toEqual({ profile: 'tassadar-agent', harness: 'codex', model: 'google/gemma-4-12b', provider: 'lmstudio' });
  expect(roleOf(written, out, 'author')).not.toHaveProperty('provider');
});

test('with no local server running there is no provider question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'p2.json') }, ui, deps);
  expect(asked.some((q) => q.startsWith('Which provider'))).toBe(false);
});

test('a local model id with a colon (Ollama) keeps it whole', async () => {
  const { deps, written } = fakeDeps({ machine: fakeMachine({ localModels: async (local) => (local === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))) }) });
  const { ui } = quietUi({ 'Add another account?': [true, false], 'Where does this account run?': 'ollama', 'Which account runs the author?': 'claude-2', 'Model for the author': 'qwen3:8b' });
  const out = join(dir, 'r.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(roleOf(written, out, 'author')).toMatchObject({ model: 'qwen3:8b', provider: 'ollama' });
});

test('--author-provider goes with the flag form and an unknown server is refused', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 'q.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:qwen3:8b', authorProvider: 'ollama', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(roleOf(written, out, 'author')).toEqual({ profile: 'artanis-agent', harness: 'codex', model: 'qwen3:8b', provider: 'ollama' });
  await expect(runInit({ repo: ['A/b'], author: 'codex:m', authorProvider: 'vllm', authorProfile: 'gh', reviewerProfile: 'forge:x', reviewer: 'claude:s', out }, quietUi().ui, deps)).rejects.toThrow('invalid provider');
});

test('Antigravity: its own models, no provider question even with a local server running, and never a folder', async () => {
  const { deps, written } = fakeDeps({ machine: { ...running.machine, resolveBinary: (name) => `/opt/bin/${name}` }, agyModels: () => [{ value: 'gemini-3.8-flash-low', label: 'gemini-3.8-flash-low', hint: 'Gemini 3.8 Flash (Low)' }] });
  const { ui, asked } = quietUi({ 'Add another account?': [true, false], 'Which agent CLI runs this account?': 'agy', 'Which account runs the author?': 'agy-2' });
  const out = join(dir, 's.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked).not.toContain('Where does this account run?');
  expect(asked.some((q) => q.startsWith('Config folder'))).toBe(false);
  expect(roleOf(written, out, 'author')).toEqual({ profile: 'artanis-agent', harness: 'agy', model: 'gemini-3.8-flash-low' });
});

test('--author agy:<model> is a valid flag form, and a provider on it is refused by the config', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 't.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'agy:gemini-3.8-flash-low', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(roleOf(written, out, 'author').harness).toBe('agy');
  await expect(runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'agy:m', authorProvider: 'lmstudio', reviewer: 'claude:sonnet', out }, quietUi().ui, deps)).rejects.toThrow('agy cannot use the provider "lmstudio"');
});
