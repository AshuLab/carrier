import { basename } from 'node:path';
import { createScopedLogger } from '@ashulab/universal-logger';
import { eq, gte, isNotNull } from 'drizzle-orm';
import type { ChatDb } from '../chat/db.ts';
import { chatTurns, sessions } from '../chat/schema.ts';
import type { Providers } from '../config/providers.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ExecutionUsage, ModelUsage } from '../storage/executions.ts';
import { readAgyRecords, type AgyRecord, type RowSource } from './agy.ts';
import { createPriceOverrides, normalizeModel, priceOf, type PriceOverride, type Tokens } from './pricing.ts';

const log = createScopedLogger('usage');

export type HistorySource = 'epic' | 'chat' | 'external';
export type HistoryHarness = 'claude' | 'codex' | 'agy';

export interface HistoryFilter {
  days: 7 | 14 | 30 | 90;
  /** `local` is any turn on a local server, whatever harness ran it. */
  provider?: 'all' | HistoryHarness | 'local';
  source?: 'all' | HistorySource;
  /** A word of the model or of the workspace, whatever the case. */
  search?: string;
}

/** The folders the external scans walk: Claude's `projects`, Codex's `sessions` and Antigravity's `conversations`, one per account. */
export interface HistoryRoots {
  claude: string[];
  codex: string[];
  agy: string[];
}

export interface HistoryPorts {
  clock: Clock;
  files: {
    /** The files under root whose name ends with suffix; none when root does not exist. */
    list(root: string, suffix: string): Promise<string[]>;
    stat(path: string): Promise<{ size: number; mtimeMs: number }>;
    /** The bytes of the file from the offset to its end. */
    read(path: string, from: number): Promise<Buffer>;
  };
  /** A SQLite file opened read-only: undefined when there is no such file, a throw when it cannot be read. */
  openReadonly(file: string): (RowSource & { close(): void }) | undefined;
}

export interface UsageRow {
  tokens: Tokens;
  costUsd: number;
  turns: number;
}

export interface UsageHistory {
  /** Epoch milliseconds of the start of the first day. */
  since: number;
  /** `providers` splits a day by who ran it (`local` for local compute and for a model priced `$0.00`), for a chart stacked by provider. */
  days: (UsageRow & { date: string; providers: Partial<Record<HistoryHarness | 'local', UsageRow>> })[];
  totals: UsageRow;
  byModel: (UsageRow & { model: string; provider: HistoryHarness | 'local'; isLocal: boolean; costStatus: 'priced' | 'unpriced' | 'local'; overridden: boolean })[];
  byWorkspace: (UsageRow & { workspace: string; source: HistorySource })[];
}

interface Turn {
  /** `harness:nativeId` of the Carrier session behind it, to tell whether an epic ran it too. */
  key?: string;
  at: number;
  source: HistorySource;
  harness: HistoryHarness;
  model: string;
  workspace: string;
  isLocal: boolean;
  tokens: Tokens;
  reportedCostUsd: number | null;
}

interface External {
  harness: HistoryHarness;
  at: number;
  sessionId: string;
  model: string;
  workspace: string;
  tokens: Tokens;
}

const GUARD_BYTES = 64;
const MAX_LINE = 32 * 1024 * 1024;
const channels = ['input', 'cachedInput', 'cacheWrite', 'output', 'reasoning'] as const;

const count = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : 0);
const text = (value: unknown) => (typeof value === 'string' ? value : undefined);
const empty = (): Tokens => ({ input: 0, cachedInput: 0, cacheWrite: 0, output: 0, reasoning: 0 });
const spent = (t: Tokens) => t.input + t.cachedInput + t.cacheWrite + t.output;
const object = (value: unknown): Record<string, unknown> => (typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {});

function mergeMax(into: Tokens, from: Tokens) {
  for (const channel of channels) into[channel] = Math.max(into[channel], from[channel]);
}

interface Cached<T> {
  size: number;
  mtimeMs: number;
  /** Where the next unread line starts. */
  offset: number;
  /** The bytes before the offset: if they changed, the file was rewritten and not appended to. */
  guard: string;
  state: T;
}

