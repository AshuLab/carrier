import { homedir } from 'node:os';
import { join } from 'node:path';
import { z } from 'zod';
import { localKinds } from '../harnesses/local.ts';
import { ProbeError, type ExtraUsage, type QuotaSnapshot, type QuotaTarget, type QuotaWindow, type UsagePorts } from './types.ts';

// What each probe asks the provider. The probes only read: a Claude token is never refreshed here, because a refresh rotates the
// refresh token and could log the person out of Claude Code. Nothing a provider says is copied into an error: a message is ours, never theirs.

const PROBE_LIMIT_MS = 15_000;
const CLAUDE_USAGE_URL = 'https://api.anthropic.com/api/oauth/usage';

/** What a probe found; `status` is `ok` unless it says otherwise. */
type Probe = (ports: UsagePorts, target: QuotaTarget) => Promise<Omit<QuotaSnapshot, 'provider' | 'status' | 'checkedAt'> & { status?: QuotaSnapshot['status'] }>;

const clamp = (percent: number) => Math.min(100, Math.max(0, percent));
const timeMs = (iso: string | null | undefined) => {
  const at = iso == null ? Number.NaN : Date.parse(iso);
  return Number.isNaN(at) ? undefined : at;
};

/** The status an HTTP answer other than 200 means. */
function httpFailure(status: number): ProbeError {
  if (status === 401 || status === 403) return new ProbeError('signed_out', 'the login was refused');
  if (status === 429) return new ProbeError('rate_limited', 'the provider is rate limiting this check');
  if (status >= 500) return new ProbeError('unavailable', `the provider answered HTTP ${status}`);
  return new ProbeError('error', `the provider answered HTTP ${status}`);
}

async function call(ports: UsagePorts, request: Parameters<UsagePorts['http']>[0]) {
  try {
    return await ports.http(request);
  } catch (error) {
    const timedOut = (error as NodeJS.ErrnoException).code === 'ETIMEDOUT' || (error as Error).name === 'TimeoutError';
    throw timedOut ? new ProbeError('error', 'the check timed out') : new ProbeError('unavailable', 'the provider could not be reached');
  }
}

// ---- Claude

const claudeCredentials = z.looseObject({
  claudeAiOauth: z.looseObject({ accessToken: z.string().min(1), expiresAt: z.number().optional(), subscriptionType: z.string().nullish() }),
});
const claudeWindow = z.object({ utilization: z.number(), resets_at: z.string().nullish() });
const claudeExtra = z.object({
  is_enabled: z.boolean(),
  monthly_limit: z.number().nullish(),
  used_credits: z.number().nullish(),
  utilization: z.number().nullish(),
  currency: z.string().nullish(),
  decimal_places: z.int().min(0).max(6).optional(),
});

const claudeWindowOf = (id: string, label: string, raw: unknown): QuotaWindow[] => {
  const parsed = claudeWindow.safeParse(raw);
  if (parsed.success === false) return [];
  const resetsAt = timeMs(parsed.data.resets_at);
  return [{ id, label, usedPercent: clamp(parsed.data.utilization), ...(resetsAt !== undefined && { resetsAt }) }];
};

/** The access token in the account's credentials file; an expired one means signed out (Claude Code itself renews it). */
async function claudeToken(ports: UsagePorts, path: string) {
  let text: string;
  try {
    text = await ports.files.read(path);
  } catch {
    throw new ProbeError('missing', 'no Claude credentials file for this account');
  }
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new ProbeError('signed_out', 'the Claude credentials file cannot be read');
  }
  const parsed = claudeCredentials.safeParse(json);
  if (parsed.success === false) throw new ProbeError('signed_out', 'the Claude credentials hold no login');
  const { claudeAiOauth: oauth } = parsed.data;
  if (oauth.expiresAt !== undefined && oauth.expiresAt <= ports.clock.now()) throw new ProbeError('signed_out', 'the Claude login expired');
  return { accessToken: oauth.accessToken, plan: oauth.subscriptionType ?? undefined };
}

