// Throwaway harness for part A: a direct SDK query injected the way src/chat/claude.ts does it, with a recording canUseTool.
import { spawn } from 'node:child_process';
import { appendFileSync, mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { query, type Query } from '@anthropic-ai/claude-agent-sdk';
import { z } from 'zod';
import { endGroup } from '../../../../src/chat/group.ts';
import { defineTool, McpSessionRegistry, startMcpServer } from '../../../../src/chat/mcp.ts';
import { realClock } from '../../../../src/orchestration/clock.ts';

export const SERVER = 'carrier-chat';
export const tmp = (prefix: string) => realpathSync(mkdtempSync(join(tmpdir(), prefix)));

/** The toy chat MCP: two tools that answer a fixed string and append to the log file named by `state.log`. */
export const state = { log: '' };
const toy = (name: string, access: 'readsAsSession' | 'actsAsSession') =>
  defineTool({ name, description: `Toy tool ${name}: returns a fixed string.`, access, input: z.strictObject({}), handler: () => (appendFileSync(state.log, `${name} executed\n`), `${name} says PONG`) });

export async function toyMcp() {
  const registry = new McpSessionRegistry(realClock);
  const server = await startMcpServer({
    registry,
    tools: [toy('ping_read', 'readsAsSession'), toy('ping_act', 'actsAsSession')],
    sessions: { exists: () => true, live: () => true, snapshot: () => ({ id: 's1', agent: 'a', harness: 'claude', folder: 'F', model: null, options: {} }), agents: () => [], health: async () => ({ git: 'ready', gh: 'ready', agents: [] }) as never },
  });
  const token = registry.issue({ sessionId: 's1', invocationId: 'i1', capabilities: ['read', 'act'] });
  return { url: server.url, token, close: () => server.close() };
}

export type Recorded = { turn: number; tool: string; input: unknown; title?: string; displayName?: string; description?: string; decisionReason?: string; blockedPath?: string; suggestions: unknown; toolUseID: string };
export type TurnLog = { prompt: string; ms: number; asked: Recorded[]; tools: { name: string; input: unknown }[]; results: { tool: string; error: boolean; text: string }[]; said: string; outcome: string; resultText?: string; denials?: unknown };

export type OpenArgs = { folder: string; mode?: string; model?: string; allowedTools?: string[]; allow?: string[]; mcp?: { url: string; token: string }; settingSources?: ('user' | 'project' | 'local')[] };

export async function open(a: OpenArgs) {
  const waiting: object[] = [];
  let wake: (() => void) | undefined;
  let ended = false;
  const iterable = (async function* () {
    while (true) {
      const next = waiting.shift();
      if (next !== undefined) yield next as never;
      else if (ended) return;
      else await new Promise<void>((r) => void (wake = r));
    }
  })();
  let pid: number | undefined;
  let turnNo = 0;
  const asked: Recorded[] = [];
  const t0 = Date.now();
  const q: Query = query({
    prompt: iterable,
    options: {
      cwd: a.folder,
      pathToClaudeCodeExecutable: process.env.CARRIER_IT_CLAUDE_COMMAND ?? 'claude',
      env: a.mcp ? { ...process.env, CARRIER_MCP_TOKEN: a.mcp.token } : process.env,
      includePartialMessages: false,
      spawnClaudeCodeProcess: (o) => {
        const child = spawn(o.command, o.args, { cwd: o.cwd, env: o.env as NodeJS.ProcessEnv, stdio: ['pipe', 'pipe', 'pipe'], detached: true });
        pid = child.pid;
        return child;
      },
      canUseTool: async (tool, input, o) => {
        const x = o as Record<string, unknown>;
        asked.push({ turn: turnNo, tool, input, title: x.title as string, displayName: x.displayName as string, description: x.description as string, decisionReason: x.decisionReason as string, blockedPath: x.blockedPath as string, suggestions: x.suggestions, toolUseID: x.toolUseID as string });
        if (a.allow?.includes(tool)) return { behavior: 'allow', updatedInput: input };
        return { behavior: 'deny', message: 'Denied by the spike probe.' };
      },
      ...(a.model && { model: a.model }),
      ...(a.mode && { permissionMode: a.mode as never }),
      ...(a.settingSources && { settingSources: a.settingSources }),
      ...(a.mcp && {
        mcpServers: { [SERVER]: { type: 'http' as const, url: a.mcp.url, headers: { Authorization: 'Bearer ${CARRIER_MCP_TOKEN}' } } },
        ...(a.allowedTools && { allowedTools: a.allowedTools }),
      }),
    },
  });
  const ready = await q.initializationResult();
  const readyMs = Date.now() - t0;
  let init: Record<string, unknown> = {};
  let turn: TurnLog | undefined;
  let done: (() => void) | undefined;
  const pump = (async () => {
    try {
      for await (const m of q as AsyncIterable<any>) {
        if (m.type === 'system' && m.subtype === 'init') init = { model: m.model, permissionMode: m.permissionMode, claude_code_version: m.claude_code_version, mcp_servers: m.mcp_servers, tools: m.tools };
        if (!turn) continue;
        if (m.type === 'assistant') for (const b of m.message?.content ?? []) {
          if (b.type === 'text') turn.said += b.text + '\n';
          if (b.type === 'tool_use') turn.tools.push({ name: b.name, input: b.input });
        }
        if (m.type === 'user') for (const b of Array.isArray(m.message?.content) ? m.message.content : []) if (b.type === 'tool_result') {
          const text = typeof b.content === 'string' ? b.content : (b.content ?? []).map((c: any) => c.text ?? '').join(' ');
          turn.results.push({ tool: b.tool_use_id, error: !!b.is_error, text: text.slice(0, 240) });
        }
        if (m.type === 'result') { turn.outcome = `${m.subtype}${m.is_error ? ' (error)' : ''}`; turn.resultText = typeof m.result === 'string' ? m.result.slice(0, 300) : undefined; turn.denials = m.permission_denials; done?.(); }
      }
    } catch (e) { if (turn) turn.outcome = `stream failed: ${String(e).slice(0, 200)}`; done?.(); }
  })();
  return {
    ready, readyMs, get init() { return init; }, asked, query: q,
    async send(prompt: string, timeout = 150_000): Promise<TurnLog> {
      turnNo++;
      const from = Date.now();
      turn = { prompt, ms: 0, asked: [], tools: [], results: [], said: '', outcome: 'timeout' };
      const finished = new Promise<void>((r) => (done = r));
      waiting.push({ type: 'user', message: { role: 'user', content: prompt }, parent_tool_use_id: null });
      wake?.();
      await Promise.race([finished, new Promise((r) => setTimeout(r, timeout))]);
      turn.ms = Date.now() - from;
      turn.asked = asked.filter((x) => x.turn === turnNo);
      const out = turn; turn = undefined;
      return out;
    },
    async close() { ended = true; wake?.(); q.close(); if (pid !== undefined) await endGroup(pid); await Promise.race([pump, new Promise((r) => setTimeout(r, 2000))]); },
  };
}

export const save = (name: string, data: unknown) => writeFileSync(join(import.meta.dirname, 'raw', `${name}.json`), JSON.stringify(data, null, 2));
