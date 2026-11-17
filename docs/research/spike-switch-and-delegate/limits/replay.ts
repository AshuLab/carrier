// Spike D3: replays usage-limit and rate-limit signals through the REAL adapters with a fake transport / fake query.
// No agent, no network, no quota. Run: node docs/research/spike-switch-and-delegate/limits/replay.ts
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { claudeChatRunner } from '../../../../src/chat/claude.ts';
import { codexChatRunner } from '../../../../src/chat/codex.ts';
import type { ChatEvent } from '../../../../src/chat/runner.ts';

const root = join(import.meta.dirname, '../../../..');
const fixture = JSON.parse(readFileSync(join(root, 'src/harnesses/claude-usage-limit.fixture.jsonl'), 'utf8').trim());
const limitText: string = fixture.result; // the CLI's own words, from a REAL capture
const clean = (events: ChatEvent[]) => events.filter((e) => e.kind !== 'option' && e.kind !== 'delta');

// ---------- Codex: a fake app-server; every turn/start is answered with the given notifications ----------
async function codexTurn(label: string, notifications: { method: string; params: unknown }[]) {
  let listener: (line: string) => void = () => {};
  const play = (m: unknown) => listener(JSON.stringify(m));
  const transport = {
    pid: undefined,
    onLine: (l: (line: string) => void) => void (listener = l),
    onExit: () => {},
    write(text: string) {
      const m = JSON.parse(text) as { id?: number; method?: string };
      if (m.id === undefined) return;
      const results: Record<string, unknown> = {
        initialize: { userAgent: 'carrier/0.167.2 (fake)' },
        'thread/start': { thread: { id: 'thread-1' }, model: 'gpt-fake', reasoningEffort: 'low' },
        'model/list': { data: [] },
        'skills/list': { data: [] },
        'turn/start': { turn: { id: 'turn-1' } },
      };
      play({ id: m.id, result: results[m.method!] });
      if (m.method === 'turn/start') queueMicrotask(() => notifications.forEach((n) => play(n)));
    },
  };
  const conversation = await codexChatRunner({ resolve: () => '/bin/codex', loggedIn: async () => true, spawn: () => transport as never, mcpWaitMs: 0 }).open({ folder: '/work', env: {} });
  const events: ChatEvent[] = [];
  conversation.onEvent((e) => events.push(e));
  conversation.send('hi');
  for (let i = 0; i < 100 && !events.some((e) => e.kind === 'turn_end'); i++) await new Promise((r) => setTimeout(r, 5));
  console.log(`CODEX ${label}\n  ${JSON.stringify(clean(events))}`);
}

const failed = (error: unknown) => ({ method: 'turn/completed', params: { threadId: 'thread-1', turn: { id: 'turn-1', status: 'failed', error, items: [] } } });
const errorNote = (message: string, codexErrorInfo: unknown, willRetry: boolean) => ({ method: 'error', params: { threadId: 'thread-1', turnId: 'turn-1', willRetry, error: { message, codexErrorInfo, additionalDetails: null, misalignment: null } } });
const usageMsg = "You've hit your usage limit. Try again at Nov 17th, 2026 3:45 PM.";

await codexTurn('a1 usage limit: error notification (willRetry false) + failed turn, codexErrorInfo usageLimitExceeded', [
  errorNote(usageMsg, 'usageLimitExceeded', false),
  failed({ message: usageMsg, codexErrorInfo: 'usageLimitExceeded', additionalDetails: null, misalignment: null }),
]);
await codexTurn('a2 transient rate limit retried by Codex, then the turn completes: error notification willRetry true', [
  errorNote('Reconnecting... 1/5 (rate limit exceeded)', 'rateLimitExceeded', true),
  { method: 'turn/completed', params: { threadId: 'thread-1', turn: { id: 'turn-1', status: 'completed', error: null, items: [] } } },
]);
await codexTurn('a3 rate limit retried to exhaustion: failed turn, responseTooManyFailedAttempts 429', [
  errorNote('exceeded retry limit, last status: 429 Too Many Requests', { responseTooManyFailedAttempts: { httpStatusCode: 429 } }, false),
  failed({ message: 'exceeded retry limit, last status: 429 Too Many Requests', codexErrorInfo: { responseTooManyFailedAttempts: { httpStatusCode: 429 } }, additionalDetails: null, misalignment: null }),
]);
await codexTurn('a4 failed turn with rateLimitExceeded (non-retried)', [failed({ message: 'Rate limit reached. Please try again in 11s', codexErrorInfo: 'rateLimitExceeded', additionalDetails: null, misalignment: null })]);
await codexTurn('a5 workspace credits (message does not start with "You\'ve hit"), codexErrorInfo usageLimitExceeded', [
  failed({ message: 'Your workspace is out of credits. Add credits to continue.', codexErrorInfo: 'usageLimitExceeded', additionalDetails: null, misalignment: null }),
]);
await codexTurn('a6 failed turn with no error object', [failed(null)]);

