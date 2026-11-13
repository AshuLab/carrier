import { chatSocketOf } from '../../../chat/config.ts';
import { CliError } from '../cli-error.ts';
import { startDetached } from '../detached.ts';
import { hostClient } from './chat.ts';

const DAYS = ['7', '14', '30'];
const PROVIDERS = ['all', 'claude', 'codex', 'agy', 'local'];
const SOURCES = ['all', 'epic', 'chat', 'external'];
const ROWS = 10;
/** The host answers once every account's probe (up to 15 s each, in parallel) and the first read of the logs are done; the app waits as long. */
export const USAGE_TIMEOUT_MS = 45_000;

type Tokens = { input: number; cachedInput: number; cacheWrite: number; output: number };
type Row = { tokens: Tokens; costUsd: number; turns: number };
type Reply = {
  quotas: { account: string; displayName?: string; provider: string; status: string; stale?: true; message?: string; windows: { label: string; group?: string; usedPercent: number; resetsAt?: number; resetLabel?: string }[]; extraUsage?: { isEnabled: boolean; usedCreditsUsd?: number; monthlyLimitUsd?: number }; credits?: { balance: string | null }; aiCreditsNotice?: string; servers?: { kind: string; running: boolean; models: string[] }[] }[];
  summary: Row;
  byModel: (Row & { model: string; provider: string; costStatus: string })[];
  byWorkspace: (Row & { workspace: string; source: string })[];
};

const oneOf = (flag: string, value: string | undefined, allowed: string[]) => {
  if (value !== undefined && allowed.includes(value) === false) throw new CliError(2, `--${flag} is one of ${allowed.join(', ')} (got "${value}")`);
  return value;
};

const count = (n: number) => (n >= 1e9 ? `${(n / 1e9).toFixed(1)}B` : n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1e3 ? `${(n / 1e3).toFixed(1)}k` : String(n));
const cache = (t: Tokens) => count(t.cachedInput + t.cacheWrite);
const cost = (row: Row, status?: string) => (status === 'unpriced' ? 'unpriced' : status === 'local' ? '$0.00 local' : `$${row.costUsd.toFixed(2)}`);

/** In the largest two units: "in 3h 5m", "in 2d 4h". */
function until(ms: number) {
  const minutes = Math.max(0, Math.round(ms / 60_000));
  if (minutes < 60) return `in ${minutes}m`;
  if (minutes < 24 * 60) return `in ${Math.floor(minutes / 60)}h ${minutes % 60}m`;
  return `in ${Math.floor(minutes / (24 * 60))}d ${Math.floor((minutes % (24 * 60)) / 60)}h`;
}

function table(header: string[], rows: string[][]) {
  const widths = header.map((h, i) => Math.max(h.length, ...rows.map((r) => r[i]!.length)));
  const line = (cells: string[]) => `${cells.map((c, i) => c.padEnd(widths[i]!)).join('  ').trimEnd()}\n`;
  return line(header) + rows.map(line).join('');
}

function render(reply: Reply, days: string, now: number) {
  const rows: string[][] = [];
  for (const q of reply.quotas) {
    const name = q.displayName ?? q.account;
    for (const w of q.windows) rows.push([name, w.group ? `${w.group} ${w.label}` : w.label, `${Math.round(w.usedPercent)}%`, w.resetsAt !== undefined ? until(w.resetsAt - now) : (w.resetLabel ?? '')]);
    for (const s of q.servers ?? []) rows.push([name, s.kind, s.running ? 'running' : 'offline', s.models.join(', ')]);
    const { extraUsage: extra, credits } = q;
    if (extra?.isEnabled) rows.push([name, 'extra credits', `$${(extra.usedCreditsUsd ?? 0).toFixed(2)}`, extra.monthlyLimitUsd !== undefined ? `of $${extra.monthlyLimitUsd.toFixed(2)}` : '']);
    if (credits?.balance != null) rows.push([name, 'credits', credits.balance, '']);
    if (q.aiCreditsNotice) rows.push([name, 'AI credits', 'n/a', q.aiCreditsNotice]);
    if (q.status !== 'ok') rows.push([name, q.provider, `${q.status}${q.stale ? ' (last known)' : ''}`, q.message ?? '']);
  }
  const { summary: s } = reply;
  let out = `Live quotas\n${rows.length > 0 ? table(['ACCOUNT', 'WINDOW', 'USED', 'RESETS'], rows) : 'No account to ask.\n'}\n`;
  out += `Last ${days} days (estimated API cost, not what a plan charges)\n${table(['TURNS', 'IN', 'CACHE', 'OUT', 'COST'], [[String(s.turns), count(s.tokens.input), cache(s.tokens), count(s.tokens.output), cost(s)]])}`;
  if (reply.byModel.length > 0) out += `\nBy model\n${table(['MODEL', 'PROVIDER', 'IN', 'CACHE', 'OUT', 'COST'], reply.byModel.slice(0, ROWS).map((m) => [m.model, m.provider, count(m.tokens.input), cache(m.tokens), count(m.tokens.output), cost(m, m.costStatus)]))}`;
  if (reply.byWorkspace.length > 0) out += `\nBy workspace\n${table(['WORKSPACE', 'SOURCE', 'IN', 'CACHE', 'OUT', 'COST'], reply.byWorkspace.slice(0, ROWS).map((w) => [w.workspace || '(unknown)', w.source, count(w.tokens.input), cache(w.tokens), count(w.tokens.output), cost(w)]))}`;
  return out;
}

/**
 * `carrier usage [--json] [--refresh] [--days 7|14|30] [--provider <name>] [--source <name>]`: the live quotas and the history from the chat host,
 * started on demand (`start` is replaceable in tests). The flags are checked before anything is started. Returns the exit code.
 */
export async function usageCommand(
  flags: { json?: boolean; refresh?: boolean; days?: string; provider?: string; source?: string },
  { start = startDetached, now = Date.now }: { start?: typeof startDetached; now?: () => number } = {},
): Promise<number> {
  const days = oneOf('days', flags.days, DAYS) ?? '30';
  const provider = oneOf('provider', flags.provider, PROVIDERS);
  const source = oneOf('source', flags.source, SOURCES);
  const client = await hostClient(chatSocketOf(), start, USAGE_TIMEOUT_MS);
  // an older host would only answer "invalid request"
  if (client.hello.capabilities.includes('usage') === false) {
    client.close();
    throw new CliError(1, 'The chat host that is running is older than this command and does not have usage. Stop it with `carrier chat --stop` (when no session is working); the next `carrier usage` starts a new one.');
  }
  let reply: Reply;
  try {
    reply = (await client.request('usage', { days: Number(days), ...(flags.refresh && { refresh: true }), ...(provider !== undefined && { provider }), ...(source !== undefined && { source }) })) as Reply;
  } catch (error) {
    throw new CliError(1, error instanceof Error ? error.message : String(error));
  } finally {
    client.close();
  }
  process.stdout.write(flags.json ? `${JSON.stringify(reply, null, 2)}\n` : render(reply, days, now()));
  return 0;
}
