import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { vi, afterAll, beforeAll, describe, expect, test } from 'vitest';
import { connectControl } from '../terminal/cli/control-client.ts';
import { realClock } from '../orchestration/clock.ts';
import { claudeChatRunner } from './claude.ts';
import { startChatHost } from './host.ts';

// The real Claude through two chat hosts over one `chat.db`: a fact told in a session of the first host is answered in
// the same session resumed by the second, after the first ended. It sends two tiny prompts to the cheapest model, so it
// uses a little of the user's own plan. It only runs when this is set explicitly:
//   CARRIER_IT_CLAUDE_CHAT=1   (optional: CARRIER_IT_CLAUDE_COMMAND=<path to the claude binary>, else the one on the path)
// No token is read or printed: the agent runs with the environment of this process, as the chat host runs it.
const enabled = process.env.CARRIER_IT_CLAUDE_CHAT === '1';

describe.skipIf(!enabled)('a chat session resumed by a second host, with the real Claude', () => {
  let root: string;
  let folder: string;
  beforeAll(() => {
    root = realpathSync(mkdtempSync(join(tmpdir(), 'cr-'))); // short: a socket path holds 103 bytes on macOS
    folder = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-resume-')));
  });
  afterAll(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    rmSync(folder, { recursive: true, force: true });
  });

  test('the second host answers with what the first was told', { timeout: 240_000 }, async () => {
    vi.stubEnv('CARRIER_HOME', root);
    mkdirSync(join(root, 'chat'), { recursive: true });
    const chat = { agents: { claude: { harness: 'claude', model: 'haiku', ...(process.env.CARRIER_IT_CLAUDE_COMMAND && { command: process.env.CARRIER_IT_CLAUDE_COMMAND }) } } };
    writeFileSync(join(root, 'chat', 'chat.json'), JSON.stringify(chat));
    const run = async (body: (client: Awaited<ReturnType<typeof connectControl>>) => Promise<void>) => {
      const exit = vi.fn();
      const host = await startChatHost({ installLogging: () => {}, clock: realClock, exit, signals: false, runners: { claude: claudeChatRunner() } });
      const client = await connectControl(join(root, 'chat', 'state', 'chat.sock'));
      try {
        await body(client);
      } finally {
        client.close();
        await host.stop();
      }
    };
    const ask = async (client: Awaited<ReturnType<typeof connectControl>>, sessionId: string, text: string) => {
      await client.request('send', { sessionId, text });
      let reply: any;
      await expect.poll(async () => (reply = await client.request('events', { sessionId, limit: 200 })) && reply.session.state, { timeout: 120_000, interval: 500 }).toBe('idle');
      return reply.events.filter((e: any) => e.kind === 'assistant').map((e: any) => e.text).join(' ') as string;
    };

    let sessionId = '';
    await run(async (client) => {
      sessionId = ((await client.request('open', { agent: 'claude', folder })) as any).session.id;
      await ask(client, sessionId, 'Remember the secret word PINEAPPLE. Reply with just: OK');
    });
    await run(async (client) => {
      await client.request('resume', { sessionId });
      expect(await ask(client, sessionId, 'What secret word did I ask you to remember? Answer with just the word.')).toContain('PINEAPPLE');
    });
  });
});
