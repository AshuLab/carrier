import { appendFileSync, mkdirSync, mkdtempSync, rmSync, truncateSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { openChatDatabase } from '../chat/db.ts';
import { chatTurns, sessions } from '../chat/schema.ts';
import type { Providers } from '../config/providers.ts';
import { openDatabase } from '../storage/db.ts';
import { epics } from '../storage/schema.ts';
import { executions, type ExecutionUsage } from '../storage/executions.ts';
import { createHistory, type HistoryFilter, type HistoryPorts, type HistoryRoots } from './history.ts';
import { createPriceOverrides } from './pricing.ts';
import { realHistoryPorts } from './real.ts';

vi.mock('@ashulab/universal-logger', () => ({ createScopedLogger: () => ({ debug() {}, info() {}, warn() {}, error() {} }) }));

const NOW = new Date(2026, 10, 13, 12).getTime(); // local noon, so the day does not depend on the time zone
const HOUR = 3_600_000;
const iso = (ms: number) => new Date(ms).toISOString();
const week: HistoryFilter = { days: 7 };

let dir: string;
let bytesRead: number;
let ports: HistoryPorts;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'history-'));
  bytesRead = 0;
  ports = {
    clock: { now: () => NOW, after: () => () => {} },
    ...realHistoryPorts,
    files: { ...realHistoryPorts.files, read: async (path, from) => { const buffer = await realHistoryPorts.files.read(path, from); bytesRead += buffer.length; return buffer; } },
  };
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

const roots = (): HistoryRoots => ({ claude: [join(dir, 'claude')], codex: [join(dir, 'codex')], agy: [join(dir, 'agy')] });
function setup(accounts: Providers = {}) {
  const chat = openChatDatabase(join(dir, 'chat.db'));
  const engineDbFile = join(dir, 'engine', 'carrier.db');
  const history = createHistory(ports, { chat, engineDbFile });
  return { chat, engineDbFile, run: (filter: HistoryFilter = week, r = roots()) => history(filter, { accounts, roots: r }) };
}
const write = (path: string, lines: string[]) => (mkdirSync(join(path, '..'), { recursive: true }), writeFileSync(path, lines.map((l) => `${l}\n`).join('')));

const claudeLine = (o: { id: string; req?: string; session?: string; model?: string; at?: number; input?: number; cacheRead?: number; cacheWrite?: number; output?: number; cwd?: string }) =>
  JSON.stringify({ type: 'assistant', sessionId: o.session ?? 'c1', requestId: o.req ?? 'r1', timestamp: iso(o.at ?? NOW - HOUR), cwd: o.cwd ?? '/work/app', message: { id: o.id, model: o.model ?? 'claude-sonnet-4-5', usage: { input_tokens: o.input ?? 0, cache_read_input_tokens: o.cacheRead ?? 0, cache_creation_input_tokens: o.cacheWrite ?? 0, output_tokens: o.output ?? 0 } } });

const codexLog = (session: string, snapshots: { input: number; cached: number; output: number; reasoning?: number }[], model = 'gpt-5-codex') => [
  JSON.stringify({ type: 'session_meta', payload: { id: session, cwd: '/work/cx' } }),
  JSON.stringify({ type: 'turn_context', payload: { model } }),
  ...snapshots.flatMap((s, i) => {
    const line = JSON.stringify({ type: 'event_msg', timestamp: iso(NOW - HOUR + i), payload: { type: 'token_count', info: { total_token_usage: { total: s.input + s.output }, last_token_usage: { input_tokens: s.input, cached_input_tokens: s.cached, output_tokens: s.output, reasoning_output_tokens: s.reasoning ?? 0 } } } });
    return [line];
  }),
];

function insertChat(chat: ReturnType<typeof openChatDatabase>, o: { id: string; nativeId?: string | null; agent?: string; harness?: 'claude' | 'codex'; at?: number; model?: string | null; usage: Record<string, number> }) {
  chat.insert(sessions).values({ id: o.id, agent: o.agent ?? 'claude', harness: o.harness ?? 'claude', folder: `/work/${o.id}`, nativeId: o.nativeId ?? null, createdAt: 1, lastActiveAt: 1 }).run();
  chat.insert(chatTurns).values({ sessionId: o.id, startedAt: o.at ?? NOW - HOUR, model: o.model === undefined ? 'claude-sonnet-4-5' : o.model, outcome: 'ok', durationMs: 1, toolCalls: 0, usage: o.usage }).run();
}

