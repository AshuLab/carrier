import type { HarnessName } from '../harnesses/names.ts';
import type { AgentEvent } from './events.ts';

export interface AgentTask {
  executionId: string;
  repo: string; // "owner/name"
  epic: number;
  stage: 'ship' | 'review' | 'fix';
  profile: string; // GitHub profile of the effective config
  harness: HarnessName;
  model: string;
  provider?: 'lmstudio' | 'ollama'; // `model` is served by that local server
  persona?: { name?: string; prompt?: string }; // of the role, told in the prompt
  sharedIdentity?: boolean; // the epic's author and reviewer use one GitHub profile: the prompt asks for the signature
  workspace: string; // checkout where the agent runs
  resultPath: string; // where the caller writes its JSON
  timeoutMs: number | null; // null = unlimited
  resumeSession?: string;
  context: {
    pr?: { number: number; headSha: string };
    round?: number;
    previousSummaries: string[];
    verifyStateFirst?: boolean;
    /** Fix turn: what the last review asked to change. Review turn after the first: the previous round's blockers, to reuse their ids. */
    blockers?: { id?: string; title: string; url?: string }[];
    /** Fix turn after a review that completed with non-blocking findings: the threads to answer and leave open. Takes the place of `blockers`. */
    observations?: { id?: string; title: string; url?: string }[];
  };
}

export type AgentExit = 'ok' | 'failed' | 'timed_out' | 'stopped' | 'auth_failed' | 'session_unavailable';

export interface AgentRun {
  /** Called as soon as the session exists. */
  onSession(cb: (sessionId: string) => void): void;
  onOutput(cb: (stream: 'stdout' | 'stderr', chunk: string) => void): void;
  /** The events of each stdout chunk, as one batch, for harnesses that have a parser (ADR 0006). */
  onEvent(cb: (events: AgentEvent[]) => void): void;
  done: Promise<{ exit: AgentExit; sessionId?: string }>;
  stop(): Promise<void>;
}

export interface AgentRunner {
  run(task: AgentTask): AgentRun;
  /** Ids of the executions alive right now, including those a previous process left running. */
  listActive(): Promise<string[]>;
  /** Stops a live execution by id; used on orphans no AgentRun handle exists for. */
  stop(executionId: string): Promise<void>;
}
