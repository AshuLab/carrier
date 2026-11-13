import { createHash } from 'node:crypto';
import { homedir } from 'node:os';
import { beforeEach, expect, test, vi } from 'vitest';
import { QUOTA_KEPT_MS, createQuotas } from './quotas.ts';
import type { RpcChild, UsagePorts } from './types.ts';

const logged: unknown[] = [];
vi.mock('@ashulab/universal-logger', () => {
  const record = (...args: unknown[]) => void logged.push(args);
  return { createScopedLogger: () => ({ debug: record, info: record, warn: record, error: record }) };
});
beforeEach(() => void (logged.length = 0));

const SECRET = 'sk-ant-SECRET-token';
const REFRESH = 'sk-ant-REFRESH-token';

const NOW = 1_800_000_000_000;
const iso = (ms: number) => new Date(ms).toISOString();

/** A clock the test moves; `after` callbacks run only when the test says time passed. */
function fakeClock() {
  let now = NOW;
  const timers = new Set<() => Promise<void>>();
  return {
    now: () => now,
    after: (_ms: number, fn: () => Promise<void>) => (timers.add(fn), () => void timers.delete(fn)),
    advance: (ms: number) => void (now += ms),
    expire: () => Promise.all([...timers].map((fn) => fn())),
  };
}

const errorWith = (code: string) => Object.assign(new Error(`${SECRET} ${code}`), { code });

/** A child that answers the way `codex app-server` does; `silent` never answers, `endsWith` ends it instead. */
function fakeRpc(options: { initialize?: unknown; limits?: unknown; silent?: boolean; startError?: NodeJS.ErrnoException } = {}) {
  const sent: string[] = [];
  let killed = 0;
  let onLine: (line: string) => void = () => {};
  const spawnRpc = (): RpcChild => ({
    send(line) {
      sent.push(line);
      const message = JSON.parse(line);
      if (options.silent || message.id === undefined) return;
      const reply = message.id === 1 ? options.initialize ?? { result: {} } : options.limits ?? { result: {} };
      queueMicrotask(() => onLine(JSON.stringify({ id: message.id, ...(reply as object) })));
    },
    onLine: (fn) => void (onLine = fn),
    onExit: (fn) => options.startError && queueMicrotask(() => fn(options.startError)),
    kill: () => void killed++,
  });
  return { spawnRpc, sent, killed: () => killed };
}

function ports(overrides: Partial<UsagePorts> = {}) {
  const clock = fakeClock();
  const fake: UsagePorts = {
    clock,
    http: async () => ({ status: 200, json: {} }),
    run: async () => ({ code: 0, stdout: '{}' }),
    spawnRpc: fakeRpc().spawnRpc,
    files: { read: async () => { throw errorWith('ENOENT'); } },
    keychain: async () => undefined,
    localModels: async () => { throw new Error('down'); },
    ...overrides,
  };
  return { fake, clock, quotas: createQuotas(fake) };
}

const credentials = (expiresAt?: number) => JSON.stringify({ other: 'kept', claudeAiOauth: { accessToken: SECRET, refreshToken: REFRESH, subscriptionType: 'max', ...(expiresAt !== undefined && { expiresAt }) } });
const claudeUsage = {
  five_hour: { utilization: 42.5, resets_at: iso(NOW + 3_600_000) },
  seven_day: { utilization: 130, resets_at: iso(NOW + 86_400_000) },
  seven_day_opus: { utilization: 7, resets_at: null },
  extra_usage: { is_enabled: true, monthly_limit: 8000, used_credits: 1250, utilization: 15.6, currency: 'USD' },
};
const claude = { provider: 'claude', configDir: '/cfg' } as const;
const readsCredentials = (text = credentials(NOW + 3_600_000)) => ({ read: async () => text });

// ---- Claude

test('claude ok: windows clamped, model scoped, plan, and spend scaled from minor units to dollars', async () => {
  const { quotas } = ports({ files: readsCredentials(), http: async () => ({ status: 200, json: claudeUsage }) });
  expect(await quotas(claude)).toEqual({
    provider: 'claude',
    status: 'ok',
    checkedAt: NOW,
    planType: 'max',
    windows: [
      { id: '5h', label: '5h', usedPercent: 42.5, resetsAt: NOW + 3_600_000 },
      { id: '7d', label: '7d', usedPercent: 100, resetsAt: NOW + 86_400_000 },
      { id: '7d:opus', label: '7d opus', usedPercent: 7 },
    ],
    extraUsage: { isEnabled: true, monthlyLimitUsd: 80, usedCreditsUsd: 12.5, utilization: 15.6, currency: 'USD' },
  });
});