/** Reads the new complete lines of a JSONL file into its state; a file that was not just appended to is read again from its start. */
async function scanLines<T>(ports: HistoryPorts, cache: Map<string, Cached<T>>, path: string, fresh: () => T, onLine: (state: T, line: string) => void): Promise<T> {
  const stat = await ports.files.stat(path);
  const prev = cache.get(path);
  if (prev !== undefined && prev.size === stat.size && prev.mtimeMs === stat.mtimeMs) return prev.state;
  let state = fresh();
  let base = 0;
  let resumeAt = 0;
  let buffer: Buffer | undefined;
  if (prev !== undefined && stat.size > prev.size) {
    const head = Math.max(0, prev.offset - GUARD_BYTES);
    const tail = await ports.files.read(path, head);
    if (tail.subarray(0, prev.offset - head).toString('base64') === prev.guard) {
      ({ state } = prev);
      buffer = tail;
      base = head;
      resumeAt = prev.offset;
    }
  }
  buffer ??= await ports.files.read(path, 0);
  const body = buffer.subarray(resumeAt - base);
  const end = body.lastIndexOf(10) + 1; // a last line without its newline is still being written
  for (const line of body.subarray(0, end).toString('utf8').split('\n')) {
    if (line === '' || line.length > MAX_LINE) continue;
    try {
      onLine(state, line);
    } catch {
      // a line that is not JSON, or not the shape this reads, counts for nothing
    }
  }
  const offset = resumeAt + end;
  cache.set(path, { size: stat.size, mtimeMs: stat.mtimeMs, offset, guard: buffer.subarray(Math.max(0, offset - base - GUARD_BYTES), offset - base).toString('base64'), state });
  return state;
}

/** The files of the roots, read through the cache; a file that cannot be read is skipped and the cache forgets files that are gone. */
async function scanRoots<T>(ports: HistoryPorts, cache: Map<string, Cached<T>>, roots: string[], suffix: string, fresh: () => T, onLine: (state: T, line: string, path: string) => void): Promise<[string, T][]> {
  const paths = new Set((await Promise.all(roots.map((root) => ports.files.list(root, suffix).catch(() => [])))).flat());
  for (const path of cache.keys()) if (paths.has(path) === false) cache.delete(path);
  const states: [string, T][] = [];
  for (const path of paths) {
    try {
      states.push([path, await scanLines(ports, cache, path, fresh, (state, line) => onLine(state, line, path))]);
    } catch (error) {
      log.warn('a usage file could not be read', { name: error instanceof Error ? error.name : typeof error });
    }
  }
  return states;
}

function claudeLine(state: Map<string, External>, line: string, path: string) {
  const event = object(JSON.parse(line));
  const message = object(event.message);
  const usage = object(message.usage);
  const id = text(message.id);
  const model = text(message.model);
  const at = Date.parse(text(event.timestamp) ?? '');
  if (event.type !== 'assistant' || id === undefined || model === undefined || model === '<synthetic>' || Number.isNaN(at)) return;
  const tokens: Tokens = { input: count(usage.input_tokens), cachedInput: count(usage.cache_read_input_tokens), cacheWrite: count(usage.cache_creation_input_tokens), output: count(usage.output_tokens), reasoning: 0 };
  const key = `${id}:${text(event.requestId) ?? ''}`;
  const seen = state.get(key);
  // A streamed message is written again as it grows: the last write has the real counts, so each channel keeps its largest.
  if (seen === undefined) state.set(key, { harness: 'claude', at, sessionId: text(event.sessionId) ?? basename(path, '.jsonl'), model, workspace: text(event.cwd) ?? '', tokens });
  else mergeMax(seen.tokens, tokens);
}

interface CodexState {
  sessionId: string;
  model: string;
  workspace: string;
  lastTotal?: string;
  records: External[];
}

