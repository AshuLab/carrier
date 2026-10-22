import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { caps, createEventState, type AgentEvent } from '../execution/events.ts';
import { secretFixtures } from '../logging/secrets.fixture.ts';
import { parseCodexEvents } from './codex.ts';

const parseAll = (lines: string[]) => {
  const state = createEventState();
  return lines.flatMap((line) => parseCodexEvents(line, state));
};
const fixture = readFileSync(join(import.meta.dirname, 'codex-exec.fixture.jsonl'), 'utf8').trimEnd().split('\n');
const line = (o: unknown) => JSON.stringify(o);
const item = (type: 'item.started' | 'item.completed', body: object) => line({ type, item: body });
const command = (id: string, cmd: string, over: object = {}) => ({ id, type: 'command_execution', command: `/bin/zsh -lc '${cmd}'`, aggregated_output: '', exit_code: null, status: 'in_progress', ...over });
const done = { status: 'completed', exit_code: 0 };

test('the recorded run: messages, commands with output and exit code, a failing command, a file change, no time', () => {
  expect(parseAll(fixture)).toEqual<AgentEvent[]>([
    { kind: 'note', text: '`--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.' },
    { kind: 'note', text: '`--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.' },
    { kind: 'say', text: 'I’ll inspect the requested files, run both directory listings (including the expected failure), then make the two specified edits.' },
    { kind: 'tool_start', callId: 'item_3', tool: 'shell', arg: "sed -n '1,200p' notes.txt" },
    { kind: 'tool_end', callId: 'item_3', tool: 'shell', status: 'ok', summary: 'hello', output: ['hello', 'world'] },
    { kind: 'tool_start', callId: 'item_4', tool: 'shell', arg: 'ls -la' },
    {
      kind: 'tool_end',
      callId: 'item_4',
      tool: 'shell',
      status: 'ok',
      summary: 'total 8',
      output: [
        'total 8',
        'drwxr-xr-x@  4 user  wheel  128 Oct 21 19:11 .',
        'drwx------@  6 user  wheel  192 Oct 21 19:11 ..',
        'drwxr-xr-x@ 12 user  wheel  384 Oct 21 19:11 .git',
        '-rw-r--r--@  1 user  wheel   12 Oct 21 19:11 notes.txt',
      ],
    },
    { kind: 'tool_start', callId: 'item_5', tool: 'shell', arg: 'ls /no/such/dir' },
    { kind: 'tool_end', callId: 'item_5', tool: 'shell', status: 'err', summary: 'Exit code 1', output: ['ls: /no/such/dir: No such file or directory'] },
    { kind: 'tool_start', callId: 'item_6', tool: 'Edit', arg: '/work/repo/extra.txt, /work/repo/notes.txt' },
    { kind: 'tool_end', callId: 'item_6', tool: 'Edit', status: 'ok', summary: '2 files' },
    { kind: 'say', text: 'DONE' },
  ]);
});

test('a call open at the end of the stream is a start with no end, and the state forgets a closed one', () => {
  const state = createEventState();
  parseCodexEvents(item('item.started', command('a', 'sleep 9')), state);
  parseCodexEvents(item('item.started', command('b', 'ls')), state);
  parseCodexEvents(item('item.completed', command('b', 'ls', done)), state);
  expect([...state.calls.keys()]).toEqual(['a']);
});

test('a turn that failed is an error; retries, reasoning, todo lists, an unknown item, an unknown line and garbage give nothing', () => {
  const state = createEventState();
  expect(parseCodexEvents(line({ type: 'turn.failed', error: { message: 'unexpected status 401 Unauthorized' } }), state)).toEqual([{ kind: 'error', text: 'unexpected status 401 Unauthorized' }]);
  const quiet = [
    line({ type: 'error', message: 'Reconnecting... 1/5' }),
    line({ type: 'thread.started', thread_id: 't' }),
    line({ type: 'turn.started' }),
    line({ type: 'turn.completed', usage: {} }),
    item('item.completed', { id: 'i', type: 'reasoning', text: 'hmm' }),
    item('item.completed', { id: 'i', type: 'todo_list', items: [] }),
    item('item.completed', { id: 'i', type: 'from_a_future_version', anything: [1, 2] }),
    line({ type: 'from_a_future_version' }),
    'not json {',
  ];
  for (const text of quiet) expect(parseCodexEvents(text, state), text).toEqual([]);
});

