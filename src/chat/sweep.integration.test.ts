import { spawn } from 'node:child_process';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import Database from 'better-sqlite3';
import { vi, afterAll, beforeAll, describe, expect, test } from 'vitest';
import { connectControl } from '../terminal/cli/control-client.ts';
import { realClock } from '../orchestration/clock.ts';
import { claudeChatRunner } from './claude.ts';
import { startChatHost } from './host.ts';

// A chat host killed with SIGKILL while a real Claude session is live leaves its agent running; the next host ends that
// process group and leaves the session resumable. The host is a child process of this test (so it can be killed) and
// the only processes signalled are that host and the agent group it recorded. It sends one tiny prompt to the cheapest
// model, so it uses a little of the user's own plan. It only runs when this is set explicitly:
//   CARRIER_IT_CLAUDE_CHAT=1   (optional: CARRIER_IT_CLAUDE_COMMAND=<path to the claude binary>, else the one on the path)
// No token is read or printed: the agent runs with the environment of this process, as the chat host runs it.
const enabled = process.env.CARRIER_IT_CLAUDE_CHAT === '1';

const groupAlive = (pgid: number) => {
  try {
    process.kill(-pgid, 0);
    return true;
  } catch {
    return false;
  }
};

describe.skipIf(!enabled)('the sweep of a dead chat host, with the real Claude', () => {
  let root: string;
  let folder: string;
  beforeAll(() => {
    root = realpathSync(mkdtempSync(join(tmpdir(), 'cs-'))); // short: a socket path holds 103 bytes on macOS
    folder = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-sweep-')));
  });
  afterAll(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    rmSync(folder, { recursive: true, force: true });
  });

  test('the next host ends the group the dead one left and the session resumes', { timeout: 240_000 }, async () => {
    const chat = { agents: { claude: { harness: 'claude', model: 'haiku', ...(process.env.CARRIER_IT_CLAUDE_COMMAND && { command: process.env.CARRIER_IT_CLAUDE_COMMAND }) } } };
    vi.stubEnv('CARRIER_HOME', root);
    mkdirSync(join(root, 'chat'), { recursive: true });
    writeFileSync(join(root, 'chat', 'chat.json'), JSON.stringify(chat));
    const main = join(import.meta.dirname, '../terminal/cli/main.ts');
    const child = spawn(process.execPath, [main, 'chat-host'], { stdio: 'ignore', env: { ...process.env, CARRIER_HOME: root } });
    const socket = join(root, 'chat', 'state', 'chat.sock');
    let pgid: number | undefined;
    try {
      let client: Awaited<ReturnType<typeof connectControl>> | undefined;
      await expect.poll(async () => (client = await connectControl(socket).catch(() => undefined)) !== undefined, { timeout: 30_000, interval: 200 }).toBe(true);
      const { session } = (await client!.request('open', { agent: 'claude', folder })) as { session: { id: string } };
      await client!.request('send', { sessionId: session.id, text: 'Reply with just: OK' });
      await expect.poll(async () => ((await client!.request('events', { sessionId: session.id, limit: 200 })) as any).session.state, { timeout: 120_000, interval: 500 }).toBe('idle');
      client!.close();

      const read = () => {
        const raw = new Database(join(root, 'chat', 'state', 'chat.db'), { readonly: true });
        const found = raw.prepare('select pid, pgid, command, nativeId from sessions where id = ?').get(session.id) as { pid: number | null; pgid: number | null; command: string | null; nativeId: string | null };
        raw.close();
        return found;
      };
      const before = read();
      expect(before).toMatchObject({ pid: expect.any(Number), pgid: before.pid, command: expect.any(String), nativeId: expect.any(String) });
      pgid = before.pgid!;
      expect(groupAlive(pgid)).toBe(true);

      child.kill('SIGKILL');
      await new Promise((resolve) => child.once('exit', resolve));
      expect(groupAlive(pgid)).toBe(true); // the agent outlived its host

      const exit = vi.fn();
      const host = await startChatHost({ installLogging: () => {}, clock: realClock, exit, signals: false, runners: { claude: claudeChatRunner() } });
      try {
        expect(groupAlive(pgid)).toBe(false);
        expect(read()).toMatchObject({ pid: null, pgid: null, command: null, nativeId: before.nativeId });
        const next = await connectControl(socket);
        try {
          await next.request('resume', { sessionId: session.id });
        } finally {
          next.close();
        }
      } finally {
        await host.stop();
      }
    } finally {
      child.kill('SIGKILL');
      if (pgid !== undefined && groupAlive(pgid)) process.kill(-pgid, 'SIGKILL'); // the agent group this test started
    }
  });
});
