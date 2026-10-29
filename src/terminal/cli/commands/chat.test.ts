import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventEmitter } from 'node:events';
import { PassThrough, Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeChatRunner, type FakeConversation } from '../../../chat/fake.ts';
import { startChatHost } from '../../../chat/host.ts';
import { FakeClock } from '../../../orchestration/fake.ts';
import { CliError } from '../cli-error.ts';
import { connectControl } from '../control-client.ts';
import { chatCommand } from './chat.ts';

let root: string;
let stops: (() => Promise<void>)[];
let written: string[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'cc-')); // short: a socket path holds 103 bytes on macOS
  vi.stubEnv('CARRIER_HOME', root);
  stops = [];
  written = [];
  vi.spyOn(process.stdout, 'write').mockImplementation((text) => (written.push(String(text)), true));
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
});

const claude = new FakeChatRunner();
const host = async () => {
  const exit = vi.fn();
  const { stop } = await startChatHost({ installLogging: () => {}, clock: new FakeClock(), exit, signals: false, runners: { claude } });
  stops.push(stop);
  return exit;
};

test('--list with no host starts one, waits for the socket, and says there are no sessions', async () => {
  const start = vi.fn(async () => {
    await host(); // what the detached child does
    return 1;
  });
  expect(await chatCommand({ list: true }, { start })).toBe(0);
  expect(start).toHaveBeenCalledWith(expect.objectContaining({ args: ['chat-host'], socketPath: join(root, 'chat', 'state', 'chat.sock'), logPath: join(root, 'chat', 'logs', 'start.log') }));
  expect(written.join('')).toBe('No chat sessions.\n');
});

test('--list with a host answering over a real socket starts no other', async () => {
  await host();
  const start = vi.fn();
  expect(await chatCommand({ list: true }, { start })).toBe(0);
  expect(start).not.toHaveBeenCalled();
  expect(written.join('')).toBe('No chat sessions.\n');
});

test('--list passes on why the host did not come up', async () => {
  const start = vi.fn(async () => {
    throw new CliError(1, 'The chat host exited before it was ready:', 'boom');
  });
  await expect(chatCommand({ list: true }, { start })).rejects.toMatchObject({ lines: ['The chat host exited before it was ready:', 'boom'] });
});

test('--stop ends the host and says so; with none it says none runs', async () => {
  const exit = await host();
  expect(await chatCommand({ stop: true })).toBe(0);
  expect(exit).toHaveBeenCalledWith(0);
  expect(written.join('')).toBe('Chat host stopped\n');
  written.length = 0;
  expect(await chatCommand({ stop: true })).toBe(0);
  expect(written.join('')).toBe('No chat host is running\n');
});

test('without --list or --stop it says how to use it', async () => {
  await expect(chatCommand({})).rejects.toMatchObject({ code: 2 });
});

// The person's lines, one per read; the pace of the answer is the fake agent's.
const typed = (...lines: string[]) => Readable.from(lines.map((line) => `${line}\n`));

test('--workspace opens a conversation, prints the answer as it streams and a tool call as one line, asks again, and /quit leaves the session open', async () => {
  await host();
  const work = join(root, 'work');
  mkdirSync(work);
  claude.conversations.length = 0;
  claude.setup = (conversation) => {
    conversation.reply = (text, c) => {
      c.emit({ kind: 'delta', text: 'You said ' });
      setTimeout(() => {
        c.emit({ kind: 'delta', text: text.toUpperCase() });
        c.emit({ kind: 'assistant', text: `You said ${text.toUpperCase()}.` });
        c.emit({ kind: 'tool_start', callId: '1', tool: 'Bash', arg: 'ls -la' }, { kind: 'tool_end', callId: '1', tool: 'Bash', status: 'ok' });
        c.emit({ kind: 'assistant', text: 'Done' }, { kind: 'turn_end', outcome: 'ok' });
      }, 30);
    };
  };
  expect(await chatCommand({ workspace: work }, { input: typed('', 'hello', 'again', '/quit'), pollMs: 5 })).toBe(0);
  const out = written.join('');
  expect(out).toContain('with claude in ');
  expect(out).toContain('> You said HELLO.\n  [Bash ls -la]\nDone\n> You said AGAIN.\n  [Bash ls -la]\nDone\n> \n');
  expect(claude.conversations[0]!.sent).toEqual(['hello', 'again']);
  expect(claude.conversations[0]!.closed).toBe(false); // /quit leaves, the session stays open
  expect(claude.opened[0]!.folder).toContain('work');
});

