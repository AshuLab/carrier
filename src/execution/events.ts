import { redact } from '../logging/redact.ts';

/** What one harness line says an agent did (ADR 0006). The engine adds the execution and the id when it stores it. */
export interface AgentEvent {
  /** ms since epoch, the line's own time. Absent when the line has none: the engine stamps its arrival. */
  at?: number;
  kind: 'say' | 'tool_start' | 'tool_end' | 'note' | 'error' | 'task';
  text?: string;
  callId?: string;
  /** The subagent that produced it. */
  agentId?: string;
  tool?: string;
  arg?: string;
  /** The model's own short sentence for a call, when it wrote one (a Bash call's `description`); `arg` is untouched. */
  description?: string;
  summary?: string;
  status?: 'ok' | 'err';
  durationMs?: number;
  /** The first and last lines of a command's result. */
  output?: string[];
  diff?: { sign: '+' | '-' | ' '; text: string }[];
  /** Hints from the model's own wording (docs/research/claude-subagent-attribution.md); only on `task`. */
  slice?: number;
  lane?: number;
}

/** What an adapter keeps between lines of one run, to pair a call with its result. */
export interface EventState {
  calls: Map<string, { at?: number; tool: string }>;
  tasks: Map<string, { description: string; slice?: number }>;
  lanes: Map<string, number>;
  /** The streamed fragments of each model turn not yet closed (Antigravity). */
  text: Map<string, string>;
}

export const createEventState = (): EventState => ({ calls: new Map(), tasks: new Map(), lanes: new Map(), text: new Map() });

// Characters, not bytes.
export const caps = { arg: 1024, summary: 200, text: 4096, output: 4096, diffLines: 200, diffLine: 200 };

/** Redacts first, so a secret is never cut in a way that hides its shape, then cuts. */
export function clean(text: string, max: number): string {
  const safe = redact(text);
  return safe.length <= max ? safe : `${safe.slice(0, max - 1)}…`;
}

/** A command's result: all of it when small, else the first and last half of the budget around a gap. */
export function boundOutput(text: string): string[] {
  const safe = redact(text).trimEnd();
  if (safe === '') return [];
  if (safe.length <= caps.output) return safe.split('\n');
  const half = Math.floor((caps.output - 3) / 2); // the gap line and its two newlines count too
  return [...safe.slice(0, half).split('\n'), '…', ...safe.slice(-half).split('\n')];
}
