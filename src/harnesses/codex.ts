import { buildPrompt } from '../prompts/build-prompt.ts';
import { childEnv, markerFor, type AgentCommand, type CommandContext, type LineSignal, type HarnessAdapter } from './common.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { boundOutput, caps, clean, type AgentEvent, type EventState } from '../execution/events.ts';

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
      buildPrompt(task, { forgeAgent: ctx.forgeAgent }),
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

const str = (value: unknown) => (typeof value === 'string' ? value : undefined);

// Codex runs every command as `<shell> -lc '<the command>'`; the user's command is what is inside.
const unwrap = (command: string) => {
  const match = /^\S+ -lc (['"])([\s\S]*)\1$/.exec(command);
  if (match === null) return command;
  return match[1] === '"' ? match[2]!.replace(/\\(["\\$`])/g, '$1') : match[2]!;
};

type Item = { id?: unknown; type?: unknown; message?: unknown; text?: unknown; command?: unknown; aggregated_output?: unknown; exit_code?: unknown; status?: unknown; changes?: unknown };

function codexEvents(line: string, state: EventState): AgentEvent[] {
  const event = JSON.parse(line) as { type?: unknown; item?: Item; error?: { message?: unknown } } | null;
  if (typeof event !== 'object' || event === null) return [];
  if (event.type === 'turn.failed') return [{ kind: 'error', text: clean(str(event.error?.message) ?? 'the turn failed', caps.text) }];
  const item = event.item;
  if (typeof item !== 'object' || item === null) return [];
  const started = event.type === 'item.started';
  if (!started && event.type !== 'item.completed') return [];
  const callId = str(item.id);
  // The stream has no time: the engine stamps each event with the arrival of its line (and so no duration either).
  if (item.type === 'agent_message') {
    const text = str(item.text);
    return text ? [{ kind: 'say', text: clean(text, caps.text) }] : [];
  }
  // Codex prints its own warnings as error items (a notice about a flag, not a failure of the run).
  if (item.type === 'error') {
    const text = str(item.message);
    return text ? [{ kind: 'note', text: clean(text, caps.summary) }] : [];
  }
  if (callId === undefined || (item.type !== 'command_execution' && item.type !== 'file_change')) return [];
  const command = item.type === 'command_execution';
  const tool = command ? 'shell' : 'Edit';
  if (started) {
    state.calls.set(callId, { tool });
    const paths = Array.isArray(item.changes) ? item.changes.map((change) => str((change as { path?: unknown })?.path)).filter((path) => path !== undefined) : [];
    return [{ kind: 'tool_start', callId, tool, arg: clean(command ? unwrap(str(item.command) ?? '') : paths.join(', '), caps.arg) }];
  }
  state.calls.delete(callId);
  if (!command) {
    const files = Array.isArray(item.changes) ? item.changes.length : 0;
    return [{ kind: 'tool_end', callId, tool, status: item.status === 'failed' ? 'err' : 'ok', summary: `${files} file${files === 1 ? '' : 's'}` }];
  }
  const code = typeof item.exit_code === 'number' ? item.exit_code : undefined;
  const text = str(item.aggregated_output) ?? '';
  const failed = code === undefined ? item.status === 'failed' : code !== 0;
  const firstLine = text.split('\n').find((l) => l.trim() !== '');
  const summary = failed && code !== undefined ? `Exit code ${code}` : firstLine && clean(firstLine, caps.summary);
  const output = boundOutput(text);
  return [{ kind: 'tool_end', callId, tool, status: failed ? 'err' : 'ok', ...(summary && { summary }), ...(output.length > 0 && { output }) }];
}

/** Events of one `exec --json` line (docs/research/codex-exec-stream.md). Never throws; reasoning, todo lists and whatever else a newer CLI adds give []. */
export function parseCodexEvents(line: string, state: EventState): AgentEvent[] {
  try {
    return codexEvents(line, state);
  } catch {
    return []; // not JSON, or a shape this version of the CLI changed: the log keeps it, the events skip it
  }
}

export const codexAdapter: HarnessAdapter = { command: buildCodexCommand, parseLine: parseCodexLine, parseEvents: parseCodexEvents };
