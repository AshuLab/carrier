import { createHash, randomBytes } from 'node:crypto';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import type { AddressInfo } from 'node:net';
import { createScopedLogger } from '@ashulab/universal-logger';
import { z } from 'zod';
import { version } from '../control/server.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { Health } from './health.ts';
import { ChatRefused } from './runner.ts';

const log = createScopedLogger('chat');

/** What a tool declares: it reads, it reads as the calling session, or it acts as the calling session. */
export const accessLevels = ['reads', 'readsAsSession', 'actsAsSession'] as const;
export type McpAccessLevel = (typeof accessLevels)[number];
export type McpCapability = 'read' | 'act';

const IDLE_MS = 24 * 60 * 60_000;
// 1 MiB: a tool call is small, and nothing here needs more.
const MAX_BODY_BYTES = 1024 * 1024;

// ---- tokens ----

type McpToken = { sessionId: string; invocationId: string; capabilities: ReadonlySet<McpCapability>; issuedAt: number; lastAliveAt: number };

const hashOf = (rawToken: string) => createHash('sha256').update(rawToken).digest('hex');

/** The credentials of the live conversations. Only the SHA-256 of a token is kept, in memory; the raw one is returned once, by `issue`. */
export class McpSessionRegistry {
  private readonly records = new Map<string, McpToken>();
  private readonly clock: Clock;

  constructor(clock: Clock) {
    this.clock = clock;
  }

  issue(args: { sessionId: string; invocationId: string; capabilities?: McpCapability[] }): string {
    const rawToken = randomBytes(32).toString('base64url');
    const now = this.clock.now();
    this.records.set(hashOf(rawToken), { sessionId: args.sessionId, invocationId: args.invocationId, capabilities: new Set(args.capabilities ?? ['read']), issuedAt: now, lastAliveAt: now });
    return rawToken;
  }

  /** The record of a live token, which counts as activity; a token idle for over 24 hours is gone. */
  lookup(rawToken: string): McpToken | undefined {
    const key = hashOf(rawToken);
    const record = this.records.get(key);
    if (record === undefined) return undefined;
    const now = this.clock.now();
    if (now - record.lastAliveAt > IDLE_MS) {
      this.records.delete(key);
      return undefined;
    }
    record.lastAliveAt = now;
    return record;
  }

  revokeByInvocation(invocationId: string): void {
    for (const [key, record] of this.records) if (record.invocationId === invocationId) this.records.delete(key);
  }

  revokeAll(): void {
    this.records.clear();
  }
}

// ---- tools ----

export type McpInvocationContext = { sessionId: string; invocationId: string; sessions: McpSessions };

export type McpTool<Input extends z.ZodType = z.ZodType> = {
  name: string;
  description: string;
  access: McpAccessLevel;
  input: Input;
  handler: (args: z.infer<Input>, ctx: McpInvocationContext) => Promise<unknown> | unknown;
};

const registered = new Map<string, McpTool>();

/** The only way a tool exists: one without a valid access level, or with a name already taken, does not register. */
export function defineTool<Input extends z.ZodType>(tool: McpTool<Input>): McpTool<Input> {
  if (!accessLevels.includes(tool.access)) throw new Error(`Tool ${tool.name} declares no valid access level`);
  if (registered.has(tool.name)) throw new Error(`Tool ${tool.name} is already registered`);
  registered.set(tool.name, tool as McpTool);
  return tool;
}

export const registeredTools = (): McpTool[] => [...registered.values()];

// ---- server ----

/** What the dispatcher asks the host about a session. */
export type McpSessions = {
  /** Whether the session still has its row. */
  exists(sessionId: string): boolean;
  /** Whether the session has a live conversation in the host. */
  live(sessionId: string): boolean;
  /** What the session is, from its row and its live options: nothing that says where a binary or a login is on this machine. */
  snapshot(sessionId: string): { id: string; agent: string; harness: string; folder: string; model: string | null; options: Record<string, string> };
  /** The configured chat agents. */
  agents(): { name: string; harness: string; model?: string; found: boolean }[];
  /** The verdicts of the health check (kept thirty seconds); never starts an agent. */
  health(): Promise<Health>;
};

export type McpServer = { url: string; close(): Promise<void> };

const SERVER_NAME = 'carrier-chat';
const protocolVersions = ['2025-06-18', '2025-03-26', '2024-11-05'];
const serverInfo = { name: SERVER_NAME, version };
const capabilities = { tools: {} };

const rpcRequest = z.object({ jsonrpc: z.literal('2.0'), method: z.string(), id: z.union([z.string(), z.number()]).optional(), params: z.record(z.string(), z.unknown()).optional() });
const callParams = z.object({ name: z.string(), arguments: z.unknown().optional() });

const rpcError = (id: string | number | null, code: number, message: string) => ({ jsonrpc: '2.0', id, error: { code, message } });
const toolResult = (text: string, isError: boolean) => ({ content: [{ type: 'text', text }], isError });