test('claude asks the usage endpoint with the bearer token and the OAuth beta header', async () => {
  const asked: Parameters<UsagePorts['http']>[0][] = [];
  const { quotas } = ports({ files: readsCredentials(), http: async (r) => (asked.push(r), { status: 200, json: claudeUsage }) });
  await quotas(claude);
  expect(asked[0]).toMatchObject({ url: 'https://api.anthropic.com/api/oauth/usage', headers: { authorization: `Bearer ${SECRET}`, 'anthropic-beta': 'oauth-2025-04-20' } });
});

test('claude decimal places other than two scale the spend', async () => {
  const body = { five_hour: claudeUsage.five_hour, extra_usage: { is_enabled: true, monthly_limit: 80_000, used_credits: 500, decimal_places: 3 } };
  const { quotas } = ports({ files: readsCredentials(), http: async () => ({ status: 200, json: body }) });
  expect((await quotas(claude)).extraUsage).toEqual({ isEnabled: true, monthlyLimitUsd: 80, usedCreditsUsd: 0.5 });
});

test('claude without a credentials file is missing; a file with no login, or a refused token, is signed out', async () => {
  expect(await ports().quotas(claude)).toMatchObject({ status: 'missing', message: expect.stringContaining('no Claude login found') });
  expect((await ports({ files: readsCredentials('{}') }).quotas(claude)).status).toBe('signed_out');
  expect((await ports({ files: readsCredentials('not json') }).quotas(claude)).status).toBe('signed_out');
  expect((await ports({ files: readsCredentials(), http: async () => ({ status: 401, json: {} }) }).quotas(claude)).status).toBe('signed_out');
});

const hashed = (dir: string) => `Claude Code-credentials-${createHash('sha256').update(dir).digest('hex').slice(0, 8)}`;

test('claude with no file reads the login from the Keychain item named after its config folder, and never leaks the token', async () => {
  const asked: string[] = [];
  const { quotas } = ports({ keychain: async (service) => (asked.push(service), service === hashed('/cfg') ? credentials(NOW + 3_600_000) : undefined), http: async () => ({ status: 200, json: claudeUsage }) });
  const snapshot = await quotas(claude);
  expect(snapshot.status).toBe('ok');
  expect(snapshot.planType).toBe('max');
  expect(asked).toContain(hashed('/cfg'));
  expect(asked).not.toContain('Claude Code-credentials');
  expect(JSON.stringify([snapshot, logged])).not.toContain(SECRET);
});

test('claude default login is the bare Keychain item; another folder never falls back to it', async () => {
  const bare = ports({ keychain: async (service) => (service === 'Claude Code-credentials' ? credentials(NOW + 3_600_000) : undefined), http: async () => ({ status: 200, json: claudeUsage }) });
  expect((await bare.quotas({ provider: 'claude', configDir: `${homedir()}/.claude` })).status).toBe('ok');
  const other = ports({ keychain: async (service) => (service === 'Claude Code-credentials' ? credentials(NOW + 3_600_000) : undefined), http: async () => ({ status: 200, json: claudeUsage }) });
  expect((await other.quotas(claude)).status).toBe('missing');
});

test('claude Keychain that does not answer is unavailable, and an expired login says Claude Code renews it', async () => {
  const denied = await ports({ keychain: async () => { throw errorWith('EACCES'); } }).quotas(claude);
  expect(denied).toMatchObject({ status: 'unavailable', message: expect.stringContaining('Keychain') });
  expect(JSON.stringify(denied)).not.toContain(SECRET);
  const expired = await ports({ keychain: async () => credentials(NOW - 1) }).quotas(claude);
  expect(expired).toMatchObject({ status: 'signed_out', message: expect.stringContaining('renews it') });
});

test('claude unavailable when the server errors or cannot be reached; timeout and other failures are errors', async () => {
  const files = readsCredentials();
  expect((await ports({ files, http: async () => ({ status: 503, json: {} }) }).quotas(claude)).status).toBe('unavailable');
  expect((await ports({ files, http: async () => { throw errorWith('ECONNREFUSED'); } }).quotas(claude)).status).toBe('unavailable');
  expect((await ports({ files, http: async () => { throw errorWith('ETIMEDOUT'); } }).quotas(claude)).status).toBe('error');
  expect((await ports({ files, http: async () => ({ status: 418, json: {} }) }).quotas(claude)).status).toBe('error');
  expect((await ports({ files, http: async () => ({ status: 200, json: 'nope' }) }).quotas(claude)).status).toBe('error');
});

