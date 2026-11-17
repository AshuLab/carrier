// Throwaway: a tiny Codex app-server client for the spike (part B). Reads nothing of ~/.codex; logs go to ./logs with the bearer token redacted.
import { spawn } from 'node:child_process';
import { appendFileSync, mkdtempSync, realpathSync, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline';
import { join } from 'node:path';

export const here = new URL('.', import.meta.url).pathname;
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// One counter file shared by every script, so the 40-turn budget holds across runs.
const TURNS_FILE = join(here, 'logs', 'turns-used.txt');
import { existsSync, readFileSync } from 'node:fs';
export const turnsUsed = () => (existsSync(TURNS_FILE) ? Number(readFileSync(TURNS_FILE, 'utf8')) : 0);
const BUDGET = 40;

export const tmp = (prefix: string) => realpathSync(mkdtempSync(join('/tmp', prefix)));

export type Handler = (method: string, params: any) => unknown | Promise<unknown>; // returns the JSON-RPC result, or throws

export class App {
  pid!: number;
  private next = 1;
  private waiting = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
  notes: { method: string; params: any }[] = [];
  requests: { method: string; params: any; answered?: unknown }[] = [];
  handler: Handler = () => { throw new Error('no handler'); };
  private child;
  private logFile: string;
  secrets: string[] = [];
  private ended = false;
  stderrTail = '';
  /** A scripted fake model answers (mock.ts): no quota is spent, so the turn is not counted. */
  mocked = false;

  constructor(logName: string, cwd: string, args: string[] = []) {
    this.logFile = join(here, 'logs', `${logName}.jsonl`);
    writeFileSync(this.logFile, '');
    this.child = spawn('codex', ['app-server', ...args], { cwd, env: process.env, stdio: ['pipe', 'pipe', 'pipe'], detached: true });
    this.pid = this.child.pid!;
    this.child.stdin.on('error', () => {});
    this.child.stderr.on('data', (d: Buffer) => { this.stderrTail = (this.stderrTail + d.toString()).slice(-400); }); // kept only in memory, never printed
    this.child.once('close', () => (this.ended = true));
    createInterface({ input: this.child.stdout }).on('line', (line) => void this.receive(line));
  }

  log(kind: string, data: unknown) {
    let text = JSON.stringify({ t: Date.now(), kind, data });
    for (const s of this.secrets) text = text.split(s).join('<TOKEN>');
    appendFileSync(this.logFile, text + '\n');
  }

  private write(obj: unknown) {
    this.log('->', obj);
    this.child.stdin.write(JSON.stringify(obj) + '\n');
  }

  request(method: string, params: unknown, timeoutMs = 60_000) {
    const id = this.next++;
    return new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => { this.waiting.delete(id); reject(new Error(`timeout ${method}`)); }, timeoutMs);
      this.waiting.set(id, { resolve: (v) => { clearTimeout(timer); resolve(v); }, reject: (e) => { clearTimeout(timer); reject(e); } });
      this.write({ id, method, params });
    });
  }

  notify(method: string) { this.write({ method }); }

  private async receive(line: string) {
    let m: any;
    try { m = JSON.parse(line); } catch { return; }
    this.log('<-', m);
    if (typeof m.method === 'string' && m.id !== undefined) {
      const rec: (typeof this.requests)[number] = { method: m.method, params: m.params };
      this.requests.push(rec);
      try {
        const result = await this.handler(m.method, m.params);
        rec.answered = result;
        this.write({ id: m.id, result });
      } catch (e) {
        rec.answered = { error: String((e as Error).message) };
        this.write({ id: m.id, error: { code: -32601, message: String((e as Error).message) } });
      }
    } else if (typeof m.method === 'string') this.notes.push({ method: m.method, params: m.params });
    else if (m.id !== undefined) {
      const w = this.waiting.get(m.id);
      this.waiting.delete(m.id);
      if (m.error) w?.reject(new Error(`${m.error.code}: ${m.error.message}`));
      else w?.resolve(m.result);
    }
  }

  async init() {
    const hello = await this.request('initialize', { clientInfo: { name: 'carrier-spike', title: 'spike', version: '0.0.0' }, capabilities: { experimentalApi: true } });
    this.notify('initialized');
    return hello;
  }

  /** One real turn; counts against the budget. Resolves with the turn/completed params. */
  async turn(threadId: string, text: string, extra: Record<string, unknown> = {}, timeoutMs = 120_000) {
    const used = turnsUsed();
    if (!this.mocked) {
      if (used >= BUDGET) throw new Error('turn budget exhausted');
      writeFileSync(TURNS_FILE, String(used + 1));
    }
    const from = this.notes.length;
    await this.request('turn/start', { threadId, input: [{ type: 'text', text, text_elements: [] }], ...extra });
    const t0 = Date.now();
    while (Date.now() - t0 < timeoutMs) {
      const done = this.notes.slice(from).find((n) => n.method === 'turn/completed' && n.params?.threadId === threadId);
      if (done) return { completed: done.params, notes: this.notes.slice(from) };
      await sleep(100);
    }
    throw new Error('turn did not complete in time');
  }

  /** Ends the app-server: only the PID this script started, by its own process group. */
  async close() {
    if (this.ended) return;
    try { process.kill(-this.pid, 'SIGTERM'); } catch {}
    for (let i = 0; i < 30 && !this.ended; i++) await sleep(100);
    if (!this.ended) { try { process.kill(-this.pid, 'SIGKILL'); } catch {} }
  }
}

/** Items of a turn's notifications, shortened. Command outputs are cut to 160 chars. */
export function itemsOf(notes: { method: string; params: any }[]) {
  return notes.filter((n) => n.method === 'item/completed').map((n) => n.params.item).filter((i: any) => ['commandExecution', 'mcpToolCall', 'fileChange', 'agentMessage'].includes(i.type)).map((i: any) => {
    if (i.type === 'commandExecution') return { type: i.type, command: i.command, status: i.status, exitCode: i.exitCode, out: String(i.aggregatedOutput ?? '').slice(0, 160) };
    if (i.type === 'mcpToolCall') return { type: i.type, server: i.server, tool: i.tool, status: i.status, args: i.arguments, result: JSON.stringify(i.result ?? null).slice(0, 160), error: i.error ?? null };
    if (i.type === 'fileChange') return { type: i.type, status: i.status, changes: (i.changes ?? []).map((c: any) => c.path) };
    return { type: i.type, text: String(i.text ?? '').slice(0, 200) };
  });
}
