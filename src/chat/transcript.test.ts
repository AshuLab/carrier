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
    const task = boundEvent({ kind: 'task', callId: 'c1', taskId: 't1', state: 'progress', agentType: 'Explore', text: `look at ${token} ${'y'.repeat(3000)}`, lastTool: 'Bash', tools: 2, tokens: 300, ms: 1200, background: true, parentCallId: 'agent-1' })!;
    expect(task).toEqual({ callId: 'c1', taskId: 't1', state: 'progress', agentType: 'Explore', text: expect.any(String), lastTool: 'Bash', tools: 2, tokens: 300, ms: 1200, background: true, parentCallId: 'agent-1' });
    expect((task.text as string).length).toBeLessThanOrEqual(chatCaps.arg);
    expect(task.text).not.toContain(token);
  });
});
