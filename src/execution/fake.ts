import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import type { AgentExit, AgentRun, AgentRunner, AgentTask } from './agent-runner.ts';
import type { Workspaces } from './workspaces.ts';

export type Behavior = {
  sessionId?: string;
  output?: ['stdout' | 'stderr', string][];
  /** Written to resultPath: an object is stringified, a string is written as is (e.g. broken JSON). */
  write?: unknown;
  /** Defaults to 'ok'. 'hang' never ends on its own, only `stop()` does. */
  exit?: AgentExit | 'hang';
};

export class FakeAgentRunner implements AgentRunner {
  tasks: AgentTask[] = [];
  stopped: string[] = [];
  /** What each run does; by default it hangs, so a test sees the execution while it is running. */
  behavior: (task: AgentTask) => Behavior = () => ({ exit: 'hang' });

  run(task: AgentTask): AgentRun {
    this.tasks.push(task);
    const { sessionId, output = [], write, exit = 'ok' } = this.behavior(task);
    const sessions: ((id: string) => void)[] = [];
    const outputs: ((stream: 'stdout' | 'stderr', chunk: string) => void)[] = [];
    let finish!: (result: { exit: AgentExit; sessionId?: string }) => void;
    const done = new Promise<{ exit: AgentExit; sessionId?: string }>((resolve) => (finish = resolve));
    // Runs after the caller registered its callbacks.
    queueMicrotask(() => {
      if (sessionId) for (const cb of sessions) cb(sessionId);
      for (const [stream, chunk] of output) for (const cb of outputs) cb(stream, chunk);
      if (write !== undefined) {
        mkdirSync(dirname(task.resultPath), { recursive: true });
        writeFileSync(task.resultPath, typeof write === 'string' ? write : JSON.stringify(write));
      }
      if (exit !== 'hang') finish({ exit, sessionId });
    });
    return {
      onSession: (cb) => void sessions.push(cb),
      onOutput: (cb) => void outputs.push(cb),
      done,
      stop: async () => {
        this.stopped.push(task.executionId);
        finish({ exit: 'stopped', sessionId });
      },
    };
  }
}

export class FakeWorkspaces implements Workspaces {
  async prepareAuthor(repo: string, epic: number) {
    return `/work/${repo}/${epic}/author`;
  }

  async prepareReviewer(repo: string, epic: number, pr: number) {
    return `/work/${repo}/${epic}/reviewer-${pr}`;
  }
}