function insertEpicRun(file: string, o: { executionId: string; sessionId: string | null; harness?: string; provider?: string | null; model?: string; usage: ExecutionUsage | null; repo?: string }) {
  mkdirSync(join(file, '..'), { recursive: true });
  const db = openDatabase(file);
  const epic = db.insert(epics).values({ repo: o.repo ?? 'acme/app', issue: Math.floor(Math.random() * 1e9) }).returning().get();
  db.insert(executions).values({ executionId: o.executionId, epicId: epic.id, stage: 'ship', sessionId: o.sessionId, harness: o.harness ?? 'claude', model: o.model ?? 'claude-sonnet-4-5', provider: o.provider ?? null, usage: o.usage, resultPath: '/r.json', startedAt: NOW - 2 * HOUR, finishedAt: NOW - HOUR }).run();
  db.$client.close();
}
const usage = (inputTokens: number, outputTokens: number, costUsd: number | null = null): ExecutionUsage => ({ inputTokens, cachedInputTokens: 0, cacheWriteTokens: 0, outputTokens, reasoningTokens: 0, costUsd });

// ---- Claude transcripts

test('a streamed Claude message and a forked copy of it count once, at the final token counts, and a synthetic or malformed line counts for nothing', async () => {
  write(join(dir, 'claude', 'p', 'a.jsonl'), [
    claudeLine({ id: 'm1', input: 100, output: 5 }),
    claudeLine({ id: 'm1', input: 100, output: 40, cacheRead: 1000, cacheWrite: 200 }), // the same message, written again as it grew
    'this is not json',
    '{"type":"assistant","message":"nope"}',
    claudeLine({ id: 'm2', model: '<synthetic>', input: 9999 }),
    claudeLine({ id: 'm3', req: 'r3', input: 10, output: 10 }),
  ]);
  write(join(dir, 'claude', 'p', 'b-fork.jsonl'), [claudeLine({ id: 'm1', input: 100, output: 40, cacheRead: 1000, cacheWrite: 200 }), claudeLine({ id: 'm1', req: 'other-request', input: 1, output: 1 })]);
  const { run } = setup();
  const result = await run();
  expect(result.totals.tokens).toEqual({ input: 100 + 10 + 1, cachedInput: 1000, cacheWrite: 200, output: 40 + 10 + 1, reasoning: 0 });
  expect(result.totals.turns).toBe(3);
  expect(result.byModel).toMatchObject([{ model: 'claude-sonnet-4-5', provider: 'claude', costStatus: 'priced', isLocal: false }]);
  expect(result.byWorkspace).toMatchObject([{ workspace: '/work/app', source: 'external', turns: 3 }]);
});

test('a second look reads only what was appended, ignores a last line still being written, and starts over when the file was rewritten', async () => {
  const file = join(dir, 'claude', 'p', 'a.jsonl');
  write(file, [claudeLine({ id: 'm1', input: 100, output: 10 })]);
  const { run } = setup();
  expect((await run()).totals.tokens.input).toBe(100);

  bytesRead = 0;
  expect((await run()).totals.tokens.input).toBe(100);
  expect(bytesRead).toBe(0); // nothing changed: nothing read

  const added = claudeLine({ id: 'm2', input: 7, output: 1 });
  appendFileSync(file, `${added}\n${claudeLine({ id: 'm3', input: 1000 }).slice(0, 30)}`); // the last line is cut
  bytesRead = 0;
  expect((await run()).totals.tokens.input).toBe(107);
  expect(bytesRead).toBeLessThan(added.length + 1 + 30 + 100); // the new bytes and a few before them, not the file
  appendFileSync(file, `${claudeLine({ id: 'm3', input: 1000 }).slice(30)}\n`);
  expect((await run()).totals.tokens.input).toBe(1107); // the cut line counts once it is whole

  write(file, [claudeLine({ id: 'x', input: 5, output: 1 })]); // rewritten, and shorter
  expect((await run()).totals.tokens.input).toBe(5);
  truncateSync(file, 0);
  expect((await run()).totals.turns).toBe(0);
});

test('a file that grew but whose earlier bytes changed is read again from the start', async () => {
  const file = join(dir, 'claude', 'p', 'a.jsonl');
  write(file, [claudeLine({ id: 'm1', input: 100 })]);
  const { run } = setup();
  await run();
  write(file, [claudeLine({ id: 'n1', input: 3, model: 'claude-haiku-4-5' }), claudeLine({ id: 'n2', input: 4 }), claudeLine({ id: 'n3', input: 5 })]);
  expect((await run()).totals.tokens.input).toBe(12);
});

