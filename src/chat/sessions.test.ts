import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { openChatDatabase } from './db.ts';
import { FakeChatRunner, FakeGit, type FakeConversation } from './fake.ts';
import { ChatRefused } from './runner.ts';
import { chatCaps } from './transcript.ts';
import { sessions as schemaSessions } from './schema.ts';
import { createSessions } from './sessions.ts';

let dir: string;
let work: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'ss-'));
  work = join(dir, 'work');
  mkdirSync(work);
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

const token = `ghp_${'a1B2'.repeat(9)}`;

function setup(chat?: Config['chat']) {
  const db = openChatDatabase(join(dir, 'chat.db'));
  const clock = new FakeClock();
  const claude = new FakeChatRunner();
  const onLiveChange = vi.fn();
  const config = { root: join(dir, 'root'), chat } as Config;
  const sessions = createSessions({ db, config, clock, runners: { claude }, env: { SOME: 'env' }, git: new FakeGit(), binaryFound: (command) => command === 'claude', onLiveChange });
  return { db, clock, claude, sessions, onLiveChange };
}
async function openOne(s = setup()) {
  const { session } = await s.sessions.open({ agent: 'claude', folder: work });
  return { ...s, id: session.id, conversation: s.claude.conversations[0]! };
}
const rows = (table: string) => {
  const raw = new Database(join(dir, 'chat.db'), { readonly: true });
  const found = raw.prepare(`select * from ${table}`).all() as any[];
  raw.close();
  return found;
};

test('a live session records its agent process and the record is cleared when it closes', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.process = { pid: 4242, pgid: 4242, command: '/bin/claude' });
  const { id } = await openOne(s);
  expect(rows('sessions')[0]).toMatchObject({ pid: 4242, pgid: 4242, command: '/bin/claude' });
  await s.sessions.close({ sessionId: id });
  expect(rows('sessions')[0]).toMatchObject({ pid: null, pgid: null, command: null });
});

test('agents lists the configured agents with whether the binary is found', () => {
  expect(setup().sessions.agents()).toEqual([
    { name: 'claude', harness: 'claude', found: true },
    { name: 'codex', harness: 'codex', found: false },
  ]);
  const { sessions } = setup({ agents: { mine: { harness: 'claude', command: 'claude', model: 'haiku' } } });
  expect(sessions.agents()).toEqual([{ name: 'mine', harness: 'claude', model: 'haiku', found: true }]);
});

const offering = (...options: [id: string, values: string[], current: string][]) => (conversation: FakeConversation) => {
  conversation.options = options.map(([id, values, current]) => ({ id, label: id.toUpperCase(), values: values.map((v) => ({ id: v, label: v })), current }));
};

test('open starts the agent in the real folder with the host environment and the chosen options, and lists the session', async () => {
  const { sessions, claude, onLiveChange } = setup({ agents: { claude: { harness: 'claude', model: 'haiku', options: { mode: 'plan' } } } });
  claude.setup = offering(['model', ['haiku', 'sonnet'], 'haiku'], ['mode', ['plan', 'default'], 'plan']);
  const opened = await sessions.open({ agent: 'claude', folder: work, options: { mode: 'default' } });
  expect(claude.opened).toEqual([{ folder: expect.stringContaining('work'), options: { model: 'haiku', mode: 'default' }, env: { SOME: 'env' } }]);
  expect(opened.session).toMatchObject({ agent: 'claude', harness: 'claude', state: 'idle', title: null, nativeId: null, archived: false });
  expect(onLiveChange).toHaveBeenCalled();
  expect(sessions.list({}).sessions.map((s) => s.id)).toEqual([opened.session.id]);
  expect(sessions.list({ archived: true }).sessions).toEqual([]);
});

test('open applies the options in order: the agent model, the agent options, then those of the request', async () => {
  const { sessions, claude } = setup({ agents: { claude: { harness: 'claude', model: 'haiku', options: { mode: 'plan', effort: 'low' } } } });
  claude.setup = offering(['model', ['haiku'], 'haiku'], ['mode', ['plan', 'default'], 'plan'], ['effort', ['low', 'high'], 'low']);
  const { session } = await sessions.open({ agent: 'claude', folder: work, options: { mode: 'default', effort: 'high' } });
  expect(Object.entries(claude.opened[0]!.options!)).toEqual([['model', 'haiku'], ['mode', 'default'], ['effort', 'high']]);
  expect(session.id).toBeDefined();
});

