import { execFile, spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { promisify } from 'node:util';
import type { AgentExit, AgentRun, AgentRunner, AgentTask } from '../execution/agent-runner.ts';
import { claudeAdapter } from './claude.ts';
import { resolveBinary, type AgentCommand, type ProviderAdapter } from './common.ts';

const exec = promisify(execFile);

export interface HostRunnerOptions {
  /** One adapter per provider; Claude's is built in, Codex's is added by its slice. */
  adapters?: Partial<Record<AgentTask['provider'], ProviderAdapter>>;
  /** Overrides the real binary found on PATH, per provider. */
  binaries?: Partial<Record<AgentTask['provider'], string>>;
  /** Token (and bot commit identity) of the task's GitHub profile, minted for this execution only. */
  credentials: (task: AgentTask) => Promise<{ githubToken: string; gitIdentity?: { name: string; email: string } }>;
  /** Time a stopped agent gets to exit after SIGTERM before SIGKILL. */
  graceMs?: number;
}

const markerRe = /carrier-exec-([\w-]+)/;

/** Pids of live processes carrying an execution marker, found in `ps` so another carrier process can see them. */
async function listMarked(): Promise<Map<string, number>> {
  const { stdout } = await exec('ps', ['-axo', 'pid=,command='], { maxBuffer: 64 * 1024 * 1024 });
  const found = new Map<string, number>();
  for (const line of stdout.split('\n')) {
    const match = markerRe.exec(line);
    if (match) found.set(match[1]!, Number(line.trim().split(/\s+/)[0]));
  }
  return found;
}

// The agent leads its own process group (detached), so the signal reaches the whole group.
function signal(pid: number, sig: NodeJS.Signals) {
  try {
    process.kill(-pid, sig);
  } catch {
    try {
      process.kill(pid, sig);
    } catch {
      // already gone
    }
  }
}

const alive = (pid: number) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

// SIGTERM first (Claude cleans its children up on it), SIGKILL if it has not exited after the grace period.
async function terminate(pid: number, graceMs: number) {
  signal(pid, 'SIGTERM');
  const deadline = Date.now() + graceMs;
  while (alive(pid) && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
  if (alive(pid)) signal(pid, 'SIGKILL');
}

export class HostAgentRunner implements AgentRunner {
  private runs = new Map<string, AgentRun>();
  private options: HostRunnerOptions;

  constructor(options: HostRunnerOptions) {
    this.options = options;
  }

  run(task: AgentTask): AgentRun {
    const sessions: ((id: string) => void)[] = [];
    const outputs: ((stream: 'stdout' | 'stderr', chunk: string) => void)[] = [];
    let sessionId: string | undefined;
    let reason: 'stopped' | 'timed_out' | undefined;
    let pid: number | undefined;
    const emit = (stream: 'stdout' | 'stderr', chunk: string) => outputs.forEach((cb) => cb(stream, chunk));
    const graceMs = this.options.graceMs ?? 5000;

    let finished = false;
    // Before the spawn there is nothing to kill: start() checks `reason` instead.
    const kill = async () => {
      if (pid !== undefined && !finished) await terminate(pid, graceMs);
    };

    const start = async (): Promise<{ exit: AgentExit; sessionId?: string }> => {
      const adapter = this.options.adapters?.[task.provider] ?? (task.provider === 'claude' ? claudeAdapter : undefined);
      if (!adapter) {
        emit('stderr', `carrier: no runner adapter for provider "${task.provider}"\n`);
        return { exit: 'failed' };
      }
      let credentials;
      try {
        credentials = await this.options.credentials(task);
      } catch (e) {
        // Without a token the run cannot start; retrying does not help, so it is an auth failure, not a technical one.
        emit('stderr', `carrier: no GitHub token for profile "${task.profile}": ${e instanceof Error ? e.message : String(e)}\n`);
        return { exit: 'auth_failed' };
      }
      if (reason) return { exit: reason };
      let command: AgentCommand;
      try {
        const binary = this.options.binaries?.[task.provider] ?? resolveBinary(task.provider);
        command = adapter.command(task, { binary, baseEnv: process.env, ...credentials });
        mkdirSync(dirname(task.resultPath), { recursive: true });
      } catch (e) {
        emit('stderr', `carrier: cannot build the ${task.provider} command: ${e instanceof Error ? e.message : String(e)}\n`);
        return { exit: 'failed' };
      }
      const child = spawn(command.bin, command.args, { cwd: command.cwd, env: command.env, stdio: ['ignore', 'pipe', 'pipe'], detached: true });
      pid = child.pid;

      let authFailed = false;
      let sessionLost = false;
      let pending = '';
      const readLine = (line: string) => {
        const signalOfLine = adapter.parseLine(line);
        if (signalOfLine?.session && !sessionId) {
          sessionId = signalOfLine.session;
          sessions.forEach((cb) => cb(sessionId!));
        }
        authFailed ||= signalOfLine?.authFailed === true;
        sessionLost ||= signalOfLine?.sessionUnavailable === true;
      };
      child.stdout.setEncoding('utf8').on('data', (chunk: string) => {
        emit('stdout', chunk);
        const lines = (pending + chunk).split('\n');
        pending = lines.pop()!;
        lines.forEach(readLine);
      });
      child.stderr.setEncoding('utf8').on('data', (chunk: string) => emit('stderr', chunk));

      const timer = task.timeoutMs === null ? undefined : setTimeout(() => {
            reason ??= 'timed_out';
            void kill();
          }, task.timeoutMs);
      const code = await new Promise<number | null>((resolve) => {
        child.on('error', (e) => {
          emit('stderr', `carrier: cannot start ${command.bin}: ${e.message}\n`);
          resolve(-1);
        });
        child.on('close', resolve);
      });
      finished = true;
      clearTimeout(timer);
      if (pending) readLine(pending);

      const exit: AgentExit = reason ?? (authFailed ? 'auth_failed' : sessionLost ? 'session_unavailable' : code === 0 ? 'ok' : 'failed');
      return { exit, sessionId };
    };

    const done = start().finally(() => this.runs.delete(task.executionId));
    const handle: AgentRun = {
      onSession: (cb) => {
        sessions.push(cb);
        if (sessionId) cb(sessionId);
      },
      onOutput: (cb) => void outputs.push(cb),
      done,
      stop: async () => {
        reason ??= 'stopped';
        await kill();
        await done;
      },
    };
    this.runs.set(task.executionId, handle);
    return handle;
  }

  async listActive() {
    return [...new Set([...this.runs.keys(), ...(await listMarked()).keys()])];
  }

  async stop(executionId: string) {
    const handle = this.runs.get(executionId);
    if (handle) return handle.stop();
    // An orphan from a previous carrier process: no handle, only its pid.
    const pid = (await listMarked()).get(executionId);
    if (pid === undefined) return;
    await terminate(pid, this.options.graceMs ?? 5000);
  }
}
