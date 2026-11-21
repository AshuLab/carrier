import { execFile } from 'node:child_process';
import { withGit } from '../execution/git-binary.ts';

/** What running one git command comes to. `code` is git's exit status, null when git could not run, ran out of time (`timedOut`) or was stopped by its `signal` (`aborted`). `stderr` is git's own words and can hold a URL: it is never logged or sent to a client as it is. */
export type GitResult = { ok: true; out: string } | { ok: false; code: number | null; timedOut?: true; aborted?: true; stderr: string };

/** The port through which the chat host runs the `git` of the machine (docs/specs/session-worktrees.md, Decisions). */
export interface Git {
  /** The host `ssh` really reaches for `host`, which may be an alias of the person's ssh config (`ssh -G`); `host` itself when ssh cannot say. Never rejects. */
  sshHost(host: string): Promise<string>;
  /** Runs `git <args>` in `folder`: no shell, so every argument stays one argument. Never rejects. `timeoutMs` replaces the default limit; `env` is added to the host's (credentials travel here, never in `args`); `signal` kills git when it aborts. `onProgress` is called with each line git writes to stderr while it runs (git is told `--progress`, since it only reports on a terminal otherwise): the caller keeps what it may show, as stderr can hold a URL. */
  run(folder: string, args: string[], options?: { timeoutMs?: number; env?: NodeJS.ProcessEnv; signal?: AbortSignal; onProgress?: (line: string) => void }): Promise<GitResult>;
}

const TIMEOUT_MS = 20_000;
const MAX_OUTPUT = 16 * 1024 * 1024;

const sshHosts = new Map<string, Promise<string>>();

/** The host's own environment plus `GIT_TERMINAL_PROMPT=0`, so a command that wants a password fails instead of waiting for one. */
export const realGit: Git = {
  // `host` is checked by the caller to start with a word character, and `--` keeps it an argument and not an option.
  // ponytail: asked once per host for the life of the process, so a change in the ssh config needs a restart of the host.
  sshHost: (host) => {
    const known = sshHosts.get(host);
    if (known !== undefined) return known;
    const asked = new Promise<string>((resolve) => {
      execFile('ssh', ['-G', '--', host], { timeout: 5_000, encoding: 'utf8' }, (error, stdout) => resolve((error === null && /^hostname (\S+)$/m.exec(stdout)?.[1]) || host));
    });
    sshHosts.set(host, asked);
    return asked;
  },
  run: (folder, args, options) =>
    // never rejects: a git that cannot start (not installed, a folder that is gone) is a result with no exit code
    withGit(
      (binary) =>
        new Promise<GitResult>((resolve, reject) => {
          const { onProgress } = options ?? {};
          const child = execFile(binary, onProgress === undefined ? args : [args[0]!, '--progress', ...args.slice(1)], { cwd: folder, env: { ...process.env, GIT_TERMINAL_PROMPT: '0', ...options?.env }, signal: options?.signal, timeout: options?.timeoutMs ?? TIMEOUT_MS, maxBuffer: MAX_OUTPUT, encoding: 'utf8' }, (error, stdout, stderr) => {
            if (error === null) return resolve({ ok: true, out: stdout });
            if (options?.signal?.aborted === true) return resolve({ ok: false, code: null, aborted: true, stderr: 'git was stopped' });
            const { code, killed } = error as NodeJS.ErrnoException & { killed?: boolean };
            if (killed) return resolve({ ok: false, code: null, timedOut: true, stderr: 'git took too long' });
            if (code === 'ENOENT') return reject(error); // `withGit` decides whether the binary is gone
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
    ).catch((error: Error) => ({ ok: false, code: null, stderr: error.message })),
};
