import { mkdirSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import type { Config } from '../config/schema.ts';
import { connectControl } from '../terminal/cli/control-client.ts';
import { FakeClock } from '../orchestration/fake.ts';
import { acquireLock } from '../storage/lock.ts';
import { FakeChatRunner } from './fake.ts';
import { HostBusy, startChatHost } from './host.ts';

let root: string;
let stops: (() => Promise<void>)[];
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'hs-')); // short: a socket path holds 103 bytes on macOS
  stops = [];
});
afterEach(async () => {
  for (const stop of stops) await stop();
  rmSync(root, { recursive: true, force: true });
});

const config = () => ({ root, logLevel: 'info' }) as Config;
async function host(clock = new FakeClock(), claude = new FakeChatRunner()) {
  const exit = vi.fn();
  const started = await startChatHost(config(), { installLogging: () => {}, clock, exit, signals: false, runners: { claude }, binaryFound: () => true });
  stops.push(started.stop);
  return { ...started, exit, clock };
}

test('the host makes its folder 0700 with a 0600 socket, a lock, chat.db with a sessions table, and answers list', async () => {
  await host();
  const chat = join(root, 'chat');
  expect(statSync(chat).mode & 0o777).toBe(0o700);
  expect(statSync(join(chat, 'chat.sock')).mode & 0o777).toBe(0o600);
  expect(statSync(join(chat, 'carrier.lock')).isFile()).toBe(true);
  const db = new Database(join(chat, 'chat.db'), { readonly: true });
  expect(db.prepare("select name from sqlite_master where name = 'sessions'").all()).toHaveLength(1);
  db.close();
  const client = await connectControl(join(chat, 'chat.sock'));
  expect(client.hello.protocol).toBe(1);
  expect(await client.request('list')).toEqual({ sessions: [] });
  client.close();
});

test('a second host on the same root is refused, and the lock is free again after stop', async () => {
  const first = await host();
  await expect(startChatHost(config(), { installLogging: () => {}, signals: false })).rejects.toThrow(HostBusy);
  await first.stop();
  const again = await host();
  expect(again.exit).not.toHaveBeenCalled();
});

test('the chat lock and the engine lock are held together on one root', async () => {
  await host();
  const engine = acquireLock(join(root, 'orchestrator'));
  expect(engine.ok).toBe(true);
  expect(acquireLock(join(root, 'chat')).ok).toBe(false); // still the host's
  if (engine.ok) engine.release();
});

test('the stop request ends the host: it exits 0, removes the socket and frees the lock', async () => {
  const { exit } = await host();
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  await client.request('stop');
  await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(0));
  const lock = acquireLock(join(root, 'chat'));
  expect(lock.ok).toBe(true);
  if (lock.ok) lock.release();
  expect(() => statSync(join(root, 'chat', 'chat.sock'))).toThrow();
});

test('the host exits a minute after its start, and a client connected keeps it up until it leaves', async () => {
  const { clock, exit } = await host();
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  await clock.advance(5 * 60_000);
  expect(exit).not.toHaveBeenCalled();
  client.close();
  // the leave reaches the host a moment after close(), so the minute is advanced until it has been armed
  await vi.waitFor(async () => {
    await clock.advance(60_000);
    expect(exit).toHaveBeenCalledWith(0);
  });
});

test('a client opens a conversation, sends, reads the events by cursor and closes it, all over the socket; the stop closes what is live', async () => {
  const claude = new FakeChatRunner();
  claude.setup = (c) => {
    c.reply = (text) => c.emit({ kind: 'assistant', text: `re: ${text}` }, { kind: 'turn_end', outcome: 'ok' });
  };
  const { exit } = await host(new FakeClock(), claude);
  const work = join(root, 'w');
  mkdirSync(work);
  const client = await connectControl(join(root, 'chat', 'chat.sock'));
  expect(client.hello.capabilities).toEqual(expect.arrayContaining(['agents', 'open', 'send', 'events', 'close', 'list']));
  expect(await client.request('agents')).toEqual([
    { name: 'claude', harness: 'claude', found: true },
    { name: 'codex', harness: 'codex', found: true },
  ]);
  await expect(client.request('open', { agent: 'claude', folder: join(root, 'chat') })).resolves.toBeDefined(); // the chat folder is the host's own, not a forbidden one
  await expect(client.request('open', { agent: 'claude', folder: join(root, 'repos') })).rejects.toThrow('does not exist');
  mkdirSync(join(root, 'repos'));
  await expect(client.request('open', { agent: 'claude', folder: join(root, 'repos') })).rejects.toThrow('inside Carrier');
  await expect(client.request('open', { agent: 'codex', folder: work })).rejects.toThrow('no chat runner for codex');
  const { session } = (await client.request('open', { agent: 'claude', folder: work })) as { session: { id: string } };
  await client.request('send', { sessionId: session.id, text: 'hi' });
  const reply = (await client.request('events', { sessionId: session.id, limit: 50 })) as any;
  expect(reply.events.map((e: any) => [e.kind, e.text])).toEqual([['user', 'hi'], ['assistant', 're: hi'], ['turn_end', undefined]]);
  expect(reply.session).toMatchObject({ id: session.id, title: 'hi', state: 'idle' });
  expect(((await client.request('list')) as any).sessions).toHaveLength(2);
  await client.request('close', { sessionId: session.id });
  expect(claude.conversations.map((c) => c.closed)).toEqual([false, true]);
  await client.request('stop');
  await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(0));
  expect(claude.conversations.map((c) => c.closed)).toEqual([true, true]);
});
