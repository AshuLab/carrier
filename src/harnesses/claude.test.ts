import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