// ---------- Claude: a fake SDK query; lines are what the CLI streams (the real adapter, only `query` faked) ----------
async function claudeTurn(label: string, lines: object[]) {
  const query = ((_: { prompt: AsyncIterable<unknown>; options: unknown }) => {
    async function* run() {
      for await (const _message of _.prompt) {
        for (const line of lines) yield line as never;
      }
    }
    return Object.assign(run(), {
      initializationResult: async () => ({ models: [], commands: [] }),
      mcpServerStatus: async () => [],
      interrupt: async () => {},
      setModel: async () => {},
      setPermissionMode: async () => {},
      close: () => {},
    });
  }) as never;
  const conversation = await claudeChatRunner({ query, resolve: () => '/bin/claude', loggedIn: async () => true }).open({ folder: '/work', env: {} });
  const events: ChatEvent[] = [];
  conversation.onEvent((e) => events.push(e));
  conversation.send('hi');
  for (let i = 0; i < 100 && !events.some((e) => e.kind === 'turn_end'); i++) await new Promise((r) => setTimeout(r, 5));
  console.log(`CLAUDE ${label}\n  ${JSON.stringify(clean(events))}`);
  await conversation.close();
}

// The synthetic assistant line: its fields (is_api_error_message, api_error, api_error_params) are CONSTRUCTED from the CLI binary's own schema, not captured.
const synthetic = (extra: object) => ({ type: 'assistant', message: { model: '<synthetic>', content: [{ type: 'text', text: limitText }] }, session_id: 's', ...extra });
const limitInfo = { status: 'rejected', resetsAt: 1763300400, rateLimitType: 'five_hour', isUsingOverage: false };

await claudeTurn('b1 the REAL captured result of the fixture alone (is_error, subtype success, 429, api_error usage_limit_reached)', [fixture]);
await claudeTurn('b2 constructed synthetic assistant (api_error usage_limit_reached + rate_limit_info) then the real result', [
  { type: 'rate_limit_event', rate_limit_info: limitInfo, uuid: 'u', session_id: 's' },
  synthetic({ error: 'rate_limit', is_api_error_message: true, api_error_status: 429, api_error: 'usage_limit_reached', api_error_params: { rate_limit_info: limitInfo } }),
  fixture,
]);
await claudeTurn('b3 a rate limit that is NOT a usage limit: synthetic error rate_limit, 429, no api_error; result 429 without api_error', [
  synthetic({ error: 'rate_limit', is_api_error_message: true, api_error_status: 429 }),
  { ...fixture, api_error: undefined, result: 'API Error: Request rejected (429) - temporary server throttle' },
]);
await claudeTurn('b4 error_during_execution result with errors[] (no api fields)', [{ type: 'result', subtype: 'error_during_execution', is_error: true, errors: ['boom'], usage: {} }]);
await claudeTurn('b5 only rate_limit_event rejected + allowed_warning, then a normal result', [
  { type: 'rate_limit_event', rate_limit_info: { status: 'allowed_warning', resetsAt: 1763300400, rateLimitType: 'five_hour', utilization: 0.9 }, uuid: 'u', session_id: 's' },
  { type: 'rate_limit_event', rate_limit_info: limitInfo, uuid: 'u2', session_id: 's' },
  { type: 'result', subtype: 'success', is_error: false, result: 'ok', usage: {} },
]);
process.exit(0);