const claude: Probe = async (ports, { configDir = join(homedir(), '.claude') }) => {
  const { accessToken, plan } = await claudeToken(ports, join(configDir, '.credentials.json'));
  const answer = await call(ports, { url: CLAUDE_USAGE_URL, headers: { authorization: `Bearer ${accessToken}`, 'anthropic-beta': 'oauth-2025-04-20', accept: 'application/json' }, timeoutMs: PROBE_LIMIT_MS });
  if (answer.status !== 200) throw httpFailure(answer.status);
  const body = z.looseObject({}).safeParse(answer.json);
  if (body.success === false) throw new ProbeError('error', 'the Claude usage answer was not understood');
  const data = body.data as Record<string, unknown>;

  const windows = [...claudeWindowOf('5h', '5h', data.five_hour), ...claudeWindowOf('7d', '7d', data.seven_day)];
  // Windows scoped to a model: `seven_day_opus` style keys, or a `model_scoped` list.
  for (const [key, value] of Object.entries(data)) {
    const model = /^seven_day_(.+)$/.exec(key)?.[1];
    if (model !== undefined) windows.push(...claudeWindowOf(`7d:${model}`, `7d ${model}`, value));
  }
  const scoped = z.array(z.looseObject({ display_name: z.string() })).safeParse(data.model_scoped);
  if (scoped.success) scoped.data.forEach((entry) => windows.push(...claudeWindowOf(`7d:${entry.display_name}`, `7d ${entry.display_name}`, entry)));

  let extraUsage: ExtraUsage | undefined;
  const extra = claudeExtra.safeParse(data.extra_usage);
  if (extra.success) {
    const usd = (minor: number | null | undefined) => (minor == null ? undefined : minor / 10 ** (extra.data.decimal_places ?? 2));
    const [monthlyLimitUsd, usedCreditsUsd] = [usd(extra.data.monthly_limit), usd(extra.data.used_credits)];
    extraUsage = {
      isEnabled: extra.data.is_enabled,
      ...(monthlyLimitUsd !== undefined && { monthlyLimitUsd }),
      ...(usedCreditsUsd !== undefined && { usedCreditsUsd }),
      ...(extra.data.utilization != null && { utilization: clamp(extra.data.utilization) }),
      ...(extra.data.currency != null && { currency: extra.data.currency }),
    };
  }
  return { windows, ...(plan !== undefined && { planType: plan }), ...(extraUsage !== undefined && { extraUsage }) };
};

// ---- Codex

const codexWindow = z.object({ usedPercent: z.number(), windowDurationMins: z.number().nullish(), resetsAt: z.number().nullish() });
const codexLimit = z.looseObject({
  limitName: z.string().nullish(),
  primary: codexWindow.nullish(),
  secondary: codexWindow.nullish(),
  credits: z.object({ hasCredits: z.boolean(), unlimited: z.boolean(), balance: z.string().nullable() }).nullish(),
  planType: z.string().nullish(),
});
const codexResult = z.looseObject({
  rateLimits: codexLimit,
  rateLimitsByLimitId: z.record(z.string(), codexLimit).nullish(),
  credits: codexLimit.shape.credits,
  planType: z.string().nullish(),
  rateLimitResetCredits: z.unknown().optional(),
});

const durationLabel = (mins: number | null | undefined) => {
  if (mins == null) return undefined;
  if (mins === 300) return '5h';
  if (mins === 10_080) return '7d';
  return mins % 1440 === 0 ? `${mins / 1440}d` : mins % 60 === 0 ? `${mins / 60}h` : `${mins}m`;
};

function codexWindows(limit: z.infer<typeof codexLimit>, id: string, group?: string): QuotaWindow[] {
  return (['primary', 'secondary'] as const).flatMap((slot) => {
    const w = limit[slot];
    if (w == null) return [];
    const duration = durationLabel(w.windowDurationMins) ?? slot;
    return [{ id: `${id}:${slot}`, label: group === undefined ? duration : `${limit.limitName ?? group} ${duration}`, ...(group !== undefined && { group }), usedPercent: clamp(w.usedPercent), ...(w.resetsAt != null && { resetsAt: w.resetsAt * 1000 }) }];
  });
}

/** The status a JSON-RPC error means, from its words; the words themselves are not kept. */
function rpcFailure(error: unknown): ProbeError {
  const message = String((error as { message?: unknown } | null)?.message ?? '');
  if (/auth|log ?in|sign ?in/i.test(message)) return new ProbeError('signed_out', 'Codex is not signed in');
  if (/\b429\b|too many requests/i.test(message)) return new ProbeError('rate_limited', 'Codex is rate limiting this check');
  return new ProbeError('error', 'Codex refused the request');
}

