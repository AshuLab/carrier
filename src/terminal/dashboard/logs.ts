import { closeSync, openSync, readSync, statSync } from 'node:fs';
import { join } from 'node:path';

// The agent's output is one JSON event per line, in a different shape for each harness. What is worth reading in each:
// what it said, and what tool it ran. Everything else (init, usage, step bookkeeping) is skipped.
const brief = (value: unknown, max = 60) => {
  const text = typeof value === 'string' ? value : JSON.stringify(value) ?? '';
  return text.length > max ? `${text.slice(0, max - 1)}…` : text;
};

// Claude's own notices: what it published and which of its background jobs ended. Starts, progress and usage are noise.
function summarizeNotice(e: Record<string, any>): string | null {
  if (e.subtype === 'code_change_published') return `▲ PR #${e.identifier} ${e.action}`;
  if (e.subtype === 'vcs_state_changed' && e.kind === 'push') return '▲ pushed';
  if (e.subtype !== 'task_notification') return null;
  const summary = String(e.summary ?? '');
  if (e.status === 'failed') return `✗ ${brief(summary, 80)}`;
  // a sub-agent (one `ship` slice) reports its result as JSON; a finished shell command is already in the log as the line that started it
  const slice = /"slice":\s*"([^"]+)",\s*"outcome":\s*"([^"]+)"/.exec(summary);
  return slice ? `✓ slice ${slice[1]} ${slice[2]}` : null;
}

export function summarizeLogLine(line: string): string | null {
  if (line.trim() === '') return null;
  let e: Record<string, any>;
  try {
    e = JSON.parse(line);
  } catch {
    return line.trim(); // not an event: an error message, say
  }
  if (e === null || typeof e !== 'object') return line.trim();
  // Claude Code (stream-json)
  if (e.type === 'assistant') {
    const parts: unknown[] = Array.isArray(e.message?.content) ? e.message.content : [];
    const out = parts.map((c: any) => (c?.type === 'text' ? String(c.text).trim() : c?.type === 'tool_use' ? `▸ ${c.name} ${brief(c.input)}` : '')).filter(Boolean);
    return out.length > 0 ? out.join(' ') : null;
  }
  if (e.type === 'result') return `result: ${brief(e.result ?? e.subtype ?? e.status ?? '', 100)}`;
  if (e.type === 'system') return summarizeNotice(e);
  // Codex (--json)
  if (e.item?.type === 'agent_message') return String(e.item.text).trim();
  if (e.item?.type === 'command_execution' && e.type === 'item.started') return `$ ${brief(e.item.command, 90)}`;
  // Antigravity (stream-json)
  if (e.event === 'step_update') {
    const su = e.step_update ?? {};
    if (su.tool_name && su.state === 'ACTIVE') return `▸ ${su.tool_name} ${brief(su.tool_info ?? '')}`;
    return su.state === 'DONE' && su.step_type === 'agent_response' && typeof su.text_delta === 'string' && su.text_delta.trim() ? su.text_delta.trim() : null;
  }
  if (e.event === 'result') return `result: ${brief(e.result?.response ?? e.result?.status ?? '', 100)}`;
  return null;
}

/** The last `count` meaningful lines of an execution's output, read from the end of the file (it can be megabytes). */
export function tailExecution(root: string, executionId: string, count: number, fileSizeLimit = 256 * 1024): string[] {
  const path = join(root, 'orchestrator', 'logs', 'executions', executionId, 'stdout.log');
  let fd: number;
  try {
    fd = openSync(path, 'r');
  } catch {
    return []; // nothing written yet
  }
  try {
    const size = statSync(path).size;
    const start = Math.max(0, size - fileSizeLimit);
    const buffer = Buffer.alloc(size - start);
    readSync(fd, buffer, 0, buffer.length, start);
    const lines = buffer.toString('utf8').split('\n');
    if (start > 0) lines.shift(); // cut in the middle of a line
    return lines.flatMap((l) => summarizeLogLine(l) ?? []).slice(-count);
  } finally {
    closeSync(fd);
  }
}
