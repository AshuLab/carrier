import { createHash } from 'node:crypto';
import { afterEach, beforeEach, expect, test } from 'vitest';
import { z } from 'zod';
import { FakeClock } from '../orchestration/fake.ts';
import { capabilities } from './mcp/capabilities.ts';
import { accessLevels, defineTool, McpSessionRegistry, registeredTools, startMcpServer, type McpServer } from './mcp.ts';
import { ChatRefused } from './runner.ts';

const DAY = 24 * 60 * 60_000;

let clock: FakeClock;
let registry: McpSessionRegistry;
let server: McpServer;
let existing: Set<string>;
let liveOnes: Set<string>;
let seen: { args: unknown; ctx: unknown }[];

// names are unique per file: `defineTool` registers globally
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
  server = await startMcpServer({ registry, tools, sessions: { exists: (id) => existing.has(id), live: (id) => liveOnes.has(id), snapshot: () => { throw new Error('not used'); }, agents: () => [], health: async () => ({ git: 'ready', gh: 'ready', agents: [] }) } });
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
  expect(registry.lookup(a)).toMatchObject({ sessionId: 's1', invocationId: 'i1', capabilities: new Set(['read']), issuedAt: 0 });
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

test('tools/list names every tool with its JSON schema', async () => {
  const token = issue();
  const { result } = await rpc(token, 'tools/list');
  expect(result.tools.map((t: any) => t.name)).toEqual(tools.map((t) => t.name));
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

test('every registered tool declares a valid access level, and one that does not cannot register', () => {
  expect(registeredTools().length).toBeGreaterThanOrEqual(tools.length);
  for (const tool of registeredTools()) expect(accessLevels, tool.name).toContain(tool.access);
  const spec = { description: 'x', input: z.strictObject({}), handler: () => 1 };
  expect(() => defineTool({ name: 'test_no_access', ...spec } as any)).toThrow('no valid access level');
  expect(() => defineTool({ name: 'test_bad_access', access: 'writes', ...spec } as any)).toThrow('no valid access level');
  expect(() => defineTool({ name: 'test_echo', access: 'reads', ...spec })).toThrow('already registered');
  expect(registeredTools().map((t) => t.name)).not.toContain('test_no_access');
});

test('capabilities is a readsAsSession tool that takes no arguments and answers what the session lends it', async () => {
  expect(capabilities).toMatchObject({ name: 'capabilities', access: 'readsAsSession' });
  expect(registeredTools().map((t) => t.name)).toContain('capabilities');
  const view = { id: 's1', agent: 'a', harness: 'claude', folder: '/work', model: null, options: {} };
  const own = await startMcpServer({
    registry,
    tools: [capabilities],
    sessions: { exists: () => true, live: () => true, snapshot: (id) => ({ ...view, id }), agents: () => [{ name: 'a', harness: 'claude', found: true }], health: async () => ({ git: 'ready', gh: 'missing', agents: [{ name: 'a', harness: 'claude', state: 'ready' }] }) },
  });
  try {
    const token = issue();
    const ask = async (args?: unknown) => ((await (await fetch(own.url, { method: 'POST', headers: { authorization: `Bearer ${token}` }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'capabilities', ...(args !== undefined && { arguments: args }) } }) })).json()) as any).result;
    for (const args of [undefined, {}]) {
      const result = await ask(args);
      expect(result.isError).toBe(false);
      expect(JSON.parse(result.content[0].text)).toEqual({ session: view, agents: [{ name: 'a', harness: 'claude', found: true, state: 'ready' }], environment: { git: 'ready', gh: 'missing' } });
    }
    expect((await ask({ extra: 1 })).isError).toBe(true);
    expect((await ask([])).isError).toBe(true);
  } finally {
    await own.close();
  }
});