// ---- Codex

test('Codex counts input without the cached tokens, once per changed snapshot, and keeps reasoning inside output', async () => {
  write(join(dir, 'codex', '2026', 'rollout-1.jsonl'), [
    ...codexLog('cx-1', [{ input: 1000, cached: 800, output: 50, reasoning: 20 }, { input: 1000, cached: 800, output: 50, reasoning: 20 }]),
    'garbage', // the second snapshot above has the same running total as the first: the same step written twice
  ]);
  appendFileSync(join(dir, 'codex', '2026', 'rollout-1.jsonl'), `${codexLog('cx-1', [{ input: 500, cached: 600, output: 5 }])[2]!.replace('"total":505', '"total":506')}\n`); // a cached count above the input never goes negative
  const { run } = setup();
  const result = await run();
  expect(result.totals.tokens).toEqual({ input: 200 + 0, cachedInput: 800 + 600, cacheWrite: 0, output: 55, reasoning: 20 });
  expect(result.totals.turns).toBe(2);
  expect(result.byModel[0]).toMatchObject({ model: 'gpt-5-codex', provider: 'codex' });
  expect(result.byWorkspace[0]).toMatchObject({ workspace: '/work/cx', source: 'external' });
});

// ---- Antigravity

const varint = (n: number) => {
  const out: number[] = [];
  for (; n >= 128; n = Math.floor(n / 128)) out.push((n % 128) | 128);
  out.push(n);
  return out;
};
const num = (field: number, value: number) => [...varint(field * 8), ...varint(value)];
const bytes = (field: number, value: number[] | string) => {
  const body = typeof value === 'string' ? [...Buffer.from(value)] : value;
  return [...varint(field * 8 + 2), ...varint(body.length), ...body];
};
const agyUsage = (o: { input?: number; output?: number; cached?: number; id?: string }) => [...num(2, o.input ?? 0), ...num(3, o.output ?? 0), ...num(5, o.cached ?? 0), ...(o.id ? bytes(11, o.id) : [])];
const generation = (model: string, usage: number[], seconds = Math.floor((NOW - HOUR) / 1000)) => Buffer.from(bytes(1, [...bytes(19, model), ...bytes(4, usage), ...bytes(9, bytes(4, num(1, seconds)))]));
const step = (model: string, usage: number[]) => Buffer.from([...bytes(24, bytes(12, model)), ...bytes(9, usage), ...bytes(8, num(1, Math.floor((NOW - HOUR) / 1000)))]);

function agyDb(file: string, generations: Buffer[], steps: Buffer[]) {
  mkdirSync(join(file, '..'), { recursive: true });
  const db = new Database(file);
  db.exec('create table gen_metadata (idx integer, data blob); create table steps (idx integer, metadata blob)');
  generations.forEach((g, i) => db.prepare('insert into gen_metadata values (?, ?)').run(i, g));
  steps.forEach((s, i) => db.prepare('insert into steps values (?, ?)').run(i, s));
  db.close();
}

test('Antigravity conversations are read from their databases once per call id, and a corrupt file or blob does not fail the rollup', async () => {
  agyDb(join(dir, 'agy', 'conv-1.db'), [generation('Gemini 2.5 Pro', agyUsage({ input: 300, output: 40, cached: 100, id: 'call-1' }))], [
    step('gemini-2.5-pro', agyUsage({ input: 300, output: 60, cached: 100, id: 'call-1' })), // the same call, seen as a step
    step('gemini-2.5-pro', agyUsage({ input: 50, output: 5, id: 'call-2' })),
  ]);
  agyDb(join(dir, 'agy', 'conv-2.db'), [Buffer.from([0x0a, 0xff, 0xff])], []); // a blob that is cut short
  writeFileSync(join(dir, 'agy', 'conv-3.db'), 'this is not a sqlite file');
  agyDb(join(dir, 'agy', 'conv-4.db'), [], []);
  const { run } = setup();
  const result = await run();
  expect(result.totals.tokens).toEqual({ input: 350, cachedInput: 100, cacheWrite: 0, output: 65, reasoning: 0 });
  expect(result.byModel).toMatchObject([{ model: 'gemini-2.5-pro', provider: 'agy', costStatus: 'priced' }]);
  expect(result.totals.turns).toBe(2);
});

// ---- Carrier sources

