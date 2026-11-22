import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { realTextGenerator, TextGeneratorFailed } from './text-generator.ts';

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'tg-'));
  vi.stubEnv('CARRIER_HOME', dir);
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

const choose = (file: object) => writeFileSync(join(dir, 'providers.json'), JSON.stringify(file));
const lmstudio = { textGenerators: { local: { kind: 'lmstudio', model: 'google/gemma-4-e4b' } }, textGenerator: 'local' };
const answer = (body: unknown, status = 200) => async (..._call: unknown[]) => new Response(JSON.stringify(body), { status });
const input = { system: 'You write titles', text: 'Fix the sidebar' };

test('it posts a system message and the text with no tools to the chosen server on its default port, and answers the text of the first choice', async () => {
  choose(lmstudio);
  const fetcher = vi.fn(answer({ choices: [{ message: { content: 'Sidebar fix' } }] }));
  expect(await realTextGenerator({ fetcher }).generate(input)).toBe('Sidebar fix');
  const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit];
  expect(url).toBe('http://localhost:1234/v1/chat/completions');
  expect(init.method).toBe('POST');
  const body = JSON.parse(init.body as string);
  expect(body).toEqual({ model: 'google/gemma-4-e4b', temperature: 0, max_tokens: 3000, messages: [{ role: 'system', content: 'You write titles' }, { role: 'user', content: 'Fix the sidebar' }] });
  expect(body).not.toHaveProperty('tools');
});

test('an Ollama generator goes to Ollama\'s port', async () => {
  choose({ textGenerators: { local: { kind: 'ollama', model: 'qwen3:4b' } }, textGenerator: 'local' });
  const fetcher = vi.fn(answer({ choices: [{ message: { content: 'x' } }] }));
  await realTextGenerator({ fetcher }).generate(input);
  expect(fetcher.mock.calls[0]![0]).toBe('http://localhost:11434/v1/chat/completions');
});

test('the generator is read from providers.json at each call', async () => {
  const fetcher = vi.fn(answer({ choices: [{ message: { content: 'x' } }] }));
  const generator = realTextGenerator({ fetcher });
  await expect(generator.generate(input)).rejects.toThrow('no text generator is chosen; choose one in Providers');
  choose(lmstudio);
  await generator.generate(input);
  expect(fetcher).toHaveBeenCalledTimes(1);
});

test('a providers.json that does not match, or that names no generator, makes no call and says so', async () => {
  const fetcher = vi.fn(answer({}));
  choose({ textGenerator: 'ghost' });
  await expect(realTextGenerator({ fetcher }).generate(input)).rejects.toThrow(/providers\.json does not match: textGenerator: .*ghost/);
  choose({ providers: { claude: { harness: 'claude' } } });
  await expect(realTextGenerator({ fetcher }).generate(input)).rejects.toBeInstanceOf(TextGeneratorFailed);
  expect(fetcher).not.toHaveBeenCalled();
});

test('a reply with no text is a failure, whatever shape it has', async () => {
  choose(lmstudio);
  for (const body of [{ choices: [{ message: { content: '' } }] }, { choices: [{ message: { content: '  \n' } }] }, { choices: [] }, {}, { choices: [{ message: { content: null } }] }]) {
    await expect(realTextGenerator({ fetcher: answer(body) }).generate(input)).rejects.toThrow('LM Studio answered with no text');
  }
});

test('a 404 says the model is missing, another status says the server\'s error, and neither echoes the server\'s words', async () => {
  choose(lmstudio);
  await expect(realTextGenerator({ fetcher: answer({ error: 'secret details' }, 404) }).generate(input)).rejects.toThrow('LM Studio does not have the model "google/gemma-4-e4b"');
  await expect(realTextGenerator({ fetcher: answer({ error: 'secret details' }, 500) }).generate(input)).rejects.toThrow('LM Studio answered with an error (HTTP 500)');
  await expect(realTextGenerator({ fetcher: answer({ error: 'secret details' }, 500) }).generate(input)).rejects.not.toThrow(/secret/);
});

test('a server that is not running says where to start it', async () => {
  choose(lmstudio);
  const fetcher = async () => {
    throw new TypeError('fetch failed');
  };
  await expect(realTextGenerator({ fetcher }).generate(input)).rejects.toThrow('LM Studio is not answering at http://localhost:1234; start its server');
});

test('a call that passes the limit is aborted and says it timed out', async () => {
  choose(lmstudio);
  const fetcher = (_url: string | URL | Request, init?: RequestInit) =>
    new Promise<Response>((_resolve, reject) => init!.signal!.addEventListener('abort', () => reject(init!.signal!.reason)));
  await expect(realTextGenerator({ fetcher, timeoutMs: 20 }).generate(input)).rejects.toThrow('LM Studio did not answer within 0.02 seconds');
});

test('an answer that is not JSON is a failure', async () => {
  choose(lmstudio);
  await expect(realTextGenerator({ fetcher: async () => new Response('<html>') }).generate(input)).rejects.toThrow('LM Studio answered with something that is not JSON');
});
