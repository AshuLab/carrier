import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeChatRunner } from '../../../chat/fake.ts';
import { startChatHost } from '../../../chat/host.ts';
import { FakeClock } from '../../../orchestration/fake.ts';
import { realHistoryPorts } from '../../../usage/real.ts';
import type { UsagePorts } from '../../../usage/types.ts';
import { CliError } from '../cli-error.ts';
import * as controlClient from '../control-client.ts';
import { connectControl } from '../control-client.ts';
import { USAGE_TIMEOUT_MS, usageCommand } from './usage.ts';

vi.mock('../control-client.ts', async (original) => {
  const real = await original<typeof import('../control-client.ts')>();
  return { ...real, connectControl: vi.fn(real.connectControl) };
});


const NOW = Date.UTC(2026, 10, 13, 12);
let root: string;
let stops: (() => Promise<void>)[];
let written: string[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'cu-')); // short: a socket path holds 103 bytes on macOS
  vi.stubEnv('CARRIER_HOME', root);
  stops = [];
  written = [];
  vi.spyOn(process.stdout, 'write').mockImplementation((text) => (written.push(String(text)), true));
  // a Claude login with one window, and one hour of an unpriced model
  const claudeDir = join(root, 'claude');
  mkdirSync(join(claudeDir, 'projects', 'app'), { recursive: true });
  writeFileSync(join(claudeDir, '.credentials.json'), JSON.stringify({ claudeAiOauth: { accessToken: 'token', subscriptionType: 'max' } }));
  const line = (id: string, model: string) => JSON.stringify({ type: 'assistant', sessionId: 's', requestId: id, timestamp: new Date(NOW - 3_600_000).toISOString(), cwd: '/work/app', message: { id, model, usage: { input_tokens: 1_500_000, cache_read_input_tokens: 2000, output_tokens: 40_000 } } });
  writeFileSync(join(claudeDir, 'projects', 'app', 's.jsonl'), `${line('m1', 'claude-sonnet-4-5')}\n${line('m2', 'mystery-1')}\n`);
  writeFileSync(join(root, 'providers.json'), JSON.stringify({ providers: { 'claude-work': { harness: 'claude', configDir: claudeDir, displayName: 'Work' } } }));
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
});

const clock = new FakeClock();
const ports: UsagePorts = {
  clock,
  http: async () => ({ status: 200, json: { five_hour: { utilization: 42.5, resets_at: new Date(NOW + 3 * 3_600_000 + 5 * 60_000).toISOString() } } }),
  run: async () => ({ code: 0, stdout: '{}' }),
  spawnRpc: () => {
    throw new Error('no child in this test');
  },
  files: { read: async (path) => (await import('node:fs/promises')).readFile(path, 'utf8') },
  keychain: async () => undefined,
  localModels: async () => Promise.reject(new Error('down')),
};
const host = async () => {
  clock.time = NOW;
  const { stop } = await startChatHost({ installLogging: () => {}, clock, exit: vi.fn(), signals: false, runners: { claude: new FakeChatRunner() }, usage: { ports, history: realHistoryPorts } });
  stops.push(stop);
};
const never = vi.fn(async () => 0);

test.each([
  [{ days: '10' }, '--days is one of 7, 14, 30 (got "10")'],
  [{ days: 'abc' }, '--days is one of 7, 14, 30 (got "abc")'],
  [{ source: 'cli' }, '--source is one of all, epic, chat, external (got "cli")'],
  [{ provider: 'gemini' }, '--provider is one of all, claude, codex, agy, local (got "gemini")'],
])('%o is a CliError with usage code 2, and no host is started', async (flags, line) => {
  const error = await usageCommand(flags, { start: never }).catch((e) => e);
  expect(error).toBeInstanceOf(CliError);
  expect(error).toMatchObject({ code: 2, lines: [line] });
  expect(never).not.toHaveBeenCalled();
});

