import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { eq } from 'drizzle-orm';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { ChatAgent } from './config.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { openChatDatabase } from './db.ts';
import { FakeChatRunner, FakeGit, fakeProjects, type FakeConversation, type FakeRepo } from './fake.ts';
import { ChatRefused } from './runner.ts';
import { chatCaps } from './transcript.ts';
import { sessions as schemaSessions } from './schema.ts';
import type { HealthProbes } from './health.ts';
import { createSessions, type SessionAges } from './sessions.ts';

let dir: string;
let work: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), 'ss-'));
  work = join(dir, 'work');
  mkdirSync(work);
  vi.stubEnv('CARRIER_HOME', join(dir, 'home'));
});
afterEach(() => {
  rmSync(dir, { recursive: true, force: true });
  vi.unstubAllEnvs();
});

const token = `ghp_${'a1B2'.repeat(9)}`;

function setup(chat?: { agents: Record<string, Omit<ChatAgent, 'name'>> }, extra: Partial<Parameters<typeof createSessions>[0]> = {}) {
  const agents = Object.entries(chat?.agents ?? { claude: { harness: 'claude' }, codex: { harness: 'codex' } }).map(([name, agent]) => ({ name, ...agent }) as ChatAgent);
  const db = openChatDatabase(join(dir, 'chat.db'));
  const clock = new FakeClock();
  const claude = new FakeChatRunner();
  const onLiveChange = vi.fn();
  const git = extra.git ?? new FakeGit();
  const sessions = createSessions({ db, agents, clock, runners: { claude }, env: { SOME: 'env' }, git, projects: fakeProjects(git, clock), binaryFound: (command) => command === 'claude', ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange, ...extra });
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
  mkdirSync(join(dir, 'home', 'engine', 'repos'), { recursive: true });
  await expect(sessions.open({ agent: 'claude', folder: join(dir, 'home', 'engine', 'repos') })).rejects.toThrow('inside Carrier');
  claude.refuseWith = 'claude is not logged in';
  await expect(sessions.open({ agent: 'claude', folder: work })).rejects.toThrow('claude is not logged in');
  expect(rows('sessions')).toEqual([]);
});

test('reasoning is stored redacted and bounded, and served only to a client that asks for it', async () => {
  const { sessions, conversation, id } = await openOne();
  const token = 'ghp_' + 'a'.repeat(36);
  sessions.send({ sessionId: id, text: 'hi' });
  conversation.emit({ kind: 'reasoning', text: `my token is ${token}` }, { kind: 'assistant', text: 'Hello' }, { kind: 'turn_end', outcome: 'ok' });
  const asked = sessions.events({ sessionId: id, limit: 50, reasoning: true });
  expect(asked.events.map((e) => e.kind)).toEqual(['user', 'reasoning', 'assistant', 'turn_end']);
  expect(JSON.stringify(asked.events[1])).not.toContain(token);

  // a client that does not ask keeps the events it knew, and the cursor still moves over what it was not sent
  const plain = sessions.events({ sessionId: id, limit: 50 });
  expect(plain.events.map((e) => e.kind)).toEqual(['user', 'assistant', 'turn_end']);
  expect(plain.cursor).toBe(4);
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
  // the list says how it went: the last words of the agent on one line, the finished turns and the model of the last
  expect(sessions.list({}).sessions[0]).toMatchObject({ lastMessage: 'Hello there', turns: 1, model: 'haiku' });
});

test('the list has the words of the agent on one line, cut, and nothing for a session it has not answered', async () => {
  const { sessions, conversation, id } = await openOne();
  expect(sessions.list({}).sessions[0]).toMatchObject({ lastMessage: null, turns: 0, model: null });
  sessions.send({ sessionId: id, text: 'hi' });
  conversation.emit({ kind: 'assistant', text: `first\n\n  second ${'x'.repeat(400)}` }, { kind: 'turn_end', outcome: 'ok' });
  const { lastMessage } = sessions.list({}).sessions[0]!;
  expect(lastMessage).toMatch(/^first second x+/);
  expect(lastMessage!.length).toBeLessThanOrEqual(201);
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
  // `id` is the event's own, a number the client uses as a cursor; the option is `option`
  expect(events.events).toMatchObject([{ id: expect.any(Number), kind: 'option', option: 'mode', value: 'default' }]);
  expect(events.options.map((o) => o.current)).toEqual(['default', 'haiku']);
  expect(rows('sessions')[0].options).toBe(JSON.stringify({ mode: 'default' })); // the session records the options it runs with
});

test('agentOptions starts the agent, reads what it offers, ends it, and asks again only after ten minutes', async () => {
  const { sessions, claude, clock } = setup();
  claude.setup = offering(['model', ['haiku', 'opus'], 'haiku']);
  const first = await sessions.agentOptions({ agent: 'claude' });
  expect(first.options).toMatchObject([{ id: 'model', current: 'haiku' }]);
  expect(first.commands).toEqual([]);
  expect(claude.conversations.map((c) => c.closed)).toEqual([true]);
  expect(rows('sessions')).toEqual([]); // no session is made for it
  await sessions.agentOptions({ agent: 'claude' });
  expect(claude.opened.length).toBe(1); // the answer is kept
  clock.time += 11 * 60_000;
  await sessions.agentOptions({ agent: 'claude' });
  expect(claude.opened.length).toBe(2);
  await expect(sessions.agentOptions({ agent: 'nope' })).rejects.toThrow('no chat agent named "nope"');
});

test('a failure of agentOptions is not kept: the next ask tries again', async () => {
  const { sessions, claude } = setup();
  claude.refuseWith = 'claude is not logged in';
  await expect(sessions.agentOptions({ agent: 'claude' })).rejects.toThrow('claude is not logged in');
  claude.refuseWith = undefined;
  await expect(sessions.agentOptions({ agent: 'claude' })).resolves.toBeDefined();
});

test('a command the session lists is invoked by its id: the person sees a slash and its name, the adapter gets the command, and the events list the commands', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.commands = [{ id: '/skills/pdf/SKILL.md', name: 'pdf', description: 'PDFs', kind: 'skill' }];
  expect(sessions.events({ sessionId: id, limit: 10 }).commands).toEqual(conversation.commands);
  sessions.send({ sessionId: id, text: 'the invoice', command: '/skills/pdf/SKILL.md' });
  expect(conversation.sent).toEqual(['the invoice']);
  expect(conversation.invoked).toEqual(['/skills/pdf/SKILL.md']);
  const stored = sessions.events({ sessionId: id, limit: 10 }).events;
  expect(stored).toMatchObject([{ kind: 'user', text: '/pdf the invoice', command: 'pdf' }]);
  expect(rows('sessions')[0]).toMatchObject({ title: '/pdf the invoice' });
});

test('a command that is not listed is refused and nothing is sent; a command with nothing after it is a message', async () => {
  const { sessions, conversation, id } = await openOne();
  conversation.commands = [{ id: 'review', name: 'review', description: 'Review', kind: 'skill' }];
  expect(() => sessions.send({ sessionId: id, text: 'x', command: 'nope' })).toThrow('does not list that command');
  expect(conversation.sent).toEqual([]);
  sessions.send({ sessionId: id, text: '', command: 'review' });
  expect(sessions.events({ sessionId: id, limit: 10 }).events).toMatchObject([{ kind: 'user', text: '/review', command: 'review' }]);
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

test('a resume that comes while a session is being deleted is refused, and the session is gone after', async () => {
  const s = setup();
  const { sessions, claude, id } = await openOne(s);
  await sessions.close({ sessionId: id });
  const deleting = sessions.delete({ sessionId: id }); // the first step of the delete runs before it yields
  await expect(sessions.resume({ sessionId: id })).rejects.toThrow('being deleted');
  await deleting;
  expect(claude.opened).toHaveLength(1);
  expect(sessions.list({}).sessions).toEqual([]);
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

test('rename sets the title, also while working, refuses an empty one or an unknown session, and the first message does not replace it', async () => {
  const s = setup();
  const a = await openOne(s);
  s.sessions.rename({ sessionId: a.id, title: '  Fix the sidebar\nsecond line ' });
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ title: 'Fix the sidebar' });
  expect(() => s.sessions.rename({ sessionId: a.id, title: '   ' })).toThrow('A title cannot be empty');
  expect(() => s.sessions.rename({ sessionId: '00000000-0000-4000-8000-000000000000', title: 'x' })).toThrow(ChatRefused);
  s.sessions.send({ sessionId: a.id, text: 'hello' }); // the first message: the session now works
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ title: 'Fix the sidebar', state: 'working' });
  s.sessions.rename({ sessionId: a.id, title: 'Still fine' });
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ title: 'Still fine' });
});

