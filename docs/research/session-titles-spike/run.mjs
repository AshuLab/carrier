// Usage: node run.mjs <model> <promptId> <out.json>
// Sends every pair of pairs.mjs, one at a time, to LM Studio's /v1/chat/completions on this Mac and records what came back and how long it took.
import { writeFileSync } from 'node:fs';
import { pairs } from './pairs.mjs';
import { prompts, userMessage } from './prompts.mjs';

const [model, promptId, out] = process.argv.slice(2);
const prompt = prompts[promptId];
if (!prompt) throw new Error(`unknown prompt ${promptId}`);
const cut = (s) => (s.length <= 2000 ? s : `${s.slice(0, 1999)}…`); // the spec: each text cut to 2,000 characters
const LIMIT_MS = 120_000; // generous on purpose: the spec's limit is 30 s and the note counts what would pass it

async function call(system, user) {
  const t0 = performance.now();
  try {
    const res = await fetch('http://localhost:1234/v1/chat/completions', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      signal: AbortSignal.timeout(LIMIT_MS),
      body: JSON.stringify({ model, temperature: 0, max_tokens: 3000, messages: [{ role: 'system', content: system }, { role: 'user', content: user }] }),
    });
    const j = await res.json();
    const ms = Math.round(performance.now() - t0);
    if (j.error) return { ms, error: JSON.stringify(j.error) };
    const m = j.choices[0].message;
    return { ms, content: m.content ?? '', reasoningTokens: j.usage?.completion_tokens_details?.reasoning_tokens ?? 0, completionTokens: j.usage?.completion_tokens ?? 0, finish: j.choices[0].finish_reason };
  } catch (e) {
    return { ms: Math.round(performance.now() - t0), error: String(e) };
  }
}

const warm = await call(prompt.system, userMessage(prompt, { first: 'hola', reply: 'hola' })); // loads the model; its time is the load, not a title
const results = [];
for (const p of pairs) {
  const r = await call(prompt.system, userMessage(prompt, { first: cut(p.first), reply: cut(p.reply) }));
  results.push({ id: p.id, ...r });
  process.stderr.write(`${p.id} ${r.ms}ms ${JSON.stringify(r.content ?? r.error)}\n`);
}
writeFileSync(out, JSON.stringify({ model, promptId, warmupMs: warm.ms, warmupError: warm.error, results }, null, 1));
