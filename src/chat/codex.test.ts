import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { FakeGit } from './fake.ts';
import { codexChatRunner, realCodexDeps, type CodexChatDeps, type CodexTransport } from './codex.ts';
import { openChatDatabase } from './db.ts';
import { endGroup } from './group.ts';
import { ChatRefused, type ChatConversation, type ChatEvent } from './runner.ts';
import { createSessions } from './sessions.ts';

// The adapter replayed against the spike's recording of a real conversation (docs/research/chat-spike/): only the
// transport, the lines of `codex app-server`, is faked. The recording plays what the real Codex said each time the
// adapter writes what the recording shows it wrote; a write that is not in the recording is collected in `unexpected`.

type Line = Record<string, any>;

const recording = readFileSync(join(import.meta.dirname, '../../docs/research/chat-spike/codex-conversation.fixture.jsonl'), 'utf8')
  .trimEnd()
  .split('\n')
  .map((line) => JSON.parse(line) as Line);
const processes = recording.reduce<Line[][]>((all, line) => (line.host === 'recording' ? [...all, [line]] : (all.at(-1)!.push(line), all)), []);
const [main, resumed, cancelled] = processes as [Line[], Line[], Line[]];
const textsOf = (lines: Line[]) => lines.filter((line) => line.host === 'turnStarted').map((line) => line.text as string);
const mainTexts = textsOf(main);
const threadId = main.find((line) => line.host === 'threadId')!.id as string;
const recordedOut = (lines: Line[], method: string) => lines.find((line) => line.dir === 'out' && line.method === method)!;

function replay(lines: Line[]) {
  let cursor = 0;
  const ids = new Map<number, number>(); // the recording's request id -> the adapter's
  const seen = { written: [] as Line[], unexpected: [] as string[] };
  let listener: (line: string) => void = () => {};
  let exited: () => void = () => {};
  const play = (message: Line) => listener(JSON.stringify(message));
  /** Plays what the server said until the recording shows the adapter writing again. */
  const advance = () => {
    while (cursor < lines.length && lines[cursor]!.dir !== 'out') {
      const line = lines[cursor++]!;
      if (line.dir !== 'in') continue;
      const { dir: _dir, emittedAtMs: _at, ...message } = line;
      play(message.method === undefined && message.id !== undefined ? { ...message, id: ids.get(message.id) ?? message.id } : message);
    }
  };
  const transport: CodexTransport & { play: typeof play; raw: (line: string) => void; exit: () => void } = {
    pid: undefined,
    play,
    raw: (line) => listener(line),
    exit: () => exited(),
    onLine: (l) => void (listener = l),
    onExit: (l) => void (exited = l),
    write(text) {
      const message = JSON.parse(text) as Line;
      seen.written.push(message);
      const next = lines[cursor];
      if (message.method === undefined && next?.dir === 'out' && next.method === undefined) {
        if (JSON.stringify(next.result) === JSON.stringify(message.result)) cursor++;
        else seen.unexpected.push(`answer ${text}`);
      } else if (message.method === 'initialized') {
        cursor++;
      } else if (message.method !== undefined && next?.dir === 'out' && next.method === message.method && (message.method !== 'turn/start' || next.params.input[0].text === message.params.input[0].text)) {
        cursor++;
        ids.set(next.id, message.id);
      } else if (message.method === 'model/list') {
        // The lists were recorded in a process of their own.
        const asked = recordedOut(recording, 'model/list');
        const answer = recording.find((line) => line.dir === 'in' && line.id === asked.id && line.result?.data)!;
        play({ id: message.id, result: answer.result });
        return;
      } else if (message.method === 'thread/resume' && message.params.threadId === 'unknown') {
        play({ id: message.id, error: { code: -32600, message: 'no rollout found' } });
        return;
      } else {
        seen.unexpected.push(text);
        return;
      }
      advance();
    },
  };
  advance();
  return { transport, seen };
}

