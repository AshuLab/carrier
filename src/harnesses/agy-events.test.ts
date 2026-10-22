import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { caps, createEventState, type AgentEvent } from '../execution/events.ts';
import { secretFixtures } from '../logging/secrets.fixture.ts';
import { parseAgyEvents } from './agy.ts';

const lines = readFileSync(new URL('./agy-stream.fixture.jsonl', import.meta.url), 'utf8').trimEnd().split('\n');
const parseAll = (input: string[]) => {
  const state = createEventState();
  return input.flatMap((l) => parseAgyEvents(l, state));
};
const conv = '00000000-0000-4000-8000-000000000001';
const step = (o: object) => JSON.stringify({ event: 'step_update', step_update: { conversation_id: conv, ...o } });
const tool = (index: number, state: 'ACTIVE' | 'DONE', name: string, parameters: object, extra: object = {}, output?: string) =>
  step({ step_index: index, state, step_type: 'tool', tool_name: name, tool_info: { name, parameters, ...(output === undefined ? {} : { output }) }, ...extra });

test('the recorded stream: tool calls paired with their duration and result, the final answer as one message', () => {
  const events = parseAll(lines);
  expect(events.map(({ kind, tool: t, status }) => [kind, t, status])).toEqual([
    ['tool_start', 'run_command', undefined],
    ['tool_end', 'run_command', 'ok'],
    ['tool_start', 'run_command', undefined],
    ['tool_end', 'run_command', 'err'],
    ['tool_start', 'read_file', undefined],
    ['tool_end', 'read_file', 'ok'],
    ['tool_start', 'edit_file', undefined],
    ['tool_end', 'edit_file', 'ok'],
    ['tool_start', 'run_command', undefined],
    ['tool_end', 'run_command', 'ok'],
    ['say', undefined, undefined],
  ]);
  expect(events[2]).toEqual<AgentEvent>({ kind: 'tool_start', callId: `${conv}:4`, tool: 'run_command', arg: 'ls /nonexistent' });
  expect(events[3]).toEqual<AgentEvent>({
    kind: 'tool_end',
    callId: `${conv}:4`,
    tool: 'run_command',
    status: 'err',
    durationMs: 114,
    summary: 'Exit code 1',
    output: ['ls: /nonexistent: No such file or directory'],
  });
  expect(events[5]).toMatchObject({ kind: 'tool_end', tool: 'read_file', durationMs: 74, summary: '2 lines, 11 bytes' });
  expect(events[5]!.output).toBeUndefined(); // only a command keeps its output
  expect(events[6]).toMatchObject({ kind: 'tool_start', tool: 'edit_file', arg: '/work/repo/notes.txt' });
  expect(events[7]).toMatchObject({ kind: 'tool_end', durationMs: 97 });
  expect(events[7]!.summary).toBeUndefined();
  expect(events[10]).toEqual<AgentEvent>({
    kind: 'say',
    text: "I have searched for 'beta', attempted to list `/nonexistent`, replaced 'beta' with 'gamma' in [notes.txt](file:///work/repo/notes.txt), and listed the directory contents.",
  });
});

test('a step that never completes is a call with no end; a turn left open is said when the run ends', () => {
  const stream = [
    tool(1, 'ACTIVE', 'run_command', { CommandLine: 'sleep 999' }),
    step({ step_index: 2, state: 'ACTIVE', step_type: 'agent_response', text_delta: 'half a thou' }),
    step({ step_index: 2, state: 'ACTIVE', step_type: 'agent_response', text_delta: 'ght' }),
  ];
  expect(parseAll(stream)).toEqual([{ kind: 'tool_start', callId: `${conv}:1`, tool: 'run_command', arg: 'sleep 999' }]);
  expect(parseAll([...stream, JSON.stringify({ event: 'result', result: { status: 'ERROR', error: 'interrupted' } })]).slice(1)).toEqual([
    { kind: 'say', text: 'half a thought' },
    { kind: 'error', text: 'interrupted' },
  ]);
});

test('an unknown step type gives nothing, an unknown tool is shown by name', () => {
  const state = createEventState();
  expect(parseAgyEvents(step({ step_index: 1, state: 'DONE', step_type: 'from_the_future', text_delta: 'x' }), state)).toEqual([]);
  expect(parseAgyEvents(JSON.stringify({ event: 'from_the_future' }), state)).toEqual([]);
  expect(parseAgyEvents(tool(2, 'ACTIVE', 'browser_click_element', { Selector: '#go' }), state)).toEqual([{ kind: 'tool_start', callId: `${conv}:2`, tool: 'browser_click_element', arg: '#go' }]);
  expect(parseAgyEvents(tool(2, 'DONE', 'browser_click_element', { Selector: '#go' }, { duration_seconds: 1.5 }, 'clicked\nok'), state)).toEqual([
    { kind: 'tool_end', callId: `${conv}:2`, tool: 'browser_click_element', status: 'ok', durationMs: 1500, summary: 'clicked' },
  ]);
});

test('it never throws, whatever the line holds', () => {
  const state = createEventState();
  for (const text of ['', ' ', 'null', '42', '"s"', '[]', '{}', 'not json {', '{"event":"step_update"}', '{"event":"step_update","step_update":null}', '{"event":"step_update","step_update":{"step_type":"tool","tool_info":"a string"}}', '{"event":"step_update","step_update":{"step_type":"tool","state":"DONE","tool_info":{"output":5,"parameters":[1]},"duration_seconds":"x"}}', '{"event":"result","result":"x"}']) {
    expect(() => parseAgyEvents(text, state), text).not.toThrow();
  }
});

test('the caps: argument 1 KB, message 4 KB, summary 200 characters, a command output 4 KB around a gap', () => {
  const long = 'x'.repeat(10_000);
  const body = Array.from({ length: 2000 }, (_, i) => `line ${i}`).join('\r\n');
  const events = parseAll([
    tool(1, 'ACTIVE', 'run_command', { CommandLine: long }),
    tool(1, 'DONE', 'run_command', { CommandLine: long }, {}, `Command exited with code 0.\n\nCommand output:\n${body}`),
    tool(2, 'DONE', 'read_file', { Path: '/f' }, {}, long),
    step({ step_index: 3, state: 'DONE', step_type: 'agent_response', text_delta: long }),
  ]);
  expect(events[0]!.arg).toHaveLength(caps.arg);
  const out = events[1]!.output!;
  expect(out.join('\n').length).toBeLessThanOrEqual(caps.output);
  expect([out[0], out.at(-1)]).toEqual(['line 0', 'line 1999']);
  expect(out).toContain('…');
  expect(events[2]!.summary).toHaveLength(caps.summary);
  expect(events[3]!.text).toHaveLength(caps.text);
});

test.each(Object.entries(secretFixtures))('no event keeps %s, wherever the agent put it', (_shape, { text, secret }) => {
  const events = parseAll([
    tool(1, 'ACTIVE', 'run_command', { CommandLine: `echo ${text}` }),
    tool(1, 'DONE', 'run_command', { CommandLine: text }, {}, `Command exited with code 1.\n\nCommand output:\nfirst\r\n${text}\r\nlast`),
    tool(2, 'DONE', 'read_file', { Path: `/f/${text}` }, {}, text),
    step({ step_index: 3, state: 'ACTIVE', step_type: 'agent_response', text_delta: text }),
    step({ step_index: 3, state: 'DONE', step_type: 'agent_response' }),
    JSON.stringify({ event: 'result', result: { status: 'ERROR', error: text } }),
  ]);
  expect(events.length).toBeGreaterThanOrEqual(5);
  expect(JSON.stringify(events)).not.toContain(secret);
});