test('open refuses an option the adapter does not list and a value it does not offer, naming the option, and leaves nothing behind', async () => {
  const { sessions, claude, onLiveChange } = setup({ agents: { claude: { harness: 'claude', options: { speed: 'fast' } } } });
  claude.setup = offering(['model', ['haiku'], 'haiku']);
  await expect(sessions.open({ agent: 'claude', folder: work })).rejects.toThrow('no option "speed"');
  await expect(sessions.open({ agent: 'claude', folder: work, options: { speed: 'fast', model: 'gpt-5' } })).rejects.toThrow('no option "speed"');
  const other = setup();
  other.claude.setup = offering(['model', ['haiku'], 'haiku']);
  await expect(other.sessions.open({ agent: 'claude', folder: work, options: { model: 'gpt-5' } })).rejects.toThrow('"gpt-5" is not a value of the option "model"; it offers: haiku');
  expect(other.claude.conversations[0]!.closed).toBe(true); // the agent that was started is ended
  expect(claude.conversations.every((c) => c.closed)).toBe(true);
  expect(other.sessions.liveCount()).toBe(0);
  expect(rows('sessions')).toEqual([]);
  expect(onLiveChange).not.toHaveBeenCalled();
});

test('open refuses, in words, an unknown agent, a harness with no runner, a bad folder and a runner that refuses', async () => {
  const { sessions, claude } = setup();
  await expect(sessions.open({ agent: 'nope', folder: work })).rejects.toThrow('no chat agent named "nope"');
  await expect(sessions.open({ agent: 'codex', folder: work })).rejects.toThrow('no chat runner for codex');
  await expect(sessions.open({ agent: 'claude', folder: join(dir, 'missing') })).rejects.toThrow('does not exist');
  mkdirSync(join(dir, 'root', 'repos'), { recursive: true });
  await expect(sessions.open({ agent: 'claude', folder: join(dir, 'root', 'repos') })).rejects.toThrow('inside Carrier');
  claude.refuseWith = 'claude is not logged in';
  await expect(sessions.open({ agent: 'claude', folder: work })).rejects.toThrow('claude is not logged in');
  expect(rows('sessions')).toEqual([]);
});

test('a conversation over several turns: events come in order after the cursor, with state, title and the streaming text', async () => {
  const { sessions, conversation, id, clock } = await openOne();
  conversation.reply = (text, c) => {
    c.emit({ kind: 'delta', text: 'Hel' }, { kind: 'delta', text: 'lo' });
    c.nativeId = 'native-1';
  };
  clock.time = 1000;
  sessions.send({ sessionId: id, text: 'first line\nsecond line' });
  let reply = sessions.events({ sessionId: id, limit: 50 });
  expect(reply.events).toEqual([{ id: 1, at: 1000, kind: 'user', text: 'first line\nsecond line' }]); // a delta is never stored
  expect(reply.streaming).toBe('Hello');
  expect(reply.session).toMatchObject({ title: 'first line', state: 'working', lastActiveAt: 1000 });

  clock.time = 2500;
  conversation.emit(
    { kind: 'assistant', text: 'Hello there' },
    { kind: 'tool_start', callId: 'c1', tool: 'Bash', arg: 'ls' },
    { kind: 'tool_end', callId: 'c1', tool: 'Bash', output: ['a', 'b'], status: 'ok' },
    { kind: 'turn_end', outcome: 'ok', model: 'haiku', usage: { input: 10, output: 3 } },
  );
  reply = sessions.events({ sessionId: id, after: reply.cursor, limit: 50 });
  expect(reply.events.map((e) => [e.id, e.kind])).toEqual([[2, 'assistant'], [3, 'tool_start'], [4, 'tool_end'], [5, 'turn_end']]);
  expect(reply.events[2]).toMatchObject({ callId: 'c1', output: ['a', 'b'], status: 'ok' });
  expect(reply.cursor).toBe(5);
  expect(reply.streaming).toBe('');
  expect(reply.session).toMatchObject({ state: 'idle', nativeId: 'native-1', createdAt: 0, lastActiveAt: 2500 });
  expect(sessions.events({ sessionId: id, after: 5, limit: 50 })).toMatchObject({ events: [], cursor: 5 });
  expect(sessions.events({ sessionId: id, limit: 2 })).toMatchObject({ cursor: 2 });

  // the agent remembers: the second turn goes to the same conversation
  sessions.send({ sessionId: id, text: 'again' });
  expect(conversation.sent).toEqual(['first line\nsecond line', 'again']);
  expect(sessions.list({}).sessions[0]!.title).toBe('first line'); // the title is the first message's
});