test('without an engine database the chat turns still add up', async () => {
  const { chat, run, engineDbFile } = setup();
  insertChat(chat, { id: 's1', usage: { input_tokens: 10, output_tokens: 5, cache_read_input_tokens: 100 } });
  expect(engineDbFile).toContain('engine');
  const result = await run();
  expect(result.totals.tokens).toEqual({ input: 10, cachedInput: 100, cacheWrite: 0, output: 5, reasoning: 0 });
  expect(result.byWorkspace).toMatchObject([{ workspace: '/work/s1', source: 'chat' }]);
});

test('an engine database that cannot be read is skipped', async () => {
  const { chat, run, engineDbFile } = setup();
  mkdirSync(join(engineDbFile, '..'), { recursive: true });
  writeFileSync(engineDbFile, 'not a database');
  insertChat(chat, { id: 's1', usage: { input_tokens: 10 } });
  expect((await run()).totals.tokens.input).toBe(10);
});

test('Codex chat turns subtract the cached tokens from the input', async () => {
  const { chat, run } = setup();
  insertChat(chat, { id: 's1', harness: 'codex', agent: 'codex', model: 'gpt-5-codex', usage: { inputTokens: 1000, cachedInputTokens: 900, outputTokens: 20, reasoningOutputTokens: 5 } });
  expect((await run()).totals.tokens).toEqual({ input: 100, cachedInput: 900, cacheWrite: 0, output: 20, reasoning: 5 });
});

test('an epic run is read from the engine database by model, with the cost the CLI reported', async () => {
  const { engineDbFile, run } = setup();
  insertEpicRun(engineDbFile, { executionId: 'e1', sessionId: 'sess-e1', usage: { ...usage(30, 10, 1.5), byModel: { 'claude-sonnet-4-5': usage(20, 5, 1), 'claude-haiku-4-5': usage(10, 5, 0.5) } } });
  insertEpicRun(engineDbFile, { executionId: 'e2', sessionId: 'sess-e2', usage: null }); // an older run, with no usage
  const result = await run();
  expect(result.totals).toMatchObject({ costUsd: 1.5, turns: 2, tokens: { input: 30, output: 10 } });
  expect(result.byWorkspace).toMatchObject([{ workspace: 'acme/app', source: 'epic', turns: 2 }]);
});

test('a session in several sources counts once, in the first of epic, chat, external', async () => {
  const { chat, engineDbFile, run } = setup();
  insertEpicRun(engineDbFile, { executionId: 'e1', sessionId: 'S-EPIC', usage: usage(1000, 0) });
  insertChat(chat, { id: 'chat-a', nativeId: 'S-EPIC', usage: { input_tokens: 200 } }); // a chat that resumed the epic's session: the epic has it
  insertChat(chat, { id: 'chat-b', nativeId: 'S-CHAT', usage: { input_tokens: 30 } });
  write(join(dir, 'claude', 'p', 'a.jsonl'), [
    claudeLine({ id: 'm1', session: 'S-EPIC', input: 4000 }),
    claudeLine({ id: 'm2', session: 'S-CHAT', input: 500 }),
    claudeLine({ id: 'm3', session: 'S-EXT', input: 6 }),
  ]);
  write(join(dir, 'codex', 'r.jsonl'), codexLog('S-CHAT', [{ input: 70000, cached: 0, output: 1 }])); // the same id under another harness is another session
  const result = await run();
  expect(result.totals.tokens.input).toBe(1000 + 30 + 6 + 70000);
  const turns = (source: string) => result.byWorkspace.filter((w) => w.source === source).reduce((sum, w) => sum + w.turns, 0);
  expect([turns('epic'), turns('chat'), turns('external')]).toEqual([1, 1, 2]);
});

// ---- Cost

test('local compute costs $0.00 and is tagged, whatever harness ran it', async () => {
  const { chat, engineDbFile, run } = setup({ 'claude-lm': { harness: 'claude', provider: 'lmstudio' } });
  insertChat(chat, { id: 's1', agent: 'claude-lm', model: 'qwen3-coder', usage: { input_tokens: 400, output_tokens: 40 } });
  insertChat(chat, { id: 's2', agent: 'claude', usage: { input_tokens: 1_000_000 } });
  insertEpicRun(engineDbFile, { executionId: 'e1', sessionId: 'x', provider: 'ollama', model: 'llama', usage: usage(900, 90, 7) });
  const result = await run();
  const local = result.byModel.filter((m) => m.isLocal);
  expect(local.map((m) => m.model).sort()).toEqual(['llama', 'qwen3-coder']);
  expect(local).toMatchObject([{ provider: 'local', costUsd: 0, costStatus: 'local' }, { provider: 'local', costUsd: 0, costStatus: 'local' }]);
  expect(result.totals.costUsd).toBeCloseTo(3); // only the cloud turn
  expect((await run({ days: 7, provider: 'local' })).totals.turns).toBe(2);
  expect((await run({ days: 7, provider: 'claude' })).totals.turns).toBe(1);
});