test('the default output is a quota table, the summary and the tables by model and workspace; with no host it starts one', async () => {
  const start = vi.fn(async () => {
    await host(); // what the detached child does
    return 1;
  });
  expect(await usageCommand({}, { start, now: () => NOW })).toBe(0);
  expect(start).toHaveBeenCalledWith(expect.objectContaining({ args: ['chat-host'], socketPath: join(root, 'chat', 'state', 'chat.sock') }));
  expect(written.join('')).toBe(
    [
      'Live quotas',
      'ACCOUNT        WINDOW    USED         RESETS',
      'Work           5h        43%          in 3h 5m',
      'Local servers  lmstudio  offline',
      'Local servers  ollama    offline',
      'Local servers  local     unavailable  no local server answered',
      '',
      'Last 30 days (estimated API cost, not what a plan charges)',
      'TURNS  IN    CACHE  OUT    COST',
      '2      3.0M  4.0k   80.0k  $5.10',
      '',
      'By model',
      'MODEL              PROVIDER  IN    CACHE  OUT    COST',
      'claude-sonnet-4-5  claude    1.5M  2.0k   40.0k  $5.10',
      'mystery-1          claude    1.5M  2.0k   40.0k  unpriced',
      '',
      'By workspace',
      'WORKSPACE  SOURCE    IN    CACHE  OUT    COST',
      '/work/app  external  3.0M  4.0k   80.0k  $5.10',
      '',
    ].join('\n'),
  );
});

test('--json prints exactly what the host answered, and --days, --provider, --source and --refresh reach it', async () => {
  await host();
  const client = await connectControl(join(root, 'chat', 'state', 'chat.sock'));
  const direct = await client.request('usage', { days: 7, provider: 'claude', source: 'external', refresh: true });
  client.close();
  expect(await usageCommand({ json: true, refresh: true, days: '7', provider: 'claude', source: 'external' }, { start: never })).toBe(0);
  expect(written.join('')).toBe(`${JSON.stringify(direct, null, 2)}\n`);
  expect(direct).toMatchObject({ checkedAt: NOW, quotas: [{ account: 'claude-work', status: 'ok' }], summary: { turns: 2 } });
  expect((direct as any).daily).toHaveLength(7);
  expect(never).not.toHaveBeenCalled();
});

test('a refusal of the host is a CliError with its words', async () => {
  await host();
  writeFileSync(join(root, 'providers.json'), JSON.stringify({ providers: { claude: { harness: 'claude', autoCompact: '300000' } } }));
  await expect(usageCommand({}, { start: never })).rejects.toMatchObject({ code: 1, lines: [expect.stringContaining('providers.claude.autoCompact')] });
});

test('the usage request waits as long as the probes and the first read of the logs can take, not the 5 s of other requests', async () => {
  await host();
  vi.mocked(controlClient.connectControl).mockClear();
  expect(await usageCommand({ json: true }, { start: never })).toBe(0);
  expect(USAGE_TIMEOUT_MS).toBe(45_000);
  expect(controlClient.connectControl).toHaveBeenCalledWith(join(root, 'chat', 'state', 'chat.sock'), { timeoutMs: USAGE_TIMEOUT_MS });
});

test('an older chat host whose hello does not list usage is told apart, and no usage request is sent', async () => {
  const requests: string[] = [];
  const server = createServer((socket) => {
    socket.setEncoding('utf8');
    socket.write(`${JSON.stringify({ event: 'hello', protocol: 1, pid: 1, startedAt: 1, version: '0.0.1', capabilities: ['agents', 'list'] })}\n`);
    socket.on('data', (chunk: string) => requests.push(...chunk.split('\n').filter(Boolean)));
  });
  mkdirSync(join(root, 'chat', 'state'), { recursive: true });
  await new Promise<void>((resolve) => server.listen(join(root, 'chat', 'state', 'chat.sock'), resolve));
  stops.push(() => new Promise((resolve) => server.close(() => resolve())));
  await expect(usageCommand({}, { start: never })).rejects.toMatchObject({ code: 1, lines: [expect.stringContaining('carrier chat --stop')] });
  expect(requests).toEqual([]);
  expect(never).not.toHaveBeenCalled();
});
