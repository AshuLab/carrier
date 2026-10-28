import { dirname } from 'node:path';
import { buildPrompt } from '../prompts/build-prompt.ts';
import { claudeLocalEnv } from './local.ts';
import { childEnv, markerFor, type AgentCommand, type CommandContext, type LineSignal, type HarnessAdapter } from './common.ts';
import type { AgentTask } from '../execution/agent-runner.ts';
import { boundOutput, caps, clean, type AgentEvent, type EventState } from '../execution/events.ts';

/** Headless Claude as in docs/research/headless-agents.md; stdin is closed by the runner. */
export function buildClaudeCommand(task: AgentTask, ctx: CommandContext): AgentCommand {
  return {
    bin: ctx.binary,
    args: [
      '-p',
      buildPrompt(task, { forgeAgent: ctx.forgeAgent }),
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
    env: { ...childEnv(ctx), ...(task.provider ? claudeLocalEnv(task.provider) : {}), ...(task.configDir && { CLAUDE_CONFIG_DIR: task.configDir }), CARRIER_RESULT_PATH: task.resultPath },
  };
}

// Shapes observed with claude 2.1.301: init carries the session; a login or key error is an assistant
// message with error "authentication_failed" and a result with api_error_status 401; a lost session is
// a result "error_during_execution" saying "No conversation found"; an API error is a result with a numeric
// api_error_status (429 with api_error "usage_limit_reached" is the session limit) and the message in result.
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
    if (event.is_error === true && typeof event.api_error_status === 'number') {
      const text = typeof event.result === 'string' ? event.result : '';
      if (event.api_error_status === 429 && event.api_error === 'usage_limit_reached') return { failure: { kind: 'usage_limit', detail: text } };
      return { failure: { kind: 'api_error', detail: `HTTP ${event.api_error_status}${text ? `: ${text}` : ''}` } };
    }
  }
  return undefined;
}

export type SubagentAttribution = { agentId: string | null; lane?: number; slice?: number };

type Block = { type?: string; id?: string; name?: string; input?: Record<string, unknown> };

function blocksOf(line: Record<string, unknown>): Block[] {
  const content = (line.message as { content?: unknown } | undefined)?.content;
  return Array.isArray(content) ? (content as Block[]) : [];
}

const sliceIn = (description: string) => {
  const slice = /slice #(\d+)/i.exec(description)?.[1];
  return slice === undefined ? undefined : Number(slice);
};

const laneIn = (blocks: Block[]) => {
  const lane = /--lane-(\d+)/.exec(JSON.stringify(blocks.filter((block) => block.type === 'tool_use').map((block) => block.input)))?.[1];
  return lane === undefined ? undefined : Number(lane);
};

/**
 * Which subagent, lane and slice each parsed stream line belongs to (docs/research/claude-subagent-attribution.md).
 * Exact: `agent_id` on a subagent's messages; `parent_tool_use_id` points back to its `Agent` call.
 * Hints, from the model's own conventions: the slice is "slice #N" in that call's description, the lane is
 * `--lane-N` in a path the subagent touched. Both stay undefined when the convention was not followed.
 */
export function attributeSubagentLines(lines: readonly Record<string, unknown>[]): SubagentAttribution[] {
  const callDescription = new Map<string, string>();
  const laneOfAgent = new Map<string, number>();
  for (const line of lines) {
    const agent = line.agent_id;
    if (typeof agent === 'string' && !laneOfAgent.has(agent)) {
      const lane = laneIn(blocksOf(line));
      if (lane !== undefined) laneOfAgent.set(agent, lane);
    }
    for (const block of blocksOf(line)) {
      if (block.type === 'tool_use' && block.name === 'Agent' && typeof block.id === 'string' && typeof block.input?.description === 'string') {
        callDescription.set(block.id, block.input.description);
      }
    }
  }
  return lines.map((line) => {
    const parent = typeof line.parent_tool_use_id === 'string' ? line.parent_tool_use_id : undefined;
    const agentId = typeof line.agent_id === 'string' ? line.agent_id : null;
    if (agentId === null) return { agentId };
    const description = (parent && callDescription.get(parent)) ?? (typeof line.task_description === 'string' ? line.task_description : '');
    const slice = sliceIn(description);
    const lane = laneOfAgent.get(agentId);
    return { agentId, ...(lane === undefined ? {} : { lane }), ...(slice === undefined ? {} : { slice }) };
  });
}

const str = (value: unknown) => (typeof value === 'string' ? value : undefined);

// The one-line argument of a call: what it acts on.
function argOf(input: Record<string, unknown> | undefined): string {
  if (!input) return '';
  for (const key of ['command', 'file_path', 'pattern', 'path', 'url', 'query', 'description']) {
    const value = str(input[key]);
    if (value !== undefined) return value;
  }
  return Object.values(input).find((value): value is string => typeof value === 'string') ?? '';
}

// A tool_result's content is a string, or a list of blocks of which the text ones count.
function resultText(content: unknown): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((part) => str((part as { text?: unknown })?.text) ?? '').join('\n');
}

// `structuredPatch` of an Edit or Write result: hunks of lines that start with ' ', '-' or '+'.
function diffOf(result: unknown): { diff: NonNullable<AgentEvent['diff']>; added: number; removed: number } | undefined {
  const hunks = (result as { structuredPatch?: unknown } | undefined)?.structuredPatch;
  if (!Array.isArray(hunks)) return undefined;
  const lines = hunks.flatMap((hunk) => ((hunk as { lines?: unknown })?.lines as unknown[] | undefined) ?? []).filter((line): line is string => typeof line === 'string');
  if (lines.length === 0) return undefined;
  const diff = lines.slice(0, caps.diffLines).map((line): NonNullable<AgentEvent['diff']>[number] => ({ sign: line[0] === '+' ? '+' : line[0] === '-' ? '-' : ' ', text: clean(line.slice(1), caps.diffLine) }));
  if (lines.length > caps.diffLines) diff.push({ sign: ' ', text: `… ${lines.length - caps.diffLines} more lines` });
  return { diff, added: lines.filter((line) => line[0] === '+').length, removed: lines.filter((line) => line[0] === '-').length };
}