const DAY = 86_400_000;
const ages = (archiveAfterDays: number | 'never' = 15) => ({ archiveAfterDays, deleteAfterDays: 'never' as const });
const archivedIds = (s: { sessions: ReturnType<typeof createSessions> }) => s.sessions.list({ archived: true }).sessions.map((x) => x.id);

test('the pass archives a session idle for the configured days and not one a day short of it', async () => {
  const s = setup();
  const due = await openOne(s);
  await s.sessions.close({ sessionId: due.id });
  s.clock.time = 1 * DAY;
  const shortOfIt = (await s.sessions.open({ agent: 'claude', folder: work })).session.id;
  await s.sessions.close({ sessionId: shortOfIt });
  s.clock.time = 15 * DAY;
  await s.sessions.applyClock(ages());
  expect(archivedIds(s)).toEqual([due.id]); // `shortOfIt` has been idle 14 days
});

test('the pass skips a working session, one waiting for an approval and a live one, and archives each once it is idle and not live', async () => {
  const s = setup();
  const working = await openOne(s);
  const waiting = (await s.sessions.open({ agent: 'claude', folder: work })).session.id;
  const live = (await s.sessions.open({ agent: 'claude', folder: work })).session.id;
  s.sessions.send({ sessionId: working.id, text: 'go' });
  s.sessions.send({ sessionId: waiting, text: 'go' });
  s.claude.conversations[1]!.emit({ kind: 'approval', approvalId: 'a1', tool: 'Bash', choices: [{ id: 'yes', label: 'Yes', allow: true }] });
  s.clock.time = 20 * DAY;
  await s.sessions.applyClock(ages(1));
  expect(archivedIds(s)).toEqual([]); // working, waiting and live
  working.conversation.emit({ kind: 'turn_end', outcome: 'ok' });
  s.claude.conversations[1]!.emit({ kind: 'turn_end', outcome: 'ok' });
  await s.sessions.applyClock(ages(1));
  expect(archivedIds(s)).toEqual([]); // idle now, but still live
  for (const sessionId of [working.id, waiting, live]) await s.sessions.close({ sessionId });
  s.clock.time = 22 * DAY;
  await s.sessions.applyClock(ages(1));
  expect(archivedIds(s).sort()).toEqual([working.id, waiting, live].sort());
});

test('with archiveAfterDays never the pass archives nothing', async () => {
  const s = await openOne();
  await s.sessions.close({ sessionId: s.id });
  s.clock.time = 1000 * DAY;
  await s.sessions.applyClock(ages('never'));
  expect(archivedIds(s)).toEqual([]);
});

test('restoring a session counts as activity: the next pass does not archive it again', async () => {
  const s = await openOne();
  await s.sessions.archive({ sessionId: s.id, archived: true });
  s.clock.time = 30 * DAY;
  await s.sessions.archive({ sessionId: s.id, archived: false });
  await s.sessions.applyClock(ages());
  expect(archivedIds(s)).toEqual([]);
  s.clock.time = 45 * DAY;
  await s.sessions.applyClock(ages());
  expect(archivedIds(s)).toEqual([s.id]);
});

const clockAges = (deleteAfterDays: number | 'never' = 30) => ({ archiveAfterDays: 15, deleteAfterDays });
const sessionIds = (s: { db: ReturnType<typeof setup>['db'] }) => s.db.select().from(schemaSessions).all().map((x) => x.id);
const keptAt = (s: { db: ReturnType<typeof setup>['db'] }, id: string) => s.db.select().from(schemaSessions).where(eq(schemaSessions.id, id)).get()?.keptAt;

/** A host over a fake git with a base repository acme/app in `work`; `inWorktree` opens a session in a worktree of it and tells the fake what git finds there. */
function worktreeSetup(ages?: () => SessionAges) {
  const git = new FakeGit();
  const s = setup(undefined, { git, ...(ages && { ages }) });
  const repo = realpathSync(work);
  const base = { head: 'main', branches: ['main'], remoteBranches: ['main'], origin: 'git@github.com:acme/app.git' };
  git.repos.set(repo, base);
  const inWorktree = async (name: string, found: { status?: string[]; unpushed?: number } = {}) => {
    const { session } = await s.sessions.open({ agent: 'claude', folder: repo, worktree: { from: 'main', name } });
    const workspace = session.workspace as { path: string; branch: string };
    git.repos.set(workspace.path, { head: workspace.branch, branches: [workspace.branch], status: found.status, unpushed: { [workspace.branch]: found.unpushed ?? 0 } });
    await s.sessions.close({ sessionId: session.id });
    return { id: session.id, ...workspace };
  };
  return { ...s, git, repo, base, inWorktree };
}

test('the pass deletes an archived idle session past deleteAfterDays with its worktree and branch, keeps the clone, and spares one a day short', async () => {
  const s = worktreeSetup();
  const due = await s.inWorktree('due');
  s.clock.time = 1 * DAY;
  const shortOfIt = await s.inWorktree('short');
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges()); // `short` has been idle 29 days: archived, not deleted
  expect(sessionIds(s)).toEqual([shortOfIt.id]);
  expect(existsSync(due.path)).toBe(false);
  expect(existsSync(shortOfIt.path)).toBe(true);
  expect(s.base.branches).toEqual(['main', shortOfIt.branch]);
  expect(existsSync(s.repo)).toBe(true);
});

test('the pass spares a worktree with uncommitted changes or with commits that exist nowhere else, marking it kept and archived', async () => {
  const s = worktreeSetup();
  const dirty = await s.inWorktree('dirty', { status: [' M a.ts'] });
  const ahead = await s.inWorktree('ahead', { unpushed: 2 });
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s).sort()).toEqual([dirty.id, ahead.id].sort());
  expect(archivedIds(s).sort()).toEqual([dirty.id, ahead.id].sort());
  expect(keptAt(s, dirty.id)).toBe(30 * DAY);
  expect(existsSync(dirty.path)).toBe(true);
  s.clock.time = 31 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(keptAt(s, dirty.id)).toBe(30 * DAY); // marked when first spared
});

test('two worktree sessions sharing a commit that exists nowhere else: the first is deleted and the second spared, in one pass', async () => {
  const s = worktreeSetup();
  const first = await s.inWorktree('first');
  const second = await s.inWorktree('second');
  // git finds the shared commit on both branches, so neither is ahead until the first branch is gone
  const run = s.git.run.bind(s.git);
  s.git.run = async (folder, args, options) => {
    const result = await run(folder, args, options);
    if (args[0] === 'branch' && args[1] === '-D' && args[2] === first.branch) s.git.repos.get(second.path)!.unpushed![second.branch] = 1;
    return result;
  };
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toEqual([second.id]);
  expect(keptAt(s, second.id)).toBe(30 * DAY);
  const previews = s.git.calls.filter((call) => call.args[0] === 'rev-list').map((call) => call.args.filter((arg) => arg.startsWith('--exclude=')));
  expect(previews).toEqual([[`--exclude=${first.branch}`], [`--exclude=${second.branch}`]]); // each one alone, never the batch
});

