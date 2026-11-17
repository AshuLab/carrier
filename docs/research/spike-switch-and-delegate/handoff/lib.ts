// Shared helpers of part C. Real agents, cheapest model, a temp folder under /tmp, a hard budget of turns shared by every script.
import { appendFileSync, existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { claudeChatRunner } from '../../../../src/chat/claude.ts';
import { codexChatRunner } from '../../../../src/chat/codex.ts';
import { McpSessionRegistry, defineTool, startMcpServer, type McpServer } from '../../../../src/chat/mcp.ts';
import { realClock } from '../../../../src/orchestration/clock.ts';
import type { ChatCommand, ChatConversation, ChatEvent } from '../../../../src/chat/runner.ts';

export const here = dirname(fileURLToPath(import.meta.url));
export const dataDir = join(here, 'data');
const TURN_LOG = join(dataDir, 'turns.jsonl');
export const TURN_BUDGET = 45;

export const turnsUsed = () => (existsSync(TURN_LOG) ? readFileSync(TURN_LOG, 'utf8').split('\n').filter(Boolean).length : 0);

export type Harness = 'claude' | 'codex';
export const MODEL: Record<Harness, string> = { claude: 'haiku', codex: 'gpt-6-luna' };
export const tmpFolder = (label: string) => realpathSync(mkdtempSync(join(tmpdir(), `hf-${label}-`)));

/** An item of the transcript: an event with the position it got. Deltas are never kept (as Carrier's own record). */
export type Item = ChatEvent & { position: number };
export type Turn = { events: ChatEvent[]; said: string; tools: string[]; outcome: string; errors: string[]; approvalsDenied: string[] };

export type Mcp = { serverName: string; url: string; token: string };

export type Live = {
  harness: Harness;
  folder: string;
  conv: ChatConversation;
  items: Item[];
  turn(text: string, command?: ChatCommand, label?: string): Promise<Turn>;
  close(): Promise<void>;
};

const openConversations = new Set<ChatConversation>();
process.on('SIGINT', () => void Promise.all([...openConversations].map((c) => c.close())).finally(() => process.exit(130)));

export async function openLive(harness: Harness, args: { folder: string; mcp?: Mcp; options?: Record<string, string>; runner?: ReturnType<typeof claudeChatRunner> }): Promise<Live> {
  const options = harness === 'claude' ? { model: MODEL.claude, permissionMode: 'default', ...args.options } : { model: MODEL.codex, effort: 'low', approvalPolicy: 'never', sandbox: 'read-only', ...args.options };
  const runner = args.runner ?? (harness === 'claude' ? claudeChatRunner() : codexChatRunner());
  const conv = await runner.open({ folder: args.folder, env: process.env, options, mcp: args.mcp });
  openConversations.add(conv);
  const items: Item[] = [];
  const denied: string[] = [];
  conv.onEvent((e) => {
    if (e.kind !== 'delta') items.push({ ...e, position: items.length });
    // an approval that the probe does not need is denied
    if (e.kind === 'approval') {
      denied.push(`${e.tool}: ${e.arg ?? ''}`.slice(0, 200));
      const no = e.choices.find((c) => !c.allow)?.id ?? 'deny';
      queueMicrotask(() => conv.answer(e.approvalId, no));
    }
  });
  const turn = async (text: string, command?: ChatCommand, label = '') => {
    if (turnsUsed() >= TURN_BUDGET) throw new Error(`turn budget of ${TURN_BUDGET} reached`);
    appendFileSync(TURN_LOG, JSON.stringify({ at: new Date().toISOString(), harness, label, bytes: Buffer.byteLength(text) }) + '\n');
    const from = items.length;
    denied.length = 0;
    items.push({ kind: 'user', text, ...(command && { command: command.name }), position: items.length });
    const start = items.length;
    conv.send(text, command);
    const t0 = Date.now();
    while (!items.slice(start).some((e) => e.kind === 'turn_end')) {
      if (Date.now() - t0 > 240_000) throw new Error('turn timed out');
      await new Promise((r) => setTimeout(r, 200));
    }
    const events = items.slice(from);
    const end = events.find((e) => e.kind === 'turn_end') as Extract<ChatEvent, { kind: 'turn_end' }>;
    const errors = events.filter((e) => e.kind === 'error').map((e) => (e as { text: string }).text);
    const result: Turn = {
      events,
      said: events.filter((e) => e.kind === 'assistant').map((e) => (e as { text: string }).text).join('\n'),
      tools: events.filter((e) => e.kind === 'tool_start').map((e) => (e as { tool: string }).tool),
      outcome: end.outcome,
      errors,
      approvalsDenied: [...denied],
    };
    if (errors.some((x) => /usage limit|rate limit|limit reached|quota/i.test(x))) throw new Error(`LIMIT: ${errors.join(' | ').slice(0, 300)}`);
    return result;
  };
  return {
    harness, folder: args.folder, conv, items, turn,
    close: async () => { openConversations.delete(conv); await conv.close(); },
  };
}

// ---- toy history tool and its server ----

export type Stored = Item;
const PAGE_TEXT = 1500; // a page shows the start of each text; the whole of it is read by item
const ITEM_TEXT = 6000; // one read of one item
const PAGE_MAX = 40;

export const idOf = (position: number) => `m${position}`;

/** Messages and tool calls of the stored transcript, as `history` shows them: never reasoning, never deltas. */
const visible = (items: Stored[]) => items.filter((i) => i.kind === 'user' || i.kind === 'assistant' || i.kind === 'tool_start' || i.kind === 'tool_end' || i.kind === 'notice');
const textOf = (i: Stored) => ('text' in i ? i.text : 'tool' in i ? `${i.kind}:${i.tool} ${'arg' in i ? i.arg ?? '' : ''}` : '');

export function historyTool(items: Stored[], counter: { calls: { args: unknown; at: number }[] }) {
  return defineTool({
    name: 'history',
    description: 'Reads the stored conversation of this session. Page it with afterPosition and limit (each text is cut to its first 1500 characters and says its length), or read one item with itemId, and with textOffset to continue a long one: the reply carries nextOffset, null at the end.',
    access: 'readsAsSession',
    input: z.strictObject({
      afterPosition: z.number().int().min(-1).optional().describe('return items after this position; -1 or omitted starts at the beginning'),
      limit: z.number().int().min(1).max(PAGE_MAX).optional().describe(`how many items, at most ${PAGE_MAX}; default 10`),
      itemId: z.string().optional().describe('read this one item, for example m4'),
      textOffset: z.number().int().min(0).optional().describe('with itemId: the character to start from'),
    }),
    handler: (args) => {
      counter.calls.push({ args, at: Date.now() });
      const shown = visible(items);
      if (args.itemId !== undefined) {
        const found = shown.find((i) => idOf(i.position) === args.itemId);
        if (found === undefined) return { error: `no item ${args.itemId}` };
        const full = textOf(found);
        const from = args.textOffset ?? 0;
        const slice = full.slice(from, from + ITEM_TEXT);
        const next = from + ITEM_TEXT < full.length ? from + ITEM_TEXT : null;
        return { id: args.itemId, position: found.position, kind: found.kind, length: full.length, textOffset: from, text: slice, nextOffset: next };
      }
      const after = args.afterPosition ?? -1;
      const page = shown.filter((i) => i.position > after).slice(0, args.limit ?? 10);
      const last = page.at(-1)?.position ?? after;
      return {
        items: page.map((i) => { const t = textOf(i); return { id: idOf(i.position), position: i.position, kind: i.kind, length: t.length, text: t.slice(0, PAGE_TEXT), truncated: t.length > PAGE_TEXT }; }),
        nextAfterPosition: shown.some((i) => i.position > last) ? last : null,
      };
    },
  });
}

export async function startHistoryServer(items: Stored[]): Promise<{ mcp: Mcp; server: McpServer; counter: { calls: { args: unknown; at: number }[] } }> {
  const registry = new McpSessionRegistry(realClock);
  const counter = { calls: [] as { args: unknown; at: number }[] };
  const server = await startMcpServer({
    registry,
    tools: [historyTool(items, counter)],
    sessions: { exists: () => true, live: () => true, snapshot: (id) => ({ id, agent: 'spike', harness: 'x', folder: '/', model: null, options: {} }), agents: () => [], health: async () => ({ git: 'ready', gh: 'ready', agents: [] }) },
  });
  const token = registry.issue({ sessionId: 's1', invocationId: 'i1' });
  return { mcp: { serverName: 'carrier-chat', url: server.url, token }, server, counter };
}

// ---- the handoff builder (ADR 0032) ----

export const HANDOFF_BYTES = 16_000;
const bytes = (s: string) => Buffer.byteLength(s, 'utf8');

/** Cuts to at most `max` UTF-8 bytes on a character boundary. */
function cutBytes(s: string, max: number) {
  let out = '';
  let used = 0;
  for (const ch of s) {
    const n = bytes(ch);
    if (used + n > max) break;
    out += ch;
    used += n;
  }
  return out;
}

export type Handoff = { text: string; messageBytes: number; textBytes: number; included: string[]; cut: string | undefined; omitted: string[] };

/**
 * The person's first message, then the newest messages walking backwards while the total stays at or under `budget` UTF-8 bytes
 * (user and assistant text only); the message that does not fit is cut to what is left (ADR 0032: "a message that is longer than what is
 * left is cut") and the walk stops; the ids of what was left out; a sentence about `history`.
 */
export function buildHandoff(items: Stored[], budget = HANDOFF_BYTES): Handoff {
  const messages = items.filter((i): i is Extract<Stored, { kind: 'user' | 'assistant' }> => i.kind === 'user' || i.kind === 'assistant');
  const first = messages[0]!;
  let used = bytes(first.text);
  const chosen = new Map<number, string>([[first.position, first.text]]);
  let cut: string | undefined;
  for (let i = messages.length - 1; i > 0; i--) {
    const m = messages[i]!;
    const n = bytes(m.text);
    if (used + n <= budget) {
      chosen.set(m.position, m.text);
      used += n;
    } else {
      const room = budget - used;
      if (room > 200) {
        chosen.set(m.position, cutBytes(m.text, room) + `\n[cut: read the rest with the history tool, itemId ${idOf(m.position)}, textOffset ${cutBytes(m.text, room).length}]`);
        cut = idOf(m.position);
        used = budget;
      }
      break;
    }
  }
  const ordered = messages.filter((m) => chosen.has(m.position));
  const omitted = messages.filter((m) => !chosen.has(m.position)).map((m) => idOf(m.position));
  const body = ordered.map((m) => `[${idOf(m.position)} ${m.kind === 'user' ? 'person' : 'assistant'}]\n${chosen.get(m.position)}`).join('\n\n');
  const text = [
    'You are taking over a conversation that another agent had with the person, in this same folder. What follows is a selection of it, not all of it: the first message of the person and the newest messages, in order. Reasoning and tool results are not included.',
    '',
    '<previous-conversation>',
    body,
    '</previous-conversation>',
    '',
    omitted.length > 0 ? `Left out of this selection: ${omitted.join(', ')}.` : 'Nothing was left out.',
    'The `history` tool of the carrier-chat MCP server reads the rest of the conversation: page it with afterPosition and limit, or read one item by itemId (with textOffset for a long one). Use it when what the person asks needs something that is not above.',
    '',
    'The person writes now:',
  ].join('\n');
  return { text, messageBytes: used, textBytes: bytes(text), included: ordered.map((m) => idOf(m.position)), cut, omitted };
}

export const save = (name: string, value: unknown) => writeFileSync(join(dataDir, name), typeof value === 'string' ? value : JSON.stringify(value, null, 1));
export const load = <T>(name: string): T => JSON.parse(readFileSync(join(dataDir, name), 'utf8')) as T;
export { rmSync };
