import type { PanelAgent } from '../status/types.ts';
import type { executionStates } from '../storage/executions.ts';

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
  summary?: string;
  status?: 'ok' | 'err';
  durationMs?: number;
  /** The first and last lines of the result, capped. */
  output?: string[];
  diff?: { sign: '+' | '-' | ' '; text: string }[];
};

/** What it takes to continue a session in a terminal; validated by the app before it builds a command (ADR 0007). */
export type ResumeDescriptor = { harness: PanelAgent['harness']; sessionId: string; cwd: string; configDir?: string };

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

export type EpicReply = {
  stages: { stage: 'queued' | 'ship' | 'review' | 'fix' | 'ready'; startedAt: number; endedAt: number | null }[];
  rounds: {
    round: number;
    reviewer: PanelAgent;
    verdict: 'approved' | 'changes_requested' | 'limit_reached';
    blockers: Blocker[];
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
    prNumber: number | null;
    closedAt: number | null;
    readAt: number;
  }[];
  /** Only the first hundred slices are read: true when the epic has more than the list holds. */
  slicesTruncated: boolean;
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