test('a kept session whose worktree is later clean is deleted by a later pass, and restoring a kept session clears keptAt', async () => {
  const s = worktreeSetup();
  const later = await s.inWorktree('later', { status: [' M a.ts'] });
  const restored = await s.inWorktree('restored', { status: [' M a.ts'] });
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(keptAt(s, later.id)).toBe(30 * DAY);
  await s.sessions.archive({ sessionId: restored.id, archived: false });
  expect(keptAt(s, restored.id)).toBeNull();
  s.git.repos.get(later.path)!.status = [];
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toEqual([restored.id]);
  expect(existsSync(later.path)).toBe(false);
});

test('a git that fails on one session leaves it alone, logs the failure and does not stop the pass for the others', async () => {
  const s = worktreeSetup();
  const broken = await s.inWorktree('broken');
  const fine = await s.inWorktree('fine');
  const run = s.git.run.bind(s.git);
  s.git.run = async (folder, args, options) => (folder === broken.path && args.includes('status') ? { ok: false, code: 128, stderr: 'fatal' } : run(folder, args, options));
  const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toEqual([broken.id]);
  expect(keptAt(s, broken.id)).toBeNull();
  expect(errors).toHaveBeenCalled();
  errors.mockRestore();
});

test('a session in the person\'s own folder is deleted without the check', async () => {
  const s = await openOne();
  await s.sessions.close({ sessionId: s.id });
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toEqual([]);
  expect(s.db.select().from(schemaSessions).all()).toEqual([]);
});

test('with archiveAfterDays or deleteAfterDays at never nothing is deleted by the clock', async () => {
  const s = await openOne();
  await s.sessions.close({ sessionId: s.id });
  s.clock.time = 1000 * DAY;
  await s.sessions.applyClock({ archiveAfterDays: 'never', deleteAfterDays: 30 });
  await s.sessions.applyClock({ archiveAfterDays: 15, deleteAfterDays: 'never' });
  expect(sessionIds(s)).toEqual([s.id]);
});

test('the pass deletes neither a working, a waiting nor a live archived session, and deletes each once it is idle and closed', async () => {
  const s = setup();
  const working = await openOne(s);
  const waiting = (await s.sessions.open({ agent: 'claude', folder: work })).session.id;
  const live = (await s.sessions.open({ agent: 'claude', folder: work })).session.id;
  s.sessions.send({ sessionId: working.id, text: 'go' });
  s.sessions.send({ sessionId: waiting, text: 'go' });
  s.claude.conversations[1]!.emit({ kind: 'approval', approvalId: 'a1', tool: 'Bash', choices: [{ id: 'yes', label: 'Yes', allow: true }] });
  s.db.update(schemaSessions).set({ archived: true }).run(); // archived while still open: a person archiving one live would have closed it first
  s.clock.time = 100 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toHaveLength(3);
  working.conversation.emit({ kind: 'turn_end', outcome: 'ok' });
  s.claude.conversations[1]!.emit({ kind: 'turn_end', outcome: 'ok' });
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toHaveLength(3); // idle now, but still live
  for (const sessionId of [working.id, waiting, live]) await s.sessions.close({ sessionId });
  s.clock.time = 200 * DAY;
  await s.sessions.applyClock(clockAges());
  expect(sessionIds(s)).toEqual([]);
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

// The health request: the probes are replaced, the states come from the verdicts alone.
const probesOf = (over: Partial<HealthProbes> = {}): HealthProbes & { calls: string[] } => {
  const calls: string[] = [];
  return {
    calls,
    loggedIn: async (harness) => (calls.push(harness), true),
    exitCode: async (command, args) => (calls.push([command, ...args].join(' ')), 0),
    gitPath: () => '/opt/homebrew/bin/git',
    ...over,
  };
};
const allFound = { binaryFound: () => true };

test('health says ready for everything that works, and missing for a binary that is not found, an agent by its own command', async () => {
  const probes = probesOf();
  const { sessions } = setup({ agents: { claude: { harness: 'claude' }, mine: { harness: 'codex', command: '/opt/codex' } } }, { probes, binaryFound: (command) => command !== 'gh' && command !== '/opt/codex' });
  expect(await sessions.health({})).toEqual({ git: 'ready', gh: 'missing', agents: [{ name: 'claude', harness: 'claude', state: 'ready' }, { name: 'mine', harness: 'codex', state: 'missing' }] });
  expect(probes.calls).not.toContain('codex');
  const none = setup(undefined, { probes: probesOf(), binaryFound: () => false });
  expect(await none.sessions.health({})).toMatchObject({ git: 'missing', gh: 'missing' });
});

test('health says signedOut for a claude, codex or gh whose login is not there, and never for git', async () => {
  const probes = probesOf({ loggedIn: async () => false, exitCode: async (command) => (command === 'gh' ? 1 : 0) });
  const { sessions } = setup(undefined, { probes, ...allFound });
  expect(await sessions.health({})).toEqual({ git: 'ready', gh: 'signedOut', agents: [{ name: 'claude', harness: 'claude', state: 'signedOut' }, { name: 'codex', harness: 'codex', state: 'signedOut' }] });
  expect(probes.calls).toEqual([]);
});

test('health reads gh with auth status for github.com', async () => {
  const probes = probesOf();
  await setup(undefined, { probes, ...allFound }).sessions.health({});
  expect(probes.calls).toContain('gh auth status --hostname github.com');
});

test('a probe that cannot start or answer, or takes over five seconds, is unknown and the others still answer', async () => {
  const never = new Promise<never>(() => {});
  const probes = probesOf({ loggedIn: async (harness) => (harness === 'claude' ? Promise.reject(new Error('cannot read')) : never), exitCode: async (command) => (command === 'gh' ? never : 0) });
  const { sessions, clock } = setup(undefined, { probes, ...allFound });
  const answer = sessions.health({});
  await clock.advance(4_999);
  let early = false;
  void answer.then(() => (early = true));
  await Promise.resolve();
  expect(early).toBe(false);
  await clock.advance(1);
  expect(await answer).toEqual({ git: 'ready', gh: 'unknown', agents: [{ name: 'claude', harness: 'claude', state: 'unknown' }, { name: 'codex', harness: 'codex', state: 'unknown' }] });
});

test('the probes of a request run in parallel: all delayed one second, the answer takes one second', async () => {
  let clockOf: ReturnType<typeof setup>['clock'];
  const slow = <T>(value: T) => new Promise<T>((resolve) => clockOf.after(1_000, async () => resolve(value)));
  const probes = probesOf({ loggedIn: () => slow(true), exitCode: () => slow(0) });
  const s = setup(undefined, { probes, ...allFound });
  clockOf = s.clock;
  let done = false;
  const answer = s.sessions.health({}).then((health) => ((done = true), health));
  await s.clock.advance(1_000);
  await Promise.resolve();
  expect(await answer).toMatchObject({ git: 'ready', gh: 'ready' });
  expect(done).toBe(true);
});

test('a second health request within thirty seconds is answered from the kept result, and refresh asks again', async () => {
  const probes = probesOf();
  const { sessions, clock } = setup(undefined, { probes, ...allFound });
  const first = await sessions.health({});
  const ran = probes.calls.length;
  expect(ran).toBeGreaterThan(0);
  clock.time = 29_999;
  expect(await sessions.health({})).toBe(first);
  expect(probes.calls).toHaveLength(ran);
  await sessions.health({ refresh: true });
  expect(probes.calls).toHaveLength(ran * 2);
  clock.time += 30_000;
  await sessions.health({});
  expect(probes.calls).toHaveLength(ran * 3);
});

test('the health reply carries only the states, whatever the probes could say', async () => {
  const leak = new Error('me@example.com acme-org ghp_secret');
  const probes = probesOf({ loggedIn: async (harness) => (harness === 'claude' ? true : Promise.reject(leak)), exitCode: async () => Promise.reject(leak) });
  const reply = await setup(undefined, { probes, ...allFound }).sessions.health({});
  expect(JSON.stringify(reply)).not.toMatch(/example|acme|ghp_/);
  expect(Object.keys(reply).sort()).toEqual(['agents', 'gh', 'git']);
});

// A plan for a folder, prepared: the session exists at once and the steps are recorded as events.
const planFor = (extra: object = {}) => ({ workspace: { kind: 'folder' as const, folder: work }, agent: 'claude', text: 'build it', ...extra });
const stepsOf = (s: ReturnType<typeof setup>, id: string) =>
  (s.sessions.events({ sessionId: id, limit: 200 }).events as any[]).filter((e) => e.kind === 'step').map((e) => `${e.step}:${e.status}${e.detail === undefined ? '' : `:${e.detail}`}`);

test('openPlan answers at once with the session preparing, and the steps run to the first answer: then working, idle, no plan', async () => {
  const s = setup();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const open = s.claude.open.bind(s.claude);
  s.claude.open = async (args) => (await gate, open(args)); // the agent step is still running
  s.claude.setup = (conversation) => void (conversation.reply = () => {});
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  expect(session).toMatchObject({ state: 'preparing', preparation: 'running', title: 'build it', workspace: { kind: 'folder' } });
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ id: session.id, state: 'preparing', preparation: 'running', live: false });
  expect(stepsOf(s, session.id)).toEqual(['agent:running']);
  release();
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['agent:running', 'agent:done', 'message:running']));
  const conversation = s.claude.conversations[0]!;
  expect(conversation.sent).toEqual(['build it']);
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'preparing', preparation: 'running', live: true });
  expect(rows('sessions')[0].plan).toContain('build it');
  conversation.emit({ kind: 'assistant', text: 'done' });
  expect(stepsOf(s, session.id)).toEqual(['agent:running', 'agent:done', 'message:running', 'message:done']);
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'working', preparation: null });
  expect(rows('sessions')[0].plan).toBeNull();
  conversation.emit({ kind: 'turn_end', outcome: 'ok' });
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: null });
  // the user's message comes before the answer, and the message step is done before the answer
  expect((s.sessions.events({ sessionId: session.id, limit: 200 }).events as any[]).map((e) => e.kind)).toEqual(['step', 'step', 'step', 'user', 'step', 'assistant', 'turn_end']);
  expect(rows('chat_turns')).toHaveLength(1);
});

