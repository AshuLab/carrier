// B6 (finishing pass): (a) what the MODEL receives back for an MCP tool call that is accepted, declined, cancelled or refused by `never`,
// and the full elicitation params with arguments (V1); (b) does a session-persist accept on ping_act also cover ping_read;
// (c) curl with its exit code inside each sandbox. Scripted fake model (mock.ts), real `codex app-server`; no real model turn.
import { appendFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { App, tmp, here } from './lib.ts';
import { startMock, type Step } from './mock.ts';
import { startToy } from './toy.ts';

const out = join(here, 'logs', 'b6-summary.txt');
writeFileSync(out, '');
const say = (...a: unknown[]) => { const line = a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(' '); console.log(line); appendFileSync(out, line + '\n'); };

const cfg = (url: string, token: string, extra: object) => ({ 'mcp_servers.carrier-chat': { url, http_headers: { Authorization: `Bearer ${token}` }, ...extra } });

async function mcp(label: string, policy: string, extra: object, answer: (tool: string) => any, steps: (ns: string) => Step[]) {
  const folder = tmp('cdxb-'); const mock = await startMock(); const toy = await startToy(join(folder, 'ping.log'), folder);
  const app = new App(`b6-${label}`, folder, mock.args); app.mocked = true; app.secrets.push(toy.token);
  const els: any[] = [];
  app.handler = (m, p) => { if (m !== 'mcpServer/elicitation/request') throw new Error('unexpected ' + m); const tool = p._meta?.tool_name; els.push({ tool, params: JSON.parse(JSON.stringify(p)) }); return answer(tool); };
  try {
    await app.init();
    const r = await app.request('thread/start', { cwd: folder, approvalPolicy: policy, sandbox: 'workspace-write', model: 'mock-model', config: cfg(toy.url, toy.token, extra) });
    for (let i = 0; i < 160 && !app.notes.some((n) => n.method === 'mcpServer/startupStatus/updated' && n.params.name === 'carrier-chat' && n.params.status === 'ready'); i++) await new Promise((x) => setTimeout(x, 50));
    mock.state.script = [{ say: 'x' }]; await app.turn(r.thread.id, 'list', {}, 30_000);
    const ns = mock.state.toolDefs.find((t: any) => t.type === 'namespace' && /carrier/.test(t.name))?.name;
    mock.state.script = steps(ns);
    mock.state.requests.length = 0;
    const res = await app.turn(r.thread.id, 'go', {}, 30_000);
    say('MCP', label, { policy, turn: res.completed.turn.status, elicitedTools: els.map((e) => e.tool), pings: toy.calls(), modelSaw: mock.state.requests.map((q) => q.outputs.at(-1) ?? null).filter(Boolean) });
    return els;
  } finally { await app.close(); await toy.close(); await mock.close(); rmSync(folder, { recursive: true, force: true }); }
}
const call = (...tools: [string, unknown?][]) => (ns: string): Step[] => [...tools.map(([t, a]) => ({ call: t, namespace: ns, args: a })), { say: 'done' }];
const V1 = { default_tools_approval_mode: 'approve', tools: { ping_act: { approval_mode: 'prompt' } } };

// (a) what the model sees
for (const a of ['accept', 'decline', 'cancel'] as const) {
  const els = await mcp(`V1-untrusted-${a}`, 'untrusted', V1, () => ({ action: a, content: a === 'accept' ? {} : null }), call(['ping_read'], ['ping_act', { note: 'hello world' }]));
  if (a === 'accept') say('V1 FULL ELICITATION PARAMS (with arguments)', els[0].params);
}
await mcp('V1-never', 'never', V1, () => ({ action: 'accept', content: {} }), call(['ping_read'], ['ping_act', { note: 'hello world' }]));
// (b) persist=session on ping_act, then ping_read: auto mode (V3)
await mcp('V3-persist-act-then-read', 'untrusted', {}, () => ({ action: 'accept', content: {}, _meta: { persist: 'session' } }), call(['ping_act'], ['ping_read'], ['ping_act'], ['ping_read']));
// (b2) same in V1 (the persist key is not offered there): the second act asks again
await mcp('V1-persist-act-twice', 'untrusted', V1, () => ({ action: 'accept', content: {}, _meta: { persist: 'session' } }), call(['ping_act'], ['ping_act']));

// (c) curl with exit code
const folder = tmp('cdxb-');
try {
  for (const [sandbox, policy] of [['read-only', 'on-request'], ['workspace-write', 'on-request'], ['workspace-write', 'never']] as const) {
    const mock = await startMock(); const app = new App(`b6-curl-${sandbox}-${policy}`, folder, mock.args); app.mocked = true;
    const asked: string[] = [];
    app.handler = (m) => { asked.push(m); return m.includes('requestApproval') ? { decision: 'decline' } : {}; };
    try {
      await app.init();
      const r = await app.request('thread/start', { cwd: folder, approvalPolicy: policy, sandbox, model: 'mock-model' });
      mock.state.script = [{ call: 'exec_command', args: { cmd: 'curl -sS -I --max-time 10 https://example.com 2>&1 | head -2; echo rc=$?; curl -sS --max-time 10 -o /dev/null -w "%{http_code}" https://example.com 2>&1; echo " rc=$?"' } }, { say: 'done' }];
      mock.state.requests.length = 0;
      await app.turn(r.thread.id, 'curl', {}, 60_000);
      say('CURL', sandbox, policy, { asked, modelSaw: mock.state.requests.at(-1)?.outputs.at(-1)?.replace(/\\n/g, ' ').slice(0, 400) });
    } finally { await app.close(); await mock.close(); }
  }
} finally { rmSync(folder, { recursive: true, force: true }); }