/** Loopback HTTP MCP server on `127.0.0.1`, an ephemeral port, `/mcp`. Every request needs the bearer token of a live conversation. */
export async function startMcpServer(deps: { registry: McpSessionRegistry; sessions: McpSessions; tools?: McpTool[] }): Promise<McpServer> {
  const tools = new Map((deps.tools ?? registeredTools()).map((tool) => [tool.name, tool]));

  const send = (res: ServerResponse, status: number, body?: unknown, headers: Record<string, string> = {}) => {
    res.writeHead(status, body === undefined ? headers : { 'content-type': 'application/json', ...headers });
    res.end(body === undefined ? undefined : JSON.stringify(body));
  };

  const readBody = (req: IncomingMessage, res: ServerResponse): Promise<string | undefined> =>
    new Promise((resolve) => {
      const chunks: Buffer[] = [];
      let size = 0;
      const tooBig = () => {
        send(res, 413, undefined, { connection: 'close' });
        req.resume(); // the rest is thrown away; the connection closes after the reply
        resolve(undefined);
      };
      if (Number(req.headers['content-length']) > MAX_BODY_BYTES) return tooBig();
      req.on('data', (chunk: Buffer) => {
        size += chunk.length;
        if (size > MAX_BODY_BYTES) {
          chunks.length = 0;
          if (!res.headersSent) tooBig();
          return;
        }
        chunks.push(chunk);
      });
      req.on('end', () => {
        if (!res.headersSent) resolve(Buffer.concat(chunks).toString('utf8'));
      });
      req.on('error', () => resolve(undefined));
    });

  const callTool = async (token: McpToken, params: unknown) => {
    const call = callParams.safeParse(params);
    if (!call.success) return { error: { code: -32602, message: 'Invalid params' } };
    const tool = tools.get(call.data.name);
    if (tool === undefined) return { error: { code: -32602, message: `Unknown tool ${call.data.name}` } };

    const wanted = tool.access === 'actsAsSession' ? 'act' : 'read';
    if (tool.access !== 'reads' && !token.capabilities.has(wanted)) return { result: toolResult('This session may not use this tool', true) };
    if (tool.access === 'readsAsSession' && !deps.sessions.exists(token.sessionId)) return { result: toolResult('This session no longer exists', true) };
    if (tool.access === 'actsAsSession' && !deps.sessions.live(token.sessionId)) return { result: toolResult('This session is not live', true) };

    // an omitted `arguments` is `{}`; null, arrays, primitives and (for a strict schema) unknown keys are for the schema to refuse
    const args = tool.input.safeParse(call.data.arguments === undefined ? {} : call.data.arguments);
    if (!args.success) return { result: toolResult(`Invalid arguments: ${z.prettifyError(args.error)}`, true) };
    try {
      const out = await tool.handler(args.data, { sessionId: token.sessionId, invocationId: token.invocationId, sessions: deps.sessions });
      return { result: toolResult(JSON.stringify(out ?? null), false) };
    } catch (error) {
      if (error instanceof ChatRefused) return { result: toolResult(error.message, true) };
      log.error(`mcp tool ${tool.name} failed`, error);
      return { result: toolResult('The tool failed', true) };
    }
  };

  const handle = async (req: IncomingMessage, res: ServerResponse) => {
    if (new URL(req.url ?? '/', 'http://127.0.0.1').pathname !== '/mcp') return send(res, 404);
    if (req.method !== 'POST') return send(res, 405, undefined, { allow: 'POST' });

    const bearer = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization ?? '');
    const token = bearer?.[1] === undefined ? undefined : deps.registry.lookup(bearer[1]);
    if (token === undefined) return send(res, 401, undefined, { 'www-authenticate': 'Bearer' });

    const text = await readBody(req, res);
    if (text === undefined) return;
    let json: unknown;
    try {
      json = JSON.parse(text);
    } catch {
      return send(res, 200, rpcError(null, -32700, 'Parse error'));
    }
    const rpc = rpcRequest.safeParse(json);
    if (!rpc.success) return send(res, 200, rpcError(null, -32600, 'Invalid request'));
    const { id, method, params } = rpc.data;
    if (id === undefined) return send(res, 202); // a notification, `notifications/initialized` or any other, wants no answer

    const reply = (result: unknown) => send(res, 200, { jsonrpc: '2.0', id, result });
    const fail = (code: number, message: string) => send(res, 200, rpcError(id, code, message));
    switch (method) {
      case 'initialize': {
        const asked = params?.protocolVersion;
        return reply({ protocolVersion: typeof asked === 'string' && protocolVersions.includes(asked) ? asked : protocolVersions[0], capabilities, serverInfo });
      }
      case 'server/discover':
        return reply({ supportedVersions: protocolVersions, capabilities, serverInfo });
      case 'ping':
        return reply({});
      case 'tools/list':
        return reply({ tools: [...tools.values()].map((t) => ({ name: t.name, description: t.description, inputSchema: z.toJSONSchema(t.input) })) });
      case 'tools/call': {
        const called = await callTool(token, params);
        return called.error === undefined ? reply(called.result) : fail(called.error.code, called.error.message);
      }
      default:
        return fail(-32601, 'Method not found');
    }
  };

  const server = createServer((req, res) => {
    handle(req, res).catch((error: unknown) => {
      log.error('mcp request failed', error);
      if (res.headersSent) res.destroy();
      else send(res, 500);
    });
  });
  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = server.address() as AddressInfo;
  return {
    url: `http://127.0.0.1:${port}/mcp`,
    close: () =>
      new Promise((resolve) => {
        server.close(() => resolve());
        server.closeAllConnections();
      }),
  };
}