function codexLine(state: CodexState, line: string) {
  const event = object(JSON.parse(line));
  const payload = object(event.payload);
  if (event.type === 'session_meta') {
    state.sessionId = text(payload.id) ?? state.sessionId;
    state.workspace = text(payload.cwd) ?? state.workspace;
  } else if (event.type === 'turn_context') {
    state.model = text(payload.model) ?? state.model;
    state.workspace = text(payload.cwd) ?? state.workspace;
  } else if (event.type === 'event_msg' && payload.type === 'token_count') {
    const info = object(payload.info);
    const total = JSON.stringify(info.total_token_usage);
    const last = object(info.last_token_usage);
    const at = Date.parse(text(event.timestamp) ?? '');
    // Codex writes the same snapshot again and again: only a changed running total is a new step.
    if (total === state.lastTotal || Number.isNaN(at)) return;
    state.lastTotal = total;
    const cached = count(last.cached_input_tokens);
    const tokens: Tokens = { input: Math.max(0, count(last.input_tokens) - cached), cachedInput: cached, cacheWrite: 0, output: count(last.output_tokens), reasoning: count(last.reasoning_output_tokens) };
    if (spent(tokens) > 0) state.records.push({ harness: 'codex', at, sessionId: state.sessionId, model: state.model, workspace: state.workspace, tokens });
  }
}

function agyFingerprint(ports: HistoryPorts, path: string) {
  const part = (p: string) => ports.files.stat(p).then((s) => `${s.size}:${s.mtimeMs}`, () => '-');
  return Promise.all([part(path), part(`${path}-wal`)]).then((parts) => parts.join('/'));
}

