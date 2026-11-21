import { readProvidersFile } from '../config/providers.ts';
import { localLabel, localUrl } from '../harnesses/local.ts';

/**
 * The text-generator port (ADR 0038): a system message and a text in, text out, with no tools.
 * A generator that cannot answer rejects with a `TextGeneratorFailed` that says why: no generator chosen, server down, model missing, time-out or no text.
 * The real one is `realTextGenerator`; the test double is `FakeTextGenerator` in `fake.ts`.
 */
export type TextGenerator = { generate(input: { system: string; text: string }): Promise<string> };

/** Why a generator gave no text, in words for the person: a fixed sentence, never what the server said. */
export class TextGeneratorFailed extends Error {}

/** How long a call may take, for the model and for the host that waits for it. */
export const TEXT_GENERATOR_LIMIT_MS = 30_000;

/** What the host has when nothing is chosen in Providers. */
export const noGeneratorChosen = 'no text generator is chosen; choose one in Providers';

/** What the host has in a test that names no generator. */
export const noTextGenerator: TextGenerator = {
  async generate() {
    throw new TextGeneratorFailed(noGeneratorChosen);
  },
};

// The measured settings of the spike (docs/research/session-titles-model-and-prompt.md): the cap leaves room for a model that reasons before it answers.
const MAX_TOKENS = 3000;

/**
 * Calls the chosen server's `/v1/chat/completions` (LM Studio and Ollama both serve it) on its default port, with the generator
 * `providers.json` names now (read at each call). `fetch` and the limit are replaceable for a test.
 */
export function realTextGenerator({ fetcher = fetch, timeoutMs = TEXT_GENERATOR_LIMIT_MS }: { fetcher?: typeof fetch; timeoutMs?: number } = {}): TextGenerator {
  return {
    async generate({ system, text }) {
      const read = readProvidersFile();
      if (read.ok === false) throw new TextGeneratorFailed(`providers.json does not match: ${read.errors[0]!.path}: ${read.errors[0]!.message}`);
      if (read.textGenerator === undefined) throw new TextGeneratorFailed(noGeneratorChosen);
      const { kind, model } = read.textGenerator;
      const server = localLabel[kind];
      const timedOut = (error: unknown) => error instanceof Error && error.name === 'TimeoutError';
      let response: Response;
      try {
        response = await fetcher(`${localUrl[kind]}/v1/chat/completions`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ model, temperature: 0, max_tokens: MAX_TOKENS, messages: [{ role: 'system', content: system }, { role: 'user', content: text }] }),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (error) {
        if (timedOut(error)) throw new TextGeneratorFailed(`${server} did not answer within ${timeoutMs / 1000} seconds`, { cause: error });
        throw new TextGeneratorFailed(`${server} is not answering at ${localUrl[kind]}; start its server`, { cause: error });
      }
      if (response.status === 404) throw new TextGeneratorFailed(`${server} does not have the model "${model}"`);
      if (response.ok === false) throw new TextGeneratorFailed(`${server} answered with an error (HTTP ${response.status})`);
      let body: { choices?: { message?: { content?: unknown } }[] };
      try {
        body = (await response.json()) as typeof body;
      } catch (error) {
        if (timedOut(error)) throw new TextGeneratorFailed(`${server} did not answer within ${timeoutMs / 1000} seconds`, { cause: error });
        throw new TextGeneratorFailed(`${server} answered with something that is not JSON`, { cause: error });
      }
      const content = body.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || content.trim() === '') throw new TextGeneratorFailed(`${server} answered with no text`);
      return content;
    },
  };
}
