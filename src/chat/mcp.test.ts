import { createHash } from 'node:crypto';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { z } from 'zod';
import { FakeClock } from '../orchestration/fake.ts';
import { capabilities } from './mcp/capabilities.ts';
import { agents } from './mcp/agents.ts';
import { delegateStart, delegateWait } from './mcp/delegate.ts';
import { history } from './mcp/history.ts';
import { delegationRefusal } from './levels.ts';
import { defineTool, McpSessionRegistry, startMcpServer, type McpServer, type McpSessions, type StoredEvent } from './mcp.ts';
import { ChatRefused } from './runner.ts';

const DAY = 24 * 60 * 60_000;

let clock: FakeClock;
let registry: McpSessionRegistry;
let server: McpServer;
let existing: Set<string>;
let liveOnes: Set<string>;
let seen: { args: unknown; ctx: unknown }[];
let started: { parentId: string; args: unknown }[];

const echo = defineTool({
  name: 'test_echo',
  description: 'Reads, for any token',
  access: 'reads',
  input: z.strictObject({ text: z.string() }),
  handler: (args, ctx) => {
    seen.push({ args, ctx });
    return { said: args.text };
  },
});
const whoami = defineTool({
  name: 'test_whoami',
  description: 'Reads as the session',
  access: 'readsAsSession',
  input: z.strictObject({}),
  handler: (args, ctx) => {
    seen.push({ args, ctx });
    return { session: ctx.sessionId };
  },
});
const change = defineTool({
  name: 'test_change',
  description: 'Acts as the session',
  access: 'actsAsSession',
  input: z.strictObject({}),
  handler: () => 'changed',
});
const refuses = defineTool({
  name: 'test_refuses',
  description: 'Says why not',
  access: 'reads',
  input: z.strictObject({}),
  handler: () => {
    throw new ChatRefused('Not today');
  },
});
const breaks = defineTool({
  name: 'test_breaks',
  description: 'Fails with a detail that is not for the agent',
  access: 'reads',
  input: z.strictObject({}),
  handler: () => {
    throw new Error('disk said secret things');
  },
});
const tools = [echo, whoami, change, refuses, breaks];

beforeEach(async () => {
  clock = new FakeClock();
  registry = new McpSessionRegistry(clock);
  existing = new Set(['s1']);
  liveOnes = new Set(['s1']);
  seen = [];
  started = [];
  server = await startMcpServer({ registry, tools, sessions: { exists: (id) => existing.has(id), live: (id) => liveOnes.has(id), snapshot: () => { throw new Error('not used'); }, agents: () => [], agentOptions: () => ({}), offer: async () => [], health: async () => ({ git: 'ready', gh: 'ready', agents: [] }), storedEvents: () => [], storedEvent: () => undefined, toolStatuses: () => ({}), delegationRefusal: () => undefined, startChild: async (parentId, args) => (started.push({ parentId, args }), { childId: 'child-1' }), related: () => false, waitChildren: async () => [] } });
});
afterEach(() => server.close());

const post = (token: string | undefined, body: unknown, headers: Record<string, string> = {}) =>
  fetch(server.url, { method: 'POST', headers: { 'content-type': 'application/json', ...(token !== undefined && { authorization: `Bearer ${token}` }), ...headers }, body: typeof body === 'string' ? body : JSON.stringify(body) });
const rpc = async (token: string, method: string, params?: unknown) => {
  const res = await post(token, { jsonrpc: '2.0', id: 1, method, ...(params !== undefined && { params }) });
  expect(res.status).toBe(200);
  return (await res.json()) as { id: unknown; result?: any; error?: { code: number; message: string } };
};
const call = (token: string, name: string, args?: unknown) => rpc(token, 'tools/call', { name, ...(args !== undefined && { arguments: args }) });
const issue = (capabilities?: ('read' | 'act')[], sessionId = 's1', invocationId = 'i1') => registry.issue({ sessionId, invocationId, ...(capabilities && { capabilities }) });

test('the registry issues 32 random bytes as base64url and keeps only their hash', () => {
  const a = issue();
  const b = issue();
  expect(a).toMatch(/^[A-Za-z0-9_-]{43}$/);
  expect(a).not.toBe(b);
  const keys = [...(registry as any).records.keys()];
  expect(keys).toContain(createHash('sha256').update(a).digest('hex'));
  expect(JSON.stringify([...(registry as any).records.values()])).not.toContain(a);
  expect(registry.lookup(a)).toMatchObject({ sessionId: 's1', invocationId: 'i1', capabilities: new Set(['read']) });
});

test('a token expires after 24 hours without activity and a valid lookup refreshes it', () => {
  const token = issue();
  clock.time = DAY;
  expect(registry.lookup(token)?.lastAliveAt).toBe(DAY); // exactly 24 hours is still alive
  clock.time = 2 * DAY;
  expect(registry.lookup(token)).toBeDefined(); // refreshed a day ago
  clock.time = 3 * DAY + 1;
  expect(registry.lookup(token)).toBeUndefined();
  clock.time = 3 * DAY + 2;
  expect(registry.lookup(token)).toBeUndefined(); // and it stays gone
});

test('revoking by invocation takes only that conversation', () => {
  const a = issue(undefined, 's1', 'i1');
  const b = issue(undefined, 's1', 'i2');
  registry.revokeByInvocation('i1');
  expect(registry.lookup(a)).toBeUndefined();
  expect(registry.lookup(b)).toBeDefined();
  registry.revokeAll();
  expect(registry.lookup(b)).toBeUndefined();
});

