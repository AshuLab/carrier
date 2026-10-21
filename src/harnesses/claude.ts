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

export type SubagentAttribution = { agentId: string | null; lane?: number; slice?: number };

type Block = { type?: string; id?: string; name?: string; input?: Record<string, unknown> };

function blocksOf(line: Record<string, unknown>): Block[] {
  const content = (line.message as { content?: unknown } | undefined)?.content;
  return Array.isArray(content) ? (content as Block[]) : [];
}

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
      const lane = /--lane-(\d+)/.exec(JSON.stringify(blocksOf(line).filter((block) => block.type === 'tool_use').map((block) => block.input)))?.[1];
      if (lane) laneOfAgent.set(agent, Number(lane));
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
    const slice = /slice #(\d+)/i.exec(description)?.[1];
    const lane = laneOfAgent.get(agentId);
    return { agentId, ...(lane === undefined ? {} : { lane }), ...(slice === undefined ? {} : { slice: Number(slice) }) };
  });
}

export const claudeAdapter: HarnessAdapter = { command: buildClaudeCommand, parseLine: parseClaudeLine };
