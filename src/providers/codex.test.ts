import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { buildCodexCommand, parseCodexLine } from './codex.ts';

const task: AgentTask = {
  executionId: 'exec-1',
  repo: 'AshuLab/carrier',
  epic: 3,
  stage: 'ship',
  profile: 'author-bot',
  provider: 'codex',
  model: 'gpt-5.6-luna',
  workspace: '/work/carrier/3',
  resultPath: '/root/orchestrator/results/exec-1.json',
  timeoutMs: null,
  context: { previousSummaries: [] },
};
const ctx = { binary: '/real/codex', githubToken: 'ghs_secret', baseEnv: { PATH: '/bin', HOME: '/h', GH_TOKEN: 'ghs_other', UNSET: undefined } };
const fixed = [
  '--json',
  '--model',
  'gpt-5.6-luna',
  '--dangerously-bypass-approvals-and-sandbox',
  '-c',
  'carrier_marker="carrier-exec-exec-1"',
];

test('command: real binary, cwd in the workspace, prompt, model, no approvals or sandbox, marker', () => {
  const command = buildCodexCommand(task, ctx);
  expect(command.bin).toBe('/real/codex');
  expect(command.cwd).toBe('/work/carrier/3');
  expect(command.args).toEqual(['exec', buildPrompt(task), ...fixed]);
});

test('resumeSession uses `exec resume <id>` with the same fixed options', () => {
  const { args } = buildCodexCommand({ ...task, resumeSession: 'thread-9' }, ctx);
  expect(args).toEqual(['exec', 'resume', 'thread-9', buildPrompt({ ...task, resumeSession: 'thread-9' }), ...fixed]);
});

test('the GitHub token goes only in the child env, replacing an inherited one', () => {
  const command = buildCodexCommand(task, ctx);
  expect(command.env).toMatchObject({ PATH: '/bin', HOME: '/h', GH_TOKEN: 'ghs_secret', GITHUB_TOKEN: 'ghs_secret', CARRIER_RESULT_PATH: task.resultPath });
  expect(command.env).not.toHaveProperty('UNSET');
  expect(JSON.stringify([command.bin, command.args, command.cwd])).not.toContain('ghs_secret');
});

// Lines as codex 0.153.4 printed them (trimmed).
test('parseCodexLine reads session, login and lost-session errors', () => {
  expect(parseCodexLine('{"type":"thread.started","thread_id":"01a1425b-2b06-7de1-854b-334d33fbb363"}')).toEqual({ session: '01a1425b-2b06-7de1-854b-334d33fbb363' });
  expect(parseCodexLine('{"type":"turn.failed","error":{"message":"unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses"}}')).toEqual({ authFailed: true });
  expect(parseCodexLine('Error: thread/resume: thread/resume failed: no rollout found for thread id 01a1 (code -32600)')).toEqual({ sessionUnavailable: true });
  // retries before the turn ends are not the end of the run
  expect(parseCodexLine('{"type":"error","message":"Reconnecting... 2/5 (unexpected status 401 Unauthorized: Missing bearer)"}')).toBeUndefined();
  expect(parseCodexLine('{"type":"turn.failed","error":{"message":"stream disconnected"}}')).toBeUndefined();
  expect(parseCodexLine('{"type":"turn.completed","usage":{}}')).toBeUndefined();
  expect(parseCodexLine('2026-10-16T01:37:13Z ERROR codex_api: HTTP error: 401 Unauthorized')).toBeUndefined();
});