test('options are those of the live conversation', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.options = [{ id: 'model', label: 'Model', values: [{ id: 'haiku', label: 'Haiku' }], current: 'haiku' }];
  expect(sessions.events({ sessionId: id, limit: 1 }).options).toEqual(conversation.options);
});

test('setOption changes an option of a live session: the adapter applies it, an option event is stored, and the reply and the events list the current values', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.options = [
    { id: 'mode', label: 'Mode', values: [{ id: 'plan', label: 'Plan' }, { id: 'default', label: 'Default' }], current: 'plan' },
    { id: 'model', label: 'Model', values: [{ id: 'haiku', label: 'Haiku' }], current: 'haiku' },
  ];
  const reply = await sessions.setOption({ sessionId: id, option: 'mode', value: 'default' });
  expect(reply.options.map((o) => [o.id, o.current])).toEqual([['mode', 'default'], ['model', 'haiku']]);
  const events = sessions.events({ sessionId: id, limit: 10 });
  expect(events.events).toMatchObject([{ kind: 'option', id: 'mode', value: 'default' }]);
  expect(events.options.map((o) => o.current)).toEqual(['default', 'haiku']);
  expect(rows('sessions')[0].options).toBe(JSON.stringify({ mode: 'default' })); // the session records the options it runs with
});

test('setOption refuses, with the reason and changing nothing, an unlisted option, a value not offered, a closed session and a missing one', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.options = [{ id: 'mode', label: 'Mode', values: [{ id: 'plan', label: 'Plan' }], current: 'plan' }];
  await expect(sessions.setOption({ sessionId: id, option: 'speed', value: 'fast' })).rejects.toThrow('no option "speed"');
  await expect(sessions.setOption({ sessionId: id, option: 'mode', value: 'yolo' })).rejects.toThrow('"yolo" is not a value of the option "mode"; it offers: plan');
  conversation.setOption = async () => {
    throw new ChatRefused('Only between turns');
  };
  await expect(sessions.setOption({ sessionId: id, option: 'mode', value: 'plan' })).rejects.toThrow('Only between turns');
  expect(sessions.events({ sessionId: id, limit: 10 }).events).toEqual([]);
  await sessions.close({ sessionId: id });
  await expect(sessions.setOption({ sessionId: id, option: 'mode', value: 'plan' })).rejects.toThrow('closed');
  await expect(sessions.setOption({ sessionId: '3f2b6a52-8f5e-4a63-9d5b-0a1d2c3e4f50', option: 'mode', value: 'plan' })).rejects.toThrow('no such session');
});

test('send refuses, with the reason, a message over 64,000 characters, a working session, a closed one and a missing one', async () => {
  const { sessions, conversation, id } = await openOne();
  expect(() => sessions.send({ sessionId: id, text: 'x'.repeat(64_001) })).toThrow('64000');
  expect(conversation.sent).toEqual([]);
  expect(() => sessions.send({ sessionId: 'nope', text: 'hi' })).toThrow('no such session');
  sessions.send({ sessionId: id, text: 'hi' });
  expect(() => sessions.send({ sessionId: id, text: 'again' })).toThrow('still answering');
  conversation.emit({ kind: 'turn_end', outcome: 'ok' });
  await sessions.close({ sessionId: id });
  expect(() => sessions.send({ sessionId: id, text: 'hi' })).toThrow('closed');
});

test('send tells the client when the agent cannot take the message, and the session stays usable', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.reply = () => {
    throw new Error('EPIPE with a path');
  };
  expect(() => sessions.send({ sessionId: id, text: 'hi' })).toThrow('could not be delivered');
  conversation.reply = () => {};
  expect(() => sessions.send({ sessionId: id, text: 'hi again' })).not.toThrow();
});