test('the server binds loopback on an ephemeral port at /mcp', () => {
  expect(server.url).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/mcp$/);
});

test('401 when the bearer token is missing, malformed, unknown, revoked or expired', async () => {
  const token = issue();
  const ping = { jsonrpc: '2.0', id: 1, method: 'ping' };
  for (const authorization of [undefined, 'Basic abc', 'Bearer', 'Bearer short', `Bearer ${'A'.repeat(43)}`, token, `bearer ${token}`]) {
    const res = await fetch(server.url, { method: 'POST', headers: { ...(authorization && { authorization }) }, body: JSON.stringify(ping) });
    expect(res.status, String(authorization)).toBe(401);
  }
  expect((await post(token, ping)).status).toBe(200);
  registry.revokeByInvocation('i1');
  expect((await post(token, ping)).status).toBe(401);
  const idle = issue();
  clock.time = DAY + 1;
  expect((await post(idle, ping)).status).toBe(401);
});

test('405 for anything but POST, 404 for another path', async () => {
  const token = issue();
  for (const method of ['GET', 'PUT', 'DELETE']) {
    const res = await fetch(server.url, { method, headers: { authorization: `Bearer ${token}` } });
    expect(res.status).toBe(405);
    expect(res.headers.get('allow')).toBe('POST');
  }
  expect((await fetch(server.url.replace('/mcp', '/other'), { method: 'POST' })).status).toBe(404);
});

test('413 for a body over 1 MiB, and one right at the limit gets through', async () => {
  const token = issue();
  const padded = (bytes: number) => JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'ping', params: { pad: '' } }).replace('""', `"${'x'.repeat(bytes - 60)}"`);
  const huge = padded(1024 * 1024 + 1);
  expect(Buffer.byteLength(huge)).toBe(1024 * 1024 + 1);
  expect((await post(token, huge)).status).toBe(413);
  // chunked, with no content-length to read first
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(new TextEncoder().encode(huge));
      controller.close();
    },
  });
  const chunked = await fetch(server.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: stream, duplex: 'half' } as RequestInit);
  expect(chunked.status).toBe(413);
  const fits = padded(1024 * 1024);
  expect(Buffer.byteLength(fits)).toBe(1024 * 1024);
  expect((await post(token, fits)).status).toBe(200);
});

test('malformed JSON is -32700 and a body that is not JSON-RPC is -32600', async () => {
  const token = issue();
  const bad = await post(token, '{"jsonrpc":');
  expect(bad.status).toBe(200);
  expect(await bad.json()).toEqual({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } });
  for (const body of [[], 'null', { jsonrpc: '1.0', id: 1, method: 'x' }, [{ jsonrpc: '2.0', id: 1, method: 'ping' }]]) {
    const res = await post(token, body);
    expect(((await res.json()) as any).error.code).toBe(-32600);
  }
});

test('initialize, server/discover, ping and unknown methods', async () => {
  const token = issue();
  const init = await rpc(token, 'initialize', { protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'x', version: '1' } });
  expect(init.result).toMatchObject({ protocolVersion: '2025-03-26', capabilities: { tools: {} }, serverInfo: { name: 'carrier-chat' } });
  expect((await rpc(token, 'initialize', { protocolVersion: '1999-01-01' })).result.protocolVersion).toBe('2025-06-18');
  expect((await rpc(token, 'server/discover')).result).toMatchObject({ supportedVersions: expect.arrayContaining(['2025-06-18']), serverInfo: { name: 'carrier-chat' } });
  expect((await rpc(token, 'ping')).result).toEqual({});
  expect((await rpc(token, 'resources/list')).error?.code).toBe(-32601);
});

test('notifications get 202 and no body, known or not', async () => {
  const token = issue();
  for (const method of ['notifications/initialized', 'notifications/whatever']) {
    const res = await post(token, { jsonrpc: '2.0', method });
    expect(res.status).toBe(202);
    expect(await res.text()).toBe('');
  }
});

test('tools/list names the tools the token may use with their JSON schema, and leaves out the ones that act unless it has act', async () => {
  const token = issue();
  const { result } = await rpc(token, 'tools/list');
  expect(result.tools.map((t: any) => t.name)).toEqual(tools.filter((t) => t.access !== 'actsAsSession').map((t) => t.name));
  expect((await rpc(issue(['read', 'act']), 'tools/list')).result.tools.map((t: any) => t.name)).toEqual(tools.map((t) => t.name));
  expect(result.tools[0]).toMatchObject({ name: 'test_echo', description: 'Reads, for any token', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, additionalProperties: false } });
});

test('tools/call runs the handler with the session of the token and answers its JSON', async () => {
  const token = issue();
  const { result } = await call(token, 'test_echo', { text: 'hi' });
  expect(result).toEqual({ content: [{ type: 'text', text: '{"said":"hi"}' }], isError: false });
  expect(seen[0]).toEqual({ args: { text: 'hi' }, ctx: { sessionId: 's1', invocationId: 'i1', sessions: expect.any(Object) } });
  expect((await rpc(token, 'tools/call', { name: 'nope' })).error?.code).toBe(-32602);
  expect((await rpc(token, 'tools/call', { arguments: {} })).error?.code).toBe(-32602);
});

