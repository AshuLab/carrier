import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { buildAgyCommand, parseAgyLine } from './agy.ts';

const task: AgentTask = {
  executionId: 'exec-1',
  repo: 'AshuLab/carrier',
  epic: 3,
  stage: 'ship',
  profile: 'author-bot',
  harness: 'agy',
  model: 'gemini-3.8-flash-low',
  workspace: '/work/carrier/3',
  resultPath: '/root/orchestrator/results/exec-1.json',
  timeoutMs: null,
  context: { previousSummaries: [] },
};
const ctx = { binary: '/real/agy', githubToken: 'ghs_secret', baseEnv: { PATH: '/bin', HOME: '/h', GH_TOKEN: 'ghs_other' } };
const fixed = ['--output-format', 'stream-json', '--model', 'gemini-3.8-flash-low', '--dangerously-skip-permissions', '--add-dir', '/root/orchestrator/results', '--log-file', join(tmpdir(), 'carrier-exec-exec-1.log')];

test('command: real binary, cwd in the workspace, stream-json, no prompts, the marker in the log path', () => {
  const command = buildAgyCommand(task, ctx);
  expect(command.bin).toBe('/real/agy');
  expect(command.cwd).toBe('/work/carrier/3');
  expect(command.args).toEqual(['-p', buildPrompt(task), ...fixed]);
  expect(command.args).not.toContain('--sandbox'); // opt-in, and Carrier needs the network
  expect(command.env).toMatchObject({ GH_TOKEN: 'ghs_secret', CARRIER_RESULT_PATH: task.resultPath });
});

test('resumeSession adds --conversation', () => {
  expect(buildAgyCommand({ ...task, resumeSession: 'c-9' }, ctx).args).toEqual(['-p', buildPrompt({ ...task, resumeSession: 'c-9' }), ...fixed, '--conversation', 'c-9']);
});

test('skills are invoked with a slash, like Claude Code (Codex uses $)', () => {
  expect(buildPrompt(task)).toContain('/ship');
  expect(buildPrompt(task)).not.toContain('$ship');
});

test('the conversation id comes from the first line, before the model is called', () => {
  expect(parseAgyLine('{"event":"init","conversation_id":"59371104-e7a2","init":{"model":"m"}}')).toEqual({ session: '59371104-e7a2' });
  expect(parseAgyLine('{"event":"step_update","step_update":{"conversation_id":"x"}}')).toBeUndefined();
  expect(parseAgyLine('not json')).toBeUndefined();
});

test('a lost conversation is only a stderr warning, and a missing login shows on both streams', () => {
  expect(parseAgyLine('warning: conversation "00000000-0000" not found')).toEqual({ sessionUnavailable: true });
  expect(parseAgyLine('Authentication required. Please visit the URL to log in:')).toEqual({ authFailed: true });
  expect(parseAgyLine('{"event":"result","result":{"status":"ERROR","error":"authentication failed or timed out"}}')).toEqual({ authFailed: true });
  expect(parseAgyLine('{"event":"result","result":{"status":"ERROR","error":"interrupted"}}')).toBeUndefined();
});
