import { expect, test, vi } from 'vitest';
import { agyAdapter } from './agy.ts';
import { claudeAdapter } from './claude.ts';
import { codexAdapter } from './codex.ts';
import { parseJsonLine, splitLines } from './common.ts';
import { createEventState } from '../execution/events.ts';

/** What the reader used to do: the whole of what is pending is searched again with each chunk. */
const oldWay = (chunks: string[]) => {
  let pending = '';
  const lines: string[] = [];
  for (const chunk of chunks) {
    const found = (pending + chunk).split('\n');
    pending = found.pop()!;
    lines.push(...found);
  }
  return { lines, rest: pending };
};
const newWay = (chunks: string[]) => {
  const reader = splitLines();
  return { lines: chunks.flatMap((chunk) => reader.push(chunk)), rest: reader.rest() };
};

test('the lines come out as they always did, whatever the chunks cut: at a newline, inside a line, empty, or a bare newline', () => {
  const text = 'one\ntwo\n\nthree\n{"a":1}\nlast with no newline';
  for (let size = 1; size <= text.length; size++) {
    const chunks = Array.from({ length: Math.ceil(text.length / size) }, (_, i) => text.slice(i * size, (i + 1) * size));
    expect(newWay(chunks), `chunks of ${size}`).toEqual(oldWay(chunks));
  }
  for (const chunks of [['\n'], ['', 'a', '', '\n', ''], ['a\n', '\nb'], ['x', '\n\n', 'y\n']]) expect(newWay(chunks)).toEqual(oldWay(chunks));
});

test('a line of ten megabytes in chunks of 64 KB comes out whole and once, and reading it does not search what was already read', () => {
  const line = 'x'.repeat(10 * 1024 * 1024);
  const reader = splitLines();
  const out: string[] = [];
  for (let at = 0; at < line.length; at += 65_536) out.push(...reader.push(line.slice(at, at + 65_536)));
  expect(out).toEqual([]); // not a line yet
  out.push(...reader.push('\n'));
  expect(out).toHaveLength(1);
  expect(out[0]!.length).toBe(line.length);
  expect(reader.rest()).toBe('');
});

test('a line that has no newline yet is not split or searched again by the chunks that follow it', () => {
  const split = vi.spyOn(String.prototype, 'split');
  const reader = splitLines();
  const chunk = 'y'.repeat(65_536);
  for (let i = 0; i < 160; i++) reader.push(chunk); // ten megabytes, no newline
  const calls = split.mock.calls.length;
  reader.push('\n');
  split.mockRestore();
  expect(calls).toBe(0); // the old reader split pending + chunk 160 times
});

test('a line goes through the events and the signal of an adapter with one JSON.parse, and a line that is not JSON gives the same error to both', () => {
  const parse = vi.spyOn(JSON, 'parse');
  const lines = {
    claude: [claudeAdapter, '{"type":"system","subtype":"init","session_id":"s1"}'],
    codex: [codexAdapter, '{"type":"thread.started","thread_id":"t1"}'],
    agy: [agyAdapter, '{"event":"init","conversation_id":"c1"}'],
  } as const;
  for (const [name, [adapter, line]] of Object.entries(lines)) {
    parse.mockClear();
    adapter.parseEvents?.(line, createEventState());
    adapter.parseLine(line, 'stdout');
    expect(parse.mock.calls.length, name).toBe(1);
  }
  parse.mockRestore();
  // not JSON: both see the failure (the Codex signal reads the text of the line when it is not JSON)
  const text = 'Error: thread/resume failed: no rollout found for thread id 01a1';
  expect(() => parseJsonLine(text)).toThrow(SyntaxError);
  expect(() => parseJsonLine(text)).toThrow(SyntaxError); // the same line again: the same error, not a value
  expect(codexAdapter.parseLine(text, 'stderr')).toEqual({ sessionUnavailable: true });
});

test('both readers of a line share its parse and then it is forgotten, so reading it again parses again', () => {
  const parse = vi.spyOn(JSON, 'parse');
  parseJsonLine('{"b":1}');
  parseJsonLine('{"b":1}');
  expect(parse.mock.calls.length).toBe(1);
  parseJsonLine('{"b":1}'); // a third reading is another line, as far as the memo knows
  expect(parse.mock.calls.length).toBe(2);
  parse.mockRestore();
});

test('a different line is parsed again, and what comes back is the line\'s own value', () => {
  expect(parseJsonLine('{"a":1}')).toEqual({ a: 1 });
  expect(parseJsonLine('{"a":2}')).toEqual({ a: 2 });
  expect(parseJsonLine('null')).toBeNull();
});
