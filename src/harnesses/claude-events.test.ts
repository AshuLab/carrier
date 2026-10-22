import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import { caps, createEventState, type AgentEvent } from '../execution/events.ts';
import { secretFixtures } from '../logging/secrets.fixture.ts';
import { parseClaudeEvents } from './claude.ts';

const readLines = (name: string) => readFileSync(join(import.meta.dirname, name), 'utf8').trimEnd().split('\n');
const parseAll = (lines: string[]) => {
  const state = createEventState();
  return lines.flatMap((line) => parseClaudeEvents(line, state));
};
const at = (ms: number) => Date.parse('2026-10-20T10:00:00.000Z') + ms;
const line = (o: unknown) => JSON.stringify(o);
const assistant = (content: unknown[], extra = {}) => line({ type: 'assistant', timestamp: '2026-10-20T10:00:00.000Z', message: { content }, ...extra });
const toolUse = (id: string, name: string, input: unknown) => ({ type: 'tool_use', id, name, input });
const result = (id: string, content: unknown, extra = {}, top = {}) =>
  line({ type: 'user', timestamp: '2026-10-20T10:00:01.000Z', message: { content: [{ type: 'tool_result', tool_use_id: id, content, ...extra }] }, ...top });

test('a hand-built stream: a call and its result paired, an edit with its diff, a failing command, a note, a subagent, an error', () => {
  expect(parseAll(readLines('claude-events.fixture.jsonl'))).toEqual<AgentEvent[]>([
    { at: at(100), kind: 'say', text: 'I will read the config and bump the constant.' },
    { at: at(100), kind: 'tool_start', callId: 'toolu_read', tool: 'Read', arg: '/w/repo/src/a.ts' },
    { at: at(250), kind: 'tool_end', callId: 'toolu_read', tool: 'Read', status: 'ok', durationMs: 150, summary: '1\texport' },
    { at: at(1000), kind: 'tool_start', callId: 'toolu_edit', tool: 'Edit', arg: '/w/repo/src/a.ts' },
    {
      at: at(1200),
      kind: 'tool_end',
      callId: 'toolu_edit',
      tool: 'Edit',
      status: 'ok',
      durationMs: 200,
      summary: '+1 -1',
      diff: [
        { sign: ' ', text: 'export' },
        { sign: '-', text: 'const a = 1;' },
        { sign: '+', text: 'const a = 2;' },
      ],
    },
    { at: at(2000), kind: 'tool_start', callId: 'toolu_bash', tool: 'Bash', arg: 'pnpm test', description: 'Run the tests' },
    {
      at: at(9000),
      kind: 'tool_end',
      callId: 'toolu_bash',
      tool: 'Bash',
      status: 'err',
      durationMs: 7000,
      summary: 'Exit code 1',
      output: ['Exit code 1', 'FAIL src/a.test.ts', '  expected 2 received 1'],
    },
    { kind: 'note', text: 'opened #42 (feat/demo/42-slice)' },
    { at: at(9500), kind: 'tool_start', callId: 'toolu_agent', tool: 'Agent', arg: 'Build slice #42' },
    { kind: 'task', agentId: 'agent-1', callId: 'toolu_agent', text: 'Build slice #42', slice: 42 },
    { at: at(10000), agentId: 'agent-1', kind: 'tool_start', callId: 'toolu_sub', tool: 'Bash', arg: 'cd /w/repo--lane-2 && git status' },
    { at: at(10300), agentId: 'agent-1', kind: 'tool_end', callId: 'toolu_sub', tool: 'Bash', status: 'ok', durationMs: 300, summary: 'On branch feat/demo/42-slice', output: ['On branch feat/demo/42-slice'] },
    { kind: 'task', agentId: 'agent-1', callId: 'toolu_agent', text: 'Build slice #42', status: 'ok', summary: '{"slice":42,"outcome":"done"}', slice: 42, lane: 2 },
    { kind: 'error', text: 'API Error: upstream failed' },
  ]);
});

test('thinking, hooks, rate limits, background commands, an unknown line and a garbage line give nothing', () => {
  const state = createEventState();
  const quiet = [
    assistant([{ type: 'thinking', thinking: 'hmm' }]),
    line({ type: 'system', subtype: 'hook_started' }),
    line({ type: 'system', subtype: 'task_started', task_id: 'b', task_type: 'local_bash', description: 'sleep' }),
    line({ type: 'system', subtype: 'task_notification', task_id: 'b', status: 'completed' }),
    line({ type: 'tool_progress' }),
    line({ type: 'rate_limit_event' }),
    line({ type: 'from_a_future_version', anything: [1, 2] }),
    'not json {',
  ];
  for (const text of quiet) expect(parseClaudeEvents(text, state)).toEqual([]);
});

test('it never throws, whatever the line holds', () => {
  const state = createEventState();
  for (const text of ['', ' ', 'null', '42', '"s"', '[]', '[1]', '{}', '{"type":"assistant"}', '{"type":"assistant","message":{"content":"x"}}', '{"type":"assistant","message":{"content":[null,1,"a",{"type":"tool_use"}]}}', '{"type":"user","message":{"content":[{"type":"tool_result"}]}}', '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"nope","content":[null,{"text":5}]}]},"tool_use_result":{"structuredPatch":[null,{"lines":[1]}]}}', '{"type":"system","subtype":"task_started","task_type":"local_agent"}', '{"type":"system","subtype":"task_notification","task_id":{}}', '{"type":"result","is_error":true}', '{"timestamp":"nonsense","type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}']) {
    expect(() => parseClaudeEvents(text, state), text).not.toThrow();
  }
  // A result with no call to pair with is still an event, without a tool; a bad timestamp leaves the time to the engine.
  expect(parseClaudeEvents(result('nope', 'x'), state)).toMatchObject([{ kind: 'tool_end', callId: 'nope', status: 'ok' }]);
  expect(parseClaudeEvents('{"timestamp":"nonsense","type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}', state)).toEqual([{ kind: 'say', text: 'hi' }]);
});

