import { dirname } from 'node:path';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { claudeLocalEnv } from './local.ts';
import { childEnv, markerFor, type AgentCommand, type CommandContext, type LineSignal, type HarnessAdapter } from './common.ts';
import type { AgentTask } from '../execution/agent-runner.ts';

/** Headless Claude as in docs/research/headless-agents.md; stdin is closed by the runner. */
export function buildClaudeCommand(task: AgentTask, ctx: CommandContext): AgentCommand {
  return {
    bin: ctx.binary,
    args: [
      '-p',
      buildPrompt(task),
      '--permission-mode',
      'bypassPermissions',
      // stream-json (not json) so the session id arrives while the run is going.
      '--output-format',
      'stream-json',
      '--verbose',
      '--model',
      task.model,
      '--add-dir',
      dirname(task.resultPath),
      '--name',
      markerFor(task.executionId),
      ...(task.resumeSession ? ['--resume', task.resumeSession] : []),
    ],
    cwd: task.workspace,
    env: { ...childEnv(ctx), ...(task.provider ? claudeLocalEnv(task.provider) : {}), CARRIER_RESULT_PATH: task.resultPath },
  };
}

// Shapes observed with claude 2.1.301: init carries the session; a login or key error is an assistant
// message with error "authentication_failed" and a result with api_error_status 401; a lost session is
// a result "error_during_execution" saying "No conversation found".
export function parseClaudeLine(line: string): LineSignal | undefined {
  let event: Record<string, unknown>;
  try {
    event = JSON.parse(line);
  } catch {
    return undefined;
  }
  if (event.type === 'system' && event.subtype === 'init' && typeof event.session_id === 'string') return { session: event.session_id };
  if (event.type === 'assistant' && event.error === 'authentication_failed') return { authFailed: true };
  if (event.type === 'result') {
    if (event.api_error_status === 401) return { authFailed: true };
    if (event.is_error === true && JSON.stringify(event.errors ?? '').includes('No conversation found')) return { sessionUnavailable: true };
  }
  return undefined;
}

export const claudeAdapter: HarnessAdapter = { command: buildClaudeCommand, parseLine: parseClaudeLine };
