export interface AgentTask {
  executionId: string;
  repo: string; // "owner/name"
  epic: number;
  stage: 'ship' | 'review' | 'fix';
  profile: string; // GitHub profile of the effective config
  provider: 'claude' | 'codex';
  model: string;
  workspace: string; // checkout where the agent runs
  resultPath: string; // where the caller writes its JSON
  timeoutMs: number | null; // null = unlimited
  resumeSession?: string;
  context: {
    pr?: { number: number; headSha: string };
    round?: number;
    previousSummaries: string[];
    verifyStateFirst?: boolean;
    /** Fix turn: what the last review asked to change. */
    blockers?: { title: string; url?: string }[];
  };
}

export type AgentExit = 'ok' | 'failed' | 'timed_out' | 'stopped' | 'auth_failed' | 'session_unavailable';

export interface AgentRun {
  /** Called as soon as the session exists. */
  onSession(cb: (sessionId: string) => void): void;
  onOutput(cb: (stream: 'stdout' | 'stderr', chunk: string) => void): void;
  done: Promise<{ exit: AgentExit; sessionId?: string }>;
  stop(): Promise<void>;
}

export interface AgentRunner {
  run(task: AgentTask): AgentRun;
}
