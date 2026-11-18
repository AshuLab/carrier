import { appendFileSync, closeSync, existsSync, fstatSync, mkdirSync, openSync, renameSync, writeSync } from 'node:fs';
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
  const write = rotatingFile(file);
  for (const method of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    console[method] = (...args: unknown[]) => write(redact(`[${method}] ${format(...args)}\n`));
  }
  configureUniversalLogger({ enabled: true, minLevel });
}

/**
 * Appends to `file` and rotates it by size: past `maxBytes` it becomes `file.1`, `file.1` becomes `file.2`, and so on,
 * and the oldest beyond `keep` files in all is overwritten. Rotation happens between whole writes, so a line is never split.
 */
export function rotatingFile(file: string, maxBytes = 10 * 1024 * 1024, keep = 10): (text: string) => void {
  mkdirSync(dirname(file), { recursive: true });
  let fd = openSync(file, 'a');
  let size = fstatSync(fd).size;
  return (text) => {
    if (size > 0 && size + Buffer.byteLength(text) > maxBytes) {
      closeSync(fd);
      let failed: unknown;
      try {
        for (let n = keep - 2; n >= 1; n--) if (existsSync(`${file}.${n}`)) renameSync(`${file}.${n}`, `${file}.${n + 1}`);
        renameSync(file, `${file}.1`);
      } catch (error) {
        failed = error; // the log was moved or deleted meanwhile: a new one starts, since a console call must never throw
      }
      mkdirSync(dirname(file), { recursive: true });
      fd = openSync(file, 'a');
      size = 0;
      if (failed !== undefined) text = `[warn] the log could not be rotated: ${String(failed)}\n${text}`;
    }
    writeSync(fd, text);
    size += Buffer.byteLength(text);
  };
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

const MAX_PENDING = 64 * 1024;

/**
 * Where the whole output of one execution goes: `<logs>/executions/<executionId>/{stdout,stderr}.log`.
 * Only whole lines are redacted and written, so a token split across two chunks is still caught; `flush` writes what is left when the run ends.
 */
export function executionOutput(logs: string, executionId: string) {
  const dir = join(logs, 'executions', executionId);
  mkdirSync(dir, { recursive: true });
  const pending = { stdout: '', stderr: '' };
  const append = (stream: 'stdout' | 'stderr', text: string) => text && appendFileSync(join(dir, `${stream}.log`), redact(text));
  return {
    write(stream: 'stdout' | 'stderr', chunk: string) {
      const text = pending[stream] + chunk;
      // a line that never ends is written anyway past the cap: memory over a perfect redaction
      const cut = text.length > MAX_PENDING ? text.length : text.lastIndexOf('\n') + 1;
      append(stream, text.slice(0, cut));
      pending[stream] = text.slice(cut);
    },
    flush() {
      append('stdout', pending.stdout);
      append('stderr', pending.stderr);
      pending.stdout = pending.stderr = '';
    },
  };
}