test('a failure at the agent leaves the session idle and not live, preparation failed, the reason in words and the plan kept', async () => {
  const s = setup();
  s.claude.refuseWith = 'claude is not logged in';
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['agent:running', 'agent:failed:claude is not logged in']));
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false });
  expect(rows('sessions')[0].plan).toContain('build it');
  expect(s.sessions.liveCount()).toBe(0);
  expect(s.onLiveChange).toHaveBeenCalled();
  await expect(s.sessions.resume({ sessionId: session.id })).rejects.toThrow('did not finish preparing');
});

test('an option the agent does not offer fails the agent step, and the agent that was started is ended', async () => {
  const s = setup();
  s.claude.setup = offering(['model', ['haiku'], 'haiku']);
  const { session } = await s.sessions.openPlan({ plan: planFor({ options: { speed: 'fast' } }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['agent:running', expect.stringContaining('agent:failed:This agent has no option "speed"')]));
  expect(s.claude.conversations[0]!.closed).toBe(true);
});

test('an agent that errors before it answers fails the message step and ends up idle, not live, with the plan kept', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.reply = () => conversation.emit({ kind: 'error', text: 'rate limited' }, { kind: 'turn_end', outcome: 'error' }));
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await vi.waitFor(() => expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false }));
  expect(stepsOf(s, session.id)).toEqual(['agent:running', 'agent:done', 'message:running', 'message:failed:The agent ended with an error before it answered']);
  expect(s.claude.conversations[0]!.closed).toBe(true);
  expect(rows('sessions')[0].plan).toContain('build it');
});

test('a message the agent cannot take fails the message step', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.reply = () => { throw new Error('pipe closed'); });
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:failed:The message could not be delivered to the agent'));
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false });
});

test('a session that was preparing when the host stopped comes back with the running step failed as interrupted, and idle', async () => {
  const first = setup();
  first.claude.open = () => new Promise(() => {}); // the agent step never ends: the host stops here
  const { session } = await first.sessions.openPlan({ plan: planFor() });
  expect(stepsOf(first, session.id)).toEqual(['agent:running']);
  first.db.$client.close();
  const next = createSessions({ db: openChatDatabase(join(dir, 'chat.db')), agents: [{ name: 'claude', harness: 'claude' } as ChatAgent], clock: new FakeClock(), runners: { claude: new FakeChatRunner() }, env: {}, git: new FakeGit(), projects: fakeProjects(new FakeGit()), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
  expect(next.list({}).sessions[0]).toMatchObject({ id: session.id, state: 'idle', preparation: 'failed', live: false });
  expect((next.events({ sessionId: session.id, limit: 200 }).events as any[]).map((e) => `${e.step}:${e.status}:${e.detail}`)).toEqual(['agent:running:undefined', 'agent:failed:Carrier stopped while this step was running']);
});

test('the host is not idle while a session is preparing, and is again once the preparation failed', async () => {
  const s = setup();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  s.claude.open = async () => (await gate, Promise.reject(new ChatRefused('not today')));
  expect(s.sessions.liveCount()).toBe(0);
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  expect(s.sessions.liveCount()).toBe(1);
  release();
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('agent:failed:not today'));
  expect(s.sessions.liveCount()).toBe(0);
  expect(s.onLiveChange).toHaveBeenCalled();
});

test('openPlan refuses a bad folder, an unknown agent and a long text, and makes no session', async () => {
  const { sessions, onLiveChange } = setup();
  await expect(sessions.openPlan({ plan: planFor({ workspace: { kind: 'folder', folder: join(dir, 'missing') } }) })).rejects.toThrow('does not exist');
  await expect(sessions.openPlan({ plan: planFor({ agent: 'nope' }) })).rejects.toThrow('no chat agent named "nope"');
  await expect(sessions.openPlan({ plan: planFor({ agent: 'codex' }) })).rejects.toThrow('no chat runner for codex');
  await expect(sessions.openPlan({ plan: planFor({ text: 'x'.repeat(chatCaps.message + 1) }) })).rejects.toThrow('the most a message can have');
  expect(rows('sessions')).toEqual([]);
  expect(onLiveChange).not.toHaveBeenCalled();
});

test('the old open leaves preparation null and records no step events', async () => {
  const s = await openOne();
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: null });
  expect(stepsOf(s, s.id)).toEqual([]);
});

test('a preparing session cannot be archived, deleted or resumed', async () => {
  const s = setup();
  s.claude.open = () => new Promise(() => {});
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await expect(s.sessions.archive({ sessionId: session.id, archived: true })).rejects.toThrow('being prepared');
  await expect(s.sessions.delete({ sessionId: session.id })).rejects.toThrow('being prepared');
  await expect(s.sessions.resume({ sessionId: session.id })).rejects.toThrow('did not finish preparing');
});

// The branch and the worktree of a plan, with a repository in the fake git.
const repoSetup = (repo: Partial<FakeRepo> = {}) => {
  const git = new FakeGit();
  const fake: FakeRepo = { head: 'main', branches: ['main', 'feat'], ...repo };
  git.repos.set(realpathSync(work), fake);
  return { ...setup(undefined, { git }), git, fake };
};

