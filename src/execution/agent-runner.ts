import type { AccountRuntime } from '../config/providers.ts';
import type { ResolvedSkills } from '../config/skills.ts';
import type { HarnessName } from '../harnesses/names.ts';
import type { ExecutionUsage, Slot, failureKinds } from '../storage/executions.ts';
import type { AgentEvent } from './events.ts';

export interface AgentTask extends AccountRuntime {
  executionId: string;
  repo: string; // "owner/name"
  epic: number;
  stage: 'ship' | 'review' | 'fix' | 'lead';
  reviewer?: Slot; // a review's slot (an extra reviewer's key); absent for ship and fix
  reviewerName?: string; // an extra reviewer's name, which the prompt calls it by; absent for the others
  profile: string; // GitHub profile of the effective config
  harness: HarnessName;
  model: string;
  provider?: 'lmstudio' | 'ollama'; // `model` is served by that local server
  option?: string; // name of the agent option the role ran on; absent on an epic saved before options existed
  configDir?: string; // the option's config folder (CLAUDE_CONFIG_DIR, CODEX_HOME); absent: the process environment's own
  persona?: { name?: string; prompt?: string }; // of the role, told in the prompt
  effort?: 'low' | 'medium' | 'high' | 'xhigh' | 'max'; // of the role: how hard the model thinks; absent, the CLI's own
  sharedIdentity?: boolean; // the epic's author and reviewer use one GitHub profile: the prompt asks for the signature
  skills?: ResolvedSkills; // the skills the stage invokes, as the epic was saved with; absent: Solve's defaults
  workspace: string; // checkout where the agent runs
  resultPath: string; // where the caller writes its JSON
  timeoutMs: number | null; // null = unlimited
  idleMs?: number; // a process that writes nothing for this long is killed (a technical failure); absent: no watchdog
  resumeSession?: string;
  context: {
    pr?: { number: number; headSha: string };
    round?: number;
    previousSummaries: string[];
    verifyStateFirst?: boolean;
    /** Fix turn: what the last review asked to change, with the reviewer of each when the epic has several. Review turn after the first: the reviewer's own blockers of the round before, to reuse their ids. */
    blockers?: { id?: string; title: string; url?: string; reviewer?: Slot }[];
    /** Fix turn after reviews that completed with non-blocking findings: the threads to answer and leave open, with the reviewer of each when the epic has several. Takes the place of `blockers`. */
    observations?: { id?: string; title: string; url?: string; reviewer?: Slot }[];
    /** Review turn of an epic with several reviewers: other reviewers publish on the same pull request. */
    severalReviewers?: true;
    /** Lead turn: what each reviewer that gave a verdict on the head they agreed on said in its summary. */
    reviewerSummaries?: { reviewer: Slot; summary: string }[];
  };
}

export type AgentExit = 'ok' | 'failed' | 'timed_out' | 'stopped' | 'auth_failed' | 'session_unavailable';

export type AgentFailure = {
  kind: (typeof failureKinds)[number];
  detail: string; // redacted, one line, at most 300 characters
  exitCode: number | null;
  signal: string | null;
  hostFreeMemMb: number | null; // only for killed, crashed and unknown
  hostLoad: number | null; // one-minute load average, same cases
};

export type AgentDone = { exit: AgentExit; sessionId?: string; failure?: AgentFailure; usage?: ExecutionUsage };

export interface AgentRun {
  /** Called as soon as the session exists. */
  onSession(cb: (sessionId: string) => void): void;
  onOutput(cb: (stream: 'stdout' | 'stderr', chunk: string) => void): void;
  /** The events of each stdout chunk, as one batch, for harnesses that have a parser (ADR 0006). */
  onEvent(cb: (events: AgentEvent[]) => void): void;
  done: Promise<AgentDone>;
  stop(): Promise<void>;
}

export interface AgentRunner {
  run(task: AgentTask): AgentRun;
  /** Ids of the executions alive right now, including those a previous process left running. */
  listActive(): Promise<string[]>;
  /** Stops a live execution by id; used on orphans no AgentRun handle exists for. */
  stop(executionId: string): Promise<void>;
}
