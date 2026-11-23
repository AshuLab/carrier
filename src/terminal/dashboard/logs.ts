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

/** The last `limit` bytes of a file as text, and whether the file went further back; null when it does not exist. */
function readTail(path: string, limit: number): { text: string; cut: boolean } | null {
  let fd: number;
  try {
    fd = openSync(path, 'r');
  } catch {
    return null;
  }
  try {
    const size = statSync(path).size;
    const start = Math.max(0, size - limit);
    const buffer = Buffer.alloc(size - start);
    readSync(fd, buffer, 0, buffer.length, start);
    return { text: buffer.toString('utf8'), cut: start > 0 };
  } finally {
    closeSync(fd);
  }
}

/**
 * The last `count` meaningful lines of an execution's output, read from the end of the file (it can be megabytes).
 * Right after a rotation `stdout.log` holds only a small block, so the end of `stdout.log.1` fills what is left of the window.
 */
export function tailExecution(logs: string, executionId: string, count: number, fileSizeLimit = 256 * 1024): string[] {
  const path = join(logs, 'executions', executionId, 'stdout.log');
  const current = readTail(path, fileSizeLimit);
  if (current === null) return []; // nothing written yet
  const room = fileSizeLimit - Buffer.byteLength(current.text);
  const older = current.cut || room <= 0 ? null : readTail(`${path}.1`, room);
  const lines = `${older?.text ?? ''}${current.text}`.split('\n');
  if (older?.cut ?? current.cut) lines.shift(); // cut in the middle of a line
  return lines.flatMap((l) => summarizeLogLine(l) ?? []).slice(-count);
}
