import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
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
const host = async () => {
  const exit = vi.fn();
  const { stop } = await startChatHost(config(), { installLogging: () => {}, clock: new FakeClock(), exit, signals: false });
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
