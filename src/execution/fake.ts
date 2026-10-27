import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { AgentDone, AgentExit, AgentFailure, AgentRun, AgentRunner, AgentTask } from './agent-runner.ts';
import type { AgentEvent } from './events.ts';
import type { Workspaces } from './workspaces.ts';

export type Behavior = {
  sessionId?: string;
  output?: ['stdout' | 'stderr', string][];
  /** Batches of events, one per output chunk, delivered after the output. */
  events?: AgentEvent[][];
  /** Written to resultPath: an object is stringified, a string is written as is (e.g. broken JSON). */
  write?: unknown;
  /** Defaults to 'ok'. 'hang' never ends on its own, only `stop()` does. */
  exit?: AgentExit | 'hang';
  /** What a 'failed' exit reports; defaults to a crash with exit code 1, and `failure: undefined` set on purpose reports none. */
  failure?: AgentFailure;
  /** The run ends with `exit` only once this settles, to let other runs start first. */
  when?: Promise<unknown>;
};

const crash: AgentFailure = { kind: 'crashed', detail: 'exit code 1', exitCode: 1, signal: null, hostFreeMemMb: 8000, hostLoad: 1.5 };

export class FakeAgentRunner implements AgentRunner {
  tasks: AgentTask[] = [];
  stopped: string[] = [];
  /** Executions alive: the running ones, plus whatever a test adds to play a previous process's orphans. */
  alive = new Set<string>();
  /** What each run does; by default it hangs, so a test sees the execution while it is running. */
  behavior: (task: AgentTask) => Behavior = () => ({ exit: 'hang' });
  private eventSinks = new Map<string, ((events: AgentEvent[]) => void)[]>();

  /** Delivers a batch of events from a run later on, when the test decides. */
  emit(executionId: string, events: AgentEvent[]) {
    for (const cb of this.eventSinks.get(executionId) ?? []) cb(events);
  }

  run(task: AgentTask): AgentRun {
    this.tasks.push(task);
    this.alive.add(task.executionId);
    const behavior = this.behavior(task);
    const { sessionId, output = [], events = [], write, exit = 'ok', when } = behavior;
    const failure = 'failure' in behavior ? behavior.failure : exit === 'failed' ? crash : undefined;
    const sessions: ((id: string) => void)[] = [];
    const outputs: ((stream: 'stdout' | 'stderr', chunk: string) => void)[] = [];
    const eventSinks: ((events: AgentEvent[]) => void)[] = [];
    this.eventSinks.set(task.executionId, eventSinks);
    let resolveDone!: (result: AgentDone) => void;
    const finish = (result: AgentDone) => {
      this.alive.delete(task.executionId);
      resolveDone(result);
    };
    const done = new Promise<AgentDone>((resolve) => (resolveDone = resolve));
    // Runs after the caller registered its callbacks.
    queueMicrotask(() => {
      if (sessionId) for (const cb of sessions) cb(sessionId);
      for (const [stream, chunk] of output) for (const cb of outputs) cb(stream, chunk);
      for (const batch of events) for (const cb of eventSinks) cb(batch);
      if (write !== undefined) {
        mkdirSync(dirname(task.resultPath), { recursive: true });
        writeFileSync(task.resultPath, typeof write === 'string' ? write : JSON.stringify(write));
      }
      if (when && exit !== 'hang') void when.then(() => finish({ exit, sessionId, failure }));
      else if (exit !== 'hang') finish({ exit, sessionId, failure });
    });
    return {
      onSession: (cb) => void sessions.push(cb),
      onOutput: (cb) => void outputs.push(cb),
      onEvent: (cb) => void eventSinks.push(cb),
      done,
      stop: async () => {
        this.stopped.push(task.executionId);
        finish({ exit: 'stopped', sessionId });
      },
    };
  }

  async listActive() {
    return [...this.alive];
  }

  async stop(executionId: string) {
    this.stopped.push(executionId);
    this.alive.delete(executionId);
  }
}

export class FakeWorkspaces implements Workspaces {
  async prepareAuthor(repo: string, epic: number) {
    return `/work/${repo}/${epic}/author`;
  }

  async prepareReviewer(repo: string, epic: number, pr: number) {
    return `/work/${repo}/${epic}/reviewer-${pr}`;
  }

  async findWorktree(repo: string, branch: string): Promise<string | null> {
    return `/work/${repo}/worktrees/${branch}`;
  }
}