test('omitted arguments are {}, while null, arrays, primitives and unknown keys are tool errors', async () => {
  const token = issue();
  expect((await call(token, 'test_whoami')).result).toMatchObject({ isError: false, content: [{ text: '{"session":"s1"}' }] });
  expect(seen[0]?.args).toEqual({});
  expect((await call(token, 'test_whoami', {})).result.isError).toBe(false);
  for (const args of [null, [], 'text', 3, { extra: 1 }]) {
    const { result, error } = await call(token, 'test_whoami', args);
    expect(error, JSON.stringify(args)).toBeUndefined();
    expect(result.isError, JSON.stringify(args)).toBe(true);
    expect(result.content[0].text).toMatch(/^Invalid arguments/);
  }
  expect(seen).toHaveLength(2); // the handler never ran for those
});

test('a handler that throws: a ChatRefused says why, anything else is "The tool failed"', async () => {
  const token = issue();
  expect((await call(token, 'test_refuses', {})).result).toEqual({ content: [{ type: 'text', text: 'Not today' }], isError: true });
  expect((await call(token, 'test_breaks', {})).result).toEqual({ content: [{ type: 'text', text: 'The tool failed' }], isError: true });
});

test('reads needs a valid token and nothing else', async () => {
  const token = issue([]); // no capability at all
  existing.clear();
  expect((await call(token, 'test_echo', { text: 'x' })).result.isError).toBe(false);
});

test('readsAsSession needs the read capability and a session that still exists', async () => {
  expect((await call(issue([]), 'test_whoami', {})).result).toMatchObject({ isError: true, content: [{ text: 'This session may not use this tool' }] });
  const token = issue(['read']);
  expect((await call(token, 'test_whoami', {})).result.isError).toBe(false);
  liveOnes.clear(); // not live, but the row is there: still fine
  expect((await call(token, 'test_whoami', {})).result.isError).toBe(false);
  existing.clear();
  expect((await call(token, 'test_whoami', {})).result).toMatchObject({ isError: true, content: [{ text: 'This session no longer exists' }] });
});

test('actsAsSession needs the act capability and a live session', async () => {
  expect((await call(issue(['read']), 'test_change', {})).result).toMatchObject({ isError: true, content: [{ text: 'This session may not use this tool' }] });
  const token = issue(['read', 'act']);
  expect((await call(token, 'test_change', {})).result).toMatchObject({ isError: false, content: [{ text: '"changed"' }] });
  liveOnes.clear();
  expect((await call(token, 'test_change', {})).result).toMatchObject({ isError: true, content: [{ text: 'This session is not live' }] });
});

test('a tool that declares no valid access level cannot be defined, and a server refuses a tool listed twice', async () => {
  const spec = { description: 'x', input: z.strictObject({}), handler: () => 1 };
  expect(() => defineTool({ name: 'test_no_access', ...spec } as any)).toThrow('no valid access level');
  expect(() => defineTool({ name: 'test_bad_access', access: 'writes', ...spec } as any)).toThrow('no valid access level');
  await expect(startMcpServer({ registry, sessions: {} as any, tools: [echo, echo] })).rejects.toThrow('listed twice');
  await expect(startMcpServer({ registry, sessions: {} as any, tools: [{ name: 'test_literal', access: 'writes', ...spec } as any] })).rejects.toThrow('no valid access level');
});

test('capabilities is a readsAsSession tool that takes no arguments and answers what the session lends it', async () => {
  expect(capabilities).toMatchObject({ name: 'capabilities', access: 'readsAsSession' });
  const view = { id: 's1', agent: 'a', harness: 'claude', folder: '/work', model: null, options: {} };
  const own = await startMcpServer({
    registry,
    tools: [capabilities],
    sessions: { exists: () => true, live: () => true, snapshot: (id) => ({ ...view, id }), agents: () => [{ name: 'a', harness: 'claude', account: 'claude', found: true }], agentOptions: () => ({}), offer: async () => [], health: async () => ({ git: 'ready', gh: 'missing', agents: [{ name: 'a', harness: 'claude', state: 'ready' }] }), storedEvents: () => [], storedEvent: () => undefined, toolStatuses: () => ({}), delegationRefusal: () => undefined, startChild: async () => { throw new Error('not used'); }, related: () => false, waitChildren: async () => [] },
  });
  try {
    const token = issue();
    const ask = async (args?: unknown) => ((await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'capabilities', ...(args !== undefined && { arguments: args }) } }) })).json()) as any).result;
    for (const args of [undefined, {}]) {
      const result = await ask(args);
      expect(result.isError).toBe(false);
      expect(JSON.parse(result.content[0].text)).toEqual({ session: view, agents: [{ name: 'a', harness: 'claude', account: 'claude', found: true, state: 'ready' }], environment: { git: 'ready', gh: 'missing' } });
    }
    expect((await ask({ extra: 1 })).isError).toBe(true);
    expect((await ask([])).isError).toBe(true);
  } finally {
    await own.close();
  }
});

// ---- history ----