test('a cloud model with no price is marked unpriced, keeps its tokens and adds no dollars', async () => {
  const { chat, run } = setup();
  insertChat(chat, { id: 's1', model: 'brand-new-model', usage: { input_tokens: 1_000_000, output_tokens: 1_000_000 } });
  insertChat(chat, { id: 's2', model: null, usage: { output_tokens: 1 } });
  const result = await run();
  expect(result.totals).toMatchObject({ costUsd: 0, tokens: { input: 1_000_000, output: 1_000_001 } });
  expect(result.byModel).toMatchObject([{ model: 'brand-new-model', costStatus: 'unpriced', costUsd: 0 }, { model: 'unknown', costStatus: 'unpriced' }]);
});

test('price overrides change the rollup and clearing one puts it back', async () => {
  const { chat, run } = setup();
  insertChat(chat, { id: 's1', model: 'brand-new-model', usage: { input_tokens: 1_000_000 } });
  const overrides = createPriceOverrides(chat, () => NOW);
  expect((await run()).byModel[0]).toMatchObject({ costStatus: 'unpriced' });
  overrides.set({ model: 'brand-new-model', action: 'custom', inputUsdPerMillion: 2, outputUsdPerMillion: 8 });
  expect((await run()).byModel[0]).toMatchObject({ costStatus: 'priced', costUsd: 2 });
  overrides.set({ model: 'Brand-New-Model', action: 'alias', aliasModel: 'claude-haiku-4-5' });
  expect((await run()).byModel[0]).toMatchObject({ costStatus: 'priced', costUsd: 1 });
  overrides.set({ model: 'brand-new-model', action: 'zero' });
  expect((await run()).byModel[0]).toMatchObject({ costStatus: 'local', provider: 'local', costUsd: 0 });
  overrides.set({ model: 'brand-new-model', action: 'clear' });
  expect((await run()).byModel[0]).toMatchObject({ costStatus: 'unpriced' });
});

// ---- Window and filters

test('days, provider, source and search narrow the rollup and the chart has one entry per day', async () => {
  const { chat, engineDbFile, run } = setup();
  insertChat(chat, { id: 'recent', usage: { input_tokens: 1 } });
  insertChat(chat, { id: 'six-days-ago', at: NOW - 6 * 24 * HOUR, usage: { input_tokens: 2 } });
  insertChat(chat, { id: 'ten-days-ago', at: NOW - 10 * 24 * HOUR, usage: { input_tokens: 4 } });
  insertEpicRun(engineDbFile, { executionId: 'e1', sessionId: 'e', model: 'claude-opus-4-5', repo: 'acme/web', usage: usage(8, 0) });
  write(join(dir, 'codex', 'r.jsonl'), codexLog('x', [{ input: 16, cached: 0, output: 0 }]));

  const week = await run({ days: 7 });
  expect(week.days.map((d) => d.date)).toHaveLength(7);
  expect(week.days.at(-1)).toMatchObject({ date: '2026-11-13', turns: 3 });
  expect(week.totals.tokens.input).toBe(1 + 2 + 8 + 16);
  expect((await run({ days: 14 })).totals.tokens.input).toBe(1 + 2 + 4 + 8 + 16);
  expect((await run({ days: 7, source: 'epic' })).totals.tokens.input).toBe(8);
  expect((await run({ days: 7, source: 'external' })).totals.tokens.input).toBe(16);
  expect((await run({ days: 7, provider: 'codex' })).totals.tokens.input).toBe(16);
  expect((await run({ days: 7, search: 'OPUS' })).totals.tokens.input).toBe(8);
  expect((await run({ days: 7, search: 'acme/web' })).totals.tokens.input).toBe(8);
  expect((await run({ days: 7, search: 'nothing like it' })).totals).toMatchObject({ turns: 0, costUsd: 0 });
});

test('a folder that does not exist is no source', async () => {
  const { run } = setup();
  expect((await run({ days: 7 }, { claude: [join(dir, 'none')], codex: [], agy: [join(dir, 'none')] })).totals.turns).toBe(0);
});
