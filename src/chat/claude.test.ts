import { mkdirSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { query as sdkQuery } from '@anthropic-ai/claude-agent-sdk';
import type { Config } from '../config/schema.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { claudeChatRunner, type ClaudeChatDeps } from './claude.ts';
import { openChatDatabase } from './db.ts';
import { ChatRefused, type ChatConversation, type ChatEvent } from './runner.ts';
import { createSessions } from './sessions.ts';

// The adapter replayed against the spike's recording of a real conversation (docs/research/chat-spike/): only the
// transport, the SDK's `query`, is faked. It hands back what the real Claude said for each message sent.

type Line = Record<string, any>;
type Segment = { text: string; lines: Line[] };

const recording = readFileSync(join(import.meta.dirname, '../../docs/research/chat-spike/claude-conversation.fixture.jsonl'), 'utf8')
  .trimEnd()
  .split('\n')
  .map((line) => JSON.parse(line) as Line);
const processes = recording.reduce<Line[][]>((all, line) => (line.host === 'recording' ? [...all, [line]] : (all.at(-1)!.push(line), all)), []);
const models = processes[0]!.find((line) => line.host === 'initializationResult')!.models;
// A turn ends at its `result`; what follows in the recording is the driver changing an option between turns.
const segmentsOf = (lines: Line[]) =>
  lines
    .reduce<Segment[]>((all, line) => (line.host === 'sent' ? [...all, { text: line.text, lines: [] }] : (all.at(-1)?.lines.push(line), all)), [])
    .map(({ text, lines }) => ({ text, lines: lines.slice(0, lines.findIndex((line) => line.type === 'result') + 1) }));
const main = segmentsOf(processes[0]!);
const resumed = segmentsOf(processes[1]!);
const sessionId = recording.find((line) => line.host === 'sessionId')!.id as string;

/** A `query` that answers each message with the next segment: the provider's lines, stopping where the recording asked the person (an approval) or called interrupt. */
function replay(segments: Segment[]) {
  const seen = { options: undefined as any, calls: [] as string[], permissions: [] as any[] };
  let interrupted: () => void;
  const gate = new Promise<void>((resolve) => (interrupted = resolve));
  const query = (({ prompt, options }: Parameters<typeof sdkQuery>[0]) => {
    seen.options = options;
    async function* run() {
      let next = 0;
      for await (const message of prompt as AsyncIterable<any>) {
        const segment = segments[next++]!;
        expect(message.message.content).toBe(segment.text);
        for (const line of segment.lines) {
          if (line.host === 'canUseTool') seen.permissions.push(await options!.canUseTool!(line.toolName, line.input, { signal: new AbortController().signal, toolUseID: line.toolUseID, suggestions: line.suggestions } as never));
          else if (line.host === 'interrupt_called') await gate;
          else if (!line.host) yield line as never;
        }
      }
    }
    return Object.assign(run(), {
      initializationResult: async () => ({ models }),
      interrupt: async () => (seen.calls.push('interrupt'), interrupted(), undefined),
      setModel: async (model?: string) => void seen.calls.push(`setModel ${model}`),
      setPermissionMode: async (mode: string) => void seen.calls.push(`setPermissionMode ${mode}`),
      close: () => void seen.calls.push('close'),
    });
  }) as unknown as typeof sdkQuery;
  return { query, seen };
}

const deps = (query: typeof sdkQuery, over: Partial<ClaudeChatDeps> = {}): ClaudeChatDeps => ({ query, resolve: (command) => command ?? '/bin/claude', loggedIn: async () => true, ...over });
const openWith = async (segments: Segment[], resume?: string) => {
  const replayed = replay(segments);
  const conversation = await claudeChatRunner(deps(replayed.query)).open({ folder: '/work', env: { A: 'b' }, ...(resume && { resume }) });
  const events: ChatEvent[] = [];
  conversation.onEvent((event) => events.push(event));
  return { conversation, events, ...replayed };
};
/** Sends a message and resolves with the events of that turn. `onEvent` can answer an approval as the person would. */
async function turn(conversation: ChatConversation, events: ChatEvent[], text: string) {
  const from = events.length;
  conversation.send(text);
  await vi.waitFor(() => expect(events.slice(from).some((e) => e.kind === 'turn_end')).toBe(true));
  return events.slice(from);
}
const kinds = (events: ChatEvent[]) => events.filter((e) => e.kind !== 'delta').map((e) => e.kind);

test('the recorded conversation: remembers across turns, runs a tool, and every turn ends with its model and usage', async () => {
  const { conversation, events, seen } = await openWith(main);
  expect(seen.options).toMatchObject({ cwd: '/work', env: { A: 'b' }, pathToClaudeCodeExecutable: '/bin/claude', includePartialMessages: true });

  const first = await turn(conversation, events, main[0]!.text);
  expect(first.filter((e) => e.kind === 'delta').length).toBeGreaterThan(0);
  expect(first.filter((e) => e.kind !== 'delta')).toEqual([
    { kind: 'assistant', text: 'OK' },
    { kind: 'turn_end', outcome: 'ok', model: 'claude-haiku-5-5', usage: expect.objectContaining({ output_tokens: 4, cache_read_input_tokens: 22126, total_cost_usd: expect.any(Number) }) },
  ]);
  expect(conversation.nativeId).toBe(sessionId);

  expect((await turn(conversation, events, main[1]!.text)).find((e) => e.kind === 'assistant')).toEqual({ kind: 'assistant', text: 'PINEAPPLE' });

  const tool = await turn(conversation, events, main[2]!.text);
  expect(tool.filter((e) => e.kind === 'tool_start' || e.kind === 'tool_end')).toEqual([
    { kind: 'tool_start', callId: expect.any(String), tool: 'Bash', arg: 'echo hello-from-spike' },
    { kind: 'tool_end', callId: expect.any(String), tool: 'Bash', output: ['hello-from-spike'], status: 'ok' },
  ]);
  expect(tool.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
});

/** Answers every approval as the person would: with the choice in `choice.id`. */
const answering = (conversation: ChatConversation, choice = { id: 'allow' }) => {
  conversation.onEvent((e) => e.kind === 'approval' && queueMicrotask(() => conversation.answer(e.approvalId, choice.id)));
  return choice;
};

test('an approval is asked with the provider choices and an allow runs the tool', async () => {
  const { conversation, events, seen } = await openWith(main);
  answering(conversation);
  for (const segment of main.slice(0, 3)) await turn(conversation, events, segment.text);

  const allowed = await turn(conversation, events, main[3]!.text);
  expect(allowed.find((e) => e.kind === 'approval')).toMatchObject({
    tool: 'Bash',
    arg: 'touch allowed.txt',
    choices: [{ id: 'allow', allow: true }, { id: 'deny', allow: false }, { id: 'suggestion:0', label: 'Always allow touch allowed.txt', allow: true }, { id: 'suggestion:1', allow: true }, { id: 'suggestion:2', allow: true }],
  });
  expect(allowed.filter((e) => e.kind === 'approval_answered')).toEqual([{ kind: 'approval_answered', approvalId: expect.any(String), choiceId: 'allow' }]);
  expect(seen.permissions[0]).toMatchObject({ behavior: 'allow', updatedInput: { command: 'touch allowed.txt' } });
});

test('a decline is honoured: the tool is denied with a message and the next message goes on', async () => {
  const { conversation, events, seen } = await openWith(main);
  const choice = answering(conversation);
  for (const segment of main.slice(0, 4)) await turn(conversation, events, segment.text);
  choice.id = 'deny';
  const declined = await turn(conversation, events, main[4]!.text);
  expect(seen.permissions[1]).toMatchObject({ behavior: 'deny', message: expect.any(String) });
  expect(declined.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
  expect(() => conversation.answer('toolu_none', 'allow')).toThrow(ChatRefused);
});

test('options are listed, change at once, and an interrupt ends the turn as interrupted and the session takes the next message', async () => {
  const { conversation, events, seen } = await openWith(main);
  answering(conversation);
  for (const segment of main.slice(0, 5)) await turn(conversation, events, segment.text);
  const byId = (id: string) => conversation.options.find((o) => o.id === id)!;
  expect(byId('permissionMode')).toMatchObject({ current: 'default', values: expect.arrayContaining([{ id: 'plan', label: expect.any(String) }]) });
  expect(byId('permissionMode').values.map((v) => v.id)).not.toContain('bypassPermissions');
  expect(byId('model').values.map((v) => v.id)).toContain('sonnet');
  expect(byId('effort').values.map((v) => v.id)).toEqual(['low', 'medium', 'high', 'xhigh', 'max']);

  await conversation.setOption('permissionMode', 'acceptEdits');
  await conversation.setOption('model', 'sonnet');
  await expect(conversation.setOption('model', 'gpt-5')).rejects.toThrow(ChatRefused);
  await expect(conversation.setOption('speed', 'fast')).rejects.toThrow(ChatRefused);
  expect(seen.calls).toEqual(['setPermissionMode acceptEdits', 'setModel sonnet']);
  expect(events.filter((e) => e.kind === 'option')).toEqual([{ kind: 'option', id: 'permissionMode', value: 'acceptEdits' }, { kind: 'option', id: 'model', value: 'sonnet' }]);
  expect([byId('permissionMode').current, byId('model').current]).toEqual(['acceptEdits', 'sonnet']);

  await turn(conversation, events, main[5]!.text);
  const from = events.length;
  conversation.send(main[6]!.text);
  await vi.waitFor(() => expect(events.length).toBeGreaterThan(from)); // the turn is running
  await conversation.interrupt(); // resolves once the turn has ended
  expect(events.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'interrupted' });
  expect(events.slice(from).some((e) => e.kind === 'error')).toBe(false);

  expect(await turn(conversation, events, main[7]!.text)).toContainEqual({ kind: 'assistant', text: 'AFTER-INTERRUPT-OK' });
});

test('the process ending on its own ends the running turn as an error and tells the host it ended', async () => {
  const { query } = replay(main);
  // the stream ends on the first message instead of answering it
  const dying = ((args: Parameters<typeof sdkQuery>[0]) => {
    const real = query(args) as any;
    async function* run() {
      for await (const _ of args.prompt as AsyncIterable<any>) return;
    }
    return Object.assign(run(), { initializationResult: real.initializationResult, close: () => {} });
  }) as unknown as typeof sdkQuery;
  const conversation = await claudeChatRunner(deps(dying)).open({ folder: '/work', env: {} });
  const events: ChatEvent[] = [];
  conversation.onEvent((event) => events.push(event));
  const ended = vi.fn();
  conversation.onEnd(ended);
  conversation.send('hi');
  await vi.waitFor(() => expect(ended).toHaveBeenCalledTimes(1));
  expect(events).toEqual([{ kind: 'error', text: 'The Claude process ended' }, { kind: 'turn_end', outcome: 'error', model: undefined }]);
});

test('a conversation resumes by the native id and keeps the context', async () => {
  const { conversation, events, seen } = await openWith(resumed, sessionId);
  expect(conversation.nativeId).toBe(sessionId);
  expect(seen.options.resume).toBe(sessionId);
  expect((await turn(conversation, events, resumed[0]!.text)).find((e) => e.kind === 'assistant')).toEqual({ kind: 'assistant', text: 'PINEAPPLE' });
});

test('a line it does not know is ignored and never throws', async () => {
  const unknown: Line[] = [{ type: 'brand_new' }, { type: 'assistant', message: 7 }, { type: 'user', message: { content: [null, { type: 'tool_result' }] } }, { type: 'stream_event', event: 3 }, { type: 'system', subtype: 'hook_started' }, { type: 'result', usage: 'x', modelUsage: null }];
  const { conversation, events } = await openWith([{ text: 'hi', lines: unknown }]);
  expect(await turn(conversation, events, 'hi')).toEqual([{ kind: 'turn_end', outcome: 'ok', model: undefined, usage: {} }]);
});

test('an effort change is a turn of its own that the person does not see', async () => {
  const done = (extra: Line = {}): Line => ({ type: 'result', subtype: 'success', is_error: false, usage: {}, ...extra });
  const { conversation, events } = await openWith([
    { text: '/effort max', lines: [{ type: 'assistant', message: { model: 'm', content: [{ type: 'text', text: 'Set effort level to max' }] } }, done()] },
    { text: 'hi', lines: [done()] },
  ]);
  await conversation.setOption('effort', 'max');
  expect(events).toEqual([{ kind: 'option', id: 'effort', value: 'max' }]);
  expect(await turn(conversation, events, 'hi')).toEqual([{ kind: 'turn_end', outcome: 'ok', model: undefined, usage: {} }]);
  expect(conversation.options.find((o) => o.id === 'effort')!.current).toBe('max');
});

test('open rejects with a reason when Claude is not installed or not logged in, and with a failure of the stream as a start failure', async () => {
  const { query } = replay([]);
  const open = (over: Partial<ClaudeChatDeps>) => claudeChatRunner(deps(query, over)).open({ folder: '/work', env: {} });
  await expect(open({ resolve: () => { throw new Error('nope'); } })).rejects.toThrow(/not installed.*"claude"/);
  await expect(claudeChatRunner(deps(query, { resolve: () => { throw new Error('nope'); } })).open({ folder: '/work', command: '/x/claude', env: {} })).rejects.toThrow(/"\/x\/claude" cannot be run/);
  await expect(open({ loggedIn: async () => false })).rejects.toThrow(/not logged in/);
  const broken = (() => ({ initializationResult: async () => Promise.reject(new Error('secret detail')), close() {}, [Symbol.asyncIterator]: () => ({ next: () => new Promise(() => {}) }) })) as unknown as typeof sdkQuery;
  await expect(claudeChatRunner(deps(broken)).open({ folder: '/work', env: {} })).rejects.toThrow(/^Claude could not be started$/);
  await expect(claudeChatRunner(deps(broken)).open({ folder: '/work', resume: 'x', env: {} })).rejects.toThrow(/could not resume/);
});

// Through the host's sessions, over a temporary SQLite: the person's message, the agent's and the turn are stored, and the native id lands on the session.
let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cl-'));
  mkdirSync(join(dir, 'work'));
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

test('the host stores the transcript of the replayed conversation and the native session id', async () => {
  const db = openChatDatabase(join(dir, 'chat.db'));
  const runner = claudeChatRunner(deps(replay(main).query));
  const sessions = createSessions({ db, config: { root: join(dir, 'root') } as Config, clock: new FakeClock(), runners: { claude: runner }, env: {}, binaryFound: () => true, onLiveChange: () => {} });
  const { session } = await sessions.open({ agent: 'claude', folder: join(dir, 'work') });
  expect(session.nativeId).toBeNull();
  for (const segment of main.slice(0, 3)) {
    sessions.send({ sessionId: session.id, text: segment.text });
    await vi.waitFor(() => expect(sessions.events({ sessionId: session.id, limit: 1 }).session.state).toBe('idle'));
  }
  const { events, session: after } = sessions.events({ sessionId: session.id, limit: 200 });
  expect(after.nativeId).toBe(sessionId);
  expect(events.map((e) => e.kind)).toEqual(['user', 'assistant', 'turn_end', 'user', 'assistant', 'turn_end', 'user', 'tool_start', 'tool_end', 'assistant', 'turn_end']);
  expect(events[0]).toMatchObject({ kind: 'user', text: main[0]!.text });
  expect(events.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok', model: 'claude-haiku-5-5' });
  await sessions.closeAll();
  db.$client.close();
});

test('the conversation reports the process it started as the leader of its own group, with the command', async () => {
  const replayed = replay(main);
  const query = ((args: Parameters<typeof sdkQuery>[0]) => {
    args.options!.spawnClaudeCodeProcess!({ command: '/bin/claude', args: [], cwd: '/work', env: {}, signal: new AbortController().signal });
    return replayed.query(args);
  }) as unknown as typeof sdkQuery;
  const spawn = (() => ({ pid: 777 })) as unknown as ClaudeChatDeps['spawn'];
  const conversation = await claudeChatRunner(deps(query, { spawn })).open({ folder: '/work', env: {} });
  expect(conversation.process).toEqual({ pid: 777, pgid: 777, command: '/bin/claude' });
  expect((await claudeChatRunner(deps(replayed.query)).open({ folder: '/work', env: {} })).process).toBeUndefined();
});
