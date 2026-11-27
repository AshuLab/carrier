import { describe, expect, it } from 'vitest';
import { clean } from '../execution/events.ts';
import { boundEvent, chatCaps, previewOf, titleOf, withoutPasted } from './transcript.ts';

const log = Array.from({ length: 87 }, (_, i) => `line ${i + 1}`).join('\n');

describe('a text pasted into the message box', () => {
  it('is a few words in a title and a preview, not its first lines', () => {
    const typed = `why does this fail?\n\n\`\`\`pasted\n${log}\n\`\`\``;
    expect(titleOf(typed)).toBe('why does this fail?');
    expect(previewOf(typed)).toBe('why does this fail? [Pasted text · 87 lines]');
    // with nothing typed it is the whole message
    expect(titleOf(`\`\`\`pasted\n${log}\n\`\`\``)).toBe('[Pasted text · 87 lines]');
    expect(previewOf(`\`\`\`\`pasted\n${log} \`\`\` inside\n\`\`\`\``)).toBe('[Pasted text · 87 lines]');
  });

  it('leaves any other fenced block, and an unclosed one, as they are', () => {
    expect(previewOf('see:\n```ts\nlet a = 1\n```')).toBe('see: ```ts let a = 1 ```');
    expect(titleOf('```pasted\nnever closed')).toBe('```pasted');
  });
});

describe('what a subagent made is stored with the call that launched it, bounded and redacted as the main agent\'s is', () => {
  const token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
  const long = Array.from({ length: 2000 }, (_, i) => `line ${i} ${token}`);

  it('keeps the parent on a call and bounds and redacts its output as it does outside a subagent', () => {
    const inside = boundEvent({ kind: 'tool_end', callId: 'c1', tool: 'Bash', output: long, status: 'ok', parentCallId: 'agent-1' })!;
    const outside = boundEvent({ kind: 'tool_end', callId: 'c1', tool: 'Bash', output: long, status: 'ok' })!;
    expect(inside).toEqual({ ...outside, parentCallId: 'agent-1' });
    expect((inside.output as string[]).join('\n').length).toBeLessThan(5000);
    expect(JSON.stringify(inside)).not.toContain(token);
    const start = boundEvent({ kind: 'tool_start', callId: 'c1', tool: 'Bash', arg: `curl -H "Authorization: ${token}" ${'x'.repeat(2000)}`, parentCallId: 'agent-1' })!;
    expect(start).toMatchObject({ callId: 'c1', parentCallId: 'agent-1' });
    expect((start.arg as string).length).toBeLessThanOrEqual(chatCaps.arg);
    expect(JSON.stringify(start)).not.toContain(token);
  });

  it('keeps the parent on a message and a thought, and a message with none is as it was', () => {
    expect(boundEvent({ kind: 'assistant', text: `done ${token}`, parentCallId: 'agent-1' })).toEqual({ text: expect.not.stringContaining(token), parentCallId: 'agent-1' });
    expect(boundEvent({ kind: 'reasoning', text: 'hm', parentCallId: 'agent-1' })).toEqual({ text: 'hm', parentCallId: 'agent-1' });
    expect(boundEvent({ kind: 'assistant', text: 'plain' })).toEqual({ text: 'plain' });
  });

  it('keeps every field of a task and bounds and redacts its words', () => {
    const task = boundEvent({ kind: 'task', callId: 'c1', taskId: 't1', state: 'progress', agentType: 'Explore', text: `look at ${token} ${'y'.repeat(3000)}`, lastTool: 'Bash', tools: 2, tokens: 300, ms: 1200, background: true, parentCallId: 'agent-1', summary: 'ignored on progress' })!;
    expect(task).toEqual({ callId: 'c1', taskId: 't1', state: 'progress', agentType: 'Explore', text: expect.any(String), lastTool: 'Bash', tools: 2, tokens: 300, ms: 1200, background: true, parentCallId: 'agent-1' });
    expect((task.text as string).length).toBeLessThanOrEqual(chatCaps.arg);
    expect(task.text).not.toContain(token);
  });

  it('redacts and cuts an end task summary at the cap of an assistant message', () => {
    for (const state of ['completed', 'failed', 'stopped'] as const) {
      const stored = boundEvent({ kind: 'task', callId: 'c1', taskId: 't1', state, summary: `secret ${token} ${'z'.repeat(chatCaps.message)}` })!;
      expect(stored.summary).toContain('[redacted]');
      expect(stored.summary).not.toContain(token);
      expect((stored.summary as string).length).toBe(chatCaps.message);
      expect((stored.summary as string).endsWith('…')).toBe(true);
    }
    // a cut inside an emoji must not leave half of it: JSON writes it as a lone surrogate and Swift's decoder refuses the whole reply
    const emoji = boundEvent({ kind: 'task', callId: 'c1', taskId: 't1', state: 'completed', summary: `${'a'.repeat(chatCaps.message - 2)}😀${'b'.repeat(10)}` })!;
    expect((emoji.summary as string).isWellFormed()).toBe(true);
    expect((emoji.summary as string).length).toBeLessThanOrEqual(chatCaps.message);
    expect((emoji.summary as string).endsWith('…')).toBe(true);
    const started = boundEvent({ kind: 'task', callId: 'c1', taskId: 't1', state: 'started', summary: 'ignored on started' })!;
    expect(started).not.toHaveProperty('summary');
  });
});

