import { mkdirSync, readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { query as sdkQuery } from '@anthropic-ai/claude-agent-sdk';
import { FakeClock } from '../orchestration/fake.ts';
import { FakeGit, fakeProjects } from './fake.ts';
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
const sentSegments = (lines: Line[]) => lines.reduce<Segment[]>((all, line) => (line.host === 'sent' ? [...all, { text: line.text, lines: [] }] : (all.at(-1)?.lines.push(line), all)), []);
const segmentsOf = (lines: Line[]) => sentSegments(lines).map(({ text, lines }) => ({ text, lines: lines.slice(0, lines.findIndex((line) => line.type === 'result') + 1) }));
const main = segmentsOf(processes[0]!);
const resumed = segmentsOf(processes[1]!);
const sessionId = recording.find((line) => line.host === 'sessionId')!.id as string;

/** A `query` that answers each message with the next segment: the provider's lines, stopping where the recording asked the person (an approval) or called interrupt. */
function replay(segments: Segment[], mcpServers?: { name: string; status: string; error?: string }[]) {
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
      initializationResult: async () => ({
        models,
        commands: [
          { name: 'review', description: 'Review a change', argumentHint: '<pr>' },
          { name: 'compact', description: 'Free up context', argumentHint: '', builtin: true },
          { name: 'exit', description: 'Leave', argumentHint: '', builtin: true },
        ],
      }),
      mcpServerStatus: async () => mcpServers ?? [],
      interrupt: async () => (seen.calls.push('interrupt'), interrupted(), undefined),
      stopTask: async (taskId: string) => void seen.calls.push(`stopTask ${taskId}`),
      setModel: async (model?: string) => void seen.calls.push(`setModel ${model}`),
      setPermissionMode: async (mode: string) => void seen.calls.push(`setPermissionMode ${mode}`),
      close: () => void seen.calls.push('close'),
    });
  }) as unknown as typeof sdkQuery;
  return { query, seen };
}