type Stored = StoredEvent & { sessionId: string };
const longText = 'x'.repeat(9000);
const stored: Stored[] = [
  { sessionId: 's1', position: 1, kind: 'user', data: { text: 'hello' } },
  { sessionId: 's1', position: 2, kind: 'reasoning', data: { text: 'private thoughts' } },
  { sessionId: 's1', position: 3, kind: 'tool_start', data: { callId: 'c1', tool: 'Bash', arg: 'ls' } },
  { sessionId: 's1', position: 4, kind: 'tool_end', data: { callId: 'c1', tool: 'Bash', output: ['TOP SECRET OUTPUT'], status: 'ok' } },
  { sessionId: 's1', position: 5, kind: 'tool_start', data: { callId: 'c2', tool: 'Read' } },
  { sessionId: 's1', position: 6, kind: 'tool_start', data: { callId: 'c3', tool: 'Grep', arg: 'foo' } },
  { sessionId: 's1', position: 7, kind: 'tool_end', data: { callId: 'c3', tool: 'Grep', output: ['STDERR'], status: 'err' } },
  { sessionId: 's1', position: 8, kind: 'assistant', data: { text: longText } },
  { sessionId: 's1', position: 9, kind: 'user', data: { text: '/review src', command: 'review' } },
  { sessionId: 's2', position: 10, kind: 'assistant', data: { text: 'not yours' } },
];
const store: McpSessions = {
  exists: (id) => id === 's1' || id === 's2',
  live: () => true,
  snapshot: () => { throw new Error('not used'); },
  agents: () => [],
  agentOptions: () => ({}),
  offer: async () => [],
  health: async () => ({ git: 'ready', gh: 'ready', agents: [] }),
  storedEvents: (id, { after, kinds, limit }) => stored.filter((e) => e.sessionId === id && e.position > after && kinds.includes(e.kind)).slice(0, limit),
  storedEvent: (id, position, kinds) => stored.find((e) => e.sessionId === id && e.position === position && kinds.includes(e.kind)),
  delegationRefusal: () => undefined,
  startChild: async () => { throw new Error('not used'); },
  related: () => false,
  waitChildren: async () => [],
  toolStatuses: (_id, callIds) => Object.fromEntries(callIds.flatMap((c): [string, 'ok' | 'err'][] => (c === 'c1' ? [[c, 'ok']] : c === 'c3' ? [[c, 'err']] : []))),
};

test('history pages the messages view from the start to a null nextPosition, and filters before the limit', async () => {
  const own = await startMcpServer({ registry, tools: [history], sessions: store });
  try {
    const token = issue();
    const ask = async (args?: unknown) => {
      const res = (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'history', ...(args !== undefined && { arguments: args }) } }) })).json()) as any;
      return { isError: res.result.isError as boolean, body: res.result.isError ? res.result.content[0].text : JSON.parse(res.result.content[0].text) };
    };
    expect(history).toMatchObject({ name: 'history', access: 'readsAsSession' });

    const first = await ask();
    expect(first.body.events.map((e: any) => [e.position, e.id, e.kind])).toEqual([[1, '1', 'user'], [8, '8', 'assistant'], [9, '9', 'user']]);
    expect(first.body.events[1].text).toHaveLength(1500);
    expect(first.body.events[2].text).toBe('/review src');
    expect(first.body.nextPosition).toBeNull();

    const one = await ask({ limit: 1 });
    expect(one.body).toMatchObject({ events: [{ position: 1, text: 'hello' }], nextPosition: 1 });
    const two = await ask({ limit: 1, afterPosition: one.body.nextPosition });
    expect(two.body.events.map((e: any) => e.position)).toEqual([8]); // the reasoning and tool rows in between are filtered before the limit
    expect(two.body.nextPosition).toBe(8);
    const three = await ask({ limit: 1, afterPosition: two.body.nextPosition });
    expect(three.body).toMatchObject({ events: [{ position: 9 }], nextPosition: null });
    expect((await ask({ sessionId: 's1', view: 'messages', afterPosition: 9 })).body).toEqual({ events: [], nextPosition: null });
  } finally {
    await own.close();
  }
});

test('history called with no arguments defaults to 40 events and pages via nextPosition until null', async () => {
  const many: Stored[] = Array.from({ length: 45 }, (_, i) => ({ sessionId: 's1', position: i + 1, kind: i % 2 === 0 ? 'user' : 'assistant', data: { text: `msg-${i + 1}` } }));
  const own = await startMcpServer({
    registry,
    tools: [history],
    sessions: { ...store, storedEvents: (id, { after, kinds, limit }) => many.filter((e) => e.sessionId === id && e.position > after && kinds.includes(e.kind)).slice(0, limit) },
  });
  try {
    const token = issue();
    const ask = async (args?: unknown) => {
      const res = (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'history', ...(args !== undefined && { arguments: args }) } }) })).json()) as any;
      return JSON.parse(res.result.content[0].text);
    };
    const first = await ask();
    expect(first.events).toHaveLength(40);
    expect(first.nextPosition).toBe(40);
    const second = await ask({ afterPosition: first.nextPosition });
    expect(second.events.map((e: any) => e.position)).toEqual([41, 42, 43, 44, 45]);
    expect(second.nextPosition).toBeNull();
  } finally {
    await own.close();
  }
});