test('text is redacted and then cut: 64,000 for messages, 1,024 for an argument, the two halves of 4,096 for an output; the row holds no token', async () => {
  const { sessions, conversation, id } = await openOne();
  sessions.send({ sessionId: id, text: `my key is ${token}` });
  const big = `${token} ${'y'.repeat(70_000)}`;
  const output = `START${'z'.repeat(9000)}END`;
  conversation.emit(
    { kind: 'assistant', text: big },
    { kind: 'tool_start', callId: 'c', tool: 'Bash', arg: `curl -H "Authorization: Bearer ${token}" ${'a'.repeat(2000)}` },
    { kind: 'tool_end', callId: 'c', tool: 'Bash', output: [output] },
  );
  const stored = sessions.events({ sessionId: id, limit: 50 }).events as any[];
  expect(stored[0].text).toBe('my key is [redacted]');
  expect(stored[1].text).toHaveLength(chatCaps.message);
  expect(stored[1].text.startsWith('[redacted] yyy')).toBe(true);
  expect(stored[2].arg.length).toBeLessThanOrEqual(1024);
  expect(stored[2].arg).not.toContain(token);
  const lines: string[] = stored[3].output;
  expect(lines.join('\n').length).toBeLessThanOrEqual(4096 + 3);
  expect(lines[0]!.startsWith('START')).toBe(true);
  expect(lines.at(-1)!.endsWith('END')).toBe(true);
  expect(lines).toContain('…');
  expect(JSON.stringify(rows('chat_events'))).not.toContain(token);
  expect(JSON.stringify(rows('sessions'))).not.toContain(token);
});

test('a title is cut at 80 characters', async () => {
  const { sessions, id } = await openOne();
  sessions.send({ sessionId: id, text: `${'t'.repeat(200)}\nmore` });
  expect(sessions.list({}).sessions[0]!.title).toHaveLength(chatCaps.title);
});

test('each finished turn stores its model, outcome, duration, tool calls and the usage as given', async () => {
  const { sessions, conversation, id, clock } = await openOne();
  clock.time = 100;
  sessions.send({ sessionId: id, text: 'go' });
  clock.time = 1600;
  conversation.emit({ kind: 'tool_start', callId: '1', tool: 'Read' }, { kind: 'tool_end', callId: '1', tool: 'Read' }, { kind: 'tool_start', callId: '2', tool: 'Bash' });
  conversation.emit({ kind: 'turn_end', outcome: 'interrupted', model: 'sonnet', usage: { inputTokens: 5, cacheReadInputTokens: 7 } });
  expect(rows('chat_turns')).toEqual([
    { id: 1, sessionId: id, startedAt: 100, model: 'sonnet', outcome: 'interrupted', durationMs: 1500, toolCalls: 2, usage: '{"inputTokens":5,"cacheReadInputTokens":7}' },
  ]);
  sessions.send({ sessionId: id, text: 'next' });
  conversation.emit({ kind: 'turn_end', outcome: 'ok' });
  expect(rows('chat_turns')[1]).toMatchObject({ toolCalls: 0, model: null, usage: null, outcome: 'ok' });
});

test('an approval holds the session waiting, and it is not idle-closed while it waits or works', async () => {
  const { sessions, conversation, id, clock } = await openOne();
  sessions.send({ sessionId: id, text: 'touch it' });
  conversation.emit({ kind: 'approval', approvalId: 'a1', tool: 'Bash', arg: 'touch x', choices: [{ id: 'allow', label: 'Allow', allow: true }] });
  expect(sessions.events({ sessionId: id, limit: 10 }).session.state).toBe('waiting_approval');
  await clock.advance(10 * 60_000);
  expect(conversation.closed).toBe(false);
});