test('a plan with a worktree makes it from the picked branch under the Carrier folder, with no checkout, and the agent works in it', async () => {
  const s = repoSetup();
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'feat', worktree: { name: 'my-fix' } }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['worktree:running', 'worktree:done', 'agent:running', 'agent:done', 'message:running']));
  const path = join(dir, 'home', 'chat', 'worktrees', 'local', 'work', 'my-fix');
  expect(rows('sessions')[0]).toMatchObject({ folder: path, workspaceKind: 'worktree', worktreePath: path, worktreeBranch: 'carrier/my-fix', worktreeFrom: 'feat', worktreeBase: realpathSync(work) });
  expect(s.claude.opened[0]).toMatchObject({ folder: path });
  expect(s.fake.head).toBe('main');
  expect(s.git.calls.some((call) => call.args[0] === 'switch')).toBe(false);
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ workspace: { kind: 'worktree', branch: 'carrier/my-fix', from: 'feat' } });
});

test('an empty or absent worktree name is generated by the host', async () => {
  const s = repoSetup();
  for (const worktree of [{}, { name: '' }]) {
    const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'main', worktree }) });
    await vi.waitFor(() => expect(stepsOf(s, session.id).slice(0, 2)).toEqual(['worktree:running', 'worktree:done']));
  }
  expect(rows('sessions').map((row) => row.worktreeBranch)).toEqual([expect.stringMatching(/^carrier\/[a-z]+-[a-z]+-[a-z]+$/), expect.stringMatching(/^carrier\/[a-z]+-[a-z]+-[a-z]+$/)]);
});

test('a typed worktree name that is taken fails the worktree step with the reason, and no agent is started', async () => {
  const s = repoSetup({ branches: ['main', 'carrier/taken'] });
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'main', worktree: { name: 'taken' } }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['worktree:running', 'worktree:failed:A branch called carrier/taken already exists']));
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false, workspace: { kind: 'folder' } });
  expect(s.claude.opened).toEqual([]);
});

test('a worktree plan without a branch fails the worktree step in words', async () => {
  const s = repoSetup();
  const { session } = await s.sessions.openPlan({ plan: planFor({ worktree: {} }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['worktree:running', 'worktree:failed:A worktree needs the branch it starts from']));
});

test('a plan with a branch and no worktree checks the branch out of a clean folder, and the steps show checkout', async () => {
  const s = repoSetup();
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'feat' }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['checkout:running', 'checkout:done', 'agent:running', 'agent:done', 'message:running']));
  expect(s.fake.head).toBe('feat');
  expect(s.claude.opened[0]).toMatchObject({ folder: realpathSync(work) });
  expect(rows('sessions')[0]).toMatchObject({ workspaceKind: 'folder' });
});

test('a remote branch is checked out as a local one that tracks it', async () => {
  const s = repoSetup({ remoteBranches: ['topic'] });
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'origin/topic' }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id).slice(0, 2)).toEqual(['checkout:running', 'checkout:done']));
  expect(s.fake.head).toBe('topic');
  expect(s.git.calls.some((call) => call.args.join(' ') === 'switch --track origin/topic')).toBe(true);
});

test('a folder already on the picked branch is not changed, so unsaved work does not fail it', async () => {
  const s = repoSetup({ status: ['M a'] });
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'main' }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id).slice(0, 2)).toEqual(['checkout:running', 'checkout:done']));
  expect(s.git.calls.some((call) => call.args[0] === 'switch')).toBe(false);
});

test('the same plan on a folder with uncommitted changes fails at checkout with the reason in words and leaves the branch alone', async () => {
  const s = repoSetup({ status: ['M a.ts', '?? b.ts'] });
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'feat' }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['checkout:running', 'checkout:failed:The folder has 2 uncommitted files, so its branch was not changed to feat. Save the work and try again.']));
  expect(s.fake.head).toBe('main');
  expect(s.git.calls.some((call) => call.args[0] === 'switch')).toBe(false);
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false });
  expect(s.claude.opened).toEqual([]);
});

test('a branch the repository does not list, or a folder that is not a repository, fails the checkout step', async () => {
  const s = repoSetup();
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'nope' }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('checkout:failed:That branch is not one this repository lists'));
  const bare = setup();
  const plain = await bare.sessions.openPlan({ plan: planFor({ branch: 'main' }) });
  await vi.waitFor(() => expect(stepsOf(bare, plain.session.id).at(-1)).toContain('checkout:failed:That folder is not a git repository'));
});

// Retry and cancel of a preparation.
const failedAtAgent = async (s: ReturnType<typeof setup>, extra: object = {}) => {
  s.claude.refuseWith = 'claude is not logged in';
  const { session } = await s.sessions.openPlan({ plan: planFor(extra) });
  await vi.waitFor(() => expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed' }));
  s.claude.refuseWith = undefined;
  return session.id;
};

test('retryPreparation repeats the steps that failed, the session is preparing again, and the first message is not shown twice', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.reply = () => {});
  const id = await failedAtAgent(s);
  const { session } = await s.sessions.retryPreparation({ sessionId: id });
  expect(session).toMatchObject({ id, state: 'preparing', preparation: 'running' });
  await vi.waitFor(() => expect(stepsOf(s, id).at(-1)).toBe('message:running'));
  expect(stepsOf(s, id)).toEqual(['agent:running', 'agent:failed:claude is not logged in', 'agent:running', 'agent:done', 'message:running']);
  s.claude.conversations[0]!.emit({ kind: 'assistant', text: 'done' });
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'working', preparation: null });
  expect(rows('sessions')[0].plan).toBeNull();
  expect((s.sessions.events({ sessionId: id, limit: 200 }).events as any[]).filter((e) => e.kind === 'user')).toHaveLength(1);
});

test('a retry after the message failed starts the agent again and sends the same message once more', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.reply = () => { throw new Error('pipe closed'); });
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await vi.waitFor(() => expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false }));
  s.claude.setup = (conversation) => void (conversation.reply = () => {});
  await s.sessions.retryPreparation({ sessionId: session.id });
  await vi.waitFor(() => expect(s.claude.conversations).toHaveLength(2));
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  expect(s.claude.conversations[1]!.sent).toEqual(['build it']);
});

test('a retry does not make the worktree twice: the one recorded on the session is reused and the agent works in it', async () => {
  const s = repoSetup();
  const id = await failedAtAgent(s, { branch: 'main', worktree: { name: 'my-fix' } });
  const path = join(dir, 'home', 'chat', 'worktrees', 'local', 'work', 'my-fix');
  expect(rows('sessions')[0]).toMatchObject({ workspaceKind: 'worktree', worktreePath: path });
  const adds = () => s.git.calls.filter((call) => call.args[0] === 'worktree' && call.args[1] === 'add').length;
  expect(adds()).toBe(1);
  await s.sessions.retryPreparation({ sessionId: id });
  await vi.waitFor(() => expect(stepsOf(s, id).at(-1)).toBe('message:running'));
  expect(adds()).toBe(1);
  expect(s.fake.worktrees).toHaveLength(1);
  expect(s.claude.opened.at(-1)).toMatchObject({ folder: path });
  // the worktree step is shown as done once, not run again
  expect(stepsOf(s, id)).toEqual(['worktree:running', 'worktree:done', 'agent:running', 'agent:failed:claude is not logged in', 'agent:running', 'agent:done', 'message:running']);
});