test('history activity lists a tool call as one line with no output and never reasoning, and a long item is read whole in parts', async () => {
  const own = await startMcpServer({ registry, tools: [history], sessions: store });
  try {
    const token = issue();
    const ask = async (args?: unknown) => {
      const res = (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'history', ...(args !== undefined && { arguments: args }) } }) })).json()) as any;
      return { isError: res.result.isError as boolean, body: res.result.isError ? res.result.content[0].text : JSON.parse(res.result.content[0].text) };
    };
    const activity = await ask({ view: 'activity' });
    expect(activity.body.events.map((e: any) => [e.position, e.kind, e.text.slice(0, 20)])).toEqual([
      [1, 'user', 'hello'],
      [3, 'tool', 'Bash ls (ok)'],
      [5, 'tool', 'Read (running)'],
      [6, 'tool', 'Grep foo (err)'],
      [8, 'assistant', 'x'.repeat(20)],
      [9, 'user', '/review src'],
    ]);
    expect(JSON.stringify(activity.body)).not.toMatch(/SECRET|STDERR|private/);
    expect((await ask({ itemId: '3', view: 'activity' })).body).toEqual({ itemId: '3', text: 'Bash ls (ok)', nextTextOffset: null });
    expect((await ask({ itemId: '3' })).body).toEqual({ itemId: '3', text: 'Bash ls (ok)', nextTextOffset: null });

    const part1 = await ask({ itemId: '8' });
    expect(part1.body.text).toBe(longText.slice(0, 4000));
    expect(part1.body.nextTextOffset).toBe(4000);
    const part2 = await ask({ itemId: '8', textOffset: 4000 });
    expect(part2.body).toMatchObject({ nextTextOffset: 8000 });
    const part3 = await ask({ itemId: '8', textOffset: 8000 });
    expect(part3.body).toEqual({ itemId: '8', text: longText.slice(8000), nextTextOffset: null });
    expect((await ask({ itemId: '8', textOffset: 9000 })).body).toEqual({ itemId: '8', text: '', nextTextOffset: null });
    expect((await ask({ itemId: '8', textOffset: 50_000 })).body).toEqual({ itemId: '8', text: '', nextTextOffset: null });
  } finally {
    await own.close();
  }
});

test('history refuses a bad limit, position, offset or type, and another session or another session\'s item with the words of one that does not exist', async () => {
  const own = await startMcpServer({ registry, tools: [history], sessions: store });
  try {
    const token = issue();
    const ask = async (args?: unknown) => {
      const res = (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'history', ...(args !== undefined && { arguments: args }) } }) })).json()) as any;
      return { isError: res.result.isError as boolean, text: res.result.content[0].text as string };
    };
    for (const bad of [{ limit: 0 }, { limit: 101 }, { limit: 1.5 }, { afterPosition: -2 }, { afterPosition: 0.5 }, { textOffset: 0 }, { textOffset: 3 }, { itemId: '8', textOffset: -1 }, { itemId: '8', textOffset: 1.5 }, { view: 'reasoning' }, { extra: 1 }]) {
      const refused = await ask(bad);
      expect([bad, refused.isError]).toEqual([bad, true]);
      expect(refused.text).toMatch(/^Invalid arguments/);
    }
    const noSession = await ask({ sessionId: 's2' });
    expect(noSession).toEqual({ isError: true, text: 'There is no such session' });
    expect(await ask({ sessionId: 'ghost' })).toEqual(noSession);
    for (const itemId of ['10', '99', '2', '4', '7', 'abc', '-1', '1.0', '01']) expect(await ask({ itemId })).toEqual({ isError: true, text: 'There is no such item' }); // another session's, missing, reasoning, tool ends, not a position
    expect(await ask({ sessionId: 's2', itemId: '10' })).toEqual(noSession);
  } finally {
    await own.close();
  }
});

// ---- agents ----

type Listed = { name: string; harness: string; account: string; found: boolean };
const roster: Listed[] = [
  { name: 'claude-edit', harness: 'claude', account: 'claude', found: true },
  { name: 'claude-read', harness: 'claude', account: 'claude', found: true },
  { name: 'codex', harness: 'codex', account: 'codex', found: true },
  { name: 'gone', harness: 'claude', account: 'other', found: false },
  { name: 'claude-auto', harness: 'claude', account: 'claude', found: true },
];
const configured: Record<string, Record<string, string>> = { 'claude-edit': { permissionMode: 'acceptEdits' }, 'claude-read': { permissionMode: 'dontAsk' }, codex: {}, gone: {}, 'claude-auto': { permissionMode: 'auto' } };
const offers: Record<string, { id: string; values: { id: string; label: string }[] }[]> = {
  'claude-edit': [{ id: 'model', values: [{ id: 'opus', label: 'Opus' }, { id: 'haiku', label: 'Haiku' }] }, { id: 'effort', values: [{ id: 'low', label: 'low' }, { id: 'high', label: 'high' }] }, { id: 'permissionMode', values: [{ id: 'default', label: 'Ask' }] }],
  'claude-read': [{ id: 'model', values: [{ id: 'sonnet', label: 'Sonnet' }] }],
};
let probed: string[];
const askAgents = async (caller: { harness: string; options: Record<string, string> }, args?: unknown) => {
  probed = [];
  const own = await startMcpServer({
    registry,
    tools: [agents],
    sessions: {
      ...store,
      snapshot: (id) => ({ id, agent: 'caller', harness: caller.harness, folder: '/work', model: null, options: caller.options }),
      agents: () => roster,
      delegationRefusal: () => delegationRefusal(caller.harness, caller.options, '0.122.0'),
      agentOptions: (name) => configured[name] ?? {},
      offer: async (name) => {
        probed.push(name);
        if (name === 'codex') throw new Error('the probe said secret things');
        return offers[name] ?? [];
      },
      health: async () => ({ git: 'ready', gh: 'ready', agents: [{ name: 'claude-edit', harness: 'claude', state: 'ready' }, { name: 'codex', harness: 'codex', state: 'signedOut' }] }),
    },
  });
  try {
    const res = (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${issue()}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'agents', ...(args !== undefined && { arguments: args }) } }) })).json()) as any;
    return { isError: res.result.isError as boolean, text: res.result.content[0].text as string };
  } finally {
    await own.close();
  }
};