function claudeEvents(line: string, state: EventState): AgentEvent[] {
  const event = JSON.parse(line) as Record<string, unknown> | null;
  if (typeof event !== 'object' || event === null) return [];
  const time = typeof event.timestamp === 'string' ? Date.parse(event.timestamp) : NaN;
  const at = Number.isNaN(time) ? undefined : time;
  const agentId = str(event.agent_id);
  const scope = { ...(at === undefined ? {} : { at }), ...(agentId === undefined ? {} : { agentId }) };
  const blocks = blocksOf(event);
  const events: AgentEvent[] = [];

  if (event.type === 'assistant') {
    if (agentId !== undefined && !state.lanes.has(agentId)) {
      const lane = laneIn(blocks);
      if (lane !== undefined) state.lanes.set(agentId, lane);
    }
    if (str(event.error) !== undefined) {
      const text = blocks.map((block) => str((block as { text?: unknown }).text)).find((t) => t) ?? String(event.error);
      return [{ ...scope, kind: 'error', text: clean(text, caps.text) }];
    }
    for (const block of blocks) {
      if (block.type === 'text') {
        const text = str((block as { text?: unknown }).text);
        if (text) events.push({ ...scope, kind: 'say', text: clean(text, caps.text) });
      } else if (block.type === 'tool_use' && typeof block.id === 'string' && typeof block.name === 'string') {
        state.calls.set(block.id, { at, tool: block.name });
        const arg = clean(argOf(block.input), caps.arg);
        const description = str(block.input?.description);
        // Only when `arg` is something else: a call whose argument is its description (an Agent) would say it twice.
        events.push({ ...scope, kind: 'tool_start', callId: block.id, tool: block.name, arg, ...(description && description !== arg && { description: clean(description, caps.summary) }) });
      }
    }
  } else if (event.type === 'user') {
    for (const block of blocks) {
      const result = block as { type?: string; tool_use_id?: unknown; content?: unknown; is_error?: unknown };
      if (result.type !== 'tool_result' || typeof result.tool_use_id !== 'string') continue;
      const call = state.calls.get(result.tool_use_id);
      state.calls.delete(result.tool_use_id);
      const text = resultText(result.content);
      const patch = diffOf(event.tool_use_result);
      const firstLine = text.split('\n').find((l) => l.trim() !== '');
      const summary = patch ? `+${patch.added} -${patch.removed}` : firstLine && clean(firstLine, caps.summary);
      // Only a command's output is kept: it is what the design collapses; a Read would copy whole files.
      const output = call?.tool === 'Bash' ? boundOutput(text) : [];
      events.push({
        ...scope,
        kind: 'tool_end',
        callId: result.tool_use_id,
        ...(call && { tool: call.tool }),
        status: result.is_error === true ? 'err' : 'ok',
        ...(call?.at !== undefined && at !== undefined && { durationMs: Math.max(0, at - call.at) }),
        ...(summary && { summary }),
        ...(output.length > 0 && { output }),
        ...(patch && { diff: patch.diff }),
      });
    }
  } else if (event.type === 'system') {
    const taskId = str(event.task_id);
    const callId = str(event.tool_use_id);
    if (event.subtype === 'task_started' && event.task_type === 'local_agent' && taskId !== undefined) {
      const description = str(event.description) ?? '';
      const slice = sliceIn(description);
      state.tasks.set(taskId, { description, slice });
      events.push({ kind: 'task', agentId: taskId, ...(callId && { callId }), text: clean(description, caps.summary), ...(slice !== undefined && { slice }) });
    } else if (event.subtype === 'task_notification' && taskId !== undefined && state.tasks.has(taskId)) {
      const { description, slice } = state.tasks.get(taskId)!;
      state.tasks.delete(taskId);
      const lane = state.lanes.get(taskId);
      const summary = str(event.summary);
      events.push({
        kind: 'task',
        agentId: taskId,
        ...(callId && { callId }),
        text: clean(description, caps.summary),
        status: event.status === 'completed' ? 'ok' : 'err',
        ...(summary && { summary: clean(summary, caps.summary) }),
        ...(slice !== undefined && { slice }),
        ...(lane !== undefined && { lane }),
      });
    } else if (event.subtype === 'code_change_published') {
      const branch = str(event.branch);
      const text = [str(event.action) ?? 'published', str(event.identifier), branch && `(${branch})`].filter(Boolean).join(' ');
      events.push({ kind: 'note', text: clean(text, caps.summary) });
    }
  } else if (event.type === 'result' && event.is_error === true) {
    events.push({ kind: 'error', text: clean(str(event.result) ?? JSON.stringify(event.errors ?? 'the run ended with an error'), caps.text) });
  }
  // Thinking, hooks, progress, rate limits and whatever else a newer CLI adds fall through: nothing to record.
  return events;
}

/** Events of one stream-json line (docs/research/macos-app-data-engine.md, "Capturing events"). Never throws. */
export function parseClaudeEvents(line: string, state: EventState): AgentEvent[] {
  try {
    return claudeEvents(line, state);
  } catch {
    return []; // not JSON, or a shape this version of the CLI changed: the log keeps it, the events skip it
  }
}

export const claudeAdapter: HarnessAdapter = { command: buildClaudeCommand, parseLine: parseClaudeLine, parseEvents: parseClaudeEvents };
