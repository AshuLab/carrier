// Throwaway: a scripted fake of the Responses API on loopback, so that Codex's own approval layer can be exercised with no quota
// (the real account was at its usage limit on 2026-11-16). The "model" does exactly what `script` says, one step per model call.
import { createServer } from 'node:http';
import type { AddressInfo } from 'node:net';

export type Step = { call: string; namespace?: string; args?: unknown } | { say: string };

export async function startMock() {
  const state = { script: [] as Step[], requests: [] as { tools: string[]; lastInputTypes: string[]; outputs: string[] }[], seq: 0, toolDefs: [] as any[] };
  const server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      if (req.method !== 'POST' || !req.url?.includes('/responses')) { res.writeHead(404).end(); return; }
      let body: any = {};
      try { body = JSON.parse(Buffer.concat(chunks).toString()); } catch {}
      const input: any[] = Array.isArray(body.input) ? body.input : [];
      const tools: string[] = (body.tools ?? []).flatMap((t: any) => (t.type === 'namespace' ? (t.tools ?? []).map((x: any) => `${t.name}::${x.name}`) : [t.name ?? t.type]));
      const outputs = input.filter((i) => i.type === 'function_call_output').slice(-2).map((i) => JSON.stringify(i.output).slice(0, 300));
      if (state.seq === 0) state.toolDefs = body.tools;
      state.requests.push({ tools, lastInputTypes: input.slice(-3).map((i) => i.type), outputs });
      const step = state.script.shift() ?? { say: 'done' };
      const id = `resp_${++state.seq}`;
      const ev = (type: string, data: unknown) => `event: ${type}\ndata: ${JSON.stringify({ type, ...(data as object) })}\n\n`;
      let item: unknown;
      if ('say' in step) item = { type: 'message', role: 'assistant', id: `msg_${state.seq}`, content: [{ type: 'output_text', text: step.say }] };
      else item = { type: 'function_call', id: `fc_${state.seq}`, call_id: `call_${state.seq}`, name: step.call, ...(step.namespace && { namespace: step.namespace }), arguments: JSON.stringify(step.args ?? {}) };
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write(ev('response.created', { response: { id } }));
      res.write(ev('response.output_item.done', { item }));
      res.end(ev('response.completed', { response: { id, usage: { input_tokens: 1, input_tokens_details: null, output_tokens: 1, output_tokens_details: null, total_tokens: 2 } } }));
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const port = (server.address() as AddressInfo).port;
  return {
    state,
    url: `http://127.0.0.1:${port}/v1`,
    /** The `-c` pairs that make `codex app-server` use this fake. */
    args: [
      '-c', 'model_provider="mock"',
      '-c', `model_providers.mock={name="mock",base_url="http://127.0.0.1:${port}/v1",wire_api="responses",supports_websockets=false}`,
      '-c', 'model="mock-model"',
    ],
    close: () => new Promise<void>((r) => { server.close(() => r()); server.closeAllConnections(); }),
  };
}