test('agents lists each configured agent with its state and the level it would have as a child of the caller, with no models unless asked', async () => {
  expect(agents).toMatchObject({ name: 'agents', access: 'readsAsSession' });
  const level1 = await askAgents({ harness: 'claude', options: { permissionMode: 'default' } });
  expect(level1.isError).toBe(false);
  expect(JSON.parse(level1.text)).toEqual({
    agents: [
      { name: 'claude-edit', harness: 'claude', found: true, state: 'ready', childLevel: 1 }, // lowered from 2 by the caller
      { name: 'claude-read', harness: 'claude', found: true, state: 'unknown', childLevel: 0 },
      { name: 'codex', harness: 'codex', found: true, state: 'signedOut', childLevel: 1 }, // no options: the adapter's defaults
      { name: 'gone', harness: 'claude', found: false, state: 'unknown', childLevel: 1 },
      { name: 'claude-auto', harness: 'claude', found: true, state: 'unknown', childLevel: 1 }, // lowered from 3 by the caller
    ],
  });
  expect(probed).toEqual([]);

  const level2 = JSON.parse((await askAgents({ harness: 'codex', options: { sandbox: 'workspace-write', approvalPolicy: 'on-request' } }, { models: false })).text);
  expect(level2.agents.map((agent: any) => [agent.name, agent.childLevel])).toEqual([['claude-edit', 2], ['claude-read', 0], ['codex', 1], ['gone', 1], ['claude-auto', 2]]);
  expect(probed).toEqual([]);
  expect((await askAgents({ harness: 'claude', options: {} })).isError).toBe(false); // a caller with no options is at the adapter's default
  expect((await askAgents({ harness: 'claude', options: {} }, { models: 'yes' })).isError).toBe(true);
});

test('agents shows a child level in every mode of the caller, up to 3 for Claude auto, and 2 for Codex under it', async () => {
  const levels = async (caller: { harness: string; options: Record<string, string> }) => {
    const { agents: listed } = JSON.parse((await askAgents(caller)).text);
    for (const agent of listed) expect(agent).not.toHaveProperty('notOffered');
    return listed.map((agent: any) => agent.childLevel);
  };
  // claude-edit is configured at 2, claude-read at 0, codex and gone at the adapter's defaults (1), claude-auto at 3
  expect(await levels({ harness: 'claude', options: { permissionMode: 'auto' } })).toEqual([2, 0, 1, 1, 3]); // a Claude child of an auto parent opens in auto
  expect(await levels({ harness: 'claude', options: { permissionMode: 'plan' } })).toEqual([0, 0, 0, 0, 0]);
  expect(await levels({ harness: 'claude', options: { permissionMode: 'dontAsk' } })).toEqual([0, 0, 0, 0, 0]);
  expect(await levels({ harness: 'codex', options: { sandbox: 'workspace-write', approvalPolicy: 'never' } })).toEqual([2, 0, 1, 1, 2]); // Codex has nothing at 3
});

test('agents answers notOffered with the words of the refusal and no childLevel when the caller may not delegate', async () => {
  const off: { harness: string; options: Record<string, string> }[] = [
    { harness: 'claude', options: { permissionMode: 'bypassPermissions' } },
    { harness: 'codex', options: { sandbox: 'danger-full-access', approvalPolicy: 'on-request' } },
  ];
  for (const caller of off) {
    const { agents: listed } = JSON.parse((await askAgents(caller)).text);
    expect(listed).toHaveLength(5);
    for (const agent of listed) {
      expect(agent).not.toHaveProperty('childLevel');
      expect(agent.notOffered).toBe(delegationRefusal(caller.harness, caller.options, '0.122.0'));
    }
    expect(listed[0].notOffered).toMatch(/off the permission scale/);
  }
});

test('the delegation tools are listed to a session with no parent in every mode that is on the scale, and not to one that is off it, a harness that is not Claude or Codex, or a Codex app-server that is unknown or older than the floor', async () => {
  const listing = async (harness: string, options: Record<string, string>, version?: string, capabilities: ('read' | 'act')[] = ['read', 'act']) => {
    const own = await startMcpServer({ registry, tools: [delegateStart, delegateWait, whoami], sessions: { exists: () => true, live: () => true, delegationRefusal: () => delegationRefusal(harness, options, version), startChild: async () => ({ childId: 'c' }), waitChildren: async () => [] } as any });
    try {
      const ask = async (method: string, params?: unknown) => (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${issue(capabilities)}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, ...(params !== undefined && { params }) }) })).json()) as any;
      const listed = ((await ask('tools/list')).result.tools as { name: string }[]).map((tool) => tool.name);
      const called = (await ask('tools/call', { name: 'delegate_start', arguments: { agent: 'codex', task: 'review' } })).result;
      return { listed, called: called.isError !== true };
    } finally {
      await own.close();
    }
  };
  const all = ['delegate_start', 'delegate_wait', 'test_whoami'];
  for (const permissionMode of ['auto', 'dontAsk', 'plan', 'default', 'acceptEdits']) expect(await listing('claude', { permissionMode }), permissionMode).toEqual({ listed: all, called: true });
  for (const approvalPolicy of ['never', 'untrusted', 'on-request']) expect(await listing('codex', { sandbox: 'workspace-write', approvalPolicy }, '0.122.0'), approvalPolicy).toEqual({ listed: all, called: true });
  const unlisted = ['delegate_wait', 'test_whoami'];
  expect(await listing('claude', { permissionMode: 'bypassPermissions' })).toEqual({ listed: unlisted, called: false });
  expect(await listing('codex', { sandbox: 'danger-full-access', approvalPolicy: 'never' }, '0.122.0')).toEqual({ listed: unlisted, called: false });
  expect(await listing('gemini', {})).toEqual({ listed: unlisted, called: false });
  expect(await listing('codex', {}, '0.121.9')).toEqual({ listed: unlisted, called: false });
  expect(await listing('codex', {})).toEqual({ listed: unlisted, called: false });
  // a child holds no act, in any mode
  expect(await listing('claude', { permissionMode: 'auto' }, undefined, ['read'])).toEqual({ listed: unlisted, called: false });
});

