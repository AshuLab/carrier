import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, expect, test } from 'vitest';
import { summarizeLogLine, tailExecution } from './logs.ts';

const root = mkdtempSync(join(tmpdir(), 'carrier-logs-'));
afterAll(() => rmSync(root, { recursive: true, force: true }));
const write = (id: string, text: string) => {
  mkdirSync(join(root, 'orchestrator', 'logs', 'executions', id), { recursive: true });
  writeFileSync(join(root, 'orchestrator', 'logs', 'executions', id, 'stdout.log'), text);
};
const j = (o: object) => JSON.stringify(o);

test('what each harness said and ran, and nothing of its bookkeeping', () => {
  expect(summarizeLogLine(j({ type: 'assistant', message: { content: [{ type: 'text', text: 'Reading the spec' }, { type: 'tool_use', name: 'Bash', input: { command: 'git status' } }] } }))).toBe('Reading the spec ▸ Bash {"command":"git status"}');
  expect(summarizeLogLine(j({ type: 'system', subtype: 'init' }))).toBeNull();
  expect(summarizeLogLine(j({ type: 'system', subtype: 'code_change_published', identifier: '663', action: 'created' }))).toBe('▲ PR #663 created');
  expect(summarizeLogLine(j({ type: 'system', subtype: 'vcs_state_changed', kind: 'push' }))).toBe('▲ pushed');
  expect(summarizeLogLine(j({ type: 'system', subtype: 'task_notification', status: 'completed', summary: '{"slice": "#653", "outcome": "ready-to-merge", "branch": "x"}' }))).toBe('✓ slice #653 ready-to-merge');
  expect(summarizeLogLine(j({ type: 'system', subtype: 'task_notification', status: 'failed', summary: 'cat > /tmp/x' }))).toBe('✗ cat > /tmp/x');
  expect(summarizeLogLine(j({ type: 'system', subtype: 'task_notification', status: 'completed', summary: 'cd /tmp' }))).toBeNull();
  expect(summarizeLogLine(j({ type: 'result', result: 'done' }))).toBe('result: done');
  expect(summarizeLogLine(j({ type: 'item.completed', item: { type: 'agent_message', text: 'Done.' } }))).toBe('Done.');
  expect(summarizeLogLine(j({ type: 'item.started', item: { type: 'command_execution', command: 'pnpm test' } }))).toBe('$ pnpm test');
  expect(summarizeLogLine(j({ event: 'step_update', step_update: { state: 'ACTIVE', tool_name: 'run_command', tool_info: 'ls' } }))).toBe('▸ run_command ls');
  expect(summarizeLogLine(j({ event: 'step_update', step_update: { state: 'DONE', step_type: 'agent_response', text_delta: 'ok\n' } }))).toBe('ok');
  expect(summarizeLogLine(j({ event: 'init', conversation_id: 'x' }))).toBeNull();
  expect(summarizeLogLine('error: something plain')).toBe('error: something plain');
  expect(summarizeLogLine('   ')).toBeNull();
});

test('the tail is the last meaningful lines, read from the end of the file', () => {
  const lines = Array.from({ length: 30 }, (_, i) => j({ type: 'result', result: `r${i}` }));
  write('e1', `${j({ type: 'system' })}\n${lines.join('\n')}\n`);
  expect(tailExecution(root, 'e1', 3)).toEqual(['result: r27', 'result: r28', 'result: r29']);
  expect(tailExecution(root, 'missing', 3)).toEqual([]); // nothing written yet

  write('big', `${'x'.repeat(2000)}\n${j({ type: 'result', result: 'last' })}\n`);
  expect(tailExecution(root, 'big', 5, 100)).toEqual(['result: last']); // a window smaller than the file cuts the first line, not the last
});
