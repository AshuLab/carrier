import { appendFileSync, mkdirSync, openSync, writeSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { format } from 'node:util';
import { configureUniversalLogger, LogLevel } from '@ashulab/universal-logger';
import type { AgentTask } from '../execution/agent-runner.ts';
import { redact } from './redact.ts';

/**
 * Sends everything the process writes with console.* (the library and its dependencies included) to `file`,
 * so the panel is the only thing that writes to the terminal. The level is not in the library's JSON: the
 * console method used adds it. writeSync, not a stream: when it returns the line is in the kernel, so SIGINT loses nothing.
 */
export function installFileLogging(file: string, minLevel: LogLevel): void {
  process.env.NODE_ENV ??= 'production'; // 'development' makes the library emit several lines per log
  mkdirSync(dirname(file), { recursive: true });
  const fd = openSync(file, 'a');
  for (const method of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    console[method] = (...args: unknown[]) => void writeSync(fd, redact(`[${method}] ${format(...args)}\n`));
  }
  configureUniversalLogger({ enabled: true, minLevel });
}

/** Context every log of an execution carries when it applies. */
export const taskContext = (c: { repo: string; epic: number; executionId: string; stage: AgentTask['stage']; round?: number | null }) => ({
  repo: c.repo,
  epic: c.epic,
  executionId: c.executionId,
  role: c.stage === 'review' ? 'reviewer' : 'author',
  stage: c.stage,
  ...(c.round && { round: c.round }),
});

/** Where the whole output of one execution goes: `<root>/orchestrator/logs/executions/<executionId>/{stdout,stderr}.log`. */
export function executionOutput(root: string, executionId: string) {
  const dir = join(root, 'orchestrator', 'logs', 'executions', executionId);
  mkdirSync(dir, { recursive: true });
  // ponytail: a token split across two chunks is not caught, buffer per stream if the agents' output shows it
  return (stream: 'stdout' | 'stderr', chunk: string) => appendFileSync(join(dir, `${stream}.log`), redact(chunk));
}
