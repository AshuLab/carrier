import { execFile } from 'node:child_process';
import { cliLoggedIn } from '../doctor/doctor.ts';
import { resolveBinary } from '../harnesses/common.ts';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatAgent } from './config.ts';

/** What one check comes to. `unknown`: the probe timed out, could not start or could not be read. */
export type ToolState = 'ready' | 'missing' | 'signedOut' | 'unknown';
export type Health = { git: ToolState; gh: ToolState; agents: { name: string; harness: string; state: ToolState }[] };

export const PROBE_LIMIT_MS = 5_000;
export const HEALTH_KEPT_MS = 30_000;
const SYSTEM_GIT = '/usr/bin/git';

/** The probes the health check runs. Each rejects when it cannot tell; only verdicts leave them, never the output. */
export interface HealthProbes {
  /** Whether the harness's CLI is logged in (the doctor's `cliLoggedIn`). */
  loggedIn(harness: ChatAgent['harness'], timeoutMs: number): Promise<boolean>;
  /** The exit code of `command args`, run without a shell. */
  exitCode(command: string, args: string[], timeoutMs: number): Promise<number>;
  /** The `git` the host's PATH finds; throws when there is none. */
  gitPath(): string;
}

export const realProbes: HealthProbes = {
  loggedIn: (harness, timeoutMs) => cliLoggedIn(harness, undefined, timeoutMs),
  exitCode: (command, args, timeoutMs) =>
    new Promise((resolve, reject) =>
      execFile(command, args, { timeout: timeoutMs }, (error) => {
        if (error === null) return resolve(0);
        const { code } = error as NodeJS.ErrnoException;
        // a number is the exit status; anything else is a process that did not start or was killed on time
        typeof code === 'number' ? resolve(code) : reject(error);
      }),
    ),
  gitPath: () => resolveBinary('git'),
};

/**
 * `git` is never run when it is the system's `/usr/bin/git`: on a Mac without the Command Line Tools that is a stub that opens the
 * installer dialog, so `xcode-select -p` asks instead. Any other `git` runs `--version`.
 */
export async function gitState({ binaryFound, probes }: { binaryFound: (command: string) => boolean; probes: HealthProbes }): Promise<ToolState> {
  if (binaryFound('git') === false) return 'missing';
  const path = probes.gitPath();
  const code = path === SYSTEM_GIT ? await probes.exitCode('xcode-select', ['-p'], PROBE_LIMIT_MS) : await probes.exitCode(path, ['--version'], PROBE_LIMIT_MS);
  return code === 0 ? 'ready' : 'missing';
}

/** The health of what the chat needs, kept for thirty seconds unless a refresh is asked; the probes of one request run in parallel. */
export function createHealth({ agents, clock, binaryFound, probes }: { agents: ChatAgent[]; clock: Clock; binaryFound: (command: string) => boolean; probes: HealthProbes }) {
  // A probe that fails, or does not answer in time, is `unknown`: the race holds even for a probe that ignores its own timeout.
  const limited = (probe: () => Promise<ToolState>) =>
    new Promise<ToolState>((resolve) => {
      const cancel = clock.after(PROBE_LIMIT_MS, async () => resolve('unknown'));
      probe().then(resolve, () => resolve('unknown')).finally(cancel);
    });
  const signedIn = async (ok: Promise<boolean>): Promise<ToolState> => ((await ok) ? 'ready' : 'signedOut');

  const gh = async () => (binaryFound('gh') ? signedIn(probes.exitCode('gh', ['auth', 'status', '--hostname', 'github.com'], PROBE_LIMIT_MS).then((code) => code === 0)) : 'missing');
  const agent = async ({ command, harness }: ChatAgent) => (binaryFound(command ?? harness) ? signedIn(probes.loggedIn(harness, PROBE_LIMIT_MS)) : 'missing');
  const probe = async (): Promise<Health> => {
    const [git, ghState, ...states] = await Promise.all([limited(() => gitState({ binaryFound, probes })), limited(gh), ...agents.map((chosen) => limited(() => agent(chosen)))]);
    return { git, gh: ghState, agents: agents.map(({ name, harness }, index) => ({ name, harness, state: states[index]! })) };
  };

  let kept: { at: number; health: Promise<Health> } | undefined;
  return ({ refresh = false }: { refresh?: boolean }) => {
    if (refresh || kept === undefined || clock.now() - kept.at >= HEALTH_KEPT_MS) kept = { at: clock.now(), health: probe() };
    return kept.health;
  };
}