test('--workspace with --agent names the agent, and a refusal of the host is shown in words', async () => {
  await host();
  await expect(chatCommand({ workspace: join(root, 'missing'), agent: 'claude' }, { input: typed('/quit') })).rejects.toMatchObject({ code: 1, lines: ['That folder does not exist'] });
  await expect(chatCommand({ workspace: root, agent: 'nobody' }, { input: typed('/quit') })).rejects.toMatchObject({ lines: ['There is no chat agent named "nobody"'] });
});

test('--workspace starts the host when none answers', async () => {
  const start = vi.fn(async () => {
    await host();
    return 1;
  });
  expect(await chatCommand({ workspace: root }, { start, input: typed('/quit') })).toBe(0);
  expect(start).toHaveBeenCalledTimes(1);
});

test('--workspace without --agent picks the first agent chat.json lists, and says so when it lists none', async () => {
  mkdirSync(join(root, 'chat'), { recursive: true });
  writeFileSync(join(root, 'chat', 'chat.json'), JSON.stringify({ agents: { mine: { harness: 'claude' }, claude: { harness: 'claude' } } }));
  const { stop } = await startChatHost({ installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude }, binaryFound: () => true });
  expect(await chatCommand({ workspace: root }, { input: typed('/quit') })).toBe(0);
  expect(written.join('')).toContain(" with mine in ");
  await stop();
  writeFileSync(join(root, 'chat', 'chat.json'), JSON.stringify({ agents: {} }));
  await host();
  await expect(chatCommand({ workspace: root }, { input: typed('/quit') })).rejects.toMatchObject({ code: 1, lines: [expect.stringContaining('lists no agents')] });
});

const nativeReply = (conversation: FakeConversation) => {
  conversation.nativeId = 'native-1';
  conversation.reply = (text, c) => c.emit({ kind: 'assistant', text: `re: ${text}` }, { kind: 'turn_end', outcome: 'ok' });
};

test('--list prints each session as id, agent, state, age and folder, the most recently active first, and closed when its agent is not running', async () => {
  const clock = new FakeClock();
  const exit = vi.fn();
  const runner = new FakeChatRunner();
  const { stop } = await startChatHost({ installLogging: () => {}, clock, exit, signals: false, runners: { claude: runner } });
  stops.push(stop);
  const older = join(root, 'older');
  const newer = join(root, 'newer');
  mkdirSync(older);
  mkdirSync(newer);
  const client = await connectControl(join(root, 'chat', 'state', 'chat.sock'));
  const a = ((await client.request('open', { agent: 'claude', folder: older })) as any).session.id;
  clock.time = 3 * 3600_000;
  const b = ((await client.request('open', { agent: 'claude', folder: newer })) as any).session.id;
  await client.request('close', { sessionId: a });
  clock.time = 3 * 3600_000 + 5 * 60_000;
  expect(await chatCommand({ list: true }, { now: () => clock.time })).toBe(0);
  const lines = written.join('').trimEnd().split('\n');
  expect(lines).toEqual([expect.stringMatching(new RegExp(`^${b}  claude  idle  5m ago  .*newer$`)), expect.stringMatching(new RegExp(`^${a}  claude  closed  3h ago  .*older$`))]);
  client.close();
});

test('--archive, --unarchive and --delete do what they say, --list --archived lists the archived ones, and a refusal is shown in words', async () => {
  await host();
  const client = await connectControl(join(root, 'chat', 'state', 'chat.sock'));
  const { session } = (await client.request('open', { agent: 'claude', folder: root })) as any;
  const run = (flags: Parameters<typeof chatCommand>[0]) => chatCommand(flags);
  const out = () => written.splice(0).join('');

  expect(await run({ archive: session.id })).toBe(0);
  expect(out()).toBe(`Session ${session.id} archived\n`);
  await run({ list: true });
  expect(out()).toBe('No chat sessions.\n');
  await run({ list: true, archived: true });
  expect(out()).toContain(session.id);
  expect(await run({ unarchive: session.id })).toBe(0);
  expect(out()).toBe(`Session ${session.id} unarchived\n`);
  await run({ list: true, archived: true });
  expect(out()).toBe('No archived chat sessions.\n');

  await client.request('resume', { sessionId: session.id }); // archiving closed the idle session
  claude.conversations.at(-1)!.reply = () => {}; // the turn never ends
  await client.request('send', { sessionId: session.id, text: 'go' });
  await expect(run({ delete: session.id })).rejects.toMatchObject({ code: 1, lines: [expect.stringContaining('interrupt or close it first')] });
  await client.request('interrupt', { sessionId: session.id });
  expect(await run({ delete: session.id })).toBe(0);
  expect(out()).toBe(`Session ${session.id} deleted\n`);
  await run({ list: true });
  expect(out()).toBe('No chat sessions.\n');
  await expect(run({ delete: session.id })).rejects.toMatchObject({ lines: ['There is no such session'] });
  client.close();
});

