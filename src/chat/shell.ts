import { spawn } from 'node:child_process';

/** What running one command comes to. `code` is its exit status, null when it could not run or was stopped (`aborted`). `output` is the end of what it wrote, which can hold a token: it is redacted and cut before anyone sees it. */
export type ShellResult = { ok: true } | { ok: false; code: number | null; aborted?: true; output: string };

/** The port through which the chat host runs a project's action (ADR 0039): `sh -c`, never a git. */
export interface Shell {
  /** Runs `command` through `sh -c` in `folder` with `env` (its host's own plus what the caller adds). No time limit: `signal` stops it, with what it started. `onProgress` gets each line it writes, stdout and stderr alike. Never rejects. */
  run(folder: string, command: string, options: { env: NodeJS.ProcessEnv; signal: AbortSignal; onProgress: (line: string) => void }): Promise<ShellResult>;
}

/** How much of the end of a command's output is kept. */
const KEPT = 64 * 1024;
// eslint-disable-next-line no-control-regex
const ansi = /\u001b\[[0-9;?]*[ -/]*[@-~]/g;

export const realShell: Shell = {
  run: (folder, command, { env, signal, onProgress }) =>
    new Promise<ShellResult>((resolve) => {
      if (signal.aborted) return resolve({ ok: false, code: null, aborted: true, output: '' });
      // its own process group, so a stop reaches what the command started (an install's children) and not only the shell
      const child = spawn('sh', ['-c', command], { cwd: folder, env, detached: true, stdio: ['ignore', 'pipe', 'pipe'] });
      let output = '';
      let partial = '';
      const lines = (chunk: string, last = false) => {
        const found = (partial + chunk).split(/[\r\n]+/);
        partial = last ? '' : found.pop()!;
        for (const line of found) if (line.trim() !== '') onProgress(line.replace(ansi, ''));
      };
      const take = (chunk: Buffer) => {
        const text = chunk.toString('utf8');
        output = (output + text).slice(-KEPT);
        lines(text);
      };
      child.stdout.on('data', take);
      child.stderr.on('data', take);
      const stop = () => {
        try {
          process.kill(-child.pid!, 'SIGTERM');
        } catch {
          // already gone
        }
      };
      signal.addEventListener('abort', stop, { once: true });
      child.on('error', (error) => resolve({ ok: false, code: null, output: error.message }));
      child.on('close', (code) => {
        signal.removeEventListener('abort', stop);
        lines('', true);
        if (signal.aborted) return resolve({ ok: false, code: null, aborted: true, output });
        resolve(code === 0 ? { ok: true } : { ok: false, code, output });
      });
    }),
};
