import { execFile, spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { freemem, loadavg } from 'node:os';
import { promisify } from 'node:util';
import type { AgentDone, AgentFailure, AgentRun, AgentRunner, AgentTask } from '../execution/agent-runner.ts';
import { failureDetail } from '../execution/failure.ts';
import { createEventState, type AgentEvent } from '../execution/events.ts';
import { claudeAdapter } from './claude.ts';
import { agyAdapter } from './agy.ts';
import { codexAdapter } from './codex.ts';
import { resolveBinary, type AgentCommand, type HarnessAdapter, type LineSignal } from './common.ts';

const exec = promisify(execFile);

export interface HostRunnerOptions {
  /** Overrides the built-in adapter of a harness (tests). */
  adapters?: Partial<Record<AgentTask['harness'], HarnessAdapter>>;
  /** Overrides the real binary found on PATH, per harness. */
  binaries?: Partial<Record<AgentTask['harness'], string>>;
  /** Token (and bot commit identity) of the task's GitHub profile, minted for this execution only. */
  credentials: (task: AgentTask) => Promise<{ githubToken: string; gitIdentity?: { name: string; email: string }; forgeAgent?: string }>;
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

const spawnError = (message: string): AgentDone => ({
  exit: 'failed',
  failure: { kind: 'spawn_error', detail: failureDetail(message), exitCode: null, signal: null, hostFreeMemMb: null, hostLoad: null },
});

// A failed process: what the exit code and the signal say, and the host at that moment. What the adapter read from the
// agent's own result names the cause and wins over the symptom; the exit code and the signal are recorded either way.
function processFailure(code: number | null, signal: NodeJS.Signals | null, adapterFailure: LineSignal['failure']): AgentFailure {
  if (adapterFailure) return { kind: adapterFailure.kind, detail: failureDetail(adapterFailure.detail), exitCode: code, signal, hostFreeMemMb: null, hostLoad: null };
  const kind = signal ? 'killed' : code ? 'crashed' : 'unknown';
  const detail = signal ?? (code ? `exit code ${code}` : 'the process ended without an exit code');
  return { kind, detail, exitCode: code, signal, hostFreeMemMb: Math.round(freemem() / 1048576), hostLoad: loadavg()[0]! };
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
    const eventSinks: ((events: AgentEvent[]) => void)[] = [];
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

    const start = async (): Promise<AgentDone> => {
      const adapter = this.options.adapters?.[task.harness] ?? { claude: claudeAdapter, codex: codexAdapter, agy: agyAdapter }[task.harness];
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
        const binary = this.options.binaries?.[task.harness] ?? resolveBinary(task.harness);
        command = adapter.command(task, { binary, baseEnv: process.env, ...credentials });
        mkdirSync(dirname(task.resultPath), { recursive: true });
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        emit('stderr', `carrier: cannot build the ${task.harness} command: ${message}\n`);
        return spawnError(`cannot build the ${task.harness} command: ${message}`);
      }
      const child = spawn(command.bin, command.args, { cwd: command.cwd, env: command.env, stdio: ['ignore', 'pipe', 'pipe'], detached: true });
      pid = child.pid;

      let authFailed = false;
      let sessionLost = false;
      let adapterFailure: LineSignal['failure'];
      const eventState = createEventState();
      // The events of the lines of one chunk, to be reported together; only stdout carries the stream.
      let batch: AgentEvent[] = [];
      const readLine = (line: string, stream: 'stdout' | 'stderr') => {
        if (stream === 'stdout') batch.push(...(adapter.parseEvents?.(line, eventState) ?? []));
        const signalOfLine = adapter.parseLine(line);
        if (signalOfLine?.session && !sessionId) {
          sessionId = signalOfLine.session;
          sessions.forEach((cb) => cb(sessionId!));
        }
        authFailed ||= signalOfLine?.authFailed === true;
        sessionLost ||= signalOfLine?.sessionUnavailable === true;
        adapterFailure ??= signalOfLine?.failure;
      };
      const reportEvents = () => {
        if (batch.length > 0) eventSinks.forEach((cb) => cb(batch));
      };
      // Some errors (Codex's lost session) only show on stderr, so both streams go through the adapter.
      const lineReader = (stream: 'stdout' | 'stderr') => {
        let pending = '';
        return {
          push: (chunk: string) => {
            emit(stream, chunk);
            const lines = (pending + chunk).split('\n');
            pending = lines.pop()!;
            batch = [];
            lines.forEach((line) => readLine(line, stream));
            reportEvents();
          },
          flush: () => {
            if (!pending) return;
            batch = [];
            readLine(pending, stream);
            reportEvents();
          },
        };
      };
      const out = lineReader('stdout');
      const err = lineReader('stderr');
      child.stdout.setEncoding('utf8').on('data', out.push);
      child.stderr.setEncoding('utf8').on('data', err.push);

      const timer = task.timeoutMs === null ? undefined : setTimeout(() => {
            reason ??= 'timed_out';
            void kill();
          }, task.timeoutMs);
      let startError: string | undefined;
      const [code, killedBy] = await new Promise<[number | null, NodeJS.Signals | null]>((resolve) => {
        child.on('error', (e) => {
          emit('stderr', `carrier: cannot start ${command.bin}: ${e.message}\n`);
          startError = e.message;
          resolve([null, null]);
        });
        child.on('close', (c, sig) => resolve([c, sig]));
      });
      finished = true;
      clearTimeout(timer);
      out.flush();
      err.flush();

      if (reason) return { exit: reason, sessionId };
      if (authFailed) return { exit: 'auth_failed', sessionId };
      if (sessionLost) return { exit: 'session_unavailable', sessionId };
      if (startError !== undefined) return { ...spawnError(`cannot start ${command.bin}: ${startError}`), sessionId };
      if (code === 0) return { exit: 'ok', sessionId };
      return { exit: 'failed', sessionId, failure: processFailure(code, killedBy, adapterFailure) };
    };

    const done = start().finally(() => this.runs.delete(task.executionId));
    const handle: AgentRun = {
      onSession: (cb) => {
        sessions.push(cb);
        if (sessionId) cb(sessionId);
      },
      onOutput: (cb) => void outputs.push(cb),
      onEvent: (cb) => void eventSinks.push(cb),
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