test('--resume prints the last 20 events of the transcript, then continues the conversation after the host was stopped and started again', async () => {
  const work = join(root, 'work');
  mkdirSync(work);
  const first = new FakeChatRunner();
  first.setup = nativeReply;
  const one = await startChatHost({ installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: first } });
  const client = await connectControl(join(root, 'chat', 'state', 'chat.sock'));
  const { session } = (await client.request('open', { agent: 'claude', folder: work })) as any;
  for (let i = 1; i <= 15; i++) {
    await client.request('send', { sessionId: session.id, text: `message ${i}` });
  }
  client.close();
  await one.stop();

  const second = new FakeChatRunner();
  second.setup = nativeReply;
  const next = await startChatHost({ installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: second } });
  stops.push(next.stop);
  expect(await chatCommand({ resume: session.id }, { input: typed('and now', '/quit'), pollMs: 5 })).toBe(0);
  const out = written.join('');
  expect(second.opened[0]).toMatchObject({ resume: 'native-1' });
  // 15 turns of user, assistant and turn_end make 45 events; the last 20 begin at the answer to message 9
  expect(out).not.toContain('message 8');
  expect(out).not.toContain('> message 9\n');
  expect(out).toContain('re: message 9\n> message 10\n');
  expect(out).toContain('> message 15\nre: message 15\n');
  expect(out).toContain('> re: and now\n');
  expect(second.conversations[0]!.sent).toEqual(['and now']);
});

test('--resume of an unknown session shows the refusal in words', async () => {
  await host();
  await expect(chatCommand({ resume: '00000000-0000-4000-8000-000000000000' }, { input: typed('/quit') })).rejects.toMatchObject({ code: 1, lines: ['There is no such session'] });
});

test('Ctrl+C while a turn runs interrupts it and returns to the prompt, where the next message is answered; Ctrl+C at the prompt leaves with the session open', async () => {
  await host();
  claude.conversations.length = 0;
  claude.setup = (conversation) => {
    conversation.reply = (text, c) => {
      if (text === 'long') c.emit({ kind: 'delta', text: 'one two ' }); // never ends by itself
      else c.emit({ kind: 'assistant', text: 'second answer' }, { kind: 'turn_end', outcome: 'ok' });
    };
    conversation.onInterrupt = (c) => c.emit({ kind: 'turn_end', outcome: 'interrupted' });
  };
  const input = new PassThrough();
  const sigint = new EventEmitter();
  const running = chatCommand({ workspace: root }, { input, sigint, pollMs: 5 });
  input.write('long\n');
  await vi.waitFor(() => expect(written.join('')).toContain('one two '));
  sigint.emit('SIGINT');
  await vi.waitFor(() => expect(written.join('')).toContain('[interrupted]'));
  input.write('again\n');
  await vi.waitFor(() => expect(written.join('')).toContain('second answer'));
  await vi.waitFor(() => expect(written.join('').endsWith('> ')).toBe(true));
  sigint.emit('SIGINT'); // at the prompt
  expect(await running).toBe(0);
  expect(claude.conversations[0]!.sent).toEqual(['long', 'again']);
  expect(claude.conversations[0]!.interrupts).toBe(1);
  expect(claude.conversations[0]!.closed).toBe(false);
  expect(sigint.listenerCount('SIGINT')).toBe(0);
});

test('/options prints each option with its current value and what it offers, /option changes one and prints it, and a refusal is shown in words', async () => {
  await host();
  claude.conversations.length = 0;
  claude.setup = (conversation) => {
    conversation.options = [
      { id: 'mode', label: 'Permission mode', values: [{ id: 'default', label: 'Default' }, { id: 'plan', label: 'Plan' }], current: 'default' },
      { id: 'model', label: 'Model', values: [{ id: 'haiku', label: 'Haiku' }], current: 'haiku' },
    ];
  };
  expect(await chatCommand({ workspace: root }, { input: typed('/options', '/option mode plan', '/option mode yolo', '/option nope x', '/option mode', '/options', '/quit'), pollMs: 5 })).toBe(0);
  const out = written.join('');
  expect(out).toContain('> Permission mode (mode): default\n    offers: default, plan\nModel (model): haiku\n    offers: haiku\n> ');
  expect(out).toContain('> Permission mode (mode): plan\n    offers: default, plan\n> ');
  expect(out).toContain('"yolo" is not a value of the option "mode"; it offers: default, plan\n');
  expect(out).toContain('no option "nope"');
  expect(out).toContain('Usage: /option <id> <value>\n');
  expect(out.lastIndexOf('Permission mode (mode): plan')).toBeGreaterThan(out.indexOf('Usage:')); // the second /options sees the change
  expect(claude.conversations[0]!.sent).toEqual([]); // none of this went to the agent
});

