import { buildPrompt } from '../prompts/build-prompt.ts';
import { childEnv, markerFor, type AgentCommand, type CommandContext, type LineSignal, type HarnessAdapter } from './common.ts';
import type { AgentTask } from '../execution/agent-runner.ts';

/**
 * Headless Codex as in docs/research/headless-agents.md; stdin is closed by the runner.
 * The unattended agent has to push and call `gh`, which Codex's sandbox blocks (no network), and nobody
 * can answer an approval, so the command skips both: the same trade as Claude's bypassPermissions (ADR 0004).
 * That one flag also covers `resume`, which takes neither --sandbox nor --add-dir, so the result path outside
 * the workspace needs no --add-dir. Login, config, plugins and hooks stay those of the user's CLI.
 */
export function buildCodexCommand(task: AgentTask, ctx: CommandContext): AgentCommand {
  return {
    bin: ctx.binary,
    args: [
      'exec',
      ...(task.resumeSession ? ['resume', task.resumeSession] : []),
      buildPrompt(task),
      // JSONL: thread.started carries the session id while the run is going.
      '--json',
      '--model',
      task.model,
      // `--oss --local-provider` is refused by `exec resume`; the config key both of them set is accepted by every form.
      ...(task.provider ? ['-c', `model_provider="${task.provider}"`] : []),
      '--dangerously-bypass-approvals-and-sandbox',
      // Codex has no flag to name a run; a config key it ignores keeps the marker in argv for listActive/stop.
      '-c',
      `carrier_marker="${markerFor(task.executionId)}"`,
    ],
    cwd: task.workspace,
    env: { ...childEnv(ctx), CARRIER_RESULT_PATH: task.resultPath },
  };
}

// Shapes observed with codex 0.153.4: thread.started carries the session; a missing login ends with
// turn.failed "unexpected status 401 Unauthorized" (the "Reconnecting... n/5 (... 401" error events before it
// are retries, not the end); resuming an unknown thread prints "no rollout found for thread id" on stderr, not JSON.
export function parseCodexLine(line: string): LineSignal | undefined {
  let event: Record<string, any>;
  try {
    event = JSON.parse(line);
  } catch {
    return line.includes('no rollout found for thread id') ? { sessionUnavailable: true } : undefined;
  }
  if (event.type === 'thread.started' && typeof event.thread_id === 'string') return { session: event.thread_id };
  if (event.type === 'turn.failed' && String(event.error?.message).includes('401 Unauthorized')) return { authFailed: true };
  return undefined;
}

export const codexAdapter: HarnessAdapter = { command: buildCodexCommand, parseLine: parseCodexLine };
