import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { expect, test } from 'vitest';
import type { AgentTask } from '../execution/agent-runner.ts';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { attributeSubagentLines, buildClaudeCommand, parseClaudeLine } from './claude.ts';
import { childEnv, resolveBinary } from './common.ts';

const task: AgentTask = {
  executionId: 'exec-1',
  repo: 'AshuLab/carrier',
  epic: 3,
  stage: 'ship',
  profile: 'author-bot',
  harness: 'claude',
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

test('a configDir sets CLAUDE_CONFIG_DIR; without one the inherited environment stays untouched', () => {
  expect(buildClaudeCommand({ ...task, configDir: '/cfg/ashu' }, { ...ctx, baseEnv: { ...ctx.baseEnv, CLAUDE_CONFIG_DIR: '/cfg/mine' } }).env.CLAUDE_CONFIG_DIR).toBe('/cfg/ashu');
  expect(buildClaudeCommand(task, { ...ctx, baseEnv: { ...ctx.baseEnv, CLAUDE_CONFIG_DIR: '/cfg/mine' } }).env.CLAUDE_CONFIG_DIR).toBe('/cfg/mine');
  expect(buildClaudeCommand(task, ctx).env).not.toHaveProperty('CLAUDE_CONFIG_DIR');
});

test('the GitHub token goes only in the child env, replacing an inherited one', () => {
  const command = buildClaudeCommand(task, ctx);
  expect(command.env).toMatchObject({ PATH: '/bin', HOME: '/h', GH_TOKEN: 'ghs_secret', GITHUB_TOKEN: 'ghs_secret', CARRIER_RESULT_PATH: task.resultPath });
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

test('git pushes with the execution token, not with the helpers of the person running carrier', () => {
  const dir = mkdtempSync(join(tmpdir(), 'carrier-git-'));
  try {
    // What the keychain is on a Mac: a global helper that would answer with the person's own credentials.
    const globalConfig = join(dir, 'gitconfig');
    writeFileSync(globalConfig, '[credential]\n\thelper = "!f() { echo username=person; echo password=PERSONS_OWN; }; f"\n');
    const env = childEnv({ ...ctx, githubToken: 'ghs_bot', baseEnv: { PATH: process.env.PATH, HOME: dir, GIT_CONFIG_GLOBAL: globalConfig, GIT_CONFIG_NOSYSTEM: '1' } });
    const asked = execFileSync('git', ['credential', 'fill'], { env, input: 'protocol=https\nhost=github.com\n\n', encoding: 'utf8' });
    expect(asked).toContain('password=ghs_bot');
    expect(asked).not.toContain('PERSONS_OWN');
    expect(JSON.stringify(env)).not.toContain('PERSONS_OWN');
    // The token travels in GH_TOKEN, never inside a git config value.
    expect(Object.entries(env).filter(([k]) => k.startsWith('GIT_CONFIG_VALUE_')).map(([, v]) => v).join()).not.toContain('ghs_bot');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// A fake `agent-forge` first in the PATH: it logs each call's argv (one line per argument) and behaves as FAKE_FORGE says.
function withFakeForge(run: (ask: (forgeAgent: string | undefined, operation: string, mode?: 'token' | 'fail' | 'silent' | 'hang') => string, calls: () => string[]) => void) {
  const dir = mkdtempSync(join(tmpdir(), 'carrier-forge-'));
  try {
    const log = join(dir, 'calls.log');
    writeFileSync(join(dir, 'agent-forge'), `#!/bin/sh\nprintf 'call\\n' >> "${log}"\nfor a in "$@"; do printf 'arg=%s\\n' "$a" >> "${log}"; done\ncase "$FAKE_FORGE" in token) echo ghs_fresh;; fail) echo boom >&2; exit 1;; hang) sleep 30; echo ghs_late;; esac\n`);
    chmodSync(join(dir, 'agent-forge'), 0o755);
    const globalConfig = join(dir, 'gitconfig');
    writeFileSync(globalConfig, '');
    const ask = (forgeAgent: string | undefined, operation: string, mode = 'token') => {
      const env = childEnv({ ...ctx, githubToken: 'ghs_start', forgeAgent, baseEnv: { PATH: `${dir}:${process.env.PATH}`, HOME: dir, GIT_CONFIG_GLOBAL: globalConfig, GIT_CONFIG_NOSYSTEM: '1', FAKE_FORGE: mode, CARRIER_FORGE_TIMEOUT: '1' } });
      return execFileSync('git', ['credential', operation], { env, input: 'protocol=https\nhost=github.com\n\n', encoding: 'utf8' });
    };
    run(ask, () => { try { return readFileSync(log, 'utf8').split('\n').filter(Boolean); } catch { return []; } });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a Forge bot gets a token minted when git asks, not the one the run started with', () => {
  withFakeForge((ask, calls) => {
    const asked = ask('artanis-agent', 'fill');
    expect(asked).toContain('password=ghs_fresh');
    expect(asked).not.toContain('ghs_start');
    expect(calls()).toEqual(['call', 'arg=token', 'arg=--agent', 'arg=artanis-agent']);
  });
});

test('when Forge fails or prints nothing, git gets the token the run started with', () => {
  withFakeForge((ask) => {
    expect(ask('artanis-agent', 'fill', 'fail')).toContain('password=ghs_start');
    expect(ask('artanis-agent', 'fill', 'silent')).toContain('password=ghs_start');
  });
});

test('when Forge hangs, git gets the token the run started with once the time limit passes', () => {
  withFakeForge((ask) => {
    const started = Date.now();
    expect(ask('artanis-agent', 'fill', 'hang')).toContain('password=ghs_start');
    expect(Date.now() - started).toBeLessThan(10_000);
  });
});

test('a gh profile (no CARRIER_FORGE_AGENT) answers with the starting token and never calls agent-forge', () => {
  withFakeForge((ask, calls) => {
    expect(ask(undefined, 'fill')).toContain('password=ghs_start');
    expect(calls()).toEqual([]);
  });
});

test('an agent name with quotes, semicolons and command substitution runs nothing and reaches Forge whole', () => {
  withFakeForge((ask, calls) => {
    const hostile = `x"; touch pwned; echo '$(touch pwned2)' \`touch pwned3\` $HOME #`;
    expect(ask(hostile, 'fill')).toContain('password=ghs_fresh');
    expect(calls()).toEqual(['call', 'arg=token', 'arg=--agent', `arg=${hostile}`]);
    expect(existsSync(join(process.cwd(), 'pwned'))).toBe(false);
  });
});

test('git store and erase answer nothing and do not call agent-forge', () => {
  withFakeForge((ask, calls) => {
    expect(ask('artanis-agent', 'approve')).toBe('');
    expect(ask('artanis-agent', 'reject')).toBe('');
    expect(calls()).toEqual([]);
  });
});

test('resolveBinary skips the Superset and Paradev wrappers', () => {
  const executable = (path: string) => path.endsWith('/claude');
  expect(resolveBinary('claude', '/Users/x/.superset/bin:/Users/x/.local/bin:/usr/bin', executable)).toBe('/Users/x/.local/bin/claude');
  expect(resolveBinary('claude', '/Users/x/.paradev/bin:/Users/x/.local/bin:/usr/bin', executable)).toBe('/Users/x/.local/bin/claude');
  expect(() => resolveBinary('claude', '/Users/x/.superset/bin:/Users/x/.paradev/bin', executable)).toThrow(/real "claude"/);
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

const claudeResult = (extra: Record<string, unknown>) => JSON.stringify({ type: 'result', is_error: false, ...extra });

test('claude usage: modelUsage entries are summed, with top-level cost ignored', () => {
  const usage = parseClaudeLine(claudeResult({ total_cost_usd: 9, modelUsage: { a: { inputTokens: 1, outputTokens: 2, costUSD: 0.5 }, b: { inputTokens: 3, cacheReadInputTokens: 4, cacheCreationInputTokens: 5, thinkingTokens: 6, costUSD: 0.25 } } }))?.usage;
  expect(usage).toMatchObject({ inputTokens: 4, cachedInputTokens: 4, cacheWriteTokens: 5, outputTokens: 2, reasoningTokens: 6, costUsd: 0.75 });
  expect(Object.keys(usage?.byModel ?? {})).toEqual(['a', 'b']);
});

test('claude usage: an empty or absent modelUsage falls back to the top-level usage and total_cost_usd', () => {
  const top = { input_tokens: 7, cache_read_input_tokens: 8, cache_creation_input_tokens: 9, output_tokens: 10, output_tokens_details: { thinking_tokens: 2 } };
  const expected = { inputTokens: 7, cachedInputTokens: 8, cacheWriteTokens: 9, outputTokens: 10, reasoningTokens: 2, costUsd: 0.1 };
  expect(parseClaudeLine(claudeResult({ modelUsage: {}, usage: top, total_cost_usd: 0.1 }))).toEqual({ usage: expected });
  expect(parseClaudeLine(claudeResult({ usage: top, total_cost_usd: 0.1 }))).toEqual({ usage: expected });
});

test('claude usage: negative, non-finite and malformed values are 0 or null and never fail the line', () => {
  expect(parseClaudeLine(claudeResult({ usage: { input_tokens: -3, output_tokens: 'x', cache_read_input_tokens: null }, total_cost_usd: 'free' }))?.usage).toEqual({ inputTokens: 0, cachedInputTokens: 0, cacheWriteTokens: 0, outputTokens: 0, reasoningTokens: 0, costUsd: null });
  expect(parseClaudeLine(claudeResult({ modelUsage: { a: 'junk', b: { inputTokens: -1, costUSD: -2 } } }))?.usage).toMatchObject({ inputTokens: 0, costUsd: 0 });
  expect(parseClaudeLine(claudeResult({ usage: 'junk', modelUsage: 5 }))).toBeUndefined();
});

test('parseClaudeLine reads the real 429 result as usage_limit', () => {
  const line = readFileSync(join(import.meta.dirname, 'claude-usage-limit.fixture.jsonl'), 'utf8').trim();
  // The top-level usage is zero on a limit result; modelUsage holds the real totals and wins.
  const model = { inputTokens: 66, cachedInputTokens: 1594034, cacheWriteTokens: 132737, outputTokens: 17614, reasoningTokens: 4255, costUsd: 0.7598399 };
  expect(parseClaudeLine(line)).toEqual({ failure: { kind: 'usage_limit', detail: "You've hit your session limit · resets 12:40pm (America/Montevideo)" }, usage: { ...model, byModel: { 'claude-sonnet-5-5': model } } });
});

test('parseClaudeLine reads any other numeric API status as api_error, and ignores what is not an error with a number', () => {
  const result = (fields: string) => `{"type":"result",${fields},"result":"Overloaded"}`;
  expect(parseClaudeLine(result('"is_error":true,"api_error_status":503'))).toEqual({ failure: { kind: 'api_error', detail: 'HTTP 503: Overloaded' } });
  expect(parseClaudeLine(result('"is_error":true,"api_error_status":429,"api_error":"rate_limit"'))).toEqual({ failure: { kind: 'api_error', detail: 'HTTP 429: Overloaded' } });
  expect(parseClaudeLine('{"type":"result","is_error":true,"api_error_status":500}')).toEqual({ failure: { kind: 'api_error', detail: 'HTTP 500' } });
  expect(parseClaudeLine(result('"is_error":true,"api_error_status":401'))).toEqual({ authFailed: true });
  expect(parseClaudeLine(result('"is_error":true,"api_error_status":null'))).toBeUndefined();
  expect(parseClaudeLine(result('"is_error":true'))).toBeUndefined();
  expect(parseClaudeLine(result('"is_error":true,"api_error_status":"429","api_error":"usage_limit_reached"'))).toBeUndefined();
  expect(parseClaudeLine(result('"is_error":false,"api_error_status":503'))).toBeUndefined();
});

test('a local model points the CLI at that server and keeps a real API key away from it', () => {
  const { env } = buildClaudeCommand({ ...task, provider: 'ollama' }, { ...ctx, baseEnv: { ...ctx.baseEnv, ANTHROPIC_API_KEY: 'sk-real' } });
  expect(env).toMatchObject({ ANTHROPIC_BASE_URL: 'http://localhost:11434', ANTHROPIC_AUTH_TOKEN: 'ollama', ANTHROPIC_API_KEY: '' });
  expect(buildClaudeCommand(task, ctx).env).not.toHaveProperty('ANTHROPIC_BASE_URL');
});

test('attributeSubagentLines ties subagent lines to an agent, a lane and a slice', () => {
  const lines = readFileSync(join(import.meta.dirname, 'claude-subagents.fixture.jsonl'), 'utf8').trim().split('\n').map((line) => JSON.parse(line));
  const result = attributeSubagentLines(lines);
  expect(result).toHaveLength(lines.length);
  const by = (agentId: string) => result.filter((r) => r.agentId === agentId);
  // Build subagents: slice from the Agent call description, lane from the worktree they touched.
  expect(by('af4e38341539ac2cf').length).toBeGreaterThan(5);
  for (const r of by('af4e38341539ac2cf')) expect(r).toEqual({ agentId: 'af4e38341539ac2cf', lane: 1, slice: 653 });
  for (const r of by('a97cac545564d0d61')) expect(r).toEqual({ agentId: 'a97cac545564d0d61', lane: 2, slice: 654 });
  // A review subagent is not a lane: exact agent, nothing else.
  for (const r of by('a72f07f44125066b2')) expect(r).toEqual({ agentId: 'a72f07f44125066b2' });
  // A line of the main thread has no agent; the Agent call line itself too.
  expect(result[0]).toEqual({ agentId: null });
  // task_* bookkeeping lines carry no agent_id: they stay with the main thread.
  expect(result[lines.findIndex((l) => l.subtype === 'task_progress')]).toEqual({ agentId: null });
});

test('the prompt carries the 401 rule only when the context has a forgeAgent', () => {
  const withAgent = buildClaudeCommand(task, { ...ctx, forgeAgent: 'artanis-agent' });
  expect(withAgent.args).toContain(buildPrompt(task, { forgeAgent: 'artanis-agent' }));
  expect(withAgent.args.join('\n')).toContain('agent-forge gh artanis-agent <the same arguments>');
  expect(buildClaudeCommand(task, ctx).args.join('\n')).not.toContain('agent-forge');
});

test('an account\'s command, compaction and launch arguments reach the process; without them the command is unchanged', () => {
  const plain = buildClaudeCommand(task, ctx);
  const command = buildClaudeCommand({ ...task, command: '/opt/claude/bin/claude', autoCompact: 300000, idleCompaction: false, launchArgs: ['--chrome', '--verbose'] }, ctx);
  expect(command.bin).toBe('/opt/claude/bin/claude');
  expect(command.args).toEqual([...plain.args, '--autocompact', '300000', '--settings', '{"idleCompaction":false}', '--chrome', '--verbose']);
  expect(command.env).toEqual(plain.env);
  expect(buildClaudeCommand({ ...task, autoCompact: 'auto' }, ctx).args.slice(-2)).toEqual(['--autocompact', 'auto']);
  expect(buildClaudeCommand({ ...task, idleCompaction: true }, ctx).args.slice(-2)).toEqual(['--settings', '{"idleCompaction":true}']);
  expect(buildClaudeCommand({ ...task, launchArgs: [] }, ctx)).toEqual(plain);
});

test('an effort is passed as --effort, and without one nothing is added', () => {
  const plain = buildClaudeCommand(task, ctx);
  expect(plain.args).not.toContain('--effort');
  const args = buildClaudeCommand({ ...task, effort: 'xhigh' }, ctx).args;
  expect(args.filter((_, i) => args[i] !== '--effort' && args[i - 1] !== '--effort')).toEqual(plain.args);
  expect(args[args.indexOf('--effort') + 1]).toBe('xhigh');
  expect(buildClaudeCommand({ ...task, effort: 'low', resumeSession: 's-1' }, ctx).args).toContain('--effort');
});

test('an engine Claude run gets no chat MCP configuration in its arguments or environment', () => {
  const { args, env } = buildClaudeCommand(task, ctx);
  expect(args).not.toContain('--mcp-config');
  expect(`${args.join('\n')}\n${Object.entries(env).flat().join('\n')}`).not.toMatch(/carrier-chat|mcp_servers|mcp-config/i);
});

test('no engine module imports the chat MCP or anything from the chat host', () => {
  const root = join(import.meta.dirname, '..');
  const sources = ['orchestration', 'execution', 'harnesses'].flatMap((dir) =>
    (readdirSync(join(root, dir), { recursive: true, encoding: 'utf8' }) as string[]).filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts')).map((f) => join(root, dir, f)),
  );
  expect(sources.length).toBeGreaterThan(0);
  for (const file of sources) expect(readFileSync(file, 'utf8'), file).not.toMatch(/(?:from|import\()\s*['"][^'"]*(?:\/chat\/|mcp)/i);
});
