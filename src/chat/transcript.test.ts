import { describe, expect, it } from 'vitest';
import { previewOf, titleOf } from './transcript.ts';

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