test('answer passes a listed choice to the agent once; an interrupted turn drops its pending approval; a closed session refuses', async () => {
  const { sessions, conversation, id } = await openOne();
  const choices = [{ id: 'allow', label: 'Allow', allow: true }, { id: 'deny', label: 'Deny', allow: false }];
  sessions.send({ sessionId: id, text: 'go' });
  conversation.emit({ kind: 'approval', approvalId: 'a1', tool: 'Bash', arg: `echo ${token}`, choices });
  expect(sessions.events({ sessionId: id, limit: 10 }).approvals).toEqual([{ approvalId: 'a1', tool: 'Bash', arg: expect.not.stringContaining(token), choices }]);
  expect(sessions.answer({ sessionId: id, approvalId: 'a1', choiceId: 'allow' })).toEqual({});
  expect(conversation.answers).toEqual([{ approvalId: 'a1', choiceId: 'allow' }]);
  expect(sessions.events({ sessionId: id, limit: 10 })).toMatchObject({ approvals: [], session: { state: 'working' } });
  conversation.emit({ kind: 'approval', approvalId: 'a2', tool: 'Bash', choices });
  conversation.emit({ kind: 'turn_end', outcome: 'interrupted' });
  expect(sessions.events({ sessionId: id, limit: 10 }).approvals).toEqual([]);
  expect(() => sessions.answer({ sessionId: id, approvalId: 'a2', choiceId: 'deny' })).toThrow('not pending');
  await sessions.close({ sessionId: id });
  expect(() => sessions.answer({ sessionId: id, approvalId: 'a2', choiceId: 'deny' })).toThrow('closed');
});

test('a live session that is idle with no client is closed after a minute: the runner closes it and the row stays; a working one is kept', async () => {
  const s = setup();
  const idleOne = await openOne(s);
  const { session: busy } = await s.sessions.open({ agent: 'claude', folder: work });
  s.sessions.send({ sessionId: busy.id, text: 'work' });
  s.onLiveChange.mockClear();
  await s.clock.advance(59_999);
  expect(idleOne.conversation.closed).toBe(false);
  await s.clock.advance(1);
  expect(idleOne.conversation.closed).toBe(true);
  expect(s.claude.conversations[1]!.closed).toBe(false);
  expect(s.sessions.liveCount()).toBe(1);
  expect(s.onLiveChange).toHaveBeenCalled();
  expect(rows('sessions').map((r) => r.id).sort()).toEqual([idleOne.id, busy.id].sort());
  expect(s.sessions.events({ sessionId: idleOne.id, limit: 1 }).options).toEqual([]); // closed: nothing live
  // the working one becomes idle when its turn ends, and then the minute runs
  s.claude.conversations[1]!.emit({ kind: 'turn_end', outcome: 'ok' });
  await s.clock.advance(60_000);
  expect(s.claude.conversations[1]!.closed).toBe(true);
});

test('with a client attached nothing is closed; the minute counts from the client leaving', async () => {
  const { sessions, conversation, clock } = await openOne();
  sessions.clientJoined();
  await clock.advance(10 * 60_000);
  expect(conversation.closed).toBe(false);
  sessions.clientLeft();
  await clock.advance(59_999);
  expect(conversation.closed).toBe(false);
  await clock.advance(1);
  expect(conversation.closed).toBe(true);
});

test('close keeps the row, ends the conversation once, and closeAll closes every live session', async () => {
  const s = setup();
  const a = await openOne(s);
  await s.sessions.open({ agent: 'claude', folder: work });
  await s.sessions.close({ sessionId: a.id });
  await s.sessions.close({ sessionId: a.id });
  expect(rows('sessions')).toHaveLength(2);
  await s.sessions.closeAll();
  expect(s.claude.conversations.map((c) => c.closed)).toEqual([true, true]);
  expect(s.sessions.liveCount()).toBe(0);
  await expect(s.sessions.close({ sessionId: 'nope' })).rejects.toThrow('no such session');
});

