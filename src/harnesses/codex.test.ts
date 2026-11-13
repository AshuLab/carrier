import { readFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { addUsage } from '../execution/usage.ts';
import { buildCodexCommand, parseCodexLine } from './codex.ts';

const task: AgentTask = {
  executionId: 'exec-1',
  repo: 'AshuLab/carrier',
  epic: 3,
  stage: 'ship',
  profile: 'author-bot',
  harness: 'codex',
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

test('a configDir sets CODEX_HOME; without one the inherited environment stays untouched', () => {
  expect(buildCodexCommand({ ...task, configDir: '/cfg/codex' }, { ...ctx, baseEnv: { ...ctx.baseEnv, CODEX_HOME: '/cfg/mine' } }).env.CODEX_HOME).toBe('/cfg/codex');
  expect(buildCodexCommand(task, { ...ctx, baseEnv: { ...ctx.baseEnv, CODEX_HOME: '/cfg/mine' } }).env.CODEX_HOME).toBe('/cfg/mine');
  expect(buildCodexCommand(task, ctx).env).not.toHaveProperty('CODEX_HOME');
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
  expect(parseCodexLine('{"type":"turn.failed","error":{"message":"stream disconnected"}}')).toEqual({ failure: { kind: 'api_error', detail: 'stream disconnected' } });
  expect(parseCodexLine('{"type":"turn.completed"}')).toBeUndefined();
  expect(parseCodexLine('2026-10-16T01:37:13Z ERROR codex_api: HTTP error: 401 Unauthorized')).toBeUndefined();
});

test('a local model selects its harness with -c, which `exec resume` accepts (it refuses --oss)', () => {
  const fresh = buildCodexCommand({ ...task, provider: 'lmstudio' }, ctx).args;
  expect(fresh.slice(fresh.indexOf('-c'))).toEqual(['-c', 'model_provider="lmstudio"', '--dangerously-bypass-approvals-and-sandbox', '-c', 'carrier_marker="carrier-exec-exec-1"']);
  const resumed = buildCodexCommand({ ...task, resumeSession: 't', provider: 'ollama' }, ctx).args;
  expect(resumed).toEqual(expect.arrayContaining(['resume', 't', 'model_provider="ollama"']));
  expect(resumed).not.toContain('--oss');
  expect(buildCodexCommand(task, ctx).args.join(' ')).not.toContain('model_provider'); // cloud models are untouched
});

// A real `codex exec --json` run (codex 0.153.4), private text replaced; shapes in docs/research/codex-exec-stream.md.
test('parseCodexLine reads the session from a real captured stream and never throws on a line', () => {
  const lines = readFileSync(new URL('./codex-exec.fixture.jsonl', import.meta.url), 'utf8').trim().split('\n');
  const signals = lines.map((line) => parseCodexLine(line));
  expect(signals.filter(Boolean)).toEqual([
    { session: '00000000-0000-7000-8000-000000000000' },
    { usage: { inputTokens: 21144, cachedInputTokens: 38400, cacheWriteTokens: 0, outputTokens: 314, reasoningTokens: 0, costUsd: null } },
  ]);
  expect(lines.length).toBe(15);
});

const completed = (usage: unknown) => JSON.stringify({ type: 'turn.completed', usage });

test('codex usage: non-cached input is input minus cached, never negative; bad fields are 0', () => {
  expect(parseCodexLine(completed({ input_tokens: 100, cached_input_tokens: 30, cache_write_input_tokens: 5, output_tokens: 20, reasoning_output_tokens: 8 }))).toEqual({
    usage: { inputTokens: 70, cachedInputTokens: 30, cacheWriteTokens: 5, outputTokens: 20, reasoningTokens: 8, costUsd: null },
  });
  expect(parseCodexLine(completed({ input_tokens: 10, cached_input_tokens: 30, output_tokens: -4, reasoning_output_tokens: 'x' }))?.usage).toMatchObject({ inputTokens: 0, cachedInputTokens: 30, outputTokens: 0, reasoningTokens: 0 });
  expect(parseCodexLine(completed('nope'))).toBeUndefined();
});

test('codex usage of a multi-turn run adds up across every turn.completed', () => {
  const turns = [completed({ input_tokens: 100, cached_input_tokens: 40, output_tokens: 10 }), completed({ input_tokens: 50, cached_input_tokens: 50, output_tokens: 5 })];
  const total = turns.map((line) => parseCodexLine(line)?.usage).reduce(addUsage);
  expect(total).toMatchObject({ inputTokens: 60, cachedInputTokens: 90, outputTokens: 15 });
});

test('the prompt carries the 401 rule only when the context has a forgeAgent', () => {
  const withAgent = buildCodexCommand(task, { ...ctx, forgeAgent: 'artanis-agent' });
  expect(withAgent.args).toContain(buildPrompt(task, { forgeAgent: 'artanis-agent' }));
  expect(withAgent.args.join('\n')).toContain('agent-forge gh artanis-agent <the same arguments>');
  expect(buildCodexCommand(task, ctx).args.join('\n')).not.toContain('agent-forge');
});

const failed = (message: string) => JSON.stringify({ type: 'turn.failed', error: { message } });

// Constructed from the sources, not captured (docs/research/agent-usage-limit-signals.md).
test('parseCodexLine reads the final turn.failed of the usage-limit fixture as usage_limit, reset time kept in the detail', () => {
  const lines = readFileSync(new URL('./codex-usage-limit.fixture.jsonl', import.meta.url), 'utf8').trim().split('\n');
  const signals = lines.map((line) => parseCodexLine(line)).filter(Boolean);
  expect(signals).toEqual([{ session: '00000000-0000-7000-8000-000000000000' }, { failure: { kind: 'usage_limit', detail: "You've hit your usage limit. Try again at Oct 28th, 2026 3:45 PM." } }]);
});

test('parseCodexLine reads every usage-limit and credit message as usage_limit', () => {
  for (const message of [
    "You've hit your usage limit. Try again later.",
    'You hit your spend cap set in your workspace. Increase your spend cap to continue.',
    'Your workspace is out of credits. Add credits to continue.',
    'Quota exceeded. Check your plan and billing details.',
  ]) {
    expect(parseCodexLine(failed(message))).toEqual({ failure: { kind: 'usage_limit', detail: message } });
  }
});

test('a retried 429, and a usage-limit error event with no turn.failed, are not usage_limit', () => {
  const retried = 'exceeded retry limit, last status: 429 Too Many Requests, request id: abc';
  expect(parseCodexLine(failed(retried))).toEqual({ failure: { kind: 'api_error', detail: retried } });
  expect(parseCodexLine('{"type":"error","message":"You\'ve hit your usage limit. Try again later."}')).toBeUndefined();
  expect(parseCodexLine('{"type":"turn.failed","error":{}}')).toEqual({ failure: { kind: 'api_error', detail: 'the turn failed' } });
});

test('an account\'s command, compaction and launch arguments reach the process; without them the command is unchanged', () => {
  const plain = buildCodexCommand(task, ctx);
  const command = buildCodexCommand({ ...task, command: '/opt/codex/bin/codex', autoCompact: 200000, launchArgs: ['--skip-git-repo-check'] }, ctx);
  expect(command.bin).toBe('/opt/codex/bin/codex');
  expect(command.args).toEqual([...plain.args, '-c', 'model_auto_compact_token_limit=200000', '--skip-git-repo-check']);
  expect(command.env).toEqual(plain.env);
  expect(buildCodexCommand({ ...task, launchArgs: [] }, ctx)).toEqual(plain);
});

test('an effort is passed as -c model_reasoning_effort, in a new run and in a resume; without one nothing is added', () => {
  expect(buildCodexCommand(task, ctx).args.join(' ')).not.toContain('model_reasoning_effort');
  for (const resumeSession of [undefined, 't-1']) {
    const run = { ...task, ...(resumeSession && { resumeSession }) };
    const plain = buildCodexCommand(run, ctx).args;
    const args = buildCodexCommand({ ...run, effort: 'high' }, ctx).args;
    expect(args.filter((a) => a !== '-c' && a !== 'model_reasoning_effort=high')).toEqual(plain.filter((a) => a !== '-c'));
    expect(args[args.indexOf('model_reasoning_effort=high') - 1]).toBe('-c');
  }
});

test('an engine Codex run gets no chat MCP configuration in its arguments or environment', () => {
  const { args, env } = buildCodexCommand(task, ctx);
  expect(`${args.join('\n')}\n${Object.entries(env).flat().join('\n')}`).not.toMatch(/carrier-chat|mcp_servers|mcp-config/i);
});
