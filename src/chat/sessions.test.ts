import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { openChatDatabase } from './db.ts';
import { FakeChatRunner } from './fake.ts';
import { chatCaps } from './transcript.ts';
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
  const sessions = createSessions({ db, config, clock, runners: { claude }, env: { SOME: 'env' }, binaryFound: (command) => command === 'claude', onLiveChange });
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

test('agents lists the configured agents with whether the binary is found', () => {
  expect(setup().sessions.agents()).toEqual([
    { name: 'claude', harness: 'claude', found: true },
    { name: 'codex', harness: 'codex', found: false },
  ]);
  const { sessions } = setup({ agents: { mine: { harness: 'claude', command: 'claude', model: 'haiku' } } });
  expect(sessions.agents()).toEqual([{ name: 'mine', harness: 'claude', model: 'haiku', found: true }]);
});

test('open starts the agent in the real folder with the host environment and the chosen options, and lists the session', async () => {
  const { sessions, claude, onLiveChange } = setup({ agents: { claude: { harness: 'claude', model: 'haiku', options: { mode: 'plan' } } } });
  const opened = await sessions.open({ agent: 'claude', folder: work, options: { mode: 'default' } });
  expect(claude.opened).toEqual([{ folder: expect.stringContaining('work'), options: { model: 'haiku', mode: 'default' }, env: { SOME: 'env' } }]);
  expect(opened.session).toMatchObject({ agent: 'claude', harness: 'claude', state: 'idle', title: null, nativeId: null, archived: false });
  expect(onLiveChange).toHaveBeenCalled();
  expect(sessions.list({}).sessions.map((s) => s.id)).toEqual([opened.session.id]);
  expect(sessions.list({ archived: true }).sessions).toEqual([]);
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