test('a retry after a failed worktree step makes the worktree', async () => {
  const s = repoSetup({ branches: ['main', 'carrier/taken'] });
  const { session } = await s.sessions.openPlan({ plan: planFor({ branch: 'main', worktree: { name: 'taken' } }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toContain('worktree:failed'));
  s.fake.branches = ['main'];
  await s.sessions.retryPreparation({ sessionId: session.id });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  expect(rows('sessions')[0]).toMatchObject({ workspaceKind: 'worktree', worktreeBranch: 'carrier/taken' });
});

test('a retry after a done checkout does not switch the branch again', async () => {
  const s = repoSetup();
  const id = await failedAtAgent(s, { branch: 'feat' });
  expect(s.fake.head).toBe('feat');
  s.git.calls.length = 0;
  await s.sessions.retryPreparation({ sessionId: id });
  await vi.waitFor(() => expect(stepsOf(s, id).at(-1)).toBe('message:running'));
  expect(s.git.calls.some((call) => call.args[0] === 'switch')).toBe(false);
  expect(stepsOf(s, id).filter((step) => step.startsWith('checkout'))).toEqual(['checkout:running', 'checkout:done']);
});

test('a retry that fails again leaves the session failed with the new reason, and it can be retried again', async () => {
  const s = setup();
  const id = await failedAtAgent(s);
  s.claude.refuseWith = 'still not logged in';
  await s.sessions.retryPreparation({ sessionId: id });
  await vi.waitFor(() => expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed' }));
  expect(stepsOf(s, id).at(-1)).toBe('agent:failed:still not logged in');
  await s.sessions.retryPreparation({ sessionId: id });
});

test('retry on a preparing session is refused', async () => {
  const s = setup();
  s.claude.open = () => new Promise(() => {});
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await expect(s.sessions.retryPreparation({ sessionId: session.id })).rejects.toThrow('still being prepared');
});

test('cancel on a failed preparation is refused and leaves the session as it was', async () => {
  const s = setup();
  const id = await failedAtAgent(s);
  await expect(s.sessions.cancelPreparation({ sessionId: id })).rejects.toThrow('not being prepared');
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ id, preparation: 'failed' });
});

test('retry and cancel are refused for a session that was not prepared from a plan, and for one that does not exist', async () => {
  const plain = await openOne();
  await expect(plain.sessions.retryPreparation({ sessionId: plain.id })).rejects.toThrow('not in a failed preparation');
  await expect(plain.sessions.cancelPreparation({ sessionId: plain.id })).rejects.toThrow('not being prepared');
  await expect(plain.sessions.retryPreparation({ sessionId: '00000000-0000-4000-8000-000000000000' })).rejects.toThrow('no such session');
});

test('retry and cancel are refused for a session that answered, which has no plan left', async () => {
  const s = setup();
  s.claude.setup = (conversation) => void (conversation.reply = () => conversation.emit({ kind: 'assistant', text: 'hi' }, { kind: 'turn_end', outcome: 'ok' }));
  const { session } = await s.sessions.openPlan({ plan: planFor() });
  await vi.waitFor(() => expect(rows('sessions')[0].plan).toBeNull());
  await expect(s.sessions.retryPreparation({ sessionId: session.id })).rejects.toThrow('not in a failed preparation');
  await expect(s.sessions.cancelPreparation({ sessionId: session.id })).rejects.toThrow('not being prepared');
});

test('cancel in the middle of the worktree stops git, takes away what was made, deletes the session and answers the plan', async () => {
  const s = repoSetup();
  let release!: () => void;
  s.git.worktreePending = new Promise<void>((resolve) => (release = resolve));
  const plan = planFor({ branch: 'main', worktree: { name: 'my-fix' } });
  const { session } = await s.sessions.openPlan({ plan });
  await vi.waitFor(() => expect(s.git.calls.some((call) => call.args[0] === 'worktree' && call.args[1] === 'add')).toBe(true));
  expect(await s.sessions.cancelPreparation({ sessionId: session.id })).toEqual({ plan });
  release();
  expect(rows('sessions')).toEqual([]);
  expect(rows('chat_events')).toEqual([]);
  expect(s.fake.worktrees ?? []).toEqual([]);
  expect(s.fake.branches).toEqual(['main', 'feat']);
  expect(s.claude.opened).toEqual([]);
  expect(s.sessions.liveCount()).toBe(0);
});

test('cancel while the agent starts ends the agent that opened late, and cancel while it waits for the first answer closes it, the worktree going with the session', async () => {
  const starting = repoSetup();
  let release!: () => void;
  const gate = new Promise<void>((resolve) => (release = resolve));
  const open = starting.claude.open.bind(starting.claude);
  starting.claude.open = async (args) => (await gate, open(args));
  const { session } = await starting.sessions.openPlan({ plan: planFor({ branch: 'main', worktree: { name: 'late' } }) });
  await vi.waitFor(() => expect(stepsOf(starting, session.id).at(-1)).toBe('agent:running'));
  const cancelling = starting.sessions.cancelPreparation({ sessionId: session.id });
  release();
  await cancelling;
  expect(starting.claude.conversations[0]!.closed).toBe(true);
  expect(rows('sessions')).toEqual([]);
  expect(starting.fake.worktrees ?? []).toEqual([]);

  const waiting = repoSetup();
  waiting.claude.setup = (conversation) => void (conversation.reply = () => {});
  const second = await waiting.sessions.openPlan({ plan: planFor({ branch: 'main', worktree: { name: 'wait' } }) });
  await vi.waitFor(() => expect(stepsOf(waiting, second.session.id).at(-1)).toBe('message:running'));
  await waiting.sessions.cancelPreparation({ sessionId: second.session.id });
  expect(waiting.claude.conversations[0]!.closed).toBe(true);
  expect(rows('sessions')).toEqual([]);
  expect(waiting.fake.worktrees ?? []).toEqual([]);
  expect(waiting.sessions.liveCount()).toBe(0);
});

test('a failed preparation is still failed, with its failed step and plan, after the host restarts, and can be retried then', async () => {
  const first = setup();
  const id = await failedAtAgent(first);
  first.db.$client.close();
  const next = createSessions({ db: openChatDatabase(join(dir, 'chat.db')), agents: [{ name: 'claude', harness: 'claude' } as ChatAgent], clock: new FakeClock(), runners: { claude: new FakeChatRunner() }, env: {}, git: new FakeGit(), projects: fakeProjects(new FakeGit()), binaryFound: () => true, ages: () => ({ archiveAfterDays: 15, deleteAfterDays: 30 }), onLiveChange: () => {} });
  expect(next.list({}).sessions[0]).toMatchObject({ id, state: 'idle', preparation: 'failed', live: false });
  expect((next.events({ sessionId: id, limit: 200 }).events as any[]).map((e) => `${e.step}:${e.status}:${e.detail}`)).toEqual(['agent:running:undefined', 'agent:failed:claude is not logged in']);
  await next.retryPreparation({ sessionId: id });
  await vi.waitFor(() => expect(next.list({}).sessions[0]).toMatchObject({ state: 'preparing', live: true }));
});

// A plan for a new project: the `project` step makes the folder with git init.
const projectPlan = (name = 'my-app', extra: object = {}) => planFor({ workspace: { kind: 'project' as const, name }, ...extra });
const projectsDir = () => join(dir, 'home', 'chat', 'projects', 'local');

test('a project plan makes the folder with git init as its first step, and the agent works in it', async () => {
  const s = setup(undefined, { git: new FakeGit() });
  const { session } = await s.sessions.openPlan({ plan: projectPlan() });
  expect(rows('sessions')[0]).toMatchObject({ folder: join(projectsDir(), 'my-app') }); // the path it will make, shown at once
  expect(existsSync(join(projectsDir(), 'my-app'))).toBe(false);
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['project:running', 'project:done', 'agent:running', 'agent:done', 'message:running']));
  expect(existsSync(join(projectsDir(), 'my-app', '.git'))).toBe(true);
  expect(s.claude.opened[0]).toMatchObject({ folder: join(projectsDir(), 'my-app') });
});

test('a project name that is taken fails the project step with the reason and leaves what exists as it was', async () => {
  mkdirSync(join(projectsDir(), 'mine'), { recursive: true });
  writeFileSync(join(projectsDir(), 'mine', 'mine.txt'), 'mine');
  const s = setup();
  const { session } = await s.sessions.openPlan({ plan: projectPlan('mine') });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['project:running', 'project:failed:mine is already a project; choose another name']));
  expect(readFileSync(join(projectsDir(), 'mine', 'mine.txt'), 'utf8')).toBe('mine');
  expect(existsSync(join(projectsDir(), 'mine', '.git'))).toBe(false);
  expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false });
  expect(s.claude.opened).toEqual([]);
});