const deps = (query: typeof sdkQuery, over: Partial<ClaudeChatDeps> = {}): ClaudeChatDeps => ({ query, resolve: (command) => command ?? '/bin/claude', loggedIn: async () => true, ...over });
const openWith = async (segments: Segment[], resume?: string, child = false) => {
  const replayed = replay(segments);
  const conversation = await claudeChatRunner(deps(replayed.query)).open({ folder: '/work', env: { A: 'b' }, ...(resume && { resume }), ...(child && { child }) });
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
  expect(seen.options).toMatchObject({ cwd: '/work', env: { A: 'b' }, pathToClaudeCodeExecutable: '/bin/claude', includePartialMessages: true, extraArgs: { 'thinking-display': 'summarized' } });

  const first = await turn(conversation, events, main[0]!.text);
  expect(first.filter((e) => e.kind === 'delta').length).toBeGreaterThan(0);
  expect(first.filter((e) => e.kind !== 'delta')).toEqual([
    { kind: 'assistant', text: 'OK' },
    { kind: 'turn_end', outcome: 'ok', model: 'claude-haiku-5-5', usage: expect.objectContaining({ output_tokens: 4, cache_read_input_tokens: 22126, context_tokens: expect.any(Number), total_cost_usd: expect.any(Number) }) },
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

test('a thinking block is a reasoning event before the answer, an empty one gives none, and a recording with none yields none', async () => {
  // the recorded thinking blocks are empty (and so give none): the text is put into one ahead of the first answer, with an empty block beside it
  const thinking = (line: Line) => ({ ...line, message: { ...line.message, content: [{ type: 'thinking', thinking: '  ' }, { type: 'thinking', thinking: 'Two words, so OK.' }, ...line.message.content] } });
  const first = main[0]!;
  const at = first.lines.findIndex((line) => line.type === 'assistant');
  const { conversation, events } = await openWith([{ ...first, lines: first.lines.map((line, i) => (i === at ? thinking(line) : line)) }]);
  const shown = await turn(conversation, events, first.text);
  expect(shown.filter((e) => e.kind !== 'delta')).toEqual([
    { kind: 'reasoning', text: 'Two words, so OK.' },
    { kind: 'assistant', text: 'OK' },
    { kind: 'turn_end', outcome: 'ok', model: 'claude-haiku-5-5', usage: expect.anything() },
  ]);
  expect(shown.some((e) => e.kind === 'delta' && e.text.includes('Two words'))).toBe(false); // never streamed in pieces

  const plain = await openWith(main);
  expect(kinds(await turn(plain.conversation, plain.events, first.text))).toEqual(['assistant', 'turn_end']);
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

test('the approvals of a child offer Allow and Deny and none of the suggestions', async () => {
  const { conversation, events, seen } = await openWith(main, undefined, true);
  answering(conversation);
  for (const segment of main.slice(0, 3)) await turn(conversation, events, segment.text);

  const allowed = await turn(conversation, events, main[3]!.text);
  expect(allowed.find((e) => e.kind === 'approval')).toMatchObject({ tool: 'Bash', arg: 'touch allowed.txt', choices: [{ id: 'allow', allow: true }, { id: 'deny', allow: false }] });
  expect((allowed.find((e) => e.kind === 'approval') as { choices: unknown[] }).choices).toHaveLength(2);
  expect(seen.permissions[0]).toMatchObject({ behavior: 'allow', updatedInput: { command: 'touch allowed.txt' } });
  expect(seen.permissions[0]).not.toHaveProperty('updatedPermissions');
});

test('delegate_start is pre-approved like the other tools of the chat MCP: no card, no input and no allowance for the session; only in plan, where the harness asks for every tool of a server, the adapter allows the chat MCP\'s tools and nothing else', async () => {
  const tool = 'mcp__carrier-chat__delegate_start';
  const input = { agent: 'codex', task: 'review the diff' };
  const asking = (toolName: string): Segment => ({ ...main[0]!, lines: [{ host: 'canUseTool', toolName, input, toolUseID: 'toolu_d', suggestions: [] } as Line, ...main[0]!.lines] });
  const run = async (toolName: string, permissionMode: string) => {
    const replayed = replay([asking(toolName)]);
    const conversation = await claudeChatRunner(deps(replayed.query)).open({ folder: '/work', env: {}, options: { permissionMode }, mcp: { serverName: 'carrier-chat', url: 'http://127.0.0.1:1/mcp', token: 'token', tools: ['capabilities', 'delegate_start'] } });
    const events: ChatEvent[] = [];
    conversation.onEvent((e) => e.kind === 'approval' && queueMicrotask(() => conversation.answer(e.approvalId, 'deny')));
    conversation.onEvent((e) => events.push(e));
    await turn(conversation, events, main[0]!.text);
    return { approvals: events.filter((e) => e.kind === 'approval'), permission: replayed.seen.permissions[0] };
  };

  const planned = await run(tool, 'plan');
  expect(planned.approvals).toEqual([]);
  expect(planned.permission).toEqual({ behavior: 'allow', updatedInput: input });

  // outside plan the harness does not call canUseTool for it; if it does (a rule of the person's settings that asks), it is the person's call, as for any tool, with nothing of the old card
  const asked = await run(tool, 'default');
  expect(asked.approvals).toEqual([{ kind: 'approval', approvalId: 'toolu_d', tool, arg: expect.any(String), choices: [{ id: 'allow', label: 'Allow', allow: true }, { id: 'deny', label: 'Deny', allow: false }] }]);
  expect(asked.permission).toMatchObject({ behavior: 'deny' });

  // a tool that is not the chat MCP's still asks in plan, and so does another server's
  for (const other of ['Bash', 'mcp__other__delegate_start']) expect((await run(other, 'plan')).approvals).toHaveLength(1);
});

test('AskUserQuestion is asked as questions, the answers go back in the tool input, a skip is a deny, and bad input is a generic approval', async () => {
  const question = { question: 'Which one?', header: 'Pick', options: [{ label: 'A', description: 'a' }, { label: 'B', description: 'b' }], multiSelect: false };
  const asking = (input: unknown): Segment => ({ ...main[0]!, lines: [{ host: 'canUseTool', toolName: 'AskUserQuestion', input, toolUseID: 'toolu_q', suggestions: [{ type: 'setMode', mode: 'plan', destination: 'session' }] } as Line, ...main[0]!.lines] });
  const run = async (input: unknown, choice: string, answers?: Record<string, string>) => {
    const { conversation, events, seen } = await openWith([asking(input)]);
    conversation.onEvent((e) => e.kind === 'approval' && queueMicrotask(() => conversation.answer(e.approvalId, choice, answers)));
    const played = await turn(conversation, events, main[0]!.text);
    return { approval: played.find((e) => e.kind === 'approval'), answered: played.find((e) => e.kind === 'approval_answered'), permission: seen.permissions[0] };
  };

  const sent = await run({ questions: [question] }, 'allow', { 'Which one?': 'B' });
  expect(sent.approval).toEqual({ kind: 'approval', approvalId: 'toolu_q', tool: 'AskUserQuestion', choices: [{ id: 'allow', label: 'Send answers', allow: true }, { id: 'deny', label: 'Skip', allow: false }], questions: [question] });
  expect(sent.answered).toEqual({ kind: 'approval_answered', approvalId: 'toolu_q', choiceId: 'allow', answers: { 'Which one?': 'B' } });
  expect(sent.permission).toEqual({ behavior: 'allow', updatedInput: { questions: [question], answers: { 'Which one?': 'B' } } });

  expect((await run({ questions: [question] }, 'deny')).permission).toEqual({ behavior: 'deny', message: 'The user skipped the questions.' });
  const generic = await run({ questions: 'none' }, 'deny');
  expect(generic.approval).toMatchObject({ tool: 'AskUserQuestion', arg: expect.any(String), choices: [{ id: 'allow' }, { id: 'deny' }, { id: 'suggestion:0' }] });
  expect(generic.approval).not.toHaveProperty('questions');

  // allowing questions without their answers is refused and leaves them pending
  const { conversation, events } = await openWith([asking({ questions: [question] })]);
  conversation.send(main[0]!.text);
  await vi.waitFor(() => expect(events.some((e) => e.kind === 'approval')).toBe(true));
  expect(() => conversation.answer('toolu_q', 'allow')).toThrow(ChatRefused);
  conversation.answer('toolu_q', 'deny');
  await vi.waitFor(() => expect(events.some((e) => e.kind === 'turn_end')).toBe(true));
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
  // what the SDK knows of a model (what it is, which exact model its alias stands for) reaches the client, so a person can tell Sonnet from Sonnet
  expect(byId('model').values.find((v) => v.id === 'sonnet')).toMatchObject({ detail: expect.any(String), version: expect.stringMatching(/^claude-/) });
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

test('the size of the window is the one model the result lists even when its key is not the name the messages carried', async () => {
  const call: Line = { type: 'assistant', message: { model: 'claude-sonnet-5-5', content: [{ type: 'text', text: 'ok' }], usage: { input_tokens: 1, cache_read_input_tokens: 10 } } };
  const result = (modelUsage: Line): Line => ({ type: 'result', subtype: 'success', is_error: false, usage: {}, modelUsage });
  const one = await openWith([{ text: 'a', lines: [call, result({ 'claude-sonnet-5-5[1m]': { contextWindow: 1_000_000 } })] }]);
  expect((await turn(one.conversation, one.events, 'a')).find((e) => e.kind === 'turn_end')).toMatchObject({ usage: { context_window: 1_000_000 } });
  // two models and neither is the one that answered: nothing is guessed
  const two = await openWith([{ text: 'b', lines: [call, result({ 'other-a': { contextWindow: 200_000 }, 'other-b': { contextWindow: 1_000_000 } })] }]);
  expect((await turn(two.conversation, two.events, 'b')).find((e) => e.kind === 'turn_end')).not.toHaveProperty('usage.context_window');
});

test('a line it does not know is ignored and never throws', async () => {
  const unknown: Line[] = [{ type: 'brand_new' }, { type: 'assistant', message: 7 }, { type: 'user', message: { content: [null, { type: 'tool_result' }] } }, { type: 'stream_event', event: 3 }, { type: 'system', subtype: 'hook_started' }, { type: 'result', usage: 'x', modelUsage: null }];
  const { conversation, events } = await openWith([{ text: 'hi', lines: unknown }]);
  expect(await turn(conversation, events, 'hi')).toEqual([{ kind: 'turn_end', outcome: 'ok', model: undefined, usage: {} }]);
});

test('a turn ends with the context of its last model call, not the sum of the calls its result adds up', async () => {
  const call = (usage: Line, parent?: string): Line => ({ type: 'assistant', ...(parent && { parent_tool_use_id: parent }), message: { model: 'claude-sonnet-5-5', content: [{ type: 'text', text: 'ok' }], usage } });
  const lines: Line[] = [
    call({ input_tokens: 3, cache_read_input_tokens: 90_000, cache_creation_input_tokens: 1_000 }),
    // a subagent's call is its own context, not the turn's
    call({ input_tokens: 5, cache_read_input_tokens: 400_000, cache_creation_input_tokens: 0 }, 'toolu_sub'),
    call({ input_tokens: 4, cache_read_input_tokens: 92_000, cache_creation_input_tokens: 500 }),
    { type: 'result', subtype: 'success', is_error: false, usage: { input_tokens: 7, cache_read_input_tokens: 182_000, cache_creation_input_tokens: 1_500, output_tokens: 20 }, modelUsage: { 'claude-sonnet-5-5': { contextWindow: 1_000_000 } } },
  ];
  const { conversation, events } = await openWith([{ text: 'hi', lines }]);
  const end = (await turn(conversation, events, 'hi')).find((e) => e.kind === 'turn_end');
  // and the size of the model's window, so the app can say how full it is
  expect(end).toMatchObject({ usage: { context_tokens: 92_504, cache_read_input_tokens: 182_000, context_window: 1_000_000 } });
  // the next turn starts clean: a result that no call came before has no context
  const next = await openWith([{ text: 'a', lines: [call({ input_tokens: 1, cache_read_input_tokens: 10 }), { type: 'result', subtype: 'success', is_error: false, usage: {} }] }, { text: 'b', lines: [{ type: 'result', subtype: 'success', is_error: false, usage: {} }] }]);
  await turn(next.conversation, next.events, 'a');
  expect((await turn(next.conversation, next.events, 'b')).find((e) => e.kind === 'turn_end')).toMatchObject({ usage: {} });
  expect((await turn(next.conversation, next.events, 'b')).find((e) => e.kind === 'turn_end')).not.toHaveProperty('usage.context_tokens');
});

test('the background tasks the SDK reports are the whole set each time, without the watchers, and a task that goes leaves the set', async () => {
  const task = (id: string, extra: Line = {}): Line => ({ task_id: id, task_type: 'local_bash', description: `run ${id}`, ...extra });
  const lines: Line[] = [
    { type: 'system', subtype: 'background_tasks_changed', tasks: [task('a'), task('w', { ambient: true }), task('b', { task_type: 'local_agent', description: 'review the diff' })] },
    { type: 'system', subtype: 'background_tasks_changed', tasks: [task('b')] },
    { type: 'system', subtype: 'background_tasks_changed', tasks: [] },
    { type: 'system', subtype: 'background_tasks_changed', tasks: 'not a list' },
    { type: 'result', subtype: 'success', is_error: false, usage: {} },
  ];
  const { conversation, events } = await openWith([{ text: 'hi', lines }]);
  const got = (await turn(conversation, events, 'hi')).filter((e) => e.kind === 'background');
  expect(got).toEqual([
    { kind: 'background', tasks: [{ id: 'a', kind: 'local_bash', description: 'run a' }, { id: 'b', kind: 'local_agent', description: 'review the diff' }] },
    { kind: 'background', tasks: [{ id: 'b', kind: 'local_bash', description: 'run b' }] },
    { kind: 'background', tasks: [] },
  ]);
});

test('a compaction is one event with the context before and after it, from either spelling of the numbers, and a failed one says why', async () => {
  const lines: Line[] = [
    { type: 'system', subtype: 'compact_boundary', compact_metadata: { trigger: 'manual', pre_tokens: 142_300, post_tokens: 18_400, duration_ms: 14_000 } },
    { type: 'system', subtype: 'compact_boundary', compactMetadata: { trigger: 'auto', preTokens: 181_000, postTokens: 22_000, durationMs: 9_000, preservedSegment: {} } },
    // what the provider does not say is left out, and a trigger it does not know is not repeated
    { type: 'system', subtype: 'compact_boundary', compact_metadata: { trigger: 'weekly', pre_tokens: 'many' } },
    { type: 'system', subtype: 'status', status: null, compact_result: 'success' },
    { type: 'system', subtype: 'status', status: null, compact_result: 'failed', compact_error: 'Not enough room to summarize' },
    { type: 'result', subtype: 'success', is_error: false, usage: {} },
  ];
  const { conversation, events } = await openWith([{ text: '/compact', lines }]);
  expect((await turn(conversation, events, '/compact')).filter((e) => e.kind === 'compact')).toEqual([
    { kind: 'compact', trigger: 'manual', before: 142_300, after: 18_400, ms: 14_000 },
    { kind: 'compact', trigger: 'auto', before: 181_000, after: 22_000, ms: 9_000 },
    { kind: 'compact' },
    { kind: 'compact', error: 'Not enough room to summarize' },
  ]);
});

const limitText = "You've hit your session limit · resets 12:40pm (America/Montevideo)";
// The CLI's own message about a limit, as its stream-json wraps it (`api_error*` are internal to the CLI and not in the SDK's types)
const synthetic = (extra: Line = {}): Line => ({ type: 'assistant', error: 'rate_limit', message: { model: '<synthetic>', content: [{ type: 'text', text: limitText }] }, ...extra });
// The real failed result the engine's fixture holds
const limitResult = JSON.parse(readFileSync(join(import.meta.dirname, '../harnesses/claude-usage-limit.fixture.jsonl'), 'utf8')) as Line;
const replayLimit = async (lines: Line[]) => {
  const { conversation, events } = await openWith([{ text: 'hi', lines }]);
  return turn(conversation, events, 'hi');
};

test('a usage limit comes out as one error that says so and carries its reset: the timestamp of the CLI\'s own message, else its words', async () => {
  const working: Line = { type: 'assistant', message: { model: 'claude-sonnet-5-5', content: [{ type: 'text', text: 'working' }] } };
  const info = { rate_limit_info: { status: 'rejected', rateLimitType: 'five_hour', resetsAt: 1_800_000_000 } };
  const stamped = await replayLimit([working, synthetic({ api_error: 'usage_limit_reached', api_error_params: info }), limitResult]);
  expect(stamped).toEqual([
    { kind: 'assistant', text: 'working' },
    { kind: 'error', text: limitText, reason: 'usage_limit', resetsAt: 1_800_000_000_000 },
    { kind: 'turn_end', outcome: 'error', model: 'claude-sonnet-5-5', usage: expect.any(Object) },
  ]);
  // the real result alone: the reset is the words of the result, and no `assistant` carries the limit's text
  const worded = await replayLimit([synthetic({ api_error: 'usage_limit_reached' }), limitResult]);
  expect(worded.filter((e) => e.kind === 'assistant')).toEqual([]);
  expect(worded.filter((e) => e.kind === 'error')).toEqual([{ kind: 'error', text: limitText, reason: 'usage_limit', resetText: 'resets 12:40pm (America/Montevideo)' }]);
  expect(worded.find((e) => e.kind === 'turn_end')).toMatchObject({ outcome: 'error', model: 'claude-sonnet-5-5' });
  // a limit with no reset says only that it is one
  const bare = await replayLimit([{ ...limitResult, result: "You're out of usage credits" }]);
  expect(bare.find((e) => e.kind === 'error')).toEqual({ kind: 'error', text: "You're out of usage credits", reason: 'usage_limit' });
});

test('the limit is told by its prefix when the result has no api_error, and a stamp of one turn does not leak into the next', async () => {
  const { conversation, events } = await openWith([
    { text: 'one', lines: [synthetic({ api_error: 'usage_limit_reached', api_error_params: { rate_limit_info: { resetsAt: 1_800_000_000 } } }), limitResult] },
    { text: 'two', lines: [{ type: 'result', subtype: 'success', is_error: true, result: "You've reached your weekly limit · resets Mon 9am", usage: {} }] },
  ]);
  expect((await turn(conversation, events, 'one')).find((e) => e.kind === 'error')).toMatchObject({ reason: 'usage_limit', resetsAt: 1_800_000_000_000 });
  expect((await turn(conversation, events, 'two')).find((e) => e.kind === 'error')).toEqual({ kind: 'error', text: "You've reached your weekly limit · resets Mon 9am", reason: 'usage_limit', resetText: 'resets Mon 9am' });
});

test('a rate limit that Claude retries is no usage limit, and a failed result of another kind is an error without a reason', async () => {
  const ok: Line = { type: 'result', subtype: 'success', is_error: false, result: 'done', usage: {} };
  const retried = await replayLimit([{ type: 'system', subtype: 'api_retry', attempt: 1, max_retries: 3, retry_delay_ms: 1000, error_status: 429, error: 'rate_limit' }, { type: 'rate_limit_event', rate_limit_info: { status: 'rejected', resetsAt: 1_800_000_000 } }, ok]);
  expect(retried.map((e) => e.kind)).toEqual(['turn_end']);
  const throttled = await replayLimit([synthetic({ message: { model: '<synthetic>', content: [{ type: 'text', text: 'API Error: Rate limited. Retry shortly.' }] } }), { type: 'result', subtype: 'success', is_error: true, api_error_status: 429, result: 'API Error: Rate limited. Retry shortly.', usage: {} }]);
  expect(throttled.find((e) => e.kind === 'error')).toEqual({ kind: 'error', text: 'API Error: Rate limited. Retry shortly.' });
  const invalidModel = await replayLimit([{ type: 'result', subtype: 'success', is_error: true, api_error_status: 404, api_error: 'model_not_found', result: 'There\'s an issue with the selected model (nope).', usage: {} }]);
  expect(invalidModel.find((e) => e.kind === 'error')).toEqual({ kind: 'error', text: "There's an issue with the selected model (nope)." });
  const keyLimit = await replayLimit([{ type: 'result', subtype: 'success', is_error: true, api_error_status: 429, result: 'API Error: 429 rate limit on this API key', usage: {} }]);
  expect(keyLimit.find((e) => e.kind === 'error')).toEqual({ kind: 'error', text: 'API Error: 429 rate limit on this API key' });
});

test('each model lists the reasoning levels it takes, the default model\'s when it has none of its own', async () => {
  const { conversation } = await openWith(main);
  const values = conversation.options.find((o) => o.id === 'model')!.values;
  const fallback = models.find((m: Line) => m.value === 'default').supportedEffortLevels;
  for (const value of values) {
    const own = models.find((m: Line) => m.value === value.id).supportedEffortLevels ?? fallback;
    expect(value.efforts).toEqual(own);
  }
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

test('a resume whose transcript is gone starts a new conversation in the same folder', async () => {
  const replayed = replay(main);
  const starts: unknown[] = [];
  const missing = ((args: Parameters<typeof sdkQuery>[0]) => {
    starts.push(args.options!.resume);
    if (args.options!.resume === undefined) return replayed.query(args);
    return { initializationResult: async () => Promise.reject(new Error('Claude Code returned an error result: No conversation found with session ID: x')), close() {}, [Symbol.asyncIterator]: () => ({ next: () => new Promise(() => {}) }) };
  }) as unknown as typeof sdkQuery;
  const conversation = await claudeChatRunner(deps(missing)).open({ folder: '/work', resume: 'x', env: {} });
  expect(starts).toEqual(['x', undefined]);
  expect(conversation.startedOver).toBe(true);
  expect(conversation.nativeId).toBeUndefined();
});

test('a resume that fails for another reason refuses, and so does one whose new conversation cannot start either', async () => {
  const failing = (message: string) => (() => ({ initializationResult: async () => Promise.reject(new Error(message)), close() {}, [Symbol.asyncIterator]: () => ({ next: () => new Promise(() => {}) }) })) as unknown as typeof sdkQuery;
  await expect(claudeChatRunner(deps(failing('boom'))).open({ folder: '/work', resume: 'x', env: {} })).rejects.toThrow(/could not resume/);
  await expect(claudeChatRunner(deps(failing('No conversation found with session ID: x'))).open({ folder: '/work', resume: 'x', env: {} })).rejects.toThrow(/^Claude could not be started$/);
});

test('an account\'s binary and login folder are what the login check and the SDK start with', async () => {
  const { query, seen } = replay([]);
  const checked: unknown[] = [];
  const env = { CLAUDE_CONFIG_DIR: '/logins/work' };
  await claudeChatRunner(deps(query, { loggedIn: async (binary, given) => (checked.push([binary, given]), true) })).open({ folder: '/work', command: '/opt/claude-work', env });
  expect(checked).toEqual([['/opt/claude-work', env]]);
  expect(seen.options).toMatchObject({ env, pathToClaudeCodeExecutable: '/opt/claude-work' });
});

test('an account\'s compaction and launch arguments reach the SDK as extraArgs, and an account that sets none adds nothing', async () => {
  const run = async (launch?: Parameters<ReturnType<typeof claudeChatRunner>['open']>[0]['launch']) => {
    const { query, seen } = replay([]);
    await claudeChatRunner(deps(query)).open({ folder: '/work', env: {}, launch });
    return seen.options!.extraArgs;
  };
  expect(await run()).toEqual({ 'thinking-display': 'summarized' });
  expect(await run({})).toEqual({ 'thinking-display': 'summarized' });
  expect(await run({ autoCompact: 'auto', idleCompaction: false, launchArgs: ['--chrome', '--max-turns', '5', '--add-x=a=b'] })).toEqual({
    chrome: null,
    'max-turns': '5',
    'add-x': 'a=b',
    autocompact: 'auto',
    settings: '{"idleCompaction":false}',
    'thinking-display': 'summarized',
  });
  expect(await run({ autoCompact: 300000 })).toMatchObject({ autocompact: '300000' });
  await expect(run({ launchArgs: ['-v'] })).rejects.toThrow('launchArgs entry 1 is not a --flag');
  await expect(run({ launchArgs: ['--chrome', '--a', 'secret-value', 'stray'] })).rejects.toThrow(/^(?!.*secret-value).*entry 4 /); // a stray token is refused by place, never by text
});

const mcp = { serverName: 'carrier-chat', url: 'http://127.0.0.1:4000/mcp', token: 'tok-secret' };

test('the chat MCP is handed to the SDK with every one of its tools, delegate_start among them, pre-approved by name, on a fresh open and on a resume; the token rides in the process environment, and neither extraArgs nor the mcpServers the SDK turns into argv hold it', async () => {
  for (const resume of [undefined, sessionId]) {
    const { query, seen } = replay([]);
    const conversation = await claudeChatRunner(deps(query)).open({ folder: '/work', env: { PATH: '/bin' }, mcp: { ...mcp, tools: ['capabilities', 'delegate_start'] }, ...(resume && { resume }) });
    expect(seen.options.mcpServers).toEqual({ 'carrier-chat': { type: 'http', url: mcp.url, headers: { Authorization: 'Bearer ${CARRIER_MCP_TOKEN}' } } });
    expect(seen.options.env).toEqual({ PATH: '/bin', CARRIER_MCP_TOKEN: 'tok-secret' });
    expect(seen.options.allowedTools).toEqual(['mcp__carrier-chat__capabilities', 'mcp__carrier-chat__delegate_start']);
    expect(seen.options.resume).toBe(resume);
    expect(JSON.stringify(seen.options.extraArgs)).not.toContain('tok-secret');
    expect(conversation.mcpProblem).toBeUndefined();
  }
});

test('without the chat MCP (a probe, or a host that could not bind it) the SDK gets no mcpServers and no allowedTools', async () => {
  const { query, seen } = replay([]);
  await claudeChatRunner(deps(query)).open({ folder: '/work', env: {} });
  expect(seen.options).not.toHaveProperty('mcpServers');
  expect(seen.options.env).not.toHaveProperty('CARRIER_MCP_TOKEN');
  expect(seen.options).not.toHaveProperty('allowedTools');
});

test('instructions are appended to the claude_code preset on a fresh open and on a resume, and without them the SDK gets no systemPrompt', async () => {
  for (const resume of [undefined, sessionId]) {
    const { query, seen } = replay([]);
    await claudeChatRunner(deps(query)).open({ folder: '/work', env: {}, instructions: 'HANDOFF TEXT', ...(resume && { resume }) });
    expect(seen.options.systemPrompt).toEqual({ type: 'preset', preset: 'claude_code', append: 'HANDOFF TEXT' });
    expect(seen.options.resume).toBe(resume);
  }
  const { query, seen } = replay([]);
  await claudeChatRunner(deps(query)).open({ folder: '/work', env: {} });
  expect(seen.options).not.toHaveProperty('systemPrompt');
});

test('a chat MCP the SDK reports as down is the conversation\'s mcpProblem, and open still succeeds; a connected or silent one is none', async () => {
  const open = async (servers?: { name: string; status: string; error?: string }[]) =>
    (await claudeChatRunner(deps(replay([], servers).query)).open({ folder: '/work', env: {}, mcp })).mcpProblem;
  expect(await open([{ name: 'other', status: 'connected' }, { name: 'carrier-chat', status: 'failed', error: 'connect ECONNREFUSED' }])).toBe('failed: connect ECONNREFUSED');
  expect(await open([{ name: 'carrier-chat', status: 'disconnected' }])).toBe('disconnected');
  expect(await open([{ name: 'carrier-chat', status: 'connected' }])).toBeUndefined();
  expect(await open([{ name: 'carrier-chat', status: 'pending' }])).toBeUndefined();
  expect(await open([{ name: 'other', status: 'failed' }])).toBeUndefined();
  expect(await open()).toBeUndefined();
  const unreadable = replay([]).query;
  const query = ((args: Parameters<typeof sdkQuery>[0]) => Object.assign(unreadable(args), { mcpServerStatus: async () => Promise.reject(new Error('no status')) })) as unknown as typeof sdkQuery;
  expect((await claudeChatRunner(deps(query)).open({ folder: '/work', env: {}, mcp })).mcpProblem).toBeUndefined();
});

// Through the host's sessions, over a temporary SQLite: the person's message, the agent's and the turn are stored, and the native id lands on the session.
let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cl-'));
  mkdirSync(join(dir, 'work'));
  vi.stubEnv('CARRIER_HOME', join(dir, 'home')); // no providers.json: the default accounts
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

test('the host stores the transcript of the replayed conversation and the native session id', async () => {
  const db = openChatDatabase(join(dir, 'chat.db'));
  const runner = claudeChatRunner(deps(replay(main).query));
  const sessions = createSessions({ db, agents: [{ name: 'claude', account: 'claude' }, { name: 'codex', account: 'codex' }], clock: new FakeClock(), runners: { claude: runner }, env: {}, git: new FakeGit(), projects: fakeProjects(new FakeGit()), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
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

test('the skills and commands the SDK lists are the conversation\'s commands, and invoking one sends it as a slash', async () => {
  const { conversation, events } = await openWith([{ ...main[0]!, text: '/review the diff' }]);
  expect(conversation.commands).toEqual([
    { id: 'review', name: 'review', description: 'Review a change', argumentHint: '<pr>', kind: 'skill' },
    { id: 'compact', name: 'compact', description: 'Free up context', kind: 'command' },
    { id: 'exit', name: 'exit', description: 'Leave', kind: 'command' },
  ]);
  // the provider's own words for what is for the terminal: not for a message box
  (conversation as any).terminalOnly = new Set(['exit']);
  expect(conversation.commands.map((c) => c.name)).toEqual(['review', 'compact']);
  const from = events.length;
  conversation.send('the diff', conversation.commands[0]);
  await vi.waitFor(() => expect(events.slice(from).some((e) => e.kind === 'turn_end')).toBe(true));
});

// The recording of a session with subagents (docs/research/chat-spike/claude-subagents.fixture.jsonl, read in docs/research/chat-subagents.md).
// Unlike the conversation above, a segment here is whole: it runs to the next message sent, because a background subagent ends after the turn's
// `result` and the SDK opens a turn of its own for it, with no message from the person.
const subagentParts = readFileSync(join(import.meta.dirname, '../../docs/research/chat-spike/claude-subagents.fixture.jsonl'), 'utf8')
  .trimEnd()
  .split('\n')
  .map((line) => JSON.parse(line) as Line)
  .reduce<Line[][]>((all, line) => (line.host === 'recording' ? [...all, [line]] : (all.at(-1)!.push(line), all)), []);

/** Plays each segment of a recording through the adapter, answering approvals as the recording did, and resolves with every event once `turns` turns have ended. */
async function playWhole(segments: Segment[], turns: number) {
  const { conversation, events } = await openWith(segments);
  answering(conversation);
  const ended = () => events.filter((e) => e.kind === 'turn_end').length;
  let expected = 0;
  for (const segment of segments) {
    expected += segment.lines.filter((line) => line.type === 'result').length;
    conversation.send(segment.text);
    await vi.waitFor(() => expect(ended()).toBe(expected), { timeout: 5_000 });
  }
  expect(ended()).toBe(turns);
  return events;
}

test('the recorded session with subagents loads: it has three subagents at once, a background one that ends after the turn, a nested one and a stopped one', async () => {
  expect(subagentParts.map((part) => part[0]!.name)).toEqual(['subagents', 'forwardSubagentText']);
  const whole = sentSegments(subagentParts[0]!);
  expect(whole).toHaveLength(2);
  const lines = subagentParts[0]!;
  const started = lines.filter((line) => line.subtype === 'task_started' && line.task_type === 'local_agent');
  expect(started.map((line) => [line.description, line.is_backgrounded, line.parent_task_id === undefined])).toEqual([
    ['Count files', false, true],
    ['Slow check', true, true],
    ['Delegator', false, true],
    ['Say hi', false, false],
    ['Long wait', false, true],
  ]);
  // the background subagent's notification arrives after the first turn's `result`
  expect(lines.findIndex((line) => line.type === 'result')).toBeLessThan(lines.findIndex((line) => line.subtype === 'task_notification' && line.task_id === started[1]!.task_id));

  const events = await playWhole(whole, 3);
  // every `Agent` call is a call of the thread that made it; the stopped one ends with an error, and the main agent's call carries no parent
  const agentCalls = events.filter((e) => e.kind === 'tool_start' && e.tool === 'Agent');
  expect(agentCalls).toHaveLength(5);
  expect(new Set(agentCalls.map((e) => (e as { callId: string }).callId)).size).toBe(5);
  expect(events.filter((e) => e.kind === 'tool_end' && e.tool === 'Agent' && e.status === 'err')).toEqual([
    { kind: 'tool_end', callId: expect.any(String), tool: 'Agent', output: ['[Request interrupted by user for tool use]'], status: 'err' },
  ]);
  expect(events.filter((e) => e.kind === 'turn_end').map((e) => e.kind === 'turn_end' && e.outcome)).toEqual(['ok', 'ok', 'ok']);
});

/** What the recording says each message was made in, as the adapter's events should say it: [kind, call or text, the launching call or null]. */
const madeIn = (lines: Line[]) =>
  lines.flatMap((line): [string, string, string | null][] => {
    const parent = typeof line.parent_tool_use_id === 'string' ? line.parent_tool_use_id : null;
    const blocks = (line.type === 'assistant' || line.type === 'user') && Array.isArray(line.message?.content) ? (line.message.content as Line[]) : [];
    return blocks.flatMap((block): [string, string, string | null][] => {
      if (line.type === 'user') return block.type === 'tool_result' ? [['tool_end', block.tool_use_id, parent]] : [];
      if (block.type === 'thinking') return block.thinking.trim() === '' ? [] : [['reasoning', block.thinking, parent]];
      if (block.type === 'text') return block.text === '' ? [] : [['assistant', block.text, parent]];
      return block.type === 'tool_use' ? [['tool_start', block.id, parent]] : [];
    });
  });
const eventsMadeIn = (events: ChatEvent[]) =>
  events.flatMap((e): [string, string, string | null][] =>
    e.kind === 'assistant' || e.kind === 'reasoning' ? [[e.kind, e.text, e.parentCallId ?? null]] : e.kind === 'tool_start' || e.kind === 'tool_end' ? [[e.kind, e.callId, e.parentCallId ?? null]] : [],
  );

test('every message the recording made inside a subagent carries the call that launched it, and no main-agent message does', async () => {
  for (const [part, turns] of [[0, 3], [1, 1]] as const) {
    const lines = subagentParts[part]!;
    const { conversation, events, seen } = await openWith(sentSegments(lines));
    expect(seen.options).toMatchObject({ forwardSubagentText: true });
    answering(conversation);
    for (const segment of sentSegments(lines)) conversation.send(segment.text);
    await vi.waitFor(() => expect(events.filter((e) => e.kind === 'turn_end')).toHaveLength(turns), { timeout: 5_000 });
    const expected = madeIn(lines);
    expect(eventsMadeIn(events)).toEqual(expected);
    // the check is not vacuous: part 1 has main and subagent messages of every kind but thoughts, part 2 has all four kinds inside a subagent
    const inside = (kind: string) => expected.some(([k, , parent]) => k === kind && parent !== null);
    expect(['tool_start', 'tool_end', 'assistant'].every(inside)).toBe(true);
    expect(expected.some(([, , parent]) => parent === null)).toBe(true);
    if (part === 1) expect(inside('reasoning')).toBe(true);
  }
});

test('a subagent\'s partial text gives no event, and the main message is the main agent\'s streamed text as before', async () => {
  const lines = subagentParts[1]!;
  const subagentWords = 'words only the subagent said';
  const partial = (parent: string | null) => ({ type: 'stream_event', parent_tool_use_id: parent, session_id: 's', uuid: 'u', event: { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: subagentWords } } });
  const call = lines.find((line) => line.type === 'assistant' && line.parent_tool_use_id !== null && line.parent_tool_use_id !== undefined)!.parent_tool_use_id as string;
  // the same recording with a subagent's partial before every message
  const withPartials = lines.flatMap((line) => (line.type === 'assistant' ? [partial(call), line] : [line]));
  const plain = await playWhole(sentSegments(lines), 1);
  const injected = await playWhole(sentSegments(withPartials), 1);
  const streamed = (events: ChatEvent[]) => events.filter((e) => e.kind === 'delta').map((e) => (e as { text: string }).text).join('');
  expect(streamed(plain)).not.toBe('');
  expect(streamed(injected)).toBe(streamed(plain));
  expect(streamed(injected)).not.toContain(subagentWords);
  expect(injected.filter((e) => e.kind === 'assistant' && e.parentCallId === undefined).some((e) => (e as { text: string }).text.includes(subagentWords))).toBe(false);
  // a partial whose parent is empty or not a string is the main agent's own
  const main = await playWhole(sentSegments(lines.flatMap((line) => (line.type === 'assistant' ? [partial(''), partial(7 as never), line] : [line]))), 1);
  expect(streamed(main).split(subagentWords)).toHaveLength(2 * lines.filter((line) => line.type === 'assistant').length + 1);
});

test('the subagents of the recording are task events joined to their launching call, and a subagent\'s Bash command is not one', async () => {
  const lines = subagentParts[0]!;
  const events = (await playWhole(sentSegments(lines), 3)).filter((e) => e.kind === 'task');
  const started = lines.filter((line) => line.subtype === 'task_started' && line.task_type === 'local_agent');
  expect(events.filter((e) => e.state === 'started').map((e) => [e.text, e.callId, e.taskId, e.background, e.agentType])).toEqual(
    started.map((line) => [line.description, line.tool_use_id, line.task_id, line.is_backgrounded, line.subagent_type]),
  );
  // every task event is of a subagent: the commands a subagent ran (`local_bash`) are not rows
  const bash = lines.filter((line) => line.task_type === 'local_bash').map((line) => line.task_id);
  expect(bash.length).toBeGreaterThan(0);
  expect(events.some((e) => bash.includes(e.taskId))).toBe(false);
  // a nested subagent is under the call of the one that launched it; the others have no parent
  const delegator = started.find((line) => line.description === 'Delegator')!;
  expect(events.filter((e) => e.state === 'started' && e.parentCallId !== undefined).map((e) => [e.text, e.parentCallId])).toEqual([['Say hi', delegator.tool_use_id]]);
  // the step and the usage of a running one, from the recording's own `task_progress`
  expect(events.find((e) => e.state === 'progress' && e.taskId === 'aea1aa9de8a2c258e')).toEqual({
    kind: 'task', callId: 'toolu_019ekANdDSU9vdwH1qKqmNq1', taskId: 'aea1aa9de8a2c258e', state: 'progress', agentType: 'general-purpose', text: 'Running List entries in current working directory', lastTool: 'Bash', tools: 1, tokens: 15111, ms: 1239,
  });
  // the ends: three completed (one after the turn's result), one stopped
  expect(events.filter((e) => e.state !== 'started' && e.state !== 'progress').map((e) => [e.taskId, e.state])).toEqual(
    lines.filter((line) => line.subtype === 'task_notification' && started.some((s) => s.task_id === line.task_id)).map((line) => [line.task_id, line.status]),
  );
  expect(events.filter((e) => e.state === 'stopped')).toEqual([expect.objectContaining({ callId: 'toolu_01LfpGpsC55uPcp3MTLtLGwE', taskId: 'af0d8b127fea03930', state: 'stopped' })]);
});

test('a turn the SDK opens by itself after a background subagent ended starts with `turn_start` at its `system/init`; a turn a message opened gives none', async () => {
  const events = await playWhole(sentSegments(subagentParts[0]!), 3);
  const marks = events.filter((e) => e.kind === 'turn_start' || e.kind === 'turn_end').map((e) => e.kind);
  // the first message's turn ends (222), then the SDK's own turn starts (230) and ends (275); the turns of the next messages (277, 356) are not announced
  expect(marks.slice(0, 3)).toEqual(['turn_end', 'turn_start', 'turn_end']);
  expect(marks.filter((kind) => kind === 'turn_start')).toHaveLength(1);
  // it comes after the subagent's end (228) and before the reply of the turn it opens
  const shown = events.filter((e) => e.kind !== 'background'); // the set of background tasks is also said when the subagent ends
  const start = shown.findIndex((e) => e.kind === 'turn_start');
  expect(shown[start - 1]).toMatchObject({ kind: 'task', state: 'completed' });
});

test('a field of the wrong type is left out of a task event and a shape the adapter does not know gives none and never throws', async () => {
  const end = main[0]!.lines.find((line) => line.type === 'result')!;
  const task = { type: 'system', session_id: 's', uuid: 'u' };
  const odd: Line[] = [
    { ...task, subtype: 'task_started', task_id: 'a', tool_use_id: 'call-a', task_type: 'local_agent', description: 5, subagent_type: {}, is_backgrounded: 'yes', parent_task_id: 7, usage: 'lots' },
    { ...task, subtype: 'task_progress', task_id: 'a', tool_use_id: 'call-a', description: 'step', last_tool_name: 4, usage: { total_tokens: '9', tool_uses: 2, duration_ms: null } },
    { ...task, subtype: 'task_started', task_type: 'local_agent', tool_use_id: 'call-b', description: 'no task id' },
    { ...task, subtype: 'task_started', task_id: 'c', task_type: 'local_agent', description: 'no call' },
    { ...task, subtype: 'task_started', task_id: 'd', tool_use_id: 'call-d', description: 'no type' },
    { ...task, subtype: 'task_progress', task_id: 'unknown', tool_use_id: 'call-u', description: 'never started' },
    { ...task, subtype: 'task_notification', task_id: 'a', tool_use_id: 'call-a', status: 'exploded' },
    { ...task, subtype: 'task_notification', task_id: 'a', tool_use_id: 'call-a', status: 'failed', usage: null },
    { ...task, subtype: 'task_updated', task_id: 'a' },
    { type: 'system', subtype: 'task_started' },
    end,
  ];
  const { conversation, events } = await openWith([{ text: 'go', lines: odd }]);
  const shown = await turn(conversation, events, 'go');
  expect(shown.filter((e) => e.kind !== 'turn_end')).toEqual([
    { kind: 'task', callId: 'call-a', taskId: 'a', state: 'started' },
    { kind: 'task', callId: 'call-a', taskId: 'a', state: 'progress', text: 'step', tools: 2 },
    { kind: 'task', callId: 'call-a', taskId: 'a', state: 'failed' },
  ]);
});

test('stopTask asks the SDK to stop the task with the id its task_started carried, and nothing else', async () => {
  const lines = subagentParts[0]!;
  const { conversation, events, seen } = await openWith(sentSegments(lines));
  answering(conversation);
  conversation.send(sentSegments(lines)[0]!.text);
  await vi.waitFor(() => expect(events.some((e) => e.kind === 'task' && e.state === 'started')).toBe(true));
  const started = events.find((e) => e.kind === 'task' && e.state === 'started' && e.text === 'Slow check')!;
  await conversation.stopTask!((started as { taskId: string }).taskId);
  expect(seen.calls.filter((call) => call.startsWith('stopTask'))).toEqual([`stopTask ${(started as { taskId: string }).taskId}`]);
});
