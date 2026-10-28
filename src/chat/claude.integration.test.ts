import { mkdtempSync, realpathSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, test } from 'vitest';
import { claudeChatRunner } from './claude.ts';
import type { ChatConversation, ChatEvent } from './runner.ts';

// The real Claude, through the user's own `claude` binary and login, in a temporary folder: two turns in one
// conversation, the second referring to the first, show that the context is kept; the model and the permission mode are
// changed in a running session and reported back. It sends two tiny prompts to the cheapest model, so it uses a little
// of the user's own plan. It only runs when this is set explicitly:
//   CARRIER_IT_CLAUDE_CHAT=1   (optional: CARRIER_IT_CLAUDE_COMMAND=<path to the claude binary>, else the one on the path)
// A second test interrupts a long turn and then asks a second message in the same session.
// No token is read or printed: the agent runs with the environment of this process, as the chat host runs it.
const enabled = process.env.CARRIER_IT_CLAUDE_CHAT === '1';

describe.skipIf(!enabled)('the Claude chat adapter against the real Claude', () => {
  let folder: string;
  let conversation: ChatConversation | undefined;
  beforeAll(() => {
    folder = realpathSync(mkdtempSync(join(tmpdir(), 'carrier-claude-chat-')));
  });
  afterAll(async () => {
    await conversation?.close();
    rmSync(folder, { recursive: true, force: true });
  });

  test('the second turn remembers the first', { timeout: 180_000 }, async () => {
    conversation = await claudeChatRunner().open({ folder, command: process.env.CARRIER_IT_CLAUDE_COMMAND, options: { model: 'haiku' }, env: process.env });
    const events: ChatEvent[] = [];
    conversation.onEvent((event) => events.push(event));
    const turn = async (text: string) => {
      const from = events.length;
      conversation!.send(text);
      await expect.poll(() => events.slice(from).some((e) => e.kind === 'turn_end'), { timeout: 120_000, interval: 200 }).toBe(true);
      return events.slice(from);
    };

    expect((await turn('Remember the secret word PINEAPPLE. Reply with just: OK')).at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
    const second = await turn('What secret word did I ask you to remember? Answer with just the word.');
    expect(second.filter((e) => e.kind === 'assistant').map((e) => (e as { text: string }).text).join(' ')).toContain('PINEAPPLE');
    expect(conversation.nativeId).toMatch(/^[0-9a-f-]{36}$/);
  });

  test('an interrupted long turn ends as interrupted and the same session answers the next message', { timeout: 180_000 }, async () => {
    const own = await claudeChatRunner().open({ folder, command: process.env.CARRIER_IT_CLAUDE_COMMAND, options: { model: 'haiku' }, env: process.env });
    const events: ChatEvent[] = [];
    own.onEvent((event) => events.push(event));
    try {
      own.send('Count from 1 to 400, one number per line, with no other text.');
      await expect.poll(() => events.some((e) => e.kind === 'delta'), { timeout: 120_000, interval: 100 }).toBe(true); // the turn is running
      await own.interrupt();
      expect(events.filter((e) => e.kind === 'turn_end')).toMatchObject([{ outcome: 'interrupted' }]);
      const from = events.length;
      own.send('Reply with just the word: READY');
      await expect.poll(() => events.slice(from).some((e) => e.kind === 'turn_end'), { timeout: 120_000, interval: 200 }).toBe(true);
      const after = events.slice(from);
      expect(after.filter((e) => e.kind === 'assistant').map((e) => (e as { text: string }).text).join(' ')).toContain('READY');
      expect(after.at(-1)).toMatchObject({ kind: 'turn_end', outcome: 'ok' });
    } finally {
      await own.close();
    }
  });

  test('the model and the permission mode change in a running session and are reported back', { timeout: 120_000 }, async () => {
    const running = await claudeChatRunner().open({ folder, command: process.env.CARRIER_IT_CLAUDE_COMMAND, options: { model: 'haiku' }, env: process.env });
    try {
      const events: ChatEvent[] = [];
      running.onEvent((event) => events.push(event));
      const current = (id: string) => running.options.find((o) => o.id === id)?.current;
      expect(running.options.map((o) => o.id)).toEqual(expect.arrayContaining(['permissionMode', 'model']));
      expect(current('model')).toBe('haiku');

      await running.setOption('permissionMode', 'acceptEdits');
      await running.setOption('model', 'sonnet');
      expect(current('permissionMode')).toBe('acceptEdits');
      expect(current('model')).toBe('sonnet');
      expect(events.filter((e) => e.kind === 'option')).toEqual(expect.arrayContaining([{ kind: 'option', id: 'permissionMode', value: 'acceptEdits' }, { kind: 'option', id: 'model', value: 'sonnet' }]));
      await expect(running.setOption('model', 'not-a-model')).rejects.toThrow();
    } finally {
      await running.close();
    }
  });
});
