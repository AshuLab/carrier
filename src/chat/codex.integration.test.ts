import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import { codexChatRunner } from './codex.ts';
import type { ChatConversation, ChatEvent } from './runner.ts';

// The real Codex, through the user's own `codex` binary and login, in a temporary folder: two turns in one conversation,
// the second referring to the first, show that the context is kept; a long turn is interrupted and the same session
// answers the next message; a second process resumes the conversation by its thread id and still remembers. It sends a
// few tiny prompts at low reasoning effort, so it uses a little of the user's own plan. It only runs when this is set
// explicitly:
//   CARRIER_IT_CODEX_CHAT=1   (optional: CARRIER_IT_CODEX_COMMAND=<path to the codex binary>, else the one on the path)
// No token is read or printed: the agent runs with the environment of this process, as the chat host runs it.
const enabled = process.env.CARRIER_IT_CODEX_CHAT === '1';

describe.skipIf(!enabled)('the Codex chat adapter against the real Codex', () => {
  let folder: string;
  const open = (resume?: string) => codexChatRunner().open({ folder, resume, command: process.env.CARRIER_IT_CODEX_COMMAND, options: { effort: 'low' }, env: process.env });
  const watch = (conversation: ChatConversation) => {
    const events: ChatEvent[] = [];
    conversation.onEvent((event) => events.push(event));
    const said = (from: number) => events.slice(from).filter((e) => e.kind === 'assistant').map((e) => (e as { text: string }).text).join(' ');
    const turn = async (text: string) => {
      const from = events.length;
      conversation.send(text);
      await expect.poll(() => events.slice(from).some((e) => e.kind === 'turn_end'), { timeout: 120_000, interval: 200 }).toBe(true);
      return from;
    };
    return { events, said, turn };
  };
  let nativeId: string | undefined;
  beforeAll(() => {
    folder = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-codex-chat-')));
  });
  afterAll(() => rmSync(folder, { recursive: true, force: true }));

  test('the second turn remembers the first, an interrupted turn ends as interrupted and the session answers the next message', { timeout: 300_000 }, async () => {
    const conversation = await open();
    try {
      const { events, said, turn } = watch(conversation);
      const first = await turn('Remember the secret word PINEAPPLE. Reply with just: OK');
      expect(events.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
      expect(said(first)).toContain('OK');
      const second = await turn('What secret word did I ask you to remember? Answer with just the word.');
      expect(said(second)).toContain('PINEAPPLE');
      expect(conversation.nativeId).toMatch(/^[0-9a-f-]{36}$/);
      nativeId = conversation.nativeId;
      expect(conversation.process).toMatchObject({ pid: expect.any(Number), pgid: conversation.process!.pid });

      const long = events.length;
      conversation.send('Count from 1 to 400, one number per line, with no other text.');
      await expect.poll(() => events.slice(long).some((e) => e.kind === 'delta'), { timeout: 120_000, interval: 100 }).toBe(true); // the turn is running
      await conversation.interrupt();
      expect(events.slice(long).filter((e) => e.kind === 'turn_end')).toMatchObject([{ outcome: 'interrupted' }]);
      const after = await turn('Reply with just the word: READY');
      expect(said(after)).toContain('READY');
      expect(events.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
    } finally {
      await conversation.close();
    }
  });

  test('a second process resumes the conversation by its thread id and still remembers it', { timeout: 180_000 }, async () => {
    expect(nativeId).toBeDefined();
    const conversation = await open(nativeId);
    try {
      const { said, turn } = watch(conversation);
      expect(conversation.nativeId).toBe(nativeId);
      expect(said(await turn('What secret word did I ask you to remember earlier? Answer with just the word.'))).toContain('PINEAPPLE');
    } finally {
      await conversation.close();
    }
  });
});