const deps = (transport: CodexTransport, over: Partial<CodexChatDeps> = {}): CodexChatDeps => ({ resolve: (command) => command ?? '/bin/codex', loggedIn: async () => true, spawn: () => transport, ...over });
const openWith = async (lines: Line[], args: { resume?: string; options?: Record<string, string> } = {}) => {
  const { transport, seen } = replay(lines);
  const conversation = await codexChatRunner(deps(transport)).open({ folder: '/work', env: { A: 'b' }, ...args });
  const events: ChatEvent[] = [];
  conversation.onEvent((event) => events.push(event));
  return { conversation, events, seen, transport };
};
/** Sends a message and resolves with the events of that turn. */
async function turn(conversation: ChatConversation, events: ChatEvent[], text: string) {
  const from = events.length;
  conversation.send(text);
  await vi.waitFor(() => expect(events.slice(from).some((e) => e.kind === 'turn_end')).toBe(true));
  return events.slice(from);
}
/** Answers every approval as the person would: with the choice in `choice.id`. */
const answering = (conversation: ChatConversation, choice = { id: 'accept' }) => {
  conversation.onEvent((e) => e.kind === 'approval' && queueMicrotask(() => conversation.answer(e.approvalId, choice.id)));
  return choice;
};
const texts = (events: ChatEvent[]) => events.filter((e) => e.kind === 'assistant').map((e) => (e as { text: string }).text);