test('resume opens a closed session again from its native id, folder and options, keeps its title, and the context goes on', async () => {
  const s = setup({ agents: { claude: { harness: 'claude', model: 'haiku' } } });
  s.claude.setup = offering(['model', ['haiku'], 'haiku']);
  const { sessions, claude, conversation, id, clock } = await openOne(s);
  conversation.reply = (_text, c) => {
    c.nativeId = 'native-1';
    c.emit({ kind: 'assistant', text: 'ok' }, { kind: 'turn_end', outcome: 'ok' });
  };
  sessions.send({ sessionId: id, text: 'remember pineapple' });
  await sessions.close({ sessionId: id });
  expect(sessions.list({}).sessions[0]).toMatchObject({ live: false });
  clock.time = 5000;

  const resumed = await sessions.resume({ sessionId: id });
  expect(claude.opened[1]).toEqual({ folder: expect.stringContaining('work'), resume: 'native-1', options: { model: 'haiku' }, env: { SOME: 'env' } });
  expect(resumed.session).toMatchObject({ id, title: 'remember pineapple', nativeId: 'native-1', state: 'idle' });
  expect(sessions.list({}).sessions[0]).toMatchObject({ live: true });
  sessions.send({ sessionId: id, text: 'again' });
  expect(claude.conversations[1]!.sent).toEqual(['again']);
  expect(sessions.events({ sessionId: id, limit: 50 }).events.map((e) => e.kind)).toEqual(['user', 'assistant', 'turn_end', 'user']); // the transcript goes on from where it was
});

test('an agent that ends on its own ends the live session: idle, or mid-turn with the turn recorded as an error; resume then reopens from the native id', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.process = { pid: 4242, pgid: 4242, command: '/bin/claude' });
  const { sessions, claude, conversation, id, onLiveChange } = await openOne(s);
  conversation.reply = (_text, c) => {
    c.nativeId = 'native-1';
    c.emit({ kind: 'assistant', text: 'ok' }, { kind: 'turn_end', outcome: 'ok' });
  };
  sessions.send({ sessionId: id, text: 'hello' });

  // idle: the process dies between turns
  onLiveChange.mockClear();
  conversation.die({ kind: 'error', text: 'The Claude process ended' });
  await vi.waitFor(() => expect(sessions.liveCount()).toBe(0));
  expect(onLiveChange).toHaveBeenCalled();
  expect(conversation.closed).toBe(true); // what the agent left behind is ended too
  expect(rows('sessions')[0]).toMatchObject({ state: 'idle', pid: null, pgid: null, command: null });
  expect(() => sessions.send({ sessionId: id, text: 'again' })).toThrow('This session is closed');

  // the resume opens the conversation again from the native id instead of attaching to the dead one
  await sessions.resume({ sessionId: id });
  expect(claude.opened[1]).toMatchObject({ resume: 'native-1' });
  const second = claude.conversations[1]!;

  // mid-turn: the adapter says the error and the end of the turn, and the host drops the session once
  sessions.send({ sessionId: id, text: 'work' });
  second.die({ kind: 'error', text: 'The Claude process ended' }, { kind: 'turn_end', outcome: 'error' });
  await vi.waitFor(() => expect(sessions.liveCount()).toBe(0));
  expect(rows('chat_turns').map((t) => t.outcome)).toEqual(['ok', 'error']);
  expect(sessions.events({ sessionId: id, limit: 50 })).toMatchObject({ session: { state: 'idle' }, approvals: [], streaming: '' });

  // an adapter that does not say the turn ended: the host records it
  await sessions.resume({ sessionId: id });
  sessions.send({ sessionId: id, text: 'more' });
  claude.conversations[2]!.die();
  await vi.waitFor(() => expect(sessions.liveCount()).toBe(0));
  expect(rows('chat_turns').map((t) => t.outcome)).toEqual(['ok', 'error', 'error']);
});

test('resume of a live session just attaches: no second conversation', async () => {
  const { sessions, claude, id } = await openOne();
  const resumed = await sessions.resume({ sessionId: id });
  expect(resumed.session.id).toBe(id);
  expect(claude.opened).toHaveLength(1);
});

test('resume of a session that never got a native id starts it again as it was opened', async () => {
  const { sessions, claude, id } = await openOne();
  await sessions.close({ sessionId: id });
  await sessions.resume({ sessionId: id });
  expect(claude.opened[1]).not.toHaveProperty('resume');
});

test('resume refuses, in words, an unknown session, a provider that does not know the id any more, a folder that is gone and an agent no longer configured', async () => {
  const { sessions, claude, id, db } = await openOne();
  db.update(schemaSessions).set({ nativeId: 'gone' }).run();
  await sessions.close({ sessionId: id });
  await expect(sessions.resume({ sessionId: 'nope' })).rejects.toThrow('no such session');
  claude.refuseWith = 'Claude could not resume that conversation';
  await expect(sessions.resume({ sessionId: id })).rejects.toThrow('could not resume');
  expect(claude.conversations).toHaveLength(1); // nothing was left live
  expect(sessions.liveCount()).toBe(0);
  claude.refuseWith = undefined;
  rmSync(work, { recursive: true });
  await expect(sessions.resume({ sessionId: id })).rejects.toThrow('does not exist');
  mkdirSync(work);
  db.update(schemaSessions).set({ agent: 'gone' }).run();
  await expect(sessions.resume({ sessionId: id })).rejects.toThrow('not configured any more');
});