test('claude rate limited keeps the last known windows, marked stale, with the time of that data', async () => {
  let status = 200;
  const { quotas, clock } = ports({ files: readsCredentials(), http: async () => ({ status, json: claudeUsage }) });
  const good = await quotas(claude);
  status = 429;
  clock.advance(QUOTA_KEPT_MS);
  const limited = await quotas(claude);
  expect(limited).toMatchObject({ status: 'rate_limited', stale: true, checkedAt: good.checkedAt, windows: good.windows, extraUsage: good.extraUsage });
});

test('claude rate limited with nothing known has no windows and is not stale', async () => {
  const limited = await ports({ files: readsCredentials(), http: async () => ({ status: 429, json: {} }) }).quotas(claude);
  expect(limited).toMatchObject({ status: 'rate_limited', windows: [] });
  expect(limited.stale).toBeUndefined();
});

test('claude with an expired token is signed out; it is never refreshed here and queries nothing', async () => {
  const asked: string[] = [];
  const { quotas } = ports({ files: readsCredentials(credentials(NOW - 1)), http: async (r) => (asked.push(r.url), { status: 200, json: claudeUsage }) });
  expect((await quotas(claude)).status).toBe('signed_out');
  expect(asked).toHaveLength(0);
});

test('no token, credential, or provider text reaches a snapshot or the log', async () => {
  const outcomes = [
    await ports({ files: readsCredentials(), http: async () => { throw errorWith('ECONNREFUSED'); } }).quotas(claude),
    await ports({ files: readsCredentials(), http: async () => ({ status: 500, json: { error: SECRET } }) }).quotas(claude),
    await ports({ files: readsCredentials(), http: async () => undefined as never }).quotas(claude), // an unexpected failure
    await ports({ run: async () => { throw errorWith('EACCES'); } }).quotas({ provider: 'agy' }),
    await ports({ spawnRpc: fakeRpc({ limits: { error: { message: `rate limits unreadable ${SECRET}` } } }).spawnRpc }).quotas({ provider: 'codex' }),
  ];
  expect(outcomes.map((o) => o.status)).toEqual(['unavailable', 'unavailable', 'error', 'error', 'error']);
  for (const text of [JSON.stringify(outcomes), JSON.stringify(logged)]) for (const secret of [SECRET, REFRESH]) expect(text).not.toContain(secret);
  expect(logged.length).toBeGreaterThan(0);
});

// ---- Codex

const codexLimits = {
  result: {
    rateLimits: { limitId: 'codex', primary: { usedPercent: 12, windowDurationMins: 300, resetsAt: 1_800_000_900 }, secondary: { usedPercent: 140, windowDurationMins: 10_080, resetsAt: 1_800_050_000 }, credits: { hasCredits: true, unlimited: false, balance: '5.00' }, planType: 'plus' },
    rateLimitsByLimitId: {
      codex: { limitId: 'codex', primary: { usedPercent: 12, windowDurationMins: 300, resetsAt: 1_800_000_900 }, secondary: { usedPercent: 140, windowDurationMins: 10_080, resetsAt: 1_800_050_000 } },
      spark: { limitId: 'spark', limitName: 'Spark', primary: { usedPercent: 99, windowDurationMins: 300, resetsAt: 1_800_000_100 }, secondary: null },
    },
    rateLimitResetCredits: { availableCount: 1, credits: [] },
  },
};
const codex = { provider: 'codex' } as const;

test('codex ok: initialize, then account/rateLimits/read; model buckets never replace the main windows', async () => {
  const rpc = fakeRpc({ limits: codexLimits });
  const snapshot = await ports({ spawnRpc: rpc.spawnRpc }).quotas(codex);
  expect(rpc.sent.map((l) => JSON.parse(l).method)).toEqual(['initialize', 'initialized', 'account/rateLimits/read']);
  expect(snapshot).toEqual({
    provider: 'codex',
    status: 'ok',
    checkedAt: NOW,
    planType: 'plus',
    windows: [
      { id: 'codex:primary', label: '5h', usedPercent: 12, resetsAt: 1_800_000_900_000 },
      { id: 'codex:secondary', label: '7d', usedPercent: 100, resetsAt: 1_800_050_000_000 },
      { id: 'spark:primary', label: 'Spark 5h', group: 'spark', usedPercent: 99, resetsAt: 1_800_000_100_000 },
    ],
    credits: { hasCredits: true, unlimited: false, balance: '5.00' },
    rateLimitResetCredits: { availableCount: 1, credits: [] },
  });
  expect(rpc.killed()).toBeGreaterThan(0);
});

