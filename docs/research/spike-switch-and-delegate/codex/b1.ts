// B1: does Codex ask for one tool of an MCP server while another stays pre-approved, and what does the request carry.
// Runs against a scripted fake model (mock.ts) because the real account was at its usage limit.
import { appendFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { App, tmp, here } from './lib.ts';
import { startMock, type Step } from './mock.ts';
import { startToy } from './toy.ts';

const SERVER = 'carrier-chat';
const out = join(here, 'logs', `b1-summary-${process.argv[2] ?? 'all'}.txt`);
writeFileSync(out, '');
const say = (...a: unknown[]) => { const line = a.map((x) => (typeof x === 'string' ? x : JSON.stringify(x))).join(' '); console.log(line); appendFileSync(out, line + '\n'); };

type Variant = 'V0 server approve, no per-tool' | 'V1 server approve + ping_act prompt' | 'V2 server prompt' | 'V3 server auto (default)' | 'V5 server auto + ping_read approve per-tool';
const configOf = (variant: Variant, url: string, token: string) => {
  const base: any = { url, http_headers: { Authorization: `Bearer ${token}` } };
  if (variant.startsWith('V0')) base.default_tools_approval_mode = 'approve';
  if (variant.startsWith('V1')) { base.default_tools_approval_mode = 'approve'; base.tools = { ping_act: { approval_mode: 'prompt' } }; }
  if (variant.startsWith('V2')) base.default_tools_approval_mode = 'prompt';
  if (variant.startsWith('V5')) base.tools = { ping_read: { approval_mode: 'approve' } };
  return { [`mcp_servers.${SERVER}`]: base };
};

type Answer = { action: 'accept' | 'decline' | 'cancel'; meta?: unknown };

async function scenario(o: { variant: Variant; policy: string; answerFor: (tool: string) => Answer; script: (ns: string) => Step[]; label: string; secondTurn?: Step[]; resumeWith?: Variant; otherThread?: boolean }) {
  const folder = tmp('cdxb-');
  const mock = await startMock();
  const toy = await startToy(join(folder, 'ping.log'), folder);
  const app = new App(`b1-${o.label}`, folder, mock.args);
  app.mocked = true;
  app.secrets.push(toy.token);
  const elicitations: any[] = [];
  app.handler = (method, params) => {
    if (method === 'mcpServer/elicitation/request') {
      const tool = guessTool(params);
      const a = o.answerFor(tool);
      elicitations.push({ tool, keys: Object.keys(params), metaKeys: Object.keys(params._meta ?? {}), answer: a.action + (a.meta ? '+meta' : '') });
      if (elicitations.length === 1) elicitations[0].params = JSON.parse(JSON.stringify(params).split(toy.token).join('<TOKEN>'));
      return { action: a.action, content: a.action === 'accept' ? {} : null, ...(a.meta !== undefined && { _meta: a.meta }) };
    }
    throw new Error('unexpected ' + method);
  };
  try {
    await app.init();
    const params: any = { cwd: folder, approvalPolicy: o.policy, sandbox: 'workspace-write', model: 'mock-model', config: configOf(o.variant, toy.url, toy.token) };
    const r = await app.request('thread/start', params);
    const t0 = Date.now();
    while (!app.notes.some((n) => n.method === 'mcpServer/startupStatus/updated' && n.params.name === SERVER && n.params.status === 'ready') && Date.now() - t0 < 8000) await new Promise((x) => setTimeout(x, 50));
    const startup = app.notes.filter((n) => n.method === 'mcpServer/startupStatus/updated' && n.params.name === SERVER).map((n) => n.params.status);
    // Which function name does the MCP tool have? Found from the first model request.
    const ns = await discoverNamespace(app, mock, r.thread.id);
    mock.state.script = o.script(ns);
    const res = await app.turn(r.thread.id, 'go', {}, 30_000);
    const items = res.notes.filter((n) => n.method === 'item/completed' && n.params.item.type === 'mcpToolCall').map((n) => ({ tool: n.params.item.tool, status: n.params.item.status, error: n.params.item.error?.message ?? n.params.item.error ?? null, result: JSON.stringify(n.params.item.result ?? null).slice(0, 80) }));
    const row: any = { label: o.label, startup, turn: res.completed.turn.status, items, elicitations: elicitations.map(({ params, ...x }) => x), pings: toy.calls() };
    if (o.secondTurn) {
      const before = elicitations.length;
      mock.state.script = o.secondTurn.map((s) => ('call' in s ? { ...s, namespace: ns } : s));
      const r2 = await app.turn(r.thread.id, 'again', {}, 30_000);
      row.second = { turn: r2.completed.turn.status, newElicitations: elicitations.length - before, pings: toy.calls() };
    }
    if (o.otherThread) {
      const before = elicitations.length;
      const t2 = await app.request('thread/start', { ...params });
      await new Promise((x) => setTimeout(x, 1500));
      mock.state.script = [{ call: 'ping_act', namespace: ns }, { say: 'done' }];
      const r4 = await app.turn(t2.thread.id, 'other thread', {}, 30_000);
      row.otherThread = { turn: r4.completed.turn.status, newElicitations: elicitations.length - before };
    }
    if (o.resumeWith) {
      // same app-server, thread still running: does the config of a resume apply?
      const before = elicitations.length;
      const rr = await app.request('thread/resume', { threadId: r.thread.id, approvalPolicy: o.policy, sandbox: 'workspace-write', model: 'mock-model', config: configOf(o.resumeWith, toy.url, toy.token) });
      await new Promise((x) => setTimeout(x, 800));
      mock.state.script = [{ call: 'ping_act', namespace: ns }, { say: 'done' }];
      const r3 = await app.turn(r.thread.id, 'after resume', {}, 30_000);
      row.resumeRunning = { to: o.resumeWith, turn: r3.completed.turn.status, newElicitations: elicitations.length - before, pings: toy.calls() };
      void rr;
    }
    return { row, first: elicitations[0]?.params, ns };
  } finally {
    await app.close(); await toy.close(); await mock.close(); rmSync(folder, { recursive: true, force: true });
  }
}

// The tool name the elicitation is about: looked for in the usual places (the value is read from the params, not assumed).
function guessTool(p: any): string {
  const text = JSON.stringify(p);
  if (text.includes('ping_act')) return 'ping_act';
  if (text.includes('ping_read')) return 'ping_read';
  return '?';
}

async function discoverNamespace(app: App, mock: Awaited<ReturnType<typeof startMock>>, threadId: string) {
  // one scripted turn that says nothing, only to read the tool list the model is given
  mock.state.script = [{ say: 'x' }];
  await app.turn(threadId, 'list', {}, 30_000);
  const defs = mock.state.toolDefs;
  const hit = defs.find((t: any) => t.type === 'namespace' && /carrier/.test(t.name));
  return hit?.name ?? '?';
}

const answer = (a: Answer['action']) => (): Answer => ({ action: a });
const both = (s: Step[]) => (ns: string) => s.map((x) => ('call' in x ? { ...x, namespace: ns } : x));
// V5 on the matrix too
const readThenAct = both([{ call: 'ping_read' }, { call: 'ping_act' }, { say: 'done' }]);

const only = process.argv[2];
const results: any[] = [];
const variants: Variant[] = ['V5 server auto + ping_read approve per-tool', 'V0 server approve, no per-tool', 'V1 server approve + ping_act prompt', 'V2 server prompt', 'V3 server auto (default)'];
if (only === undefined || only === 'matrix') {
  for (const variant of variants) for (const policy of ['untrusted', 'on-request', 'never']) for (const a of ['accept', 'decline', 'cancel'] as const) {
    if (policy === 'never' && a !== 'accept') continue; // never asks, the answer does not matter
    const { row, first, ns } = await scenario({ variant, policy, answerFor: answer(a), script: readThenAct, label: `${variant.slice(0, 2)}-${policy}-${a}` });
    say('ROW', variant, policy, a, row);
    if (first && !results.some((x) => x.keys)) { results.push({ keys: true }); say('FIRST ELICITATION PARAMS', first, 'ns', ns); }
  }
}
if (only === undefined || only === 'persist') {
  // accept carrying _meta persist=session on the first ping_act; then the second ping_act in the same turn and again in a second turn
  // (never 'always': that would write the person's config)
  for (const variant of ['V1 server approve + ping_act prompt', 'V2 server prompt', 'V3 server auto (default)', 'V5 server auto + ping_read approve per-tool'] as Variant[]) for (const meta of [{ persist: 'session' }, undefined]) {
    const { row, first } = await scenario({ variant, policy: 'untrusted', answerFor: () => ({ action: 'accept', meta }), script: both([{ call: 'ping_act', args: { note: 'hello world' } }, { call: 'ping_act' }, { say: 'done' }]), label: `persist-${variant.slice(0, 2)}-${meta ? 'session' : 'none'}`, secondTurn: [{ call: 'ping_act' }, { say: 'done' }], otherThread: true });
    say('PERSIST', variant, meta ? 'accept+_meta.persist=session' : 'accept plain', row);
    if (meta) say('  first elicitation _meta', first?._meta, 'message', first?.message);
  }
}
if (only === undefined || only === 'resume') {
  const { row } = await scenario({ variant: 'V0 server approve, no per-tool', policy: 'untrusted', answerFor: answer('accept'), script: both([{ call: 'ping_read' }, { say: 'done' }]), label: 'resume-running', resumeWith: 'V1 server approve + ping_act prompt' });
  say('RESUME (running thread)', row);
}

if (only === undefined || only === 'resume2') {
  // a resume in a NEW app-server process (the thread is not running): does the per-tool config of the resume apply?
  const folder = tmp('cdxb-');
  const mock = await startMock();
  const toy = await startToy(join(folder, 'ping.log'), folder);
  const base = { cwd: folder, approvalPolicy: 'untrusted', sandbox: 'workspace-write', model: 'mock-model' };
  const a1 = new App('b1-resume2-first', folder, mock.args);
  a1.mocked = true;
  a1.secrets.push(toy.token);
  let threadId = '';
  let ns = '';
  try {
    await a1.init();
    a1.handler = () => { throw new Error('no requests expected'); };
    const r = await a1.request('thread/start', { ...base, config: configOf('V0 server approve, no per-tool', toy.url, toy.token) });
    threadId = r.thread.id;
    await new Promise((x) => setTimeout(x, 1500));
    ns = await discoverNamespace(a1, mock, threadId); // one scripted turn, so that the thread has a rollout
  } finally { await a1.close(); }
  for (const [label, cfg] of [['resume with V1 (ping_act prompt)', 'V1 server approve + ping_act prompt'], ['resume with V2 (server prompt)', 'V2 server prompt']] as [string, Variant][]) {
    const a2 = new App('b1-resume2-second', folder, mock.args);
    a2.mocked = true;
    a2.secrets.push(toy.token);
    const el: string[] = [];
    a2.handler = (m, p) => { if (m === 'mcpServer/elicitation/request') { el.push(guessTool(p)); return { action: 'accept', content: {} }; } throw new Error('unexpected ' + m); };
    try {
      await a2.init();
      const rr = await a2.request('thread/resume', { threadId, ...base, config: configOf(cfg, toy.url, toy.token) });
      await new Promise((x) => setTimeout(x, 1500));
      const before = toy.calls().length;
      mock.state.script = [{ call: 'ping_read', namespace: ns }, { call: 'ping_act', namespace: ns }, { say: 'done' }];
      const t = await a2.turn(threadId, 'after resume', {}, 30_000);
      say('RESUME (fresh process)', label, { resumedId: rr.thread.id === threadId, turn: t.completed.turn.status, elicitationsFor: el, pingsAfter: toy.calls().slice(before) });
    } finally { await a2.close(); }
  }
  await toy.close(); await mock.close(); rmSync(folder, { recursive: true, force: true });
}