test('the recorded conversation: remembers across turns, streams, and every turn ends with its model and usage', async () => {
  const { conversation, events, seen } = await openWith(main, { options: { model: 'gpt-5.6-luna' } });
  expect(seen.written.find((m) => m.method === 'thread/start')!.params).toEqual(recordedOut(main, 'thread/start').params);
  expect(conversation.nativeId).toBe(threadId);

  await conversation.setOption('effort', 'low');
  const first = await turn(conversation, events, mainTexts[0]!);
  expect(seen.written.find((m) => m.method === 'turn/start')!.params).toEqual(recordedOut(main, 'turn/start').params); // the effort rode with the first turn
  expect(first.filter((e) => e.kind === 'delta')).toEqual([{ kind: 'delta', text: 'OK' }]);
  expect(first.filter((e) => e.kind !== 'delta' && e.kind !== 'option')).toEqual([
    { kind: 'assistant', text: 'OK' },
    { kind: 'turn_end', outcome: 'ok', model: 'gpt-5.6-luna', usage: expect.objectContaining({ totalTokens: 18291, outputTokens: 5 }) },
  ]);

  const second = await turn(conversation, events, mainTexts[1]!);
  expect(texts(second)).toEqual(['PINEAPPLE']);
  expect(second.filter((e) => e.kind === 'delta').map((e) => (e as { text: string }).text).join('')).toBe('PINEAPPLE');
  expect(second.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok', usage: expect.objectContaining({ totalTokens: 23163 }) });
  expect(seen.unexpected).toEqual([]);
});

test('an approval is asked with the provider choices; an allow runs the command', async () => {
  const { conversation, events, seen } = await openWith(main);
  answering(conversation);
  for (const text of mainTexts.slice(0, 2)) await turn(conversation, events, text);

  const allowed = await turn(conversation, events, mainTexts[2]!);
  expect(allowed.find((e) => e.kind === 'approval')).toEqual({
    kind: 'approval',
    approvalId: '0',
    tool: 'command',
    arg: "/bin/zsh -lc 'touch allowed.txt'",
    choices: [
      { id: 'accept', label: 'Allow', allow: true },
      { id: 'decline', label: 'Deny', allow: false },
      { id: 'amend', label: 'Always allow touch allowed.txt', allow: true },
      { id: 'cancel', label: 'Deny and stop the turn', allow: false },
    ],
  });
  expect(allowed.filter((e) => e.kind === 'approval_answered')).toEqual([{ kind: 'approval_answered', approvalId: '0', choiceId: 'accept' }]);
  expect(allowed.filter((e) => e.kind === 'tool_start' || e.kind === 'tool_end')).toEqual([
    { kind: 'tool_start', callId: expect.any(String), tool: 'command', arg: "/bin/zsh -lc 'touch allowed.txt'" },
    { kind: 'tool_end', callId: expect.any(String), tool: 'command', status: 'ok' },
  ]);
  expect(texts(allowed)).toEqual(['I’ll create the requested file in the workspace.', 'DONE']);
  expect(allowed.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
  expect(seen.unexpected).toEqual([]);
});

test('a decline is honoured and the next message goes on; an approval that is not pending cannot be answered', async () => {
  const { conversation, events, seen } = await openWith(main);
  const choice = answering(conversation);
  for (const text of mainTexts.slice(0, 3)) await turn(conversation, events, text);
  choice.id = 'decline';
  const declined = await turn(conversation, events, mainTexts[3]!);
  expect(declined.filter((e) => e.kind === 'tool_end')).toMatchObject([{ status: 'err' }]);
  expect(texts(declined)).toContain('REFUSED');
  expect(declined.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
  expect(() => conversation.answer('9', 'accept')).toThrow(ChatRefused);
  expect(seen.unexpected).toEqual([]);
});

test('the cancel choice denies and ends the turn as interrupted, and the session takes the next message', async () => {
  const { conversation, events, seen } = await openWith(cancelled);
  answering(conversation, { id: 'cancel' });
  const cancelledTurn = await turn(conversation, events, textsOf(cancelled)[0]!);
  expect(cancelledTurn.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'interrupted' });
  expect(cancelledTurn.some((e) => e.kind === 'error')).toBe(false);
  expect(texts(await turn(conversation, events, textsOf(cancelled)[1]!))).toEqual(['STILL-ALIVE']);
  expect(seen.unexpected).toEqual([]);
});

test('options are listed, change from the next turn, an interrupt ends the turn as interrupted and the session takes the next message', async () => {
  const { conversation, events, seen } = await openWith(main);
  const choice = answering(conversation);
  for (const text of mainTexts.slice(0, 4)) {
    if (text === mainTexts[3]) choice.id = 'decline';
    await turn(conversation, events, text);
  }
  const byId = (id: string) => conversation.options.find((o) => o.id === id)!;
  expect(byId('approvalPolicy')).toMatchObject({ current: 'untrusted', values: [{ id: 'untrusted' }, { id: 'on-request' }, { id: 'never' }] });
  expect(byId('sandbox')).toMatchObject({ current: 'workspace-write', values: [{ id: 'read-only' }, { id: 'workspace-write' }] });
  expect(byId('model').values.map((v) => v.id)).toEqual(['gpt-5.6-terra', 'gpt-5.6-luna']);
  expect(byId('model').current).toBe('gpt-5.6-luna');
  expect(byId('effort').values.map((v) => v.id)).toEqual(['low', 'medium', 'high', 'xhigh', 'max']);

  await conversation.setOption('model', 'gpt-5.6-terra');
  await conversation.setOption('approvalPolicy', 'on-request');
  await conversation.setOption('sandbox', 'read-only');
  await expect(conversation.setOption('model', 'gpt-5')).rejects.toThrow(ChatRefused);
  await expect(conversation.setOption('speed', 'fast')).rejects.toThrow(ChatRefused);
  expect(seen.written.filter((m) => m.method === 'turn/start')).toHaveLength(4); // nothing was sent yet
  expect(events.filter((e) => e.kind === 'option')).toEqual([
    { kind: 'option', id: 'model', value: 'gpt-5.6-terra' },
    { kind: 'option', id: 'approvalPolicy', value: 'on-request' },
    { kind: 'option', id: 'sandbox', value: 'read-only' },
  ]);

  await turn(conversation, events, mainTexts[4]!);
  expect(seen.written.filter((m) => m.method === 'turn/start').at(-1)!.params).toMatchObject({ model: 'gpt-5.6-terra', approvalPolicy: 'on-request', sandboxPolicy: { type: 'readOnly' } });
  await conversation.setOption('model', 'gpt-5.6-luna');
  const from = events.length;
  conversation.send(mainTexts[5]!);
  await vi.waitFor(() => expect(events.slice(from).some((e) => e.kind === 'delta')).toBe(true)); // the turn is running
  expect(seen.written.filter((m) => m.method === 'turn/start').at(-1)!.params).toMatchObject({ model: 'gpt-5.6-luna' });
  await conversation.interrupt(); // resolves once the turn has ended
  expect(events.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'interrupted' });
  expect(events.slice(from).some((e) => e.kind === 'error')).toBe(false);
  expect(seen.written.find((m) => m.method === 'turn/interrupt')!.params).toEqual(recordedOut(main, 'turn/interrupt').params);

  expect(texts(await turn(conversation, events, mainTexts[6]!))).toEqual(['AFTER-INTERRUPT-OK']);
  expect(seen.unexpected).toEqual([]);
});

test('a model that does not list the current reasoning effort brings its own default', async () => {
  const { conversation, events } = await openWith(main);
  await conversation.setOption('model', 'gpt-5.6-terra');
  await conversation.setOption('effort', 'ultra');
  events.length = 0;
  await conversation.setOption('model', 'gpt-5.6-luna');
  expect(events).toEqual([
    { kind: 'option', id: 'model', value: 'gpt-5.6-luna' },
    { kind: 'option', id: 'effort', value: 'medium' },
  ]);
  expect(conversation.options.find((o) => o.id === 'effort')).toMatchObject({ current: 'medium' });
});

test('a conversation resumes by the native id and keeps the context', async () => {
  const { conversation, events, seen } = await openWith(resumed, { resume: threadId, options: { model: 'gpt-5.6-luna' } });
  expect(conversation.nativeId).toBe(threadId);
  expect(seen.written.find((m) => m.method === 'thread/resume')!.params).toEqual(recordedOut(resumed, 'thread/resume').params);
  expect(texts(await turn(conversation, events, textsOf(resumed)[0]!))).toEqual(['PINEAPPLE']);
  expect(seen.unexpected).toEqual([]);
});

test('a line it does not know is ignored and never throws; a server request it does not know is answered', async () => {
  const { conversation, events, seen, transport } = await openWith(main);
  const before = seen.written.length;
  for (const line of ['not json', '[]', 'null', '{"method":7}', '{"id":99,"result":1}', '{"method":"brand/new","params":5}', '{"method":"item/completed","params":{"item":7}}', '{"method":"item/started","params":{"item":{"type":"commandExecution"}}}', '{"method":"thread/tokenUsage/updated","params":{"tokenUsage":"x"}}', '{"method":"turn/completed"}'])
    transport.raw(line); // the last one is a turn that ends with no status: the only line here that gives events
  expect(events).toEqual([{ kind: 'error', text: 'The turn failed' }, { kind: 'turn_end', outcome: 'error', model: 'gpt-5.6-luna', usage: {} }]);
  transport.play({ id: 77, method: 'item/fileChange/requestApproval', params: {} });
  transport.play({ id: 78, method: 'mcpServer/elicitation/request', params: null });
  expect(seen.written.slice(before)).toEqual([
    { id: 77, error: { code: -32601, message: expect.stringContaining('item/fileChange/requestApproval') } },
    { id: 78, error: { code: -32601, message: expect.any(String) } },
  ]);
  expect(conversation.options.length).toBeGreaterThan(0);
});

test('open rejects with a reason when Codex is not installed, not logged in, or does not start or resume', async () => {
  const { transport } = replay(main);
  const open = (over: Partial<CodexChatDeps>, args: { command?: string; resume?: string } = {}) => codexChatRunner(deps(transport, over)).open({ folder: '/work', env: {}, ...args });
  const notThere = () => {
    throw new Error('nope');
  };
  await expect(open({ resolve: notThere })).rejects.toThrow(/not installed.*"codex"/);
  await expect(open({ resolve: notThere }, { command: '/x/codex' })).rejects.toThrow(/"\/x\/codex" cannot be run/);
  await expect(open({ loggedIn: async () => false })).rejects.toThrow(/not logged in/);
  const dies = { onLine() {}, write: () => dies.end(), end: () => {}, onExit: (l: () => void) => void (dies.end = l) } as CodexTransport & { end: () => void };
  await expect(open({ spawn: () => dies })).rejects.toThrow(/^Codex could not be started$/);
  await expect(open({ spawn: () => replay(main).transport }, { resume: 'unknown' })).rejects.toThrow(/could not resume/);
  const refused = await open({ resolve: notThere }).catch((error: unknown) => error);
  expect(refused).toBeInstanceOf(ChatRefused);
});

test('the process ending on its own ends the running turn as an error', async () => {
  const { conversation, events, transport } = await openWith(main);
  const from = events.length;
  const ended = vi.fn();
  conversation.onEnd(ended);
  conversation.send('hi'); // nothing in the recording answers it: the process dies instead
  transport.exit();
  expect(events.slice(from)).toEqual([{ kind: 'error', text: 'The Codex process ended' }, { kind: 'turn_end', outcome: 'error', model: 'gpt-5.6-luna' }]);
  expect(ended).toHaveBeenCalledTimes(1);
});

test('the conversation reports the process it started as the leader of its own group, with the command', async () => {
  const { transport } = replay(main);
  const conversation = await codexChatRunner(deps(Object.assign(transport, { pid: 777 }))).open({ folder: '/work', env: {} });
  expect(conversation.process).toEqual({ pid: 777, pgid: 777, command: '/bin/codex' });
  expect((await openWith(main)).conversation.process).toBeUndefined();
});

// Through the host's sessions, over a temporary SQLite: the person's message, the agent's and the turn are stored, and the native id lands on the session.
let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'cx-'));
  mkdirSync(join(dir, 'work'));
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