test('codex without a secondary window, or a weekly-only plan, still reads', async () => {
  const limits = { result: { rateLimits: { primary: { usedPercent: 98, windowDurationMins: 43_200, resetsAt: 1_800_000_900 }, secondary: null } } };
  expect((await ports({ spawnRpc: fakeRpc({ limits }).spawnRpc }).quotas(codex)).windows).toEqual([{ id: 'codex:primary', label: '30d', usedPercent: 98, resetsAt: 1_800_000_900_000 }]);
});

test('codex statuses: no binary is missing, an auth error is signed out, a 429 is rate limited, an early exit is unavailable', async () => {
  const startError = Object.assign(new Error('spawn codex ENOENT'), { code: 'ENOENT' });
  expect((await ports({ spawnRpc: fakeRpc({ startError, silent: true }).spawnRpc }).quotas(codex)).status).toBe('missing');
  expect((await ports({ spawnRpc: fakeRpc({ limits: { error: { message: 'codex account authentication required to read rate limits' } } }).spawnRpc }).quotas(codex)).status).toBe('signed_out');
  expect((await ports({ spawnRpc: fakeRpc({ limits: { error: { message: 'HTTP 429 Too Many Requests' } } }).spawnRpc }).quotas(codex)).status).toBe('rate_limited');
  expect((await ports({ spawnRpc: fakeRpc({ startError: new Error('exited'), silent: true }).spawnRpc }).quotas(codex)).status).toBe('unavailable');
  expect((await ports({ spawnRpc: fakeRpc({ limits: { result: { nonsense: true } } }).spawnRpc }).quotas(codex)).status).toBe('error');
});

test('codex rate limited keeps the last known windows, stale', async () => {
  let reply: unknown = codexLimits;
  const { quotas, clock } = ports({ spawnRpc: () => fakeRpc({ limits: reply }).spawnRpc() });
  const good = await quotas(codex);
  reply = { error: { message: '429' } };
  clock.advance(QUOTA_KEPT_MS);
  expect(await quotas(codex)).toMatchObject({ status: 'rate_limited', stale: true, windows: good.windows, credits: good.credits });
});

test('codex that never answers is an error at the limit and its child is ended', async () => {
  const rpc = fakeRpc({ silent: true });
  const { quotas, clock } = ports({ spawnRpc: rpc.spawnRpc });
  const pending = quotas(codex);
  await clock.expire();
  expect(await pending).toMatchObject({ status: 'error', message: 'the check timed out' });
  expect(rpc.killed()).toBeGreaterThan(0);
});

// ---- Antigravity

const agyAnswer = {
  status: 'SUCCESS',
  command: {
    data: {
      groups: [
        { name: 'Gemini Models', buckets: [{ id: 'gemini-weekly', name: 'Weekly Limit Remaining', remaining_fraction: 0.88, reset_time: '2026-11-18T03:22:14Z' }, { id: 'gemini-5h', name: 'Five Hour Limit Remaining', remaining_fraction: 1.2, reset_time: '2026-11-13T06:50:36Z' }] },
        { name: 'Claude and GPT models', buckets: [{ id: '3p-5h', name: 'Five Hour Limit Remaining', description: 'it will fully refresh in 2 hours', remaining_fraction: 0.25 }] },
        { name: 'Dynamic Pool', buckets: [{ id: 'dyn', name: 'Weekly', remaining_fraction: 0, reset_time: '2026-11-20T04:22:01Z' }] },
      ],
    },
  },
};
const agy = { provider: 'agy' } as const;

test('agy ok: every pool the CLI reports, remaining turned into used, a reset time or its own words, and the credits notice', async () => {
  const ran: [string, string[], NodeJS.ProcessEnv][] = [];
  const { quotas } = ports({ run: async (command, args, { env }) => (ran.push([command, args, env]), { code: 0, stdout: JSON.stringify(agyAnswer) }) });
  const snapshot = await quotas(agy);
  expect(ran[0]![0]).toBe('agy');
  expect(ran[0]![1]).toEqual(['-p', '/usage', '--output-format', 'json']);
  expect(ran[0]![2].BROWSER).toBe('true');
  expect(snapshot.aiCreditsNotice).toBe('Unavailable via native CLI');
  expect(snapshot.windows.map((w) => [w.id, w.group, Math.round(w.usedPercent)])).toEqual([
    ['gemini-weekly', 'Gemini Models', 12],
    ['gemini-5h', 'Gemini Models', 0],
    ['3p-5h', 'Claude and GPT models', 75],
    ['dyn', 'Dynamic Pool', 100],
  ]);
  expect(snapshot.windows[0]!.resetsAt).toBe(Date.parse('2026-11-18T03:22:14Z'));
  expect(snapshot.windows[2]).toMatchObject({ resetLabel: 'it will fully refresh in 2 hours' });
  expect(snapshot.windows[2]!.resetsAt).toBeUndefined();
});