test('an option changed during a session is the one a resume opens with', async () => {
  const { sessions, claude, id } = await openOne();
  claude.setup = offering(['mode', ['plan', 'default'], 'default']);
  await sessions.close({ sessionId: id });
  const reopened = await sessions.resume({ sessionId: id });
  expect(reopened.options.map((o) => o.id)).toEqual(['mode']);
  await sessions.setOption({ sessionId: id, option: 'mode', value: 'plan' });
  await sessions.close({ sessionId: id });
  await sessions.resume({ sessionId: id });
  expect(claude.opened[2]).toMatchObject({ options: { mode: 'plan' } });
});

test('two resumes of one closed session leave one live conversation', async () => {
  const { sessions, claude, id } = await openOne();
  await sessions.close({ sessionId: id });
  await Promise.all([sessions.resume({ sessionId: id }), sessions.resume({ sessionId: id })]);
  expect(sessions.liveCount()).toBe(1);
  expect(claude.conversations.map((c) => c.closed)).toEqual([true, false, true]); // the late one is closed
});

test('an interrupt ends the running turn as interrupted and the session takes the next message; with no turn it changes nothing', async () => {
  const { sessions, conversation, id, clock } = await openOne();
  expect(await sessions.interrupt({ sessionId: id })).toEqual({});
  expect(conversation.interrupts).toBe(0);
  expect(rows('chat_turns')).toEqual([]);

  clock.time = 100;
  sessions.send({ sessionId: id, text: 'count to 400' });
  clock.time = 700;
  expect(await sessions.interrupt({ sessionId: id })).toEqual({}); // this adapter never says the turn ended: the host records it
  expect(conversation.interrupts).toBe(1);
  expect(sessions.events({ sessionId: id, limit: 10 }).session.state).toBe('idle');
  expect(sessions.events({ sessionId: id, limit: 10 }).events.map((e) => [e.kind, (e as any).outcome])).toEqual([['user', undefined], ['turn_end', 'interrupted']]);
  expect(rows('chat_turns')).toMatchObject([{ outcome: 'interrupted', durationMs: 600 }]);

  sessions.send({ sessionId: id, text: 'next' });
  conversation.emit({ kind: 'turn_end', outcome: 'ok' });
  expect(rows('chat_turns').map((t) => t.outcome)).toEqual(['interrupted', 'ok']);
});

test('an adapter that ends the turn on interrupt is recorded once, and a waiting approval is interrupted too', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.onInterrupt = (c) => c.emit({ kind: 'turn_end', outcome: 'interrupted', model: 'sonnet' });
  sessions.send({ sessionId: id, text: 'touch it' });
  conversation.emit({ kind: 'approval', approvalId: 'a1', tool: 'Bash', choices: [] });
  expect(sessions.events({ sessionId: id, limit: 10 }).session.state).toBe('waiting_approval');
  await sessions.interrupt({ sessionId: id });
  conversation.emit({ kind: 'turn_end', outcome: 'interrupted' }); // a late duplicate
  expect(rows('chat_turns')).toMatchObject([{ outcome: 'interrupted', model: 'sonnet' }]);
  expect(sessions.events({ sessionId: id, limit: 10 }).session.state).toBe('idle');
});

test('an interrupt on a closed session is ok and changes nothing; on an unknown one it is refused', async () => {
  const { sessions, conversation, id } = await openOne();
  await sessions.close({ sessionId: id });
  expect(await sessions.interrupt({ sessionId: id })).toEqual({});
  expect(conversation.interrupts).toBe(0);
  await expect(sessions.interrupt({ sessionId: '3b241101-e2bb-4255-8caf-4136c566a962' })).rejects.toThrow('no such session');
});