test('a name that is not a plain folder name is refused and makes no session', async () => {
  const s = setup();
  for (const name of ['', '.', '..', 'a/b', '../x', '.hidden']) await expect(s.sessions.openPlan({ plan: projectPlan(name) }), name).rejects.toThrow('not a plain folder name');
  expect(rows('sessions')).toEqual([]);
  expect(existsSync(projectsDir())).toBe(false);
});

test('a git init that fails removes what the step made, fails it without git\'s words, and a retry makes the project once the name is free again', async () => {
  const git = new FakeGit();
  git.failures.set('init -b main', { ok: false, code: 1, stderr: 'fatal: something with a https://x:tok@github.com url' });
  const s = setup(undefined, { git });
  const { session } = await s.sessions.openPlan({ plan: projectPlan('broken') });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['project:running', 'project:failed:git could not start the project broken']));
  expect(existsSync(join(projectsDir(), 'broken'))).toBe(false);
  git.failures.clear();
  await s.sessions.retryPreparation({ sessionId: session.id });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  expect(existsSync(join(projectsDir(), 'broken', '.git'))).toBe(true);
});

test('a retry after the project was made does not make it twice', async () => {
  const git = new FakeGit();
  const s = setup(undefined, { git });
  const id = await failedAtAgent(s, { workspace: { kind: 'project', name: 'my-app' } });
  expect(git.calls.filter((call) => call.args[0] === 'init')).toHaveLength(1);
  await s.sessions.retryPreparation({ sessionId: id });
  await vi.waitFor(() => expect(stepsOf(s, id).at(-1)).toBe('message:running'));
  expect(git.calls.filter((call) => call.args[0] === 'init')).toHaveLength(1);
  expect(s.claude.opened.at(-1)).toMatchObject({ folder: join(projectsDir(), 'my-app') });
  expect(stepsOf(s, id).filter((step) => step.startsWith('project'))).toEqual(['project:running', 'project:done']);
});

// A plan for a repository: the `clone` step (or `fetch`) comes first, then the rest as for a folder.
const repoPlan = (extra: object = {}, repo = 'acme/app') => planFor({ workspace: { kind: 'repo' as const, repo }, ...extra });
const cloneOf = (repo = 'acme/app') => join(dir, 'home', 'chat', 'projects', ...repo.split('/'));
const clonesOf = (s: { git: FakeGit }) => s.git.calls.filter((call) => call.args[0] === 'clone');
const repoSession = (cloned: Partial<FakeRepo> = {}) => {
  const git = new FakeGit();
  git.cloned = cloned;
  return { ...setup(undefined, { git }), git };
};

test('a plan for a repository clones it into the projects folder first, with git\'s progress while it runs, then the agent works in it', async () => {
  const s = repoSession();
  let release!: () => void;
  s.git.clonePending = new Promise<void>((resolve) => (release = resolve));
  s.claude.setup = (conversation) => void (conversation.reply = () => {});
  const { session } = await s.sessions.openPlan({ plan: repoPlan() });
  expect(session).toMatchObject({ state: 'preparing', preparation: 'running', folder: cloneOf() });
  await vi.waitFor(() => expect(clonesOf(s)).toHaveLength(1));
  expect(stepsOf(s, session.id)).toEqual(['clone:running']);
  expect(s.sessions.events({ sessionId: session.id, limit: 50 }).progress).toBeNull();
  s.git.emitProgress("Cloning into 'x'...", 'Receiving objects: 45% (45/100)');
  expect(s.sessions.events({ sessionId: session.id, limit: 50 }).progress).toBe('Receiving objects: 45%');
  expect(rows('chat_events').map((e) => e.data)).not.toContain(expect.stringContaining('Receiving')); // never stored
  release();
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['clone:running', 'clone:done', 'agent:running', 'agent:done', 'message:running']));
  expect(s.sessions.events({ sessionId: session.id, limit: 50 }).progress).toBeNull();
  expect(clonesOf(s)[0]).toMatchObject({ args: ['clone', '--', 'https://github.com/acme/app.git', cloneOf()] });
  expect(s.claude.opened[0]).toMatchObject({ folder: cloneOf() });
  expect(rows('sessions')[0]).toMatchObject({ folder: cloneOf(), workspaceKind: 'folder' });
});

test('a repository already in the projects folder is fetched, and the steps say fetch', async () => {
  const s = repoSession();
  mkdirSync(join(cloneOf(), '.git'), { recursive: true });
  s.git.repos.set(cloneOf(), { head: 'main', branches: ['main'], origin: 'git@github.com:acme/app.git' });
  const { session } = await s.sessions.openPlan({ plan: repoPlan() });
  await vi.waitFor(() => expect(stepsOf(s, session.id)).toEqual(['fetch:running', 'fetch:done', 'agent:running', 'agent:done', 'message:running']));
  expect(clonesOf(s)).toHaveLength(0);
  expect(s.git.calls.some((call) => call.args[0] === 'fetch' && call.folder === cloneOf())).toBe(true);
});

test('a worktree plan for a repository to clone starts from a branch GitHub listed, and a branch plan checks it out of the fresh clone', async () => {
  const s = repoSession({ branches: ['main'], remoteBranches: ['main', 'feat/x'] });
  const { session } = await s.sessions.openPlan({ plan: repoPlan({ branch: 'feat/x', worktree: {} }) });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  expect(stepsOf(s, session.id)).toEqual(['clone:running', 'clone:done', 'worktree:running', 'worktree:done', 'agent:running', 'agent:done', 'message:running']);
  expect(rows('sessions')[0]).toMatchObject({ workspaceKind: 'worktree', worktreeFrom: 'origin/feat/x', worktreeBase: cloneOf() });
  expect(s.claude.opened[0]!.folder).toBe(rows('sessions')[0].worktreePath);

  const other = repoSession({ branches: ['main'], remoteBranches: ['main', 'feat/x'] });
  const { session: second } = await other.sessions.openPlan({ plan: repoPlan({ branch: 'feat/x' }, 'acme/other') });
  await vi.waitFor(() => expect(stepsOf(other, second.id).at(-1)).toBe('message:running'));
  expect(stepsOf(other, second.id).slice(0, 4)).toEqual(['clone:running', 'clone:done', 'checkout:running', 'checkout:done']);
  expect(other.git.repos.get(cloneOf('acme/other'))!.head).toBe('feat/x');
  expect(other.claude.opened[0]).toMatchObject({ folder: cloneOf('acme/other') });
});

test('a failed clone leaves no partial folder, says why in words, and Try again clones again and goes on', async () => {
  const s = repoSession();
  s.git.failures.set(`clone -- https://github.com/acme/app.git ${cloneOf()}`, { ok: false, code: 128, stderr: 'fatal: unable to access https://x:ghp_secrettoken@github.com/acme/app.git/: Could not resolve host' });
  const { session } = await s.sessions.openPlan({ plan: repoPlan() });
  await vi.waitFor(() => expect(s.sessions.list({}).sessions[0]).toMatchObject({ state: 'idle', preparation: 'failed', live: false }));
  expect(stepsOf(s, session.id)).toEqual(['clone:running', 'clone:failed:GitHub could not be reached; check the network connection']);
  expect(existsSync(cloneOf())).toBe(false);
  expect(JSON.stringify(rows('chat_events'))).not.toContain('secrettoken');
  expect(s.claude.opened).toEqual([]);
  s.git.failures.clear();
  await s.sessions.retryPreparation({ sessionId: session.id });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  expect(stepsOf(s, session.id).slice(2)).toEqual(['clone:running', 'clone:done', 'agent:running', 'agent:done', 'message:running']);
  expect(clonesOf(s)).toHaveLength(2);
});

