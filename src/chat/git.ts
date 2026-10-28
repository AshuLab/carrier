import { execFile } from 'node:child_process';

/** What running one git command comes to. `code` is git's exit status, null when git could not run or ran out of time. `stderr` is git's own words and can hold a URL: it is never logged or sent to a client as it is. */
export type GitResult = { ok: true; out: string } | { ok: false; code: number | null; timedOut?: true; stderr: string };

/** The port through which the chat host runs the `git` of the machine (docs/specs/session-worktrees.md, Decisions). */
export interface Git {
  /** Runs `git <args>` in `folder`: no shell, so every argument stays one argument. Never rejects. `timeoutMs` replaces the default limit. */
  run(folder: string, args: string[], options?: { timeoutMs?: number }): Promise<GitResult>;
}

const TIMEOUT_MS = 20_000;
const MAX_OUTPUT = 16 * 1024 * 1024;

/** The host's own environment plus `GIT_TERMINAL_PROMPT=0`, so a command that wants a password fails instead of waiting for one. */
export const realGit: Git = {
  run: (folder, args, options) =>
    new Promise((resolve) => {
      execFile('git', args, { cwd: folder, env: { ...process.env, GIT_TERMINAL_PROMPT: '0' }, timeout: options?.timeoutMs ?? TIMEOUT_MS, maxBuffer: MAX_OUTPUT, encoding: 'utf8' }, (error, stdout, stderr) => {
        if (error === null) return resolve({ ok: true, out: stdout });
        const { code, killed } = error as NodeJS.ErrnoException & { killed?: boolean };
        if (killed) return resolve({ ok: false, code: null, timedOut: true, stderr: 'git took too long' });
        resolve({ ok: false, code: typeof code === 'number' ? code : null, stderr: stderr || error.message });
      });
    }),
};
