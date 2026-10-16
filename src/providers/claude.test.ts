import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { buildClaudeCommand, parseClaudeLine } from './claude.ts';
import { childEnv, resolveBinary } from './common.ts';

const task: AgentTask = {
  executionId: 'exec-1',
  repo: 'AshuLab/carrier',
  epic: 3,
  stage: 'ship',
  profile: 'author-bot',
  provider: 'claude',
  model: 'haiku',
  workspace: '/work/carrier/3',
  resultPath: '/root/orchestrator/results/exec-1.json',
  timeoutMs: null,
  context: { previousSummaries: [] },
};
const ctx = { binary: '/real/claude', githubToken: 'ghs_secret', baseEnv: { PATH: '/bin', HOME: '/h', GH_TOKEN: 'ghs_other', UNSET: undefined } };

test('command: real binary, cwd in the workspace, prompt, model, marker', () => {
  const command = buildClaudeCommand(task, ctx);
  expect(command.bin).toBe('/real/claude');
  expect(command.cwd).toBe('/work/carrier/3');
  expect(command.args).toEqual([
    '-p',
    buildPrompt(task),
    '--permission-mode',
    'bypassPermissions',
    '--output-format',
    'stream-json',
    '--verbose',
    '--model',
    'haiku',
    '--add-dir',
    '/root/orchestrator/results',
    '--name',
    'carrier-exec-exec-1',
  ]);
});

test('resumeSession adds --resume', () => {
  const { args } = buildClaudeCommand({ ...task, resumeSession: 'sess-9' }, ctx);
  expect(args.slice(-2)).toEqual(['--resume', 'sess-9']);
  expect(buildClaudeCommand(task, ctx).args).not.toContain('--resume');
});

test('the GitHub token goes only in the child env, replacing an inherited one', () => {
  const command = buildClaudeCommand(task, ctx);
  expect(command.env).toMatchObject({ PATH: '/bin', HOME: '/h', GH_TOKEN: 'ghs_secret', GITHUB_TOKEN: 'ghs_secret' });
  expect(command.env).not.toHaveProperty('UNSET');
  expect(JSON.stringify([command.bin, command.args, command.cwd])).not.toContain('ghs_secret');
});

test('a bot identity sets author and committer', () => {
  const env = childEnv({ ...ctx, gitIdentity: { name: 'artanis-agent[bot]', email: '1+artanis-agent[bot]@users.noreply.github.com' } });
  expect(env).toMatchObject({
    GIT_AUTHOR_NAME: 'artanis-agent[bot]',
    GIT_COMMITTER_NAME: 'artanis-agent[bot]',
    GIT_AUTHOR_EMAIL: '1+artanis-agent[bot]@users.noreply.github.com',
    GIT_COMMITTER_EMAIL: '1+artanis-agent[bot]@users.noreply.github.com',
  });
  expect(childEnv(ctx)).not.toHaveProperty('GIT_AUTHOR_NAME');
});

test('resolveBinary skips the Superset wrappers', () => {
  const executable = (path: string) => path.endsWith('/claude');
  expect(resolveBinary('claude', '/Users/x/.superset/bin:/Users/x/.local/bin:/usr/bin', executable)).toBe('/Users/x/.local/bin/claude');
  expect(() => resolveBinary('claude', '/Users/x/.superset/bin', executable)).toThrow(/real "claude"/);
});

// Lines as claude 2.1.301 printed them (trimmed).
test('parseClaudeLine reads session, auth and lost-session errors', () => {
  expect(parseClaudeLine('{"type":"system","subtype":"hook_started","session_id":"s1"}')).toBeUndefined();
  expect(parseClaudeLine('{"type":"system","subtype":"init","cwd":"/w","session_id":"s1"}')).toEqual({ session: 's1' });
  expect(parseClaudeLine('{"type":"assistant","error":"authentication_failed","message":{"content":[{"type":"text","text":"Not logged in · Please run /login"}]}}')).toEqual({ authFailed: true });
  expect(parseClaudeLine('{"type":"result","is_error":true,"api_error_status":401,"result":"Invalid API key · Fix external API key"}')).toEqual({ authFailed: true });
  expect(parseClaudeLine('{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["No conversation found with session ID: x"]}')).toEqual({ sessionUnavailable: true });
  expect(parseClaudeLine('{"type":"result","is_error":false,"api_error_status":null,"result":"OK"}')).toBeUndefined();
  expect(parseClaudeLine('not json')).toBeUndefined();
});