test('agents lists models and efforts from the probe only when asked, and says so for an agent whose probe fails or that is not found', async () => {
  const { agents: listed } = JSON.parse((await askAgents({ harness: 'claude', options: { permissionMode: 'default' } }, { models: true })).text);
  expect(probed.sort()).toEqual(['claude-auto', 'claude-edit', 'claude-read', 'codex']); // a probe for an agent that is not found would only fail
  expect(listed[0]).toMatchObject({ name: 'claude-edit', models: [{ id: 'opus', label: 'Opus' }, { id: 'haiku', label: 'Haiku' }], efforts: ['low', 'high'] });
  expect(listed[1]).toMatchObject({ name: 'claude-read', models: [{ id: 'sonnet', label: 'Sonnet' }], efforts: [] });
  expect(listed[2]).toMatchObject({ name: 'codex', childLevel: 1, modelsUnavailable: 'The models of this agent could not be listed' });
  expect(listed[2]).not.toHaveProperty('models');
  expect(JSON.stringify(listed)).not.toContain('secret');
  expect(listed[3]).toMatchObject({ name: 'gone', modelsUnavailable: expect.stringContaining('not found') });
});

test('delegate_start is an actsAsSession tool: a token without act can neither list nor call it, one with act starts a child for its own session and gets its id', async () => {
  expect(delegateStart).toMatchObject({ name: 'delegate_start', access: 'actsAsSession' });
  expect(delegateStart.description).toContain('Delegate only when the person asked for other agents');
  const withDelegate = await startMcpServer({ registry, tools: [delegateStart], sessions: { exists: () => true, live: () => true, delegationRefusal: () => undefined, startChild: async (parentId: string, args: unknown) => (started.push({ parentId, args }), { childId: 'child-1' }) } as any });
  try {
    const ask = async (token: string, method: string, params?: unknown) => (await (await fetch(withDelegate.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, ...(params !== undefined && { params }) }) })).json()) as any;
    const delegate = (token: string, args: unknown) => ask(token, 'tools/call', { name: 'delegate_start', arguments: args });

    expect((await ask(issue(['read']), 'tools/list')).result.tools).toEqual([]);
    expect((await delegate(issue(['read']), { agent: 'codex', task: 'review' })).result).toMatchObject({ isError: true, content: [{ text: 'This session may not use this tool' }] });
    expect(started).toEqual([]);

    const token = issue(['read', 'act']);
    const listed = (await ask(token, 'tools/list')).result.tools[0];
    expect(listed).toMatchObject({ name: 'delegate_start', inputSchema: { required: ['agent', 'task'], additionalProperties: false } });
    const answer = (await delegate(token, { agent: 'codex', task: 'review the diff', model: 'gpt-5', requestId: 'r1' })).result;
    expect(answer).toEqual({ content: [{ type: 'text', text: '{"childId":"child-1"}' }], isError: false });
    expect(started).toEqual([{ parentId: 's1', args: { agent: 'codex', task: 'review the diff', model: 'gpt-5', requestId: 'r1' } }]);

    for (const args of [{ task: 'x' }, { agent: 'a' }, { agent: '', task: 'x' }, { agent: 'a', task: '' }, { agent: 'a'.repeat(101), task: 'x' }, { agent: 'a', task: 'x'.repeat(64_001) }, { agent: 'a', task: 'x', model: 'm'.repeat(101) }, { agent: 'a', task: 'x', requestId: '' }, { agent: 'a', task: 'x', requestId: 'r'.repeat(65) }, { agent: 'a', task: 'x', level: 2 }]) {
      expect((await delegate(token, args)).result, JSON.stringify(args).slice(0, 60)).toMatchObject({ isError: true });
    }
    expect(started).toHaveLength(1);
    expect((await delegate(token, { agent: 'a', task: 'x'.repeat(64_000), requestId: 'r'.repeat(64) })).result.isError).toBe(false);

    // the words of a refusal reach the agent as they are
    const refusing = await startMcpServer({ registry, tools: [delegateStart], sessions: { exists: () => true, live: () => true, delegationRefusal: () => undefined, startChild: async () => { throw new ChatRefused('This session already has 4 children'); } } as any });
    try {
      const refused = (await (await fetch(refusing.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'delegate_start', arguments: { agent: 'a', task: 'x' } } }) })).json()) as any;
      expect(refused.result).toMatchObject({ isError: true, content: [{ text: 'This session already has 4 children' }] });
    } finally {
      await refusing.close();
    }
  } finally {
    await withDelegate.close();
  }
});