describe('the stored form of an error', () => {
  it('keeps its reason and its reset, the words cut like the text', () => {
    expect(boundEvent({ kind: 'error', text: 'plain' })).toEqual({ text: 'plain' });
    expect(boundEvent({ kind: 'error', text: 'limit', reason: 'usage_limit', resetsAt: 1_800_000_000_000 })).toEqual({ text: 'limit', reason: 'usage_limit', resetsAt: 1_800_000_000_000 });
    const stored = boundEvent({ kind: 'error', text: 'limit', reason: 'usage_limit', resetText: `resets 9am ${'x'.repeat(chatCaps.error)}` })!;
    expect(stored.reason).toBe('usage_limit');
    expect((stored.resetText as string).length).toBeLessThanOrEqual(chatCaps.error);
  });
});

describe('the stored form of an approval', () => {
  it('keeps the whole text up to the length of a message', () => {
    const choices = [{ id: 'allow', label: 'Allow', allow: true }];
    const stored = boundEvent({ kind: 'approval', approvalId: 'a1', tool: 'delegate_start', arg: 'x'.repeat(chatCaps.message + 10), choices })!;
    expect((stored.arg as string).length).toBe(chatCaps.message);
  });
});

describe('the preview of a long message reads only its start', () => {
  // what the preview was before it read only the start: the whole message redacted and then cut
  const whole = (text: string) => clean(withoutPasted(text).replace(/\s+/g, ' ').trim(), chatCaps.preview);
  const token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
  const prose = 'The quick brown fox, see src/chat/a.ts line 12.\n'.repeat(1_400);
  const samples: Record<string, string> = {
    short: 'Done. Tests pass.',
    prose,
    code: 'const a = { b: 1 }; // x\n'.repeat(2_700),
    blanksFirst: `${' \n\t'.repeat(5_000)}hello world ${'a'.repeat(500)}`,
    blanksBetween: `first${' '.repeat(40_000)}second ${'b'.repeat(300)}`,
    pasted: `why?\n\n\`\`\`pasted\n${prose}\n\`\`\`\n${prose}`,
    secretInside: `deploy with ${token} now ${prose}`,
    secretAtTheEdge: `${'x'.repeat(190)} ${token} ${prose}`,
    // 195 words, then blanks that make the first 2,000 characters end 5 characters into a key that `redact` knows from 16 characters on
    keyAtTheRawEdge: `${'a'.repeat(195)}${' '.repeat(1_800)}sk-${'A'.repeat(30)} ${prose}`,
    // a quoted value that opens in the preview and closes past what is read: redact hides the whole assignment only when it sees the closing quote
    quotedSecret: `deploy with DB_PASSWORD="hunter2 correct horse${' battery staple'.repeat(150)}" thanks`,
    quotedMultiline: `export API_KEY='${Array.from({ length: 200 }, (_, i) => `secret line ${i}`).join('\n')}'\n${prose}`,
    // a token whose middle part runs past the first 2,000 characters: redact needs the third part to hide it
    jwtPastTheRead: `token: eyJ${'a'.repeat(20)}.${'b'.repeat(1_990)}.${'c'.repeat(100)} tail ${prose}`,
    nameRunPastTheRead: `see ${'KEY'.repeat(700)}=1 ${prose}`,
    exactly: 'e'.repeat(chatCaps.preview),
    justOver: 'e'.repeat(chatCaps.preview + 1),
  };

  it('is what reading the whole message gave, for prose, code, blanks, a pasted block and a secret near the cut', () => {
    for (const [name, text] of Object.entries(samples)) expect(previewOf(text), name).toBe(whole(text));
    expect(previewOf(samples.secretInside!)).toContain('[redacted]');
    expect(previewOf(samples.secretAtTheEdge!)).not.toContain('ghp_');
    expect(previewOf(samples.keyAtTheRawEdge!)).not.toContain('sk-');
    expect(previewOf(samples.quotedSecret!)).not.toContain('hunter2');
    expect(previewOf(samples.quotedMultiline!)).not.toContain('secret line');
    expect(previewOf(samples.jwtPastTheRead!)).not.toContain('eyJ');
  });

  it('redacts a private key block that starts in the preview and runs past what was read', () => {
    const key = `-----BEGIN PRIVATE KEY-----\n${'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC'.repeat(400)}\n-----END PRIVATE KEY-----\n${prose}`;
    expect(previewOf(`here: ${key}`)).toBe(whole(`here: ${key}`));
    expect(previewOf(`here: ${key}`)).not.toContain('MIIE');
  });

  it('is much cheaper than redacting and collapsing 64,000 characters', () => {
    const text = prose.slice(0, chatCaps.message);
    const time = (read: (text: string) => string) => {
      for (let i = 0; i < 20; i++) read(text);
      const start = performance.now();
      for (let i = 0; i < 300; i++) read(text);
      return performance.now() - start;
    };
    expect(time(previewOf) * 4).toBeLessThan(time(whole));
  });
});