test('agy statuses: no binary is missing, a timeout and an unreadable answer are errors, a login prompt is signed out', async () => {
  expect((await ports({ run: async () => { throw errorWith('ENOENT'); } }).quotas(agy)).status).toBe('missing');
  expect((await ports({ run: async () => { throw errorWith('ETIMEDOUT'); } }).quotas(agy)).status).toBe('error');
  expect((await ports({ run: async () => ({ code: 0, stdout: '<html>' }) }).quotas(agy)).status).toBe('error');
  expect((await ports({ run: async () => ({ code: 1, stdout: '' }) }).quotas(agy)).status).toBe('unavailable');
  expect((await ports({ run: async () => ({ code: 0, stdout: JSON.stringify({ status: 'ERROR', response: 'Please sign in to Antigravity' }) }) }).quotas(agy)).status).toBe('signed_out');
  expect((await ports({ run: async () => ({ code: 0, stdout: JSON.stringify({ status: 'SUCCESS', response: 'hi' }) }) }).quotas(agy)).status).toBe('error');
});

// ---- Local servers

const local = { provider: 'local' } as const;

test('local servers: which answer, with the models they have', async () => {
  const { quotas } = ports({ localModels: async (kind) => { if (kind === 'ollama') throw new Error('down'); return ['qwen']; } });
  expect(await quotas(local)).toEqual({
    provider: 'local',
    status: 'ok',
    checkedAt: NOW,
    windows: [],
    servers: [{ kind: 'lmstudio', running: true, models: ['qwen'] }, { kind: 'ollama', running: false, models: [] }],
  });
});

test('local with no server answering is unavailable but still lists both', async () => {
  const snapshot = await ports().quotas(local);
  expect(snapshot.status).toBe('unavailable');
  expect(snapshot.servers).toHaveLength(2);
});

// ---- The cache

function counted() {
  let calls = 0;
  const release: (() => void)[] = [];
  const t = ports({
    files: readsCredentials(),
    http: () => (calls++, new Promise((resolve) => release.push(() => resolve({ status: 200, json: claudeUsage })))),
  });
  return { ...t, calls: () => calls, release: () => release.splice(0).forEach((r) => r()) };
}

test('calls that arrive while a probe runs share it', async () => {
  const t = counted();
  const all = [t.quotas(claude), t.quotas(claude), t.quotas(claude, { refresh: true })];
  await vi.waitFor(() => expect(t.calls()).toBe(1));
  t.release();
  const [a, b, c] = await Promise.all(all);
  expect(t.calls()).toBe(1);
  expect(a).toBe(b);
  expect(a).toBe(c);
});

test('a snapshot is served for sixty seconds, then probed again', async () => {
  const t = counted();
  const first = t.quotas(claude);
  await vi.waitFor(() => expect(t.calls()).toBe(1));
  t.release();
  await first;
  t.clock.advance(QUOTA_KEPT_MS - 1);
  await t.quotas(claude);
  expect(t.calls()).toBe(1);
  t.clock.advance(1);
  const again = t.quotas(claude);
  await vi.waitFor(() => expect(t.calls()).toBe(2));
  t.release();
  expect((await again).checkedAt).toBe(NOW + QUOTA_KEPT_MS);
});

test('refresh: true probes again inside the sixty seconds', async () => {
  const t = counted();
  const first = t.quotas(claude);
  await vi.waitFor(() => expect(t.calls()).toBe(1));
  t.release();
  await first;
  const again = t.quotas(claude, { refresh: true });
  await vi.waitFor(() => expect(t.calls()).toBe(2));
  t.release();
  await again;
});

test('providers and accounts are cached apart, and one failing does not touch the others', async () => {
  const { quotas } = ports({ files: readsCredentials(), http: async () => ({ status: 200, json: claudeUsage }) });
  const [a, b] = await Promise.all([quotas(claude), quotas({ provider: 'claude', configDir: '/other' }), quotas(local)]);
  expect(a.status).toBe('ok');
  expect(b.status).toBe('ok');
  expect((await quotas(local)).status).toBe('unavailable');
  expect((await quotas(claude)).status).toBe('ok');
});
