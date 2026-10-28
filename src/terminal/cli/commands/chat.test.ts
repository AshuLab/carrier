import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeChatRunner, type FakeConversation } from '../../../chat/fake.ts';
import { startChatHost } from '../../../chat/host.ts';
import type { Config } from '../../../config/schema.ts';
import { FakeClock } from '../../../orchestration/fake.ts';
import { CliError } from '../cli-error.ts';
import { connectControl } from '../control-client.ts';
import { chatCommand } from './chat.ts';

let root: string;
let stops: (() => Promise<void>)[];
let written: string[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'cc-')); // short: a socket path holds 103 bytes on macOS
  stops = [];
  written = [];
  vi.spyOn(process.stdout, 'write').mockImplementation((text) => (written.push(String(text)), true));
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
  vi.restoreAllMocks();
});

const config = () => ({ root, logLevel: 'info' }) as Config;
const claude = new FakeChatRunner();
const host = async () => {
  const exit = vi.fn();
  const { stop } = await startChatHost(config(), { installLogging: () => {}, clock: new FakeClock(), exit, signals: false, runners: { claude } });
  stops.push(stop);
  return exit;
};

test('--list with no host starts one, waits for the socket, and says there are no sessions', async () => {
  const start = vi.fn(async () => {
    await host(); // what the detached child does
    return 1;
  });
  expect(await chatCommand({ list: true }, config(), '/abs/config.json', { start })).toBe(0);
  expect(start).toHaveBeenCalledWith(expect.objectContaining({ args: ['chat-host', '--config', '/abs/config.json'], socketPath: join(root, 'chat', 'chat.sock'), logPath: join(root, 'chat', 'logs', 'start.log') }));
  expect(written.join('')).toBe('No chat sessions.\n');
});

test('--list with a host answering over a real socket starts no other', async () => {
  await host();
  const start = vi.fn();
  expect(await chatCommand({ list: true }, config(), '/abs/config.json', { start })).toBe(0);
  expect(start).not.toHaveBeenCalled();
  expect(written.join('')).toBe('No chat sessions.\n');
});

test('--list passes on why the host did not come up', async () => {
  const start = vi.fn(async () => {
    throw new CliError(1, 'The chat host exited before it was ready:', 'boom');
  });
  await expect(chatCommand({ list: true }, config(), '/abs/config.json', { start })).rejects.toMatchObject({ lines: ['The chat host exited before it was ready:', 'boom'] });
});

test('--stop ends the host and says so; with none it says none runs', async () => {
  const exit = await host();
  expect(await chatCommand({ stop: true }, config(), '/abs/config.json')).toBe(0);
  expect(exit).toHaveBeenCalledWith(0);
  expect(written.join('')).toBe('Chat host stopped\n');
  written.length = 0;
  expect(await chatCommand({ stop: true }, config(), '/abs/config.json')).toBe(0);
  expect(written.join('')).toBe('No chat host is running\n');
});

test('without --list or --stop it says how to use it', async () => {
  await expect(chatCommand({}, config(), '/abs/config.json')).rejects.toMatchObject({ code: 2 });
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
  expect(await chatCommand({ workspace: work }, config(), '/abs/config.json', { input: typed('', 'hello', 'again', '/quit'), pollMs: 5 })).toBe(0);
  const out = written.join('');
  expect(out).toContain('with claude in ');
  expect(out).toContain('> You said HELLO.\n  [Bash ls -la]\nDone\n> You said AGAIN.\n  [Bash ls -la]\nDone\n> \n');
  expect(claude.conversations[0]!.sent).toEqual(['hello', 'again']);
  expect(claude.conversations[0]!.closed).toBe(false); // /quit leaves, the session stays open
  expect(claude.opened[0]!.folder).toContain('work');
});

test('--workspace with --agent names the agent, and a refusal of the host is shown in words', async () => {
  await host();
  await expect(chatCommand({ workspace: join(root, 'missing'), agent: 'claude' }, config(), '/abs/config.json', { input: typed('/quit') })).rejects.toMatchObject({ code: 1, lines: ['That folder does not exist'] });
  await expect(chatCommand({ workspace: root, agent: 'nobody' }, config(), '/abs/config.json', { input: typed('/quit') })).rejects.toMatchObject({ lines: ['There is no chat agent named "nobody"'] });
});

test('--workspace starts the host when none answers', async () => {
  const start = vi.fn(async () => {
    await host();
    return 1;
  });
  expect(await chatCommand({ workspace: root }, config(), '/abs/config.json', { start, input: typed('/quit') })).toBe(0);
  expect(start).toHaveBeenCalledTimes(1);
});

const nativeReply = (conversation: FakeConversation) => {
  conversation.nativeId = 'native-1';
  conversation.reply = (text, c) => c.emit({ kind: 'assistant', text: `re: ${text}` }, { kind: 'turn_end', outcome: 'ok' });
};

test('--list prints each session as id, agent, state, age and folder, the most recently active first, and closed when its agent is not running', async () => {
  const clock = new FakeClock();
  const exit = vi.fn();
  const runner = new FakeChatRunner();
  const { stop } = await startChatHost(config(), { installLogging: () => {}, clock, exit, signals: false, runners: { claude: runner } });
  stops.push(stop);
  const older = join(root, 'older');
  const newer = join(root, 'newer');
  mkdirSync(older);
  mkdirSync(newer);
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  const a = ((await client.request('open', { agent: 'claude', folder: older })) as any).session.id;
  clock.time = 3 * 3600_000;
  const b = ((await client.request('open', { agent: 'claude', folder: newer })) as any).session.id;
  await client.request('close', { sessionId: a });
  clock.time = 3 * 3600_000 + 5 * 60_000;
  expect(await chatCommand({ list: true }, config(), '/abs/config.json', { now: () => clock.time })).toBe(0);
  const lines = written.join('').trimEnd().split('\n');
  expect(lines).toEqual([expect.stringMatching(new RegExp(`^${b}  claude  idle  5m ago  .*newer$`)), expect.stringMatching(new RegExp(`^${a}  claude  closed  3h ago  .*older$`))]);
  client.close();
});

test('--resume prints the last 20 events of the transcript, then continues the conversation after the host was stopped and started again', async () => {
  const work = join(root, 'work');
  mkdirSync(work);
  const first = new FakeChatRunner();
  first.setup = nativeReply;
  const one = await startChatHost(config(), { installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: first } });
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  const { session } = (await client.request('open', { agent: 'claude', folder: work })) as any;
  for (let i = 1; i <= 15; i++) {
    await client.request('send', { sessionId: session.id, text: `message ${i}` });
  }
  client.close();
  await one.stop();

  const second = new FakeChatRunner();
  second.setup = nativeReply;
  const next = await startChatHost(config(), { installLogging: () => {}, clock: new FakeClock(), exit: vi.fn(), signals: false, runners: { claude: second } });
  stops.push(next.stop);
  expect(await chatCommand({ resume: session.id }, config(), '/abs/config.json', { input: typed('and now', '/quit'), pollMs: 5 })).toBe(0);
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
  await expect(chatCommand({ resume: '00000000-0000-4000-8000-000000000000' }, config(), '/abs/config.json', { input: typed('/quit') })).rejects.toMatchObject({ code: 1, lines: ['There is no such session'] });
});
