import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { childEnv, markerFor, type AgentCommand, type CommandContext, type HarnessAdapter, type LineSignal } from './common.ts';
import type { AgentTask } from '../execution/agent-runner.ts';

/**
 * Headless Antigravity as in docs/research/antigravity.md; stdin is closed by the runner.
 * `agy` has no flag to name a run, so the marker rides in the path of its log file, which is part of argv.
 * Permissions are skipped explicitly (ADR 0004) instead of relying on the operator's `toolPermission` setting, and
 * there is no sandbox to turn off: `--sandbox` is opt-in. Resume restores context from any cwd, like Claude.
 */
export function buildAgyCommand(task: AgentTask, ctx: CommandContext): AgentCommand {
  return {
    bin: ctx.binary,
    args: [
      '-p',
      buildPrompt(task),
      // stream-json (not json) so the conversation id arrives while the run is going.
      '--output-format',
      'stream-json',
      '--model',
      task.model,
      '--dangerously-skip-permissions',
      '--add-dir',
      dirname(task.resultPath),
      '--log-file',
      join(tmpdir(), `${markerFor(task.executionId)}.log`), // agy's own log, not ours to keep: the OS cleans the temp folder
      ...(task.resumeSession ? ['--conversation', task.resumeSession] : []),
    ],
    cwd: task.workspace,
    env: { ...childEnv(ctx), CARRIER_RESULT_PATH: task.resultPath },
  };
}

// Shapes observed with agy 1.4.0: the first stdout line is `init` with the conversation id, written before the model is
// called; a missing login prints "Authentication required" on stderr and ~60 s later ends with a `result` whose error is
// "authentication failed or timed out"; resuming an unknown id does NOT fail: it exits 0 in a new conversation and only
// says so on stderr. Both streams go through here.
export function parseAgyLine(line: string): LineSignal | undefined {
  if (line.includes('Authentication required')) return { authFailed: true };
  if (/warning: conversation ".*" not found/.test(line)) return { sessionUnavailable: true };
  let event: Record<string, any>;
  try {
    event = JSON.parse(line);
  } catch {
    return undefined;
  }
  if (event.event === 'init' && typeof event.conversation_id === 'string') return { session: event.conversation_id };
  if (event.event === 'result' && event.result?.error === 'authentication failed or timed out') return { authFailed: true };
  return undefined;
}

export const agyAdapter: HarnessAdapter = { command: buildAgyCommand, parseLine: parseAgyLine };
