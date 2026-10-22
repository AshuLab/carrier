import type { needsHumanKinds } from '../storage/schema.ts';

// What the panel shows, whatever draws it: read from SQLite by snapshot.ts, drawn by dashboard.ts (a terminal) or plain.ts (a pipe).
export type PanelEpic = {
  repo: string;
  issue: number;
  status: 'running' | 'needs_human';
  stage: 'ship' | 'review' | 'fix' | null;
  /** Review round, null until the final PR is validated. */
  round: number | null;
  maxReviews: number;
  blockers: number;
  /** ms since epoch, when the epic entered its current stage. */
  stageSince: number;
  /** ms since epoch of the agent's last output; a different fact from the stage. */
  lastActivityAt: number | null;
  issueUrl: string;
  prUrl: string | null;
  lastError: string | null;
  needsHumanReason: string | null;
  /** Slices closed out of the total as GitHub reports them; null until the first read or when GitHub sends none. */
  slices: { done: number; total: number } | null;
  /** The latest execution of the epic: where its agent's output is. */
  executionId: string | null;
};

export type PanelSnapshot = {
  now: number;
  slots: { busy: number; total: number };
  /** Queued epics, oldest first. */
  queue: { repo: string; issue: number }[];
  epics: PanelEpic[];
  /** When this carrier process started (ms since epoch). */
  startedAt: number;
  /** How many repos are watched. */
  repos: number;
  /** When the next poll is due; null before the first is scheduled. */
  nextCheckAt: number | null;
  /** Why GitHub work is stalled right now (GitHub down, a profile rejected), null when all is well. */
  problem: string | null;
  /** Intake is paused by the person at the terminal. */
  paused: boolean;
  /** The epics that ended ready for test, most recent first. */
  done: { repo: string; issue: number; title: string | null; labels: string[]; prNumber: number | null; finishedAt: number | null; executionId: string | null }[];
};

// What the control socket serves: the panel's snapshot plus what the macOS app draws. Everything here is additive (protocol 1),
// and the terminal panel keeps reading `PanelSnapshot`, of which this is a superset.
export type PanelAgent = { harness: 'claude' | 'codex' | 'agy'; model: string; provider: string | null };
export type PanelAgents = { author: PanelAgent; reviewer: PanelAgent };
export type NeedsHumanKind = (typeof needsHumanKinds)[number];

export type EpicAdditions = {
  /** The issue's title; null until the engine reads it. */
  title: string | null;
  labels: string[];
  /** ms since epoch. */
  queuedAt: number;
  startedAt: number | null;
  finishedAt: number | null;
  branch: string | null;
  workspace: string | null;
  needsHumanKind: NeedsHumanKind | null;
  /** Titles of the open blockers, at most ten of two hundred characters. */
  blockerTitles: string[];
  /** The agents frozen when the epic started; null while it is queued. */
  agents: PanelAgents | null;
};

export type PanelSession = {
  executionId: string;
  repo: string;
  issue: number;
  stage: 'ship' | 'review' | 'fix';
  round: number | null;
  harness: PanelAgent['harness'];
  model: string;
  startedAt: number;
  /** The newest event of the execution; null until events are recorded. */
  last: { kind: string; text: string; at: number } | null;
};

export type ControlSnapshot = Omit<PanelSnapshot, 'queue' | 'epics'> & {
  queue: (PanelSnapshot['queue'][number] & { title: string | null; queuedAt: number })[];
  epics: (PanelEpic & EpicAdditions)[];
  engine: {
    version: string;
    pollIntervalMs: number;
    maxConcurrentEpics: number;
    /** null until the engine reads GitHub's limit. */
    rateLimit: { remaining: number; limit: number; resetAt: number; profile: 'orchestrator' } | null;
  };
  /** One row per watched repository; lastCheckedAt is null (and ok true) until its first poll. */
  watched: { repo: string; lastCheckedAt: number | null; ok: boolean; error: string | null; agents: PanelAgents }[];
  /** The running executions, at most one per running epic. */
  sessions: PanelSession[];
};
