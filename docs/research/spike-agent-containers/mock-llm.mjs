// Mock minimo de las APIs de modelo (Anthropic Messages y OpenAI Responses) para probar los CLI sin credenciales reales.
// Uso: node mock-llm.mjs <puerto> <log.jsonl>
import http from 'node:http';
import { appendFileSync } from 'node:fs';
const [port, logFile] = [Number(process.argv[2]), process.argv[3]];
let n = 0;

const lastUserText = (blocks) => {
  const t = [];
  for (const b of blocks ?? []) {
    if (typeof b === 'string') t.push(b);
    else if (b?.type === 'text' || b?.type === 'input_text') t.push(b.text);
  }
  return t.join('\n');
};

function decide(body, flavor) {
  const raw = JSON.stringify(body);
  let last, isToolResult = false;
  if (flavor === 'anthropic') {
    const m = (body.messages ?? []).filter((x) => x.role === 'user' || x.role === 'assistant').at(-1);
    isToolResult = Array.isArray(m?.content) && m.content.some((b) => b.type === 'tool_result');
    last = typeof m?.content === 'string' ? m.content : lastUserText(m?.content);
  } else {
    const items = Array.isArray(body.input) ? body.input : [];
    const m = items.filter((x) => x.type === 'function_call_output' || x.role === 'user').at(-1);
    isToolResult = m?.type === 'function_call_output';
    last = m?.role === 'user' ? lastUserText(m.content) : '';
  }
  if (isToolResult) return { text: 'DONE' };
  const g = /GITFLOW:(.*)/s.exec(last);
  if (g) return { tool: g[1].trim() };
  if (/RECALL/.test(last)) {
    const hits = [...new Set(raw.match(/TANGERINE-\d+/g) ?? [])];
    // el prompt actual no contiene el codigo: si aparece, vino del historial de la sesion
    return { text: 'RECALLED:' + (hits.join(',') || 'NONE') };
  }
  return { text: 'OK' };
}

const sse = (res, events) => {
  res.writeHead(200, { 'content-type': 'text/event-stream' });
  for (const [e, d] of events) res.write(`event: ${e}\ndata: ${JSON.stringify(d)}\n\n`);
  res.end();
};

function anthropic(body, res) {
  const d = decide(body, 'anthropic');
  const id = 'msg_mock' + ++n;
  const model = body.model ?? 'mock';
  const usage = { input_tokens: 10, output_tokens: 5 };
  if (body.stream === false || body.stream === undefined) {
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify({ id, type: 'message', role: 'assistant', model, content: [{ type: 'text', text: d.text ?? 'OK' }], stop_reason: 'end_turn', stop_sequence: null, usage }));
  }
  const ev = [['message_start', { type: 'message_start', message: { id, type: 'message', role: 'assistant', model, content: [], stop_reason: null, stop_sequence: null, usage } }]];
  if (d.tool) {
    ev.push(['content_block_start', { type: 'content_block_start', index: 0, content_block: { type: 'tool_use', id: 'toolu_mock' + n, name: 'Bash', input: {} } }]);
    ev.push(['content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'input_json_delta', partial_json: JSON.stringify({ command: d.tool, description: 'run' }) } }]);
  } else {
    ev.push(['content_block_start', { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } }]);
    ev.push(['content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: d.text } }]);
  }
  ev.push(['content_block_stop', { type: 'content_block_stop', index: 0 }]);
  ev.push(['message_delta', { type: 'message_delta', delta: { stop_reason: d.tool ? 'tool_use' : 'end_turn', stop_sequence: null }, usage: { output_tokens: 5 } }]);
  ev.push(['message_stop', { type: 'message_stop' }]);
  sse(res, ev);
}

function responses(body, res) {
  const d = decide(body, 'openai');
  const rid = 'resp_mock' + ++n;
  const base = { id: rid, object: 'response', status: 'in_progress', model: body.model ?? 'mock', output: [] };
  const ev = [['response.created', { type: 'response.created', response: base }]];
  let item;
  if (d.tool) {
    item = { type: 'function_call', id: 'fc_mock' + n, call_id: 'call_mock' + n, name: process.env.MOCK_CODEX_TOOL ?? 'shell', arguments: JSON.stringify(process.env.MOCK_CODEX_TOOL === 'exec_command' ? { cmd: d.tool } : { command: ['bash', '-lc', d.tool] }), status: 'completed' };
    ev.push(['response.output_item.added', { type: 'response.output_item.added', output_index: 0, item }]);
  } else {
    item = { type: 'message', id: 'msg_mock' + n, role: 'assistant', status: 'completed', content: [{ type: 'output_text', text: d.text, annotations: [] }] };
    ev.push(['response.output_item.added', { type: 'response.output_item.added', output_index: 0, item: { ...item, content: [] } }]);
    ev.push(['response.output_text.delta', { type: 'response.output_text.delta', item_id: item.id, output_index: 0, content_index: 0, delta: d.text }]);
  }
  ev.push(['response.output_item.done', { type: 'response.output_item.done', output_index: 0, item }]);
  ev.push(['response.completed', { type: 'response.completed', response: { ...base, status: 'completed', output: [item], usage: { input_tokens: 10, output_tokens: 5, total_tokens: 15, input_tokens_details: { cached_tokens: 0 }, output_tokens_details: { reasoning_tokens: 0 } } } }]);
  sse(res, ev);
}

http.createServer((req, res) => {
  const chunks = [];
  req.on('data', (c) => chunks.push(c));
  req.on('end', () => {
    let body = {};
    try { body = JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch {}
    appendFileSync(logFile, JSON.stringify({ method: req.method, url: req.url, ua: req.headers['user-agent'], hasAuth: Boolean(req.headers.authorization || req.headers['x-api-key']), body }) + '\n');
    if (req.url.startsWith('/v1/messages') && req.method === 'POST') return anthropic(body, res);
    if (req.url.startsWith('/v1/responses') && req.method === 'POST') return responses(body, res);
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end('{"error":"mock: not implemented"}');
  });
}).listen(port, '0.0.0.0', () => console.log('mock on', port));
