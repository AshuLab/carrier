import type { ReviewThread } from '../orchestration/github.ts';
import type { PanelAgent } from '../status/types.ts';
import type { executionStates } from '../storage/executions.ts';
import type { AgentFailure } from '../execution/agent-runner.ts';

// What the new control requests answer in `data`. The macOS app has matching types (macos/Sources/CarrierCore/Replies.swift)
// and decodes the golden files macos/Tests/Fixtures/reply-*.json, written by replies.test.ts. Times are ms since epoch.

/** One row of an execution's output. A tool call is two immutable events joined by `callId`: the app merges them. */
export type ExecEvent = {
  /** The cursor: it only grows. */
  id: number;
  at: number;
  kind: 'say' | 'tool_start' | 'tool_end' | 'note' | 'error' | 'task';
  text?: string;
  callId?: string;
  /** The subagent that produced it, when there is one. */
  agentId?: string;
  tool?: string;
  arg?: string;
  /** The model's short sentence for the call, when it wrote one; the app can show it instead of the command. */
  description?: string;
  summary?: string;
  status?: 'ok' | 'err';
  durationMs?: number;
  /** The first and last lines of the result, capped. */
  output?: string[];
  diff?: { sign: '+' | '-' | ' '; text: string }[];
};

/** What it takes to continue a session in a terminal; validated by the app before it builds a command (ADR 0007). */
export type ResumeDescriptor = { harness: PanelAgent['harness']; sessionId: string; cwd: string; configDir?: string };

/** What the agent reported when its execution ended (the imported result), redacted and cut. */
export type SessionResult = {
  outcome: 'completed' | 'changes_requested' | 'needs_human';
  /** At most 1500 characters. */
  summary: string;
  /** Only a completed result has one; the evidence is at most 600 characters. */
  verification: { ci: 'passed' | 'absent'; evidence: string } | null;
  /** needs_human only, at most 600 characters. */
  reason: string | null;
};

/** Why an execution ended badly (glossary: Failure kind); the detail is redacted and at most 300 characters. */
export type SessionFailure = {
  kind: AgentFailure['kind'];
  detail: string;
  exitCode: number | null;
  signal: string | null;
  hostFreeMemMb: number | null;
  hostLoad: number | null;
};

export type SessionsReply = {
  /** Newest first. */
  sessions: {
    executionId: string;
    stage: 'ship' | 'review' | 'fix';
    role: 'author' | 'reviewer';
    round: number | null;
    agent: PanelAgent;
    status: (typeof executionStates)[number];
    startedAt: number;
    finishedAt: number | null;
    /** null while the session runs: the engine owns it. */
    resume: ResumeDescriptor | null;
    /** null while no result was imported (a running execution included). */
    result: SessionResult | null;
    /** null for an execution with no failure kind: one that ended ok, that Carrier stopped, or from before the kind existed. */
    failure: SessionFailure | null;
  }[];
};

export type EventsReply = {
  events: ExecEvent[];
  /** The `after` of the next request. */
  next: number;
  running: boolean;
  /** false when the harness has no parser yet: the app falls back to `tail`. */
  structured: boolean;
};

export type Blocker = {
  /** null in a result that predates stable ids. */
  id: string | null;
  title: string;
  url: string | null;
  mark: 'new' | 'carried' | 'fixed';
  /** The mark was guessed by matching titles, not stated by the reviewer. */
  approximate: boolean;
};

/** A non-blocking finding a `completed` review listed, shaped like a blocker without its marks. */
export type Observation = { id: string | null; title: string; url: string | null };

export type EpicReply = {
  stages: { stage: 'queued' | 'ship' | 'review' | 'fix' | 'ready'; startedAt: number; endedAt: number | null }[];
  rounds: {
    round: number;
    reviewer: PanelAgent;
    verdict: 'approved' | 'changes_requested' | 'limit_reached';
    blockers: Blocker[];
    /** In the reviewer's order; empty when the review listed none or predates the field. */
    observations: Observation[];
    reviewMs: number | null;
    fixMs: number | null;
    /** The head the review looked at, and the head the fix left. */
    reviewedSha: string | null;
    fixedSha: string | null;
    commits: { sha: string; subject: string }[];
  }[];
  /** A cache of GitHub, never read to decide anything (ADR 0008). */
  slices: {
    number: number;
    title: string;
    state: 'closed' | 'skipped' | 'in_progress' | 'waiting' | 'ready';
    /** The numbers of the slices that still block it. */
    blockedBy: number[];
    /** The slice's own pull request, found by its branch name. */
    prNumber: number | null;
    prState: 'open' | 'draft' | 'merged' | 'closed' | null;
    /** When that pull request was merged; `closedAt` is when the issue closed. */
    prMergedAt: number | null;
    closedAt: number | null;
    readAt: number;
    /** Only on a slice in progress whose agent the author stream names (hints, docs/research/claude-subagent-attribution.md): null when it gave none. */
    lane?: number | null;
    /** The agent's latest tool call, cut to 80 characters; null when it is not building the slice now. */
    activity?: string | null;
  }[];
  /** Only the first hundred slices are read: true when the epic has more than the list holds. */
  slicesTruncated: boolean;
  /** A cache of GitHub, in GitHub's order (ADR 0008): the final pull request's review threads, empty while none were read. */
  threads: ReviewThread[];
  /** Only the first hundred threads are read: true when the pull request has more than the list holds. */
  threadsTruncated: boolean;
  /** `reviewer` is the detached checkout the reviewer works in. */
  worktrees: { kind: 'epic' | 'reviewer' | 'lane'; lane: number | null; path: string }[];
  branch: string | null;
  /** null during ship, before the pull request exists. */
  pr: {
    number: number;
    url: string;
    draft: boolean;
    mergeState: string;
    reviewDecision: string | null;
    /** null when there are no checks, which is not the same as pending. */
    checks: { passing: number; failing: number; pending: number } | null;
  } | null;
};

export type FilesReply = {
  sections: {
    id: string;
    kind: 'session' | 'lane' | 'merged';
    title: string;
    added: number;
    removed: number;
    files: {
      path: string;
      added: number;
      removed: number;
      /** The ids of the other sections that touch this file. */
      alsoIn: string[];
    }[];
  }[];
  /** The epic branch against the default branch (what the pull request will show); null when git cannot say. */
  total: { files: number; added: number; removed: number } | null;
  /** Files were left out to keep the reply small; the numbers of a section still count every file. */
  truncated: boolean;
};
