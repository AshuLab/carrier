import { expect, test } from 'vitest';
import { FakeChatRunner } from './fake.ts';
import { buildHandoff } from './handoff.ts';
import type { StoredEvent } from './mcp.ts';

const user = (position: number, text: string, command?: string): StoredEvent => ({ position, kind: 'user', data: { text, ...(command !== undefined && { command }) } });
const agent = (position: number, text: string): StoredEvent => ({ position, kind: 'assistant', data: { text } });
const bytes = (text: string) => Buffer.byteLength(text, 'utf8');
// what the frame and the labels add around a handoff of one short message: found by building it
const frame = bytes(buildHandoff([user(0, '')], 100_000)!);

test('a session with no message of the person or the agent has no handoff', () => {
  expect(buildHandoff([])).toBeUndefined();
  expect(buildHandoff([{ position: 0, kind: 'reasoning', data: { text: 'hm' } }, { position: 1, kind: 'tool_start', data: { tool: 'Bash' } }, { position: 2, kind: 'notice', data: { text: 'n' } }])).toBeUndefined();
});

test('nothing is left out when everything fits, and reasoning and tool state are not in it', () => {
  const text = buildHandoff([user(0, 'hello'), { position: 1, kind: 'reasoning', data: { text: 'SECRET-THOUGHT' } }, { position: 2, kind: 'tool_start', data: { tool: 'Bash', arg: 'rm' } }, agent(3, 'hi there')])!;
  expect(text).toContain('[0] person:\nhello');
  expect(text).toContain('[3] agent:\nhi there');
  expect(text).not.toContain('SECRET-THOUGHT');
  expect(text).not.toContain('Bash');
  expect(text).toContain('Every message of the conversation is above.');
  expect(text).not.toContain('Left out');
  expect(text.endsWith('The `history` tool of the chat MCP reads them whole.')).toBe(true);
});

test('a command the person invoked is shown as the command', () => {
  expect(buildHandoff([user(0, '/pong ALPHA', 'pong'), agent(1, 'PONG:ALPHA')])).toContain('[0] person:\n/pong ALPHA');
});

test('the person\'s first message stays, then the newest, and the ids left out are their positions', () => {
  const events = [user(10, 'first'), agent(11, 'a'.repeat(50)), user(12, 'b'.repeat(50)), agent(13, 'c'.repeat(50)), user(14, 'newest')];
  const budget = bytes(buildHandoff([events[0]!, events[4]!], 100_000)!) + 10;
  const text = buildHandoff(events, budget)!;
  expect(text).toContain('[10] person:\nfirst');
  expect(text).toContain('[14] person:\nnewest');
  expect(text).not.toContain('bbbb');
  expect(text).toContain('Left out or cut, by id: 11, 12, 13.');
  expect(bytes(text)).toBeLessThanOrEqual(budget);
});

test('one message longer than the budget is cut at the budget', () => {
  const text = buildHandoff([user(0, 'x'.repeat(5000))], 1000)!;
  expect(bytes(text)).toBeLessThanOrEqual(1000);
  expect(bytes(text)).toBeGreaterThan(900);
  expect(text).toContain('[0] person (cut):');
  expect(text).toContain('Left out or cut, by id: 0.');
});

test('a cut never splits a multibyte character', () => {
  // each emoji is 4 bytes, so for most budgets the cut falls inside one
  for (let extra = 0; extra < 8; extra++) {
    const budget = frame + 40 + extra;
    const text = buildHandoff([user(0, '\u{1F600}'.repeat(100))], budget)!;
    expect(text).toContain('\u{1F600}');
    expect(text).not.toContain('\uFFFD');
    expect(bytes(text)).toBeLessThanOrEqual(budget);
    expect(Buffer.from(text, 'utf8').toString('utf8')).toBe(text);
  }
  const text = buildHandoff([user(0, 'ñ'.repeat(3000))], 1000)!;
  expect(bytes(text)).toBeLessThanOrEqual(1000);
  expect(text).not.toContain('\uFFFD');
});

test('a text exactly at the budget is not cut, and one byte less cuts it', () => {
  const events = [user(0, 'hello'), agent(1, 'world')];
  const exact = bytes(buildHandoff(events, 100_000)!);
  expect(buildHandoff(events, exact)).toBe(buildHandoff(events, 100_000));
  const under = buildHandoff(events, exact - 1)!;
  expect(under).toContain('Left out or cut, by id: 1.');
  expect(bytes(under)).toBeLessThanOrEqual(exact - 1);
});

test('the default budget is 16,000 bytes of the whole text', () => {
  const events = [user(0, 'first'), ...Array.from({ length: 20 }, (_, i) => (i % 2 === 0 ? agent(i + 1, 'é'.repeat(1000)) : user(i + 1, 'ñ'.repeat(1000))))];
  const text = buildHandoff(events)!;
  expect(bytes(text)).toBeLessThanOrEqual(16_000);
  expect(bytes(text)).toBeGreaterThan(15_000);
  expect(text).toContain('[0] person:\nfirst');
  expect(text).toContain('[20] person:'); // the newest comes first in line for the budget
});

test('the fake runner records the instructions a conversation was opened with', async () => {
  const runner = new FakeChatRunner();
  await runner.open({ folder: '/work', env: {}, instructions: 'HANDOFF TEXT' });
  await runner.open({ folder: '/work', env: {} });
  expect(runner.opened.map((args) => args.instructions)).toEqual(['HANDOFF TEXT', undefined]);
});