const dayKey = (ms: number) => {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

/** What a chat turn used, in the channels of the harness that wrote it. Claude's input excludes the cached tokens, Codex's includes them. */
function chatTokens(harness: 'claude' | 'codex', usage: Record<string, number>): Tokens {
  if (harness === 'claude') return { input: count(usage.input_tokens), cachedInput: count(usage.cache_read_input_tokens), cacheWrite: count(usage.cache_creation_input_tokens), output: count(usage.output_tokens), reasoning: 0 };
  const cached = count(usage.cachedInputTokens);
  return { input: Math.max(0, count(usage.inputTokens) - cached), cachedInput: cached, cacheWrite: 0, output: count(usage.outputTokens), reasoning: count(usage.reasoningOutputTokens) };
}

const modelTokens = (u: ModelUsage): Tokens => ({ input: count(u.inputTokens), cachedInput: count(u.cachedInputTokens), cacheWrite: count(u.cacheWriteTokens), output: count(u.outputTokens), reasoning: count(u.reasoningTokens) });

/**
 * The history of what was used: Carrier's epics (read-only from the engine's database, which may not exist yet), Carrier's chats and
 * the sessions the agent CLIs wrote on their own. A session in more than one source counts once, in the first of epic, chat,
 * external. The external scans are kept between calls and read only what was added.
 */
export function createHistory(ports: HistoryPorts, deps: { chat: ChatDb; engineDbFile: string }) {
  const claudeCache = new Map<string, Cached<Map<string, External>>>();
  const codexCache = new Map<string, Cached<CodexState>>();
  const agyCache = new Map<string, { fingerprint: string; records: AgyRecord[] }>();
  const overrides = createPriceOverrides(deps.chat, () => ports.clock.now());

  function epicTurns(): { turns: Turn[]; keys: Set<string> } {
    const result = { turns: [] as Turn[], keys: new Set<string>() };
    let db: ReturnType<HistoryPorts['openReadonly']>;
    try {
      db = ports.openReadonly(deps.engineDbFile);
    } catch (error) {
      log.warn('the engine database could not be opened', { name: error instanceof Error ? error.name : typeof error });
      return result;
    }
    if (db === undefined) return result;
    try {
      for (const row of db.rows('select x.sessionId, x.harness, x.model, x.provider, x.usage, x.startedAt, x.finishedAt, e.repo from executions x join epics e on e.id = x.epicId')) {
        const harness = row.harness;
        if (harness !== 'claude' && harness !== 'codex' && harness !== 'agy') continue;
        const sessionId = text(row.sessionId);
        if (sessionId !== undefined) result.keys.add(`${harness}:${sessionId}`);
        if (typeof row.usage !== 'string') continue;
        const usage = JSON.parse(row.usage) as ExecutionUsage;
        const parts: [string, ModelUsage][] = Object.entries(usage.byModel ?? { [text(row.model) ?? 'unknown']: usage });
        for (const [model, part] of parts) {
          const tokens = modelTokens(part);
          const cost = part.costUsd;
          if (spent(tokens) > 0) result.turns.push({ at: Number(row.finishedAt ?? row.startedAt), source: 'epic', harness, model, workspace: text(row.repo) ?? '', isLocal: row.provider === 'lmstudio' || row.provider === 'ollama', tokens, reportedCostUsd: typeof cost === 'number' ? cost : null });
        }
      }
    } catch (error) {
      log.warn('the engine database could not be read', { name: error instanceof Error ? error.name : typeof error });
    } finally {
      db.close();
    }
    return result;
  }

  function chatSide(since: number, accounts: Providers): { turns: Turn[]; keys: Set<string> } {
    const keys = new Set(deps.chat.select({ nativeId: sessions.nativeId, harness: sessions.harness }).from(sessions).where(isNotNull(sessions.nativeId)).all().map((s) => `${s.harness}:${s.nativeId}`));
    const rows = deps.chat
      .select({ nativeId: sessions.nativeId, harness: sessions.harness, agent: sessions.agent, folder: sessions.folder, at: chatTurns.startedAt, model: chatTurns.model, usage: chatTurns.usage })
      .from(chatTurns)
      .innerJoin(sessions, eq(chatTurns.sessionId, sessions.id))
      .where(gte(chatTurns.startedAt, since))
      .all();
    // ponytail: a Claude result's total_cost_usd may run across the whole session, so a chat turn is priced from the table and not from it.
    const turns = rows.map((r): Turn => ({ key: r.nativeId === null ? undefined : `${r.harness}:${r.nativeId}`, at: r.at, source: 'chat', harness: r.harness, model: r.model ?? 'unknown', workspace: r.folder, isLocal: accounts[r.agent]?.provider !== undefined, tokens: chatTokens(r.harness, r.usage ?? {}), reportedCostUsd: null }));
    return { turns: turns.filter((t) => spent(t.tokens) > 0), keys };
  }

  return async function history(filter: HistoryFilter, { accounts, roots }: { accounts: Providers; roots: HistoryRoots }): Promise<UsageHistory> {
    const now = ports.clock.now();
    const first = new Date(now);
    first.setHours(0, 0, 0, 0);
    first.setDate(first.getDate() - (filter.days - 1));
    const since = first.getTime();

    const epic = epicTurns();
    const chat = chatSide(since, accounts);
    const turns: Turn[] = [...epic.turns];
    for (const t of chat.turns) if (t.key === undefined || epic.keys.has(t.key) === false) turns.push(t);
    const taken = new Set([...epic.keys, ...chat.keys]);

    const merged = new Map<string, External>();
    for (const [, records] of await scanRoots(ports, claudeCache, roots.claude, '.jsonl', () => new Map<string, External>(), claudeLine)) {
      for (const [key, record] of records) {
        const seen = merged.get(key);
        if (seen === undefined) merged.set(key, { ...record, tokens: { ...record.tokens } });
        else mergeMax(seen.tokens, record.tokens); // a forked or resumed file writes the same message again
      }
    }
    const codex = await scanRoots(ports, codexCache, roots.codex, '.jsonl', (): CodexState => ({ sessionId: '', model: 'unknown', workspace: '', records: [] }), codexLine);
    const external = [...merged.values(), ...codex.flatMap(([path, state]) => state.records.map((r) => ({ ...r, sessionId: r.sessionId || basename(path, '.jsonl') }))), ...(await scanAgy(roots.agy))];
    for (const r of external) {
      if (taken.has(`${r.harness}:${r.sessionId}`) === false) turns.push({ at: r.at, source: 'external', harness: r.harness, model: r.model, workspace: r.workspace, isLocal: false, tokens: r.tokens, reportedCostUsd: null });
    }

    return rollup(turns, filter, since, overrides.list());
  };

  async function scanAgy(dirs: string[]): Promise<External[]> {
    const paths = new Set((await Promise.all(dirs.map((dir) => ports.files.list(dir, '.db').catch(() => [])))).flat());
    for (const path of agyCache.keys()) if (paths.has(path) === false) agyCache.delete(path);
    const found: External[] = [];
    for (const path of paths) {
      try {
        const fingerprint = await agyFingerprint(ports, path);
        let cached = agyCache.get(path);
        if (cached?.fingerprint !== fingerprint) {
          const db = ports.openReadonly(path);
          if (db === undefined) continue;
          try {
            cached = { fingerprint, records: readAgyRecords(db, (await ports.files.stat(path)).mtimeMs) };
          } finally {
            db.close();
          }
          agyCache.set(path, cached);
        }
        found.push(...cached.records.map((r) => ({ ...r, harness: 'agy' as const, sessionId: basename(path, '.db'), workspace: '' })));
      } catch (error) {
        agyCache.delete(path);
        log.warn('an Antigravity database could not be read', { name: error instanceof Error ? error.name : typeof error });
      }
    }
    return found;
  }
}

function rollup(turns: Turn[], filter: HistoryFilter, since: number, overrides: ReadonlyMap<string, PriceOverride>): UsageHistory {
  const row = (): UsageRow => ({ tokens: empty(), costUsd: 0, turns: 0 });
  const add = (into: UsageRow, tokens: Tokens, costUsd: number) => {
    for (const channel of channels) into.tokens[channel] += tokens[channel];
    into.costUsd += costUsd;
    into.turns++;
  };
  const days = new Map<string, UsageHistory['days'][number]>();
  const cursor = new Date(since);
  for (let i = 0; i < filter.days; i++, cursor.setDate(cursor.getDate() + 1)) days.set(dayKey(cursor.getTime()), { date: dayKey(cursor.getTime()), ...row(), providers: {} });
  const totals = row();
  const models = new Map<string, UsageHistory['byModel'][number] & { unpriced: boolean }>();
  const workspaces = new Map<string, UsageHistory['byWorkspace'][number]>();
  const search = filter.search?.trim().toLowerCase() ?? '';

  for (const turn of turns) {
    const day = days.get(dayKey(turn.at));
    if (day === undefined) continue;
    const priced = turn.isLocal ? ({ costUsd: 0, status: 'local' } as const) : priceOf(turn.model, turn.tokens, overrides, turn.reportedCostUsd);
    const provider = priced.status === 'local' ? 'local' : turn.harness;
    if (filter.source !== undefined && filter.source !== 'all' && filter.source !== turn.source) continue;
    if (filter.provider !== undefined && filter.provider !== 'all' && filter.provider !== provider) continue;
    if (search !== '' && `${turn.model}\n${turn.workspace}`.toLowerCase().includes(search) === false) continue;
    add(day, turn.tokens, priced.costUsd);
    add((day.providers[provider] ??= row()), turn.tokens, priced.costUsd);
    add(totals, turn.tokens, priced.costUsd);
    const modelKey = `${turn.model}\0${provider}`;
    let model = models.get(modelKey);
    if (model === undefined) models.set(modelKey, (model = { ...row(), model: turn.model, provider, isLocal: provider === 'local', costStatus: 'local', overridden: false, unpriced: false }));
    add(model, turn.tokens, priced.costUsd);
    model.unpriced ||= priced.status === 'unpriced';
    model.overridden ||= overrides.has(normalizeModel(turn.model));
    model.costStatus = model.unpriced ? 'unpriced' : provider === 'local' ? 'local' : 'priced';
    const workspaceKey = `${turn.workspace}\0${turn.source}`;
    let workspace = workspaces.get(workspaceKey);
    if (workspace === undefined) workspaces.set(workspaceKey, (workspace = { ...row(), workspace: turn.workspace, source: turn.source }));
    add(workspace, turn.tokens, priced.costUsd);
  }

  const heaviest = <R extends UsageRow>(a: R, b: R) => b.costUsd - a.costUsd || spent(b.tokens) - spent(a.tokens);
  return {
    since,
    days: [...days.values()],
    totals,
    byModel: [...models.values()].map(({ unpriced: _, ...m }) => m).sort(heaviest),
    byWorkspace: [...workspaces.values()].sort(heaviest),
  };
}