test('the sanitised subagent stream: three tasks start and end, the slice and the lane are hints, calls pair', () => {
  const events = parseAll(readLines('claude-subagents.fixture.jsonl'));
  const tasks = events.filter((e) => e.kind === 'task');
  expect(tasks.map((e) => [e.agentId, e.status ?? 'start', e.slice, e.lane])).toEqual([
    ['af4e38341539ac2cf', 'start', 653, undefined],
    ['a97cac545564d0d61', 'start', 654, undefined],
    ['a72f07f44125066b2', 'start', undefined, undefined],
    ['af4e38341539ac2cf', 'ok', 653, 1],
    ['a97cac545564d0d61', 'ok', 654, 2],
    ['a72f07f44125066b2', 'ok', undefined, undefined],
  ]);
  // The fixture is a sample (some results have no call before them); a pair keeps the subagent and the tool.
  expect(events.filter((e) => e.callId === 'toolu_01CQqHfDhG5Vd6y4DBTnSCbf')).toMatchObject([
    { kind: 'tool_start', tool: 'Read', agentId: 'af4e38341539ac2cf' },
    { kind: 'tool_end', tool: 'Read', status: 'ok', agentId: 'af4e38341539ac2cf', durationMs: 155 },
  ]);
});

test('the caps: argument 1 KB, summary 200 characters, message 4 KB', () => {
  const long = 'x'.repeat(10_000);
  const state = createEventState();
  const [say, start] = parseClaudeEvents(assistant([{ type: 'text', text: long }, toolUse('c1', 'Bash', { command: long })]), state);
  expect(say!.text).toHaveLength(caps.text);
  expect(start!.arg).toHaveLength(1024);
  const [end] = parseClaudeEvents(result('c1', `${long}\nsecond`), state);
  expect(end!.summary).toHaveLength(200);
  expect(end!.summary!.endsWith('…')).toBe(true);
});

test('the caps: a command output keeps its first and last lines within 4 KB, and only a command keeps one', () => {
  const body = Array.from({ length: 2000 }, (_, i) => `line ${i}`).join('\n');
  const state = createEventState();
  parseClaudeEvents(assistant([toolUse('c1', 'Bash', { command: 'ls' }), toolUse('c2', 'Read', { file_path: '/f' })]), state);
  const [bash] = parseClaudeEvents(result('c1', body), state);
  const out = bash!.output!;
  expect(out.join('\n').length).toBeLessThanOrEqual(caps.output);
  expect(out[0]).toBe('line 0');
  expect(out.at(-1)).toBe('line 1999');
  expect(out).toContain('…');
  const [read] = parseClaudeEvents(result('c2', body), state);
  expect(read!.output).toBeUndefined();
  // A small output is whole.
  parseClaudeEvents(assistant([toolUse('c3', 'Bash', { command: 'ls' })]), state);
  expect(parseClaudeEvents(result('c3', 'a\nb'), state)[0]!.output).toEqual(['a', 'b']);
});

test('the caps: a diff stops at 200 lines of 200 characters, and says how many it left out', () => {
  const lines = Array.from({ length: 500 }, (_, i) => `+${'y'.repeat(300)}${i}`);
  const state = createEventState();
  parseClaudeEvents(assistant([toolUse('c1', 'Write', { file_path: '/f' })]), state);
  const [end] = parseClaudeEvents(result('c1', 'ok', {}, { tool_use_result: { structuredPatch: [{ lines }] } }), state);
  expect(end!.summary).toBe('+500 -0');
  expect(end!.diff).toHaveLength(caps.diffLines + 1);
  expect(end!.diff![0]!.text).toHaveLength(caps.diffLine);
  expect(end!.diff!.at(-1)).toEqual({ sign: ' ', text: '… 300 more lines' });
});

test.each(Object.entries(secretFixtures))('no event keeps %s, wherever the agent put it', (_shape, { text, secret }) => {
  const state = createEventState();
  const stream = [
    assistant([{ type: 'text', text }, toolUse('c1', 'Bash', { command: `echo ${text}` }), toolUse('c2', 'Edit', { file_path: `/f/${text}` })]),
    result('c1', `first\n${text}\nlast`),
    result('c2', text, {}, { tool_use_result: { structuredPatch: [{ lines: [`+${text}`, `-${text}`, ` ${text}`] }] } }),
    line({ type: 'system', subtype: 'task_started', task_id: 'a', task_type: 'local_agent', description: text }),
    line({ type: 'system', subtype: 'task_notification', task_id: 'a', status: 'failed', summary: text }),
    line({ type: 'system', subtype: 'code_change_published', identifier: text, branch: text }),
    line({ type: 'result', is_error: true, result: text }),
    assistant([{ type: 'text', text }], { error: 'authentication_failed' }),
  ];
  const events = stream.flatMap((l) => parseClaudeEvents(l, state));
  expect(events.length).toBeGreaterThanOrEqual(10);
  expect(JSON.stringify(events)).not.toContain(secret);
});
