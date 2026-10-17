import { expect, test } from 'vitest';
import { claudeLocalEnv, listLocalModels } from './local.ts';

test('LM Studio: the chat models, without the embedding ones', async () => {
  const urls: string[] = [];
  const models = await listLocalModels('lmstudio', async (url) => (urls.push(url), { data: [{ id: 'qwen/qwen3.8-27b' }, { id: 'text-embedding-nomic-embed-text-v1.5' }, { id: 'google/gemma-4-12b' }] }));
  expect(models).toEqual(['qwen/qwen3.8-27b', 'google/gemma-4-12b']);
  expect(urls).toEqual(['http://localhost:1234/v1/models']);
});

test('Ollama: the names it has pulled', async () => {
  expect(await listLocalModels('ollama', async () => ({ models: [{ name: 'qwen3:8b' }, {}] }))).toEqual(['qwen3:8b']);
});

test('a server that does not answer is an error, not an empty list', async () => {
  await expect(listLocalModels('ollama', async () => Promise.reject(new Error('ECONNREFUSED')))).rejects.toThrow('ECONNREFUSED');
});

test('the Claude env never carries a real key', () => {
  expect(claudeLocalEnv('lmstudio')).toEqual({ ANTHROPIC_BASE_URL: 'http://localhost:1234', ANTHROPIC_AUTH_TOKEN: 'lmstudio', ANTHROPIC_API_KEY: '' });
});