const say = (conversation: FakeConversation, sessions: ReturnType<typeof setup>['sessions'], id: string) => {
  conversation.reply = (_text, c) => c.emit({ kind: 'assistant', text: 'hi' }, { kind: 'tool_start', callId: 'c', tool: 'Bash' }, { kind: 'turn_end', outcome: 'ok' });
  sessions.send({ sessionId: id, text: 'hello' });
};

test('archive marks a session and the archived listing shows it instead of the others; unarchive brings it back', async () => {
  const s = setup();
  const a = await openOne(s);
  const b = (await s.sessions.open({ agent: 'claude', folder: work })).session.id;
  await s.sessions.archive({ sessionId: a.id, archived: true });
  expect(s.sessions.list({}).sessions.map((x) => x.id)).toEqual([b]);
  expect(s.sessions.list({ archived: true }).sessions.map((x) => x.id)).toEqual([a.id]);
  expect(s.sessions.list({ archived: true }).sessions[0]).toMatchObject({ archived: true, live: false });
  await s.sessions.archive({ sessionId: a.id, archived: false });
  expect(s.sessions.list({ archived: true }).sessions).toEqual([]);
  expect(s.sessions.list({}).sessions).toHaveLength(2);
});

test('archive and delete close a live idle session first', async () => {
  const s = setup();
  const a = await openOne(s);
  await s.sessions.archive({ sessionId: a.id, archived: true });
  expect(a.conversation.closed).toBe(true);
  expect(s.sessions.liveCount()).toBe(0);
  const b = await s.sessions.open({ agent: 'claude', folder: work });
  await s.sessions.delete({ sessionId: b.session.id });
  expect(s.claude.conversations[1]!.closed).toBe(true);
  expect(s.sessions.liveCount()).toBe(0);
});

test('delete leaves nothing of the session in sessions, chat_events or chat_turns, and keeps the others', async () => {
  const s = setup();
  const a = await openOne(s);
  const b = await s.sessions.open({ agent: 'claude', folder: work });
  say(a.conversation, s.sessions, a.id);
  s.claude.conversations[1]!.reply = (_t, c) => c.emit({ kind: 'turn_end', outcome: 'ok' });
  s.sessions.send({ sessionId: b.session.id, text: 'other' });
  expect(rows('chat_events')).toHaveLength(6);
  expect(rows('chat_turns')).toHaveLength(2);
  await s.sessions.delete({ sessionId: a.id });
  expect(rows('sessions').map((r) => r.id)).toEqual([b.session.id]);
  expect(rows('chat_events').map((r) => r.sessionId)).toEqual([b.session.id, b.session.id]);
  expect(rows('chat_turns').map((r) => r.sessionId)).toEqual([b.session.id]);
  expect(() => s.sessions.events({ sessionId: a.id, limit: 5 })).toThrow('no such session');
});

test('archive and delete refuse a working session and one waiting for an approval, with the reason, and change nothing', async () => {
  const s = setup();
  const a = await openOne(s);
  a.conversation.reply = () => {};
  s.sessions.send({ sessionId: a.id, text: 'go' });
  for (const attempt of [() => s.sessions.archive({ sessionId: a.id, archived: true }), () => s.sessions.delete({ sessionId: a.id })]) {
    await expect(attempt()).rejects.toThrow(/working; interrupt or close it first/);
  }
  a.conversation.emit({ kind: 'approval', approvalId: 'p', tool: 'Bash', choices: [] });
  await expect(s.sessions.delete({ sessionId: a.id })).rejects.toThrow(/waiting for an approval; interrupt or close it first/);
  await expect(s.sessions.archive({ sessionId: a.id, archived: true })).rejects.toBeInstanceOf(ChatRefused);
  expect(rows('sessions')).toHaveLength(1);
  expect(rows('sessions')[0]!.archived).toBe(0);
  expect(rows('chat_events').length).toBeGreaterThan(0);
  expect(a.conversation.closed).toBe(false);
});

test('archive, unarchive and delete refuse an unknown session in words', async () => {
  const { sessions } = setup();
  for (const attempt of [sessions.archive({ sessionId: 'nope', archived: true }), sessions.archive({ sessionId: 'nope', archived: false }), sessions.delete({ sessionId: 'nope' })]) {
    await expect(attempt).rejects.toThrow('There is no such session');
  }
});
