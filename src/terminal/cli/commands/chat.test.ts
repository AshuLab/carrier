import { mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventEmitter } from 'node:events';
import { PassThrough, Readable } from 'node:stream';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { FakeChatRunner } from '../../../chat/fake.ts';
import { startChatHost } from '../../../chat/host.ts';
import type { Config } from '../../../config/schema.ts';
import { FakeClock } from '../../../orchestration/fake.ts';
import { CliError } from '../cli-error.ts';
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
  const running = chatCommand({ workspace: root }, config(), '/abs/config.json', { input, sigint, pollMs: 5 });
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
  expect(await chatCommand({ workspace: root }, config(), '/abs/config.json', { input: typed('/options', '/option mode plan', '/option mode yolo', '/option nope x', '/option mode', '/options', '/quit'), pollMs: 5 })).toBe(0);
  const out = written.join('');
  expect(out).toContain('> Permission mode (mode): default\n    offers: default, plan\nModel (model): haiku\n    offers: haiku\n> ');
  expect(out).toContain('> Permission mode (mode): plan\n    offers: default, plan\n> ');
  expect(out).toContain('"yolo" is not a value of the option "mode"; it offers: default, plan\n');
  expect(out).toContain('no option "nope"');
  expect(out).toContain('Usage: /option <id> <value>\n');
  expect(out.lastIndexOf('Permission mode (mode): plan')).toBeGreaterThan(out.indexOf('Usage:')); // the second /options sees the change
  expect(claude.conversations[0]!.sent).toEqual([]); // none of this went to the agent
});