test('a missing exit code falls back on the status, and a field the stream lacks is simply absent', () => {
  const state = createEventState();
  expect(parseCodexEvents(item('item.completed', command('a', 'x', { status: 'failed', exit_code: null })), state)).toEqual([{ kind: 'tool_end', callId: 'a', tool: 'shell', status: 'err' }]);
  expect(parseCodexEvents(item('item.completed', { id: 'f', type: 'file_change', changes: [{ path: '/a', kind: 'add' }], status: 'failed' }), state)).toEqual([{ kind: 'tool_end', callId: 'f', tool: 'Edit', status: 'err', summary: '1 file' }]);
});

test('it never throws, whatever the line holds', () => {
  const state = createEventState();
  for (const text of ['', ' ', 'null', '42', '"s"', '[]', '{}', '{"item":null}', '{"type":"item.started"}', '{"type":"item.started","item":"x"}', '{"type":"item.completed","item":{"type":"command_execution"}}', '{"type":"item.started","item":{"id":1,"type":"command_execution","command":5}}', '{"type":"item.started","item":{"id":"c","type":"file_change","changes":[null,1,{"path":5}]}}', '{"type":"item.completed","item":{"id":"c","type":"command_execution","aggregated_output":[1],"exit_code":"x"}}', '{"type":"turn.failed"}', '{"type":"turn.failed","error":null}']) {
    expect(() => parseCodexEvents(text, state), text).not.toThrow();
  }
});

test('the caps: message 4 KB, argument 1 KB, summary 200 characters, a command output keeps its first and last lines within 4 KB', () => {
  const long = 'x'.repeat(10_000);
  const state = createEventState();
  expect(parseCodexEvents(item('item.completed', { id: 'm', type: 'agent_message', text: long }), state)[0]!.text).toHaveLength(caps.text);
  const [start] = parseCodexEvents(item('item.started', command('c', long)), state);
  expect(start!.arg).toHaveLength(caps.arg);
  const [small] = parseCodexEvents(item('item.completed', command('c', 'x', { ...done, aggregated_output: `${long}\nsecond` })), state);
  expect(small!.summary).toHaveLength(caps.summary);

  const body = Array.from({ length: 2000 }, (_, i) => `line ${i}`).join('\n');
  const [end] = parseCodexEvents(item('item.completed', command('d', 'x', { ...done, aggregated_output: body })), state);
  expect(end!.output!.join('\n').length).toBeLessThanOrEqual(caps.output);
  expect(end!.output![0]).toBe('line 0');
  expect(end!.output!.at(-1)).toBe('line 1999');
  expect(end!.output).toContain('…');
});

test.each(Object.entries(secretFixtures))('no event keeps %s, wherever the agent put it', (_shape, { text, secret }) => {
  const stream = [
    item('item.completed', { id: 'm', type: 'agent_message', text }),
    item('item.completed', { id: 'e', type: 'error', message: text }),
    item('item.started', command('c', `echo ${text}`)),
    item('item.completed', command('c', `echo ${text}`, { status: 'failed', exit_code: 2, aggregated_output: `first\n${text}\nlast` })),
    item('item.completed', command('d', 'x', { ...done, aggregated_output: `${text}\nsecond` })),
    item('item.started', { id: 'f', type: 'file_change', changes: [{ path: `/f/${text}`, kind: 'add' }], status: 'in_progress' }),
    line({ type: 'turn.failed', error: { message: text } }),
  ];
  const events = parseAll(stream);
  expect(events.length).toBeGreaterThanOrEqual(7);
  expect(JSON.stringify(events)).not.toContain(secret);
});