test('the host stores the transcript of the replayed conversation and the native thread id', async () => {
  const db = openChatDatabase(join(dir, 'chat.db'));
  const runner = codexChatRunner(deps(replay(main).transport));
  const sessions = createSessions({ db, config: { root: join(dir, 'root') } as Config, clock: new FakeClock(), runners: { codex: runner }, env: {}, git: new FakeGit(), binaryFound: () => true, onLiveChange: () => {} });
  const { session } = await sessions.open({ agent: 'codex', folder: join(dir, 'work') });
  for (const text of mainTexts.slice(0, 2)) {
    sessions.send({ sessionId: session.id, text });
    await vi.waitFor(() => expect(sessions.events({ sessionId: session.id, limit: 1 }).session.state).toBe('idle'));
  }
  const { events, session: after } = sessions.events({ sessionId: session.id, limit: 200 });
  expect(after.nativeId).toBe(threadId);
  expect(events.map((e) => e.kind)).toEqual(['user', 'assistant', 'turn_end', 'user', 'assistant', 'turn_end']);
  await sessions.closeAll();
  db.$client.close();
});

test('the real transport starts "<binary> app-server" as the leader of its own group, and reports its lines and its end', async () => {
  const binary = join(dir, 'fake-codex');
  writeFileSync(binary, '#!/bin/sh\necho "{\\"args\\":\\"$*\\"}"\nsleep 30\n');
  chmodSync(binary, 0o755);
  const transport = realCodexDeps.spawn(binary, { cwd: dir, env: process.env });
  const lines: string[] = [];
  transport.onLine((line) => lines.push(line));
  await vi.waitFor(() => expect(lines).toEqual(['{"args":"app-server"}']));
  expect(execFileSync('ps', ['-o', 'pgid=', '-p', String(transport.pid)], { encoding: 'utf8' }).trim()).toBe(String(transport.pid));
  const ended = new Promise<void>((resolve) => transport.onExit(resolve));
  await endGroup(transport.pid!);
  await ended;

  const missing = realCodexDeps.spawn(join(dir, 'nothing-here'), { cwd: dir, env: process.env });
  await new Promise<void>((resolve) => missing.onExit(resolve));
});
