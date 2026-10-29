import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { Ui } from '../../prompts/types.ts';
import { fakeDeps, quietUi, roleOf, twoOptions, useTempDir } from '../testing.ts';
import { runInit } from '../wizard.ts';

const dir = useTempDir();

const running = { localModels: async (local: string) => (local === 'lmstudio' ? ['google/gemma-4-12b', 'qwen/qwen3.8-27b'] : Promise.reject(new Error('down'))) };

test('the model is picked from what the CLI offers; Codex starts on the model it already runs with', async () => {
  const { deps, written } = fakeDeps({ codexModels: () => [{ value: 'gpt-a', label: 'gpt-a' }, { value: 'gpt-test', label: 'gpt-test' }] });
  const { ui, asked } = quietUi(twoOptions);
  const out = join(dir, 'm.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked.filter((q) => q.startsWith('Model for the'))).toHaveLength(2); // a select each, answered by its initial value
  expect(roleOf(written[out]!, 'author')).toMatchObject({ model: 'sonnet' });
  expect(roleOf(written[out]!, 'reviewer')).toMatchObject({ model: 'gpt-test' });
});

test('"Other…" in the model list asks for the id', async () => {
  const { deps, written } = fakeDeps();
  const { ui } = quietUi({ 'Model for the author': '\0other' });
  const withText: Ui = { ...ui, text: async (o) => (o.message === 'Model for the author' ? 'claude-x-1' : ui.text(o)) };
  const out = join(dir, 'n.json');
  await runInit({ repo: ['A/b'], out }, withText, deps);
  expect(roleOf(written[out]!, 'author').model).toBe('claude-x-1');
});

test('each question has one meaning: harness, then provider (only when there is a choice), then that provider\'s models, then the folder', async () => {
  const { deps, written } = fakeDeps({ ...running, configFolders: (h) => (h === 'codex' ? ['/home/d/.codex'] : []) });
  const selects: Record<string, string[]> = {};
  const { ui } = quietUi({ ...twoOptions, 'Where does this provider run?': ['\0native', 'lmstudio'] });
  const spy: Ui = { ...ui, select: async (o) => ((selects[o.message] = o.options.map((x) => `${x.value}${x.disabled ? ' (disabled)' : ''}`)), ui.select(o)) };
  const out = join(dir, 'p.json');
  await runInit({ repo: ['A/b'], out }, spy, deps);
  expect(selects['Which agent CLI runs this provider?']).toEqual(['claude', 'codex', 'agy']); // only harnesses
  expect(selects['Where does this provider run?']).toEqual(['\0native', 'lmstudio', 'ollama (disabled)']); // Ollama is there, not running
  expect(selects['Model for the reviewer']).toEqual(['google/gemma-4-12b', 'qwen/qwen3.8-27b', '\0other']); // only LM Studio's models, no cloud ones (the last one asked)
  expect(selects['Config folder of this Codex provider']).toEqual(['/home/d/.codex', '\0inherit', '\0path']);
  expect(roleOf(written[out]!, 'reviewer')).toEqual({ profile: 'tassadar-agent', harness: 'codex', model: 'google/gemma-4-12b', provider: 'lmstudio' });
  expect(roleOf(written[out]!, 'author')).not.toHaveProperty('provider');
});

test('with no local server running there is no provider question', async () => {
  const { deps } = fakeDeps();
  const { ui, asked } = quietUi();
  await runInit({ repo: ['A/b'], out: join(dir, 'p2.json') }, ui, deps);
  expect(asked.some((q) => q.startsWith('Which provider'))).toBe(false);
});

test('a local model id with a colon (Ollama) keeps it whole', async () => {
  const { deps, written } = fakeDeps({ localModels: async (local) => (local === 'ollama' ? ['qwen3:8b'] : Promise.reject(new Error('down'))) });
  const { ui } = quietUi({ 'Where does this provider run?': 'ollama', 'Model for the author': 'qwen3:8b' });
  const out = join(dir, 'r.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(roleOf(written[out]!, 'author')).toMatchObject({ model: 'qwen3:8b', provider: 'ollama' });
});

test('--author-provider goes with the flag form and an unknown server is refused', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 'q.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'codex:qwen3:8b', authorProvider: 'ollama', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(roleOf(written[out]!, 'author')).toEqual({ profile: 'artanis-agent', harness: 'codex', model: 'qwen3:8b', provider: 'ollama' });
  await expect(runInit({ repo: ['A/b'], author: 'codex:m', authorProvider: 'vllm', authorProfile: 'gh', reviewerProfile: 'forge:x', reviewer: 'claude:s', out }, quietUi().ui, deps)).rejects.toThrow('invalid provider');
});

test('Antigravity: its own models, no provider question even with a local server running, and never a folder', async () => {
  const { deps, written } = fakeDeps({ ...running, agyModels: () => [{ value: 'gemini-3.8-flash-low', label: 'gemini-3.8-flash-low', hint: 'Gemini 3.8 Flash (Low)' }] });
  const { ui, asked } = quietUi({ 'Which agent CLI runs this provider?': 'agy' });
  const out = join(dir, 's.json');
  await runInit({ repo: ['A/b'], out }, ui, deps);
  expect(asked).not.toContain('Where does this provider run?');
  expect(asked.some((q) => q.startsWith('Config folder'))).toBe(false);
  expect(roleOf(written[out]!, 'author')).toEqual({ profile: 'artanis-agent', harness: 'agy', model: 'gemini-3.8-flash-low' });
});

test('--author agy:<model> is a valid flag form, and a provider on it is refused by the config', async () => {
  const { deps, written } = fakeDeps();
  const out = join(dir, 't.json');
  await runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'agy:gemini-3.8-flash-low', reviewer: 'claude:sonnet', out }, quietUi().ui, deps);
  expect(roleOf(written[out]!, 'author').harness).toBe('agy');
  await expect(runInit({ repo: ['A/b'], authorProfile: 'forge:artanis-agent', reviewerProfile: 'gh', author: 'agy:m', authorProvider: 'lmstudio', reviewer: 'claude:sonnet', out }, quietUi().ui, deps)).rejects.toThrow('agy cannot use the provider "lmstudio"');
});
