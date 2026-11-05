import { execFile } from 'node:child_process';

/** What running one git command comes to. `code` is git's exit status, null when git could not run or ran out of time. `stderr` is git's own words and can hold a URL: it is never logged or sent to a client as it is. */
export type GitResult = { ok: true; out: string } | { ok: false; code: number | null; timedOut?: true; stderr: string };

/** The port through which the chat host runs the `git` of the machine (docs/specs/session-worktrees.md, Decisions). */
export interface Git {
  /** Runs `git <args>` in `folder`: no shell, so every argument stays one argument. Never rejects. `timeoutMs` replaces the default limit; `env` is added to the host's (credentials travel here, never in `args`); `signal` kills git when it aborts. `onProgress` is called with each line git writes to stderr while it runs (git is told `--progress`, since it only reports on a terminal otherwise): the caller keeps what it may show, as stderr can hold a URL. */
  run(folder: string, args: string[], options?: { timeoutMs?: number; env?: NodeJS.ProcessEnv; signal?: AbortSignal; onProgress?: (line: string) => void }): Promise<GitResult>;
}

const TIMEOUT_MS = 20_000;
const MAX_OUTPUT = 16 * 1024 * 1024;

/** The host's own environment plus `GIT_TERMINAL_PROMPT=0`, so a command that wants a password fails instead of waiting for one. */
export const realGit: Git = {
  run: (folder, args, options) =>
    new Promise((resolve) => {
      const { onProgress } = options ?? {};
      const child = execFile('git', onProgress === undefined ? args : [args[0]!, '--progress', ...args.slice(1)], { cwd: folder, env: { ...process.env, GIT_TERMINAL_PROMPT: '0', ...options?.env }, signal: options?.signal, timeout: options?.timeoutMs ?? TIMEOUT_MS, maxBuffer: MAX_OUTPUT, encoding: 'utf8' }, (error, stdout, stderr) => {
        if (error === null) return resolve({ ok: true, out: stdout });
        const { code, killed } = error as NodeJS.ErrnoException & { killed?: boolean };
        if (killed) return resolve({ ok: false, code: null, timedOut: true, stderr: 'git took too long' });
        resolve({ ok: false, code: typeof code === 'number' ? code : null, stderr: stderr || error.message });
      });
      if (onProgress !== undefined) {
        // git ends a progress line with a carriage return, so it is not a line until the next one comes
        let partial = '';
        child.stderr?.on('data', (chunk: string) => {
          const lines = (partial + chunk).split(/[\r\n]+/);
          partial = lines.pop()!;
          for (const line of lines) onProgress(line);
        });
      }
    }),
};