// The fake agent asks before it "touches" a file; it runs the tool only when the person allowed it.
const asking = (conversation: FakeConversation) => {
  let asked = 0;
  conversation.reply = (_text, c) => {
    c.emit({ kind: 'approval', approvalId: `a${++asked}`, tool: 'Bash', arg: 'touch x.txt', choices: [{ id: 'allow', label: 'Allow', allow: true }, { id: 'deny', label: 'Deny', allow: false }] });
  };
  const answer = conversation.answer.bind(conversation);
  conversation.answer = (approvalId, choiceId) => {
    answer(approvalId, choiceId);
    if (choiceId === 'allow') conversation.emit({ kind: 'tool_start', callId: '1', tool: 'Bash', arg: 'touch x.txt' });
    conversation.emit({ kind: 'assistant', text: choiceId === 'allow' ? 'Created' : 'Not created' }, { kind: 'turn_end', outcome: 'ok' });
  };
};

test('an approval is shown with the tool, its argument and the choices; the number typed is sent and a decline does not run the tool', async () => {
  await host();
  claude.conversations.length = 0;
  claude.setup = asking;
  expect(await chatCommand({ workspace: root }, { input: typed('touch it', '2', 'again', '1', '/quit'), pollMs: 5 })).toBe(0);
  const out = written.join('');
  expect(out).toContain('Bash touch x.txt needs your approval:\n  1) Allow\n  2) Deny\nchoose> ');
  expect(claude.conversations[0]!.answers).toEqual([{ approvalId: 'a1', choiceId: 'deny' }, { approvalId: 'a2', choiceId: 'allow' }]);
  expect(out).toContain('Not created\n> ');
  expect(out.split('Not created')[0]).not.toContain('[Bash touch x.txt]'); // declined: no tool call
  expect(out).toContain('  [Bash touch x.txt]\nCreated\n');
});

test('a choice that is not listed is asked again', async () => {
  await host();
  claude.conversations.length = 0;
  claude.setup = asking;
  await chatCommand({ workspace: root }, { input: typed('touch it', 'maybe', '9', 'deny', '/quit'), pollMs: 5 });
  expect(written.join('')).toContain('Type a number from 1 to 2\nchoose> Type a number from 1 to 2\nchoose> ');
  expect(claude.conversations[0]!.answers).toEqual([{ approvalId: 'a1', choiceId: 'deny' }]);
});

test('leaving while an approval waits keeps it pending, and --resume asks it again and honours the answer', async () => {
  await host();
  claude.conversations.length = 0;
  claude.setup = asking;
  const first = chatCommand({ workspace: root }, { input: typed('touch it'), pollMs: 5 }); // the input ends at the approval
  expect(await first).toBe(0);
  const conversation = claude.conversations[0]!;
  expect(conversation.answers).toEqual([]);
  expect(conversation.closed).toBe(false);
  const id = /Chat (\S+) with/.exec(written.join(''))![1]!;
  written.length = 0;
  expect(await chatCommand({ resume: id }, { input: typed('1', '/quit'), pollMs: 5 })).toBe(0);
  expect(written.join('')).toContain('Bash touch x.txt needs your approval:\n  1) Allow\n  2) Deny\nchoose> ');
  expect(conversation.answers).toEqual([{ approvalId: 'a1', choiceId: 'allow' }]);
  expect(written.join('')).toContain('Created\n');
});

test('an interrupt while an approval waits drops the question and returns to the prompt', async () => {
  await host();
  claude.conversations.length = 0;
  claude.setup = (conversation) => {
    asking(conversation);
    conversation.onInterrupt = (c) => c.emit({ kind: 'turn_end', outcome: 'interrupted' });
  };
  const input = new PassThrough();
  const sigint = new EventEmitter();
  const running = chatCommand({ workspace: root }, { input, sigint, pollMs: 5 });
  input.write('touch it\n');
  await vi.waitFor(() => expect(written.join('')).toContain('choose> '));
  sigint.emit('SIGINT');
  await vi.waitFor(() => expect(written.join('')).toContain('[interrupted]'));
  await vi.waitFor(() => expect(written.join('').endsWith('> ')).toBe(true));
  input.write('/quit\n');
  expect(await running).toBe(0);
  expect(claude.conversations[0]!.answers).toEqual([]);
});