/** `initialize`, then `account/rateLimits/read`, on a child that is always ended: on the answer, on an error, on exit, and at the limit. */
function readCodexLimits(ports: UsagePorts, command: string, env: NodeJS.ProcessEnv): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const child = ports.spawnRpc(command, ['app-server'], env);
    let cancel = () => {};
    const finish = (settle: () => void) => {
      cancel();
      child.kill();
      settle();
    };
    cancel = ports.clock.after(PROBE_LIMIT_MS, async () => finish(() => reject(new ProbeError('error', 'the check timed out'))));
    child.onExit((error) => finish(() => reject(error?.code === 'ENOENT' ? new ProbeError('missing', 'the codex binary was not found') : new ProbeError('unavailable', 'codex app-server ended before it answered'))));
    child.onLine((line) => {
      let message: { id?: unknown; result?: unknown; error?: unknown };
      try {
        message = JSON.parse(line);
      } catch {
        return;
      }
      if (typeof message.id !== 'number') return; // notifications
      if (message.error !== undefined) return finish(() => reject(rpcFailure(message.error)));
      if (message.id === 1) {
        child.send(JSON.stringify({ method: 'initialized' }));
        child.send(JSON.stringify({ id: 2, method: 'account/rateLimits/read' }));
      } else if (message.id === 2) finish(() => resolve(message.result));
    });
    child.send(JSON.stringify({ id: 1, method: 'initialize', params: { clientInfo: { name: 'carrier', title: 'Carrier', version: '0.0.0' } } }));
  });
}

const codex: Probe = async (ports, { configDir, command = 'codex' }) => {
  const result = codexResult.safeParse(await readCodexLimits(ports, command, { ...process.env, ...(configDir !== undefined && { CODEX_HOME: configDir }) }));
  if (result.success === false) throw new ProbeError('error', 'the Codex rate limits were not understood');
  const { rateLimits, rateLimitsByLimitId = {}, rateLimitResetCredits } = result.data;
  // The main windows are the `codex` limit; a model-specific limit adds windows of its own and never replaces them.
  const main = rateLimitsByLimitId?.codex ?? rateLimits;
  const windows = codexWindows(main, 'codex');
  for (const [id, limit] of Object.entries(rateLimitsByLimitId ?? {})) if (id !== 'codex') windows.push(...codexWindows(limit, id, id));
  const planType = result.data.planType ?? rateLimits.planType ?? undefined;
  const credits = result.data.credits ?? rateLimits.credits ?? undefined;
  return { windows, ...(planType !== undefined && { planType }), ...(credits != null && { credits }), ...(rateLimitResetCredits !== undefined && { rateLimitResetCredits }) };
};

// ---- Antigravity

const agyOutput = z.looseObject({
  status: z.string().optional(),
  response: z.string().optional(),
  command: z.object({
    data: z.object({
      groups: z.array(z.object({ name: z.string(), buckets: z.array(z.object({ id: z.string(), name: z.string(), description: z.string().optional(), remaining_fraction: z.number(), reset_time: z.string().nullish() })) })),
    }),
  }).optional(),
});

const agy: Probe = async (ports, { command = 'agy' }) => {
  let out: { code: number; stdout: string };
  try {
    out = await ports.run(command, ['-p', '/usage', '--output-format', 'json'], { env: { ...process.env, BROWSER: 'true' }, timeoutMs: PROBE_LIMIT_MS });
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') throw new ProbeError('missing', 'the agy binary was not found');
    throw new ProbeError('error', code === 'ETIMEDOUT' ? 'the check timed out' : 'agy could not be run');
  }
  let json: unknown;
  try {
    json = JSON.parse(out.stdout);
  } catch {
    throw new ProbeError(out.code === 0 ? 'error' : 'unavailable', 'agy did not answer with JSON');
  }
  const parsed = agyOutput.safeParse(json);
  const groups = parsed.success ? parsed.data.command?.data.groups : undefined;
  if (groups === undefined) throw /sign|log ?in|auth/i.test(parsed.success ? (parsed.data.response ?? '') : '') ? new ProbeError('signed_out', 'Antigravity is not signed in') : new ProbeError('error', 'the agy usage answer was not understood');
  const windows = groups.flatMap((group) =>
    group.buckets.map((bucket): QuotaWindow => {
      const resetsAt = timeMs(bucket.reset_time);
      return { id: bucket.id, label: `${group.name} · ${bucket.name}`, group: group.name, usedPercent: clamp((1 - bucket.remaining_fraction) * 100), ...(resetsAt !== undefined ? { resetsAt } : bucket.description !== undefined && { resetLabel: bucket.description }) };
    }),
  );
  return { windows, aiCreditsNotice: 'Unavailable via native CLI' };
};

// ---- Local servers

const local: Probe = async (ports) => {
  const servers = await Promise.all(localKinds.map((kind) => ports.localModels(kind).then((models) => ({ kind, running: true, models }), () => ({ kind, running: false, models: [] as string[] }))));
  return servers.some((s) => s.running) ? { windows: [], servers } : { status: 'unavailable', message: 'no local server answered', windows: [], servers };
};

export const probes: Record<QuotaTarget['provider'], Probe> = { claude, codex, agy, local };
