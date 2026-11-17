// The toy chat MCP: Carrier's own server with two tools, each returning a fixed string and appending to a log.
import { appendFileSync, readFileSync } from 'node:fs';
import { z } from 'zod';
import { McpSessionRegistry, startMcpServer, defineTool } from '../../../../src/chat/mcp.ts';
import { realClock } from '../../../../src/orchestration/clock.ts';

export async function startToy(logFile: string, folder: string) {
  const registry = new McpSessionRegistry(realClock);
  const mk = (name: string, access: 'readsAsSession' | 'actsAsSession') =>
    defineTool({ name, description: `Toy ${name}: returns a fixed string.`, access, input: z.strictObject({ note: z.string().optional() }), handler: () => { appendFileSync(logFile, `${name}\n`); return `${name}-ok`; } });
  const server = await startMcpServer({
    registry,
    tools: [mk('ping_read', 'readsAsSession'), mk('ping_act', 'actsAsSession')],
    sessions: { exists: () => true, live: () => true, snapshot: (id) => ({ id, agent: 'it', harness: 'codex', folder, model: null, options: {} }), agents: () => [], health: async () => ({ git: 'ready', gh: 'ready', agents: [] }) },
  });
  const token = registry.issue({ sessionId: 's1', invocationId: 'i1', capabilities: ['read', 'act'] });
  const calls = () => { try { return readFileSync(logFile, 'utf8').split('\n').filter(Boolean); } catch { return []; } };
  return { url: server.url, token, calls, close: () => server.close() };
}