test('a retry after the clone was done does not clone or fetch again', async () => {
  const s = repoSession();
  s.claude.refuseWith = 'claude is not logged in';
  const { session } = await s.sessions.openPlan({ plan: repoPlan() });
  await vi.waitFor(() => expect(s.sessions.list({}).sessions[0]).toMatchObject({ preparation: 'failed' }));
  s.claude.refuseWith = undefined;
  s.git.calls.length = 0;
  await s.sessions.retryPreparation({ sessionId: session.id });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  expect(s.git.calls.filter((call) => ['clone', 'fetch'].includes(call.args[0]!))).toEqual([]);
  expect(stepsOf(s, session.id).filter((step) => step.startsWith('clone'))).toEqual(['clone:running', 'clone:done']);
});

test('cancel in the middle of a clone removes the half clone, deletes the session and answers the plan', async () => {
  const s = repoSession();
  s.git.clonePending = new Promise<void>(() => {});
  const plan = repoPlan();
  const { session } = await s.sessions.openPlan({ plan });
  await vi.waitFor(() => expect(existsSync(cloneOf())).toBe(true)); // the half clone
  expect(await s.sessions.cancelPreparation({ sessionId: session.id })).toEqual({ plan });
  expect(existsSync(cloneOf())).toBe(false);
  expect(rows('sessions')).toEqual([]);
  expect(rows('chat_events')).toEqual([]);
  expect(s.claude.opened).toEqual([]);
  expect(s.sessions.liveCount()).toBe(0);
});

test('a clone that finished stays in the projects folder when the session is cancelled after it', async () => {
  const s = repoSession();
  s.claude.setup = (conversation) => void (conversation.reply = () => {});
  const { session } = await s.sessions.openPlan({ plan: repoPlan() });
  await vi.waitFor(() => expect(stepsOf(s, session.id).at(-1)).toBe('message:running'));
  await s.sessions.cancelPreparation({ sessionId: session.id });
  expect(existsSync(join(cloneOf(), '.git'))).toBe(true);
  expect(rows('sessions')).toEqual([]);
});

test('two preparations of the same repository share one clone, and it stops only when both are cancelled', async () => {
  const s = repoSession();
  let release!: () => void;
  s.git.clonePending = new Promise<void>((resolve) => (release = resolve));
  const one = await s.sessions.openPlan({ plan: repoPlan() });
  await vi.waitFor(() => expect(clonesOf(s)).toHaveLength(1));
  const two = await s.sessions.openPlan({ plan: repoPlan({}, 'ACME/app') }); // another spelling of the same folder
  await vi.waitFor(() => expect(stepsOf(s, two.session.id)).toEqual(['clone:running']));
  await s.sessions.cancelPreparation({ sessionId: one.session.id });
  expect(existsSync(cloneOf())).toBe(true); // the second still waits for it
  release();
  await vi.waitFor(() => expect(stepsOf(s, two.session.id).at(-1)).toBe('message:running'));
  expect(clonesOf(s)).toHaveLength(1);
  expect(s.claude.opened).toHaveLength(1);

  const both = repoSession();
  both.git.clonePending = new Promise<void>(() => {});
  const first = await both.sessions.openPlan({ plan: repoPlan({}, 'acme/two') });
  const second = await both.sessions.openPlan({ plan: repoPlan({}, 'acme/two') });
  await vi.waitFor(() => expect(existsSync(cloneOf('acme/two'))).toBe(true));
  await both.sessions.cancelPreparation({ sessionId: first.session.id });
  expect(existsSync(cloneOf('acme/two'))).toBe(true);
  await both.sessions.cancelPreparation({ sessionId: second.session.id });
  expect(existsSync(cloneOf('acme/two'))).toBe(false);
  expect(clonesOf(both)).toHaveLength(1);
});

test('a repository that is not owner/name, or a projects folder that is not valid, is refused before a session is made', async () => {
  const s = repoSession();
  for (const repo of ['', '../x', 'a/b/c', 'solo']) await expect(s.sessions.openPlan({ plan: repoPlan({}, repo) }), repo).rejects.toThrow('is not a repository');
  mkdirSync(join(dir, 'home', 'chat'), { recursive: true });
  writeFileSync(join(dir, 'home', 'chat', 'chat.json'), JSON.stringify({ projectsFolder: join(dir, 'home', 'engine', 'mine') }));
  await expect(s.sessions.openPlan({ plan: repoPlan() })).rejects.toThrow("inside Carrier's own engine folder");
  expect(rows('sessions')).toEqual([]);
  expect(s.git.calls).toEqual([]);
});

test('list says when the clock deletes an archived session: lastActiveAt plus deleteAfterDays, and nothing for one not archived or kept', async () => {
  const s = worktreeSetup();
  const kept = await s.inWorktree('kept', { status: [' M a.ts'] });
  s.clock.time = 10 * DAY;
  const due = await s.inWorktree('due');
  await s.sessions.archive({ sessionId: due.id, archived: true });
  s.clock.time = 20 * DAY;
  const active = await s.inWorktree('active');
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(clockAges()); // archives and spares `kept`; `due` has been idle 20 days and `active` 10
  const listed = (archived: boolean) => Object.fromEntries(s.sessions.list({ archived }).sessions.map((x) => [x.id, x]));
  expect(listed(false)[active.id]).toMatchObject({ kept: false, deleteAt: null });
  expect(listed(true)[due.id]).toMatchObject({ kept: false, deleteAt: 40 * DAY });
  expect(listed(true)[kept.id]).toMatchObject({ kept: true, deleteAt: null });
  await s.sessions.archive({ sessionId: kept.id, archived: false });
  expect(listed(false)[kept.id]).toMatchObject({ kept: false, deleteAt: null });
});

test('a kept session stops reading as kept once the ages no longer make it due, and reads kept again when they do', async () => {
  const ages: { archiveAfterDays: number | 'never'; deleteAfterDays: number | 'never' } = clockAges();
  const s = worktreeSetup(() => ages);
  await s.inWorktree('kept', { status: [' M a.ts'] });
  s.clock.time = 30 * DAY;
  await s.sessions.applyClock(ages); // spared: due and unsaved
  const row = () => s.sessions.list({ archived: true }).sessions[0];
  expect(row()).toMatchObject({ kept: true, deleteAt: null });
  ages.deleteAfterDays = 40;
  expect(row()).toMatchObject({ kept: false, deleteAt: 40 * DAY });
  ages.deleteAfterDays = 'never';
  expect(row()).toMatchObject({ kept: false, deleteAt: null });
  ages.deleteAfterDays = 30;
  expect(row()).toMatchObject({ kept: true, deleteAt: null });
});

test('closeAll tells a pass in flight to leave the sessions it has not reached alone', async () => {
  const s = worktreeSetup();
  const first = await s.inWorktree('first');
  const second = await s.inWorktree('second');
  s.clock.time = 30 * DAY;
  let release = () => {};
  const gate = new Promise<void>((resolve) => (release = resolve));
  const run = s.git.run.bind(s.git);
  s.git.run = async (folder, args, options) => (await gate, run(folder, args, options));
  const pass = s.sessions.applyClock(clockAges()); // waits in git for the first session
  await s.sessions.closeAll();
  release();
  await pass;
  expect(sessionIds(s).sort()).toEqual([first.id, second.id].sort());
  expect(existsSync(first.path) && existsSync(second.path)).toBe(true);
});

test.each([
  [{ archiveAfterDays: 'never', deleteAfterDays: 30 }],
  [{ archiveAfterDays: 15, deleteAfterDays: 'never' }],
] as const)('list gives no deleteAt for an archived session when an age is never (%j)', async (ages) => {
  const s = await openOne(setup(undefined, { ages: () => ages }));
  await s.sessions.archive({ sessionId: s.id, archived: true });
  expect(s.sessions.list({ archived: true }).sessions[0]).toMatchObject({ kept: false, deleteAt: null });
});
