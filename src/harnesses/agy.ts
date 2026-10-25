import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { childEnv, markerFor, type AgentCommand, type CommandContext, type HarnessAdapter, type LineSignal } from './common.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { boundOutput, caps, clean, type AgentEvent, type EventState } from '../execution/events.ts';

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
      buildPrompt(task, { forgeAgent: ctx.forgeAgent }),
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

const str = (value: unknown) => (typeof value === 'string' ? value : undefined);
const obj = (value: unknown): Record<string, unknown> => (typeof value === 'object' && value !== null ? (value as Record<string, unknown>) : {});

// What the call acts on: the command or the path, else the first text parameter of a tool not seen before.
function argOf(parameters: Record<string, unknown>): string {
  return str(parameters.CommandLine) ?? str(parameters.Path) ?? Object.values(parameters).find((value): value is string => typeof value === 'string') ?? '';
}

const exitCode = (output: string) => /^Command exited with code (\d+)/.exec(output)?.[1];

function agyEvents(line: string, state: EventState): AgentEvent[] {
  const event = obj(JSON.parse(line));
  if (event.event === 'result') {
    // A turn left open (the run was cut short) still said what it said.
    const pending = [...state.text.values()].join('').trim();
    state.text.clear();
    const { status, error } = obj(event.result);
    const failed = str(error) ?? (str(status) !== undefined && status !== 'SUCCESS' ? `the run ended: ${status}` : undefined);
    return [...(pending ? [{ kind: 'say' as const, text: clean(pending, caps.text) }] : []), ...(failed === undefined ? [] : [{ kind: 'error' as const, text: clean(failed, caps.text) }])];
  }
  if (event.event !== 'step_update') return []; // init, and whatever a newer agy adds
  const step = obj(event.step_update);
  const key = `${str(step.conversation_id) ?? ''}:${String(step.step_index)}`;
  const done = step.state === 'DONE';
  const delta = str(step.text_delta) ?? '';

  if (step.step_type === 'agent_response') {
    const text = (state.text.get(key) ?? '') + delta;
    if (!done) {
      state.text.set(key, text);
      return [];
    }
    state.text.delete(key);
    return text.trim() === '' ? [] : [{ kind: 'say', text: clean(text.trim(), caps.text) }];
  }
  if (step.step_type !== 'tool') return []; // user_input, and step types not seen yet: nothing to record
  const info = obj(step.tool_info);
  const tool = str(step.tool_name) ?? str(info.name) ?? 'tool';
  if (!done) {
    state.calls.set(key, { tool });
    return [{ kind: 'tool_start', callId: key, tool, arg: clean(argOf(obj(info.parameters)), caps.arg) }];
  }
  state.calls.delete(key);
  const output = str(info.output) ?? '';
  const code = tool === 'run_command' ? exitCode(output) : undefined;
  // A command's own output is what the design collapses; a read returns only a size, an edit nothing.
  const body = code === undefined ? [] : boundOutput(output.slice(output.indexOf('Command output:') + 'Command output:'.length).replace(/\r\n/g, '\n').replace(/^\n/, ''));
  const first = output.split('\n').find((l) => l.trim() !== '');
  const summary = code === undefined ? first && clean(first, caps.summary) : `Exit code ${code}`;
  return [
    {
      kind: 'tool_end',
      callId: key,
      tool,
      status: code === undefined || code === '0' ? 'ok' : 'err',
      ...(typeof step.duration_seconds === 'number' && { durationMs: Math.round(step.duration_seconds * 1000) }),
      ...(summary && { summary }),
      ...(body.length > 0 && { output: body }),
    },
  ];
}

/** Events of one stream-json line (docs/research/antigravity-stream.md). Never throws. */
export function parseAgyEvents(line: string, state: EventState): AgentEvent[] {
  try {
    return agyEvents(line, state);
  } catch {
    return []; // not JSON, or a shape this version of agy changed: the log keeps it, the events skip it
  }
}

export const agyAdapter: HarnessAdapter = { command: buildAgyCommand, parseLine: parseAgyLine, parseEvents: parseAgyEvents };
