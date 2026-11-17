import { describe, expect, it } from 'vitest';
import { boundEvent, chatCaps, previewOf, titleOf } from './transcript.ts';

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
  it('drops the input the adapter handed the host and keeps the whole text up to the length of a message', () => {
    const choices = [{ id: 'allow', label: 'Allow', allow: true }];
    const stored = boundEvent({ kind: 'approval', approvalId: 'a1', tool: 'delegate_start', arg: 'x'.repeat(chatCaps.message + 10), input: { task: 'secret' }, choices })!;
    expect(stored).not.toHaveProperty('input');
    expect((stored.arg as string).length).toBe(chatCaps.message);
  });
});