test('a delegation tool is listed and callable only while the session may delegate, and the call re-checks what the listing saw', async () => {
  expect(delegateStart.delegation).toBe(true);
  let refusal: string | undefined;
  const own = await startMcpServer({ registry, tools: [delegateStart, whoami], sessions: { exists: () => true, live: () => true, delegationRefusal: () => refusal, startChild: async (parentId: string, args: unknown) => (started.push({ parentId, args }), { childId: 'child-1' }) } as any });
  try {
    const ask = async (method: string, params?: unknown) => (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, ...(params !== undefined && { params }) }) })).json()) as any;
    const token = issue(['read', 'act']);
    const names = async () => (await ask('tools/list')).result.tools.map((tool: { name: string }) => tool.name);
    const start = async () => (await ask('tools/call', { name: 'delegate_start', arguments: { agent: 'codex', task: 'review' } })).result;

    expect(await names()).toEqual(['delegate_start', 'test_whoami']);
    refusal = 'This session\'s options are off the permission scale, so a child cannot be given a level';
    expect(await names()).toEqual(['test_whoami']); // what reads stays
    expect(await start()).toMatchObject({ isError: true, content: [{ text: refusal }] });
    expect(started).toEqual([]);

    // the agent listed the tools while the mode asked, and the person changed it after: the call is the check that holds
    refusal = undefined;
    expect(await names()).toContain('delegate_start');
    refusal = 'now it is off the scale';
    expect(await start()).toMatchObject({ isError: true, content: [{ text: 'now it is off the scale' }] });
    expect(started).toEqual([]);
    refusal = undefined;
    expect((await start()).isError).toBe(false);
    expect(started).toHaveLength(1);
  } finally {
    await own.close();
  }
});

test('history reads a child for its parent and a parent for its child, and refuses any other session with the words of one that does not exist', async () => {
  const family = (id: string, other: string) => (id === 's1' && other === 's2') || (id === 's2' && other === 's1'); // s1 is the parent of s2, s3 is a stranger
  const own = await startMcpServer({ registry, tools: [history], sessions: { ...store, exists: () => true, related: family } });
  try {
    const ask = async (token: string, args: unknown) => (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'history', arguments: args } }) })).json()) as any;
    const parent = issue(['read'], 's1');
    const child = issue(['read'], 's2', 'i2');
    expect((await ask(parent, { sessionId: 's2' })).result.content[0].text).toContain('not yours');
    expect((await ask(parent, { sessionId: 's2', itemId: '10' })).result).toMatchObject({ isError: false });
    expect((await ask(child, { sessionId: 's1' })).result.content[0].text).toContain('hello');
    const nowhere = (await ask(parent, { sessionId: 'nope' })).result;
    for (const refused of [nowhere, (await ask(issue(['read'], 's3', 'i3'), { sessionId: 's2' })).result, (await ask(issue(['read'], 's1', 'i4'), { sessionId: 's3' })).result]) {
      expect(refused).toEqual({ content: [{ type: 'text', text: 'There is no such session' }], isError: true });
    }
  } finally {
    await own.close();
  }
});

test('delegate_wait is a readsAsSession tool that takes one to four ids and a timeout of 1 to 45 seconds, and answers what the host reports for its own session', async () => {
  const waited: unknown[] = [];
  const reports = [{ childId: 'c1', agent: 'a', state: 'done', message: 'ok' }];
  const own = await startMcpServer({ registry, tools: [delegateWait], sessions: { exists: () => true, live: () => true, waitChildren: async (...args: unknown[]) => (waited.push(args), reports) } as any });
  try {
    expect(delegateWait).toMatchObject({ name: 'delegate_wait', access: 'readsAsSession' });
    const token = issue(['read']);
    const wait = async (args: unknown) => (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'delegate_wait', arguments: args } }) })).json()) as any;
    const listed = (await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) })).json()) as any;
    expect(listed.result.tools.map((t: any) => t.name)).toEqual(['delegate_wait']); // a token that only reads sees it

    expect((await wait({ childIds: ['c1'] })).result).toEqual({ content: [{ type: 'text', text: JSON.stringify({ children: reports }) }], isError: false });
    expect((await wait({ childIds: ['c1', 'c2', 'c3', 'c4'], timeoutMs: 45000 })).result.isError).toBe(false);
    expect((await wait({ childIds: ['c1'], timeoutMs: 1000 })).result.isError).toBe(false);
    expect(waited).toEqual([['s1', ['c1'], 30000], ['s1', ['c1', 'c2', 'c3', 'c4'], 45000], ['s1', ['c1'], 1000]]);

    for (const args of [{ childIds: [] }, { childIds: ['1', '2', '3', '4', '5'] }, {}, { childIds: ['c1'], timeoutMs: 999 }, { childIds: ['c1'], timeoutMs: 45001 }, { childIds: ['c1'], timeoutMs: 1500.5 }, { childIds: [1] }, { childIds: ['c1'], more: true }]) {
      expect((await wait(args)).result, JSON.stringify(args)).toMatchObject({ isError: true });
    }
    expect(waited).toHaveLength(3);
  } finally {
    await own.close();
  }
});
