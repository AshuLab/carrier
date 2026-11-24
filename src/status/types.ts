import type { Labels } from '../orchestration/github.ts';
import type { TextParams } from '../orchestration/text-params.ts';
import type { Slot } from '../storage/executions.ts';
import type { needsHumanKinds, unansweredReasons } from '../storage/schema.ts';

/** The observations an epic went to ready for test with because no pass would answer them (glossary: Unanswered observations). */
export type UnansweredObservations = { count: number; reason: (typeof unansweredReasons)[number] };

/**
 * The agent options of an epic: the accounts it can restart on, the option each role runs on.
 * `extraReviewers` (the option of each, `reviewer-2` first) and `lead` are there only when the epic has them, and `failed`, the role of the execution that stopped a stopped epic with either.
 */
export type EpicOptions = { names: string[]; author: string | null; reviewer: string | null; extraReviewers?: (string | null)[]; lead?: string | null; failed?: 'author' | Slot };

/** How the latest decided round of an epic with several reviewers came out: how many gave a verdict out of how many were configured, and why each other gave none (cut and redacted). */
export type PanelReviewers = { given: number; of: number; none: { slot: Slot; why: string }[] };

// What the panel shows, whatever draws it: read from SQLite by snapshot.ts, drawn by dashboard.ts (a terminal) or plain.ts (a pipe).
export type PanelEpic = {
  repo: string;
  issue: number;
  status: 'running' | 'needs_human';
  /** The issue's title, when the snapshot carries it (the control snapshot does; null until the engine reads it). */
  title?: string | null;
  stage: 'ship' | 'review' | 'fix' | null;
  /** The epic is in the stage `lead`, which `stage` reports as `review` because the app's stage is a strict enum; absent otherwise. */
  lead?: true;
  /** Review round, null until the final PR is validated. */
  round: number | null;
  maxReviews: number;
  blockers: number;
  /** Titles of the open blockers (the control snapshot carries them), shown under a review or fix card. */
  blockerTitles?: string[];
  /** ms since epoch, when the epic entered its current stage. */
  stageSince: number;
  /** ms since epoch of the agent's last output; a different fact from the stage. */
  lastActivityAt: number | null;
  issueUrl: string;
  prUrl: string | null;
  lastError: string | null;
  needsHumanReason: string | null;
  /** The text code of the reason and its parameters; absent when the epic has none, and on a reason stored before the codes, which has its words only. */
  needsHumanCode?: string;
  needsHumanParams?: TextParams;
  /** Slices closed out of the total as GitHub reports them; null until the first read or when GitHub sends none. */
  slices: { done: number; total: number } | null;
  /** The latest execution of the epic: where its agent's output is. */
  executionId: string | null;
  /** Absent from an epic reserved before options existed. */
  options?: EpicOptions;
  /** Only an epic with several reviewers that has a decided round has it: the latest one's count. */
  reviewers?: PanelReviewers;
  /** ms since epoch: when an epic stopped on its quota resumes by itself; absent when it does not. */
  resumeAt?: number;
  /** ms since epoch: when the retry of a running epic's `api_error` starts; absent when none waits. */
  retryAt?: number;
};

export type PanelSnapshot = {
  now: number;
  slots: { busy: number; total: number };
  /** Queued epics, oldest first. */
  queue: { repo: string; issue: number; title?: string | null }[];
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
  /** The labels by role as the engine runs on them now; absent from an engine that does not send it (then they are the defaults). */
  labels?: Labels;
  /** Each watched repo's last check; absent from an engine that does not send it (the control snapshot always has it). */
  watched?: { repo: string; ok: boolean; error: string | null }[];
  /** The epics that ended ready for test, most recent first. */
  done: { repo: string; issue: number; title: string | null; labels: string[]; prNumber: number | null; finishedAt: number | null; executionId: string | null; unansweredObservations?: UnansweredObservations; reviewers?: PanelReviewers; reviewedSha?: string; approvedSha?: string; leadApproval?: boolean }[];
  /** The merged and cancelled epics inside the finished window, newest first; absent from an engine that does not send it (the control snapshot always has it). */
  finished?: PanelFinished[];
};

export type PanelFinished = {
  repo: string; issue: number; title: string | null; labels: string[]; prNumber: number | null; finishedAt: number;
  status: 'merged' | 'cancelled';
  /** null when merged. */
  cancelReason: string | null;
  /** The last execution of the epic. */
  executionId: string | null;
};

// What the control socket serves: the panel's snapshot plus what the macOS app draws. Everything here is additive (protocol 1),
// and the terminal panel keeps reading `PanelSnapshot`, of which this is a superset.
export type PanelAgent = { harness: 'claude' | 'codex' | 'agy'; model: string; provider: string | null };
/** The agents of an epic; `extraReviewers` (`reviewer-2` first) and `lead` are there only when it has them. */
export type PanelAgents = { author: PanelAgent; reviewer: PanelAgent; extraReviewers?: PanelAgent[]; lead?: PanelAgent };
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
  /** The head the reviewers agreed on (the head of the decision that sent the epic to its observations pass or to ready for test); absent until a round agreed. */
  reviewedSha?: string;
  /** The head the lead reviewer approved, set when it completes; may differ from `reviewedSha` when the head moved while the lead reviewed. Absent without a completed lead. */
  approvedSha?: string;
  /** Whether the lead's result says it submitted the pull request's formal approval; absent until the lead completes. */
  leadApproval?: boolean;
};

export type PanelSession = {
  executionId: string;
  repo: string;
  issue: number;
  stage: 'ship' | 'review' | 'fix';
  /** The lead reviewer's session: `stage` says `review` for it, and this flag, the lead. */
  lead?: true;
  round: number | null;
  /** The harness and the model the execution ran with, from its own record. */
  harness: PanelAgent['harness'];
  model: string;
  /** The slot of a review (`reviewer`, `reviewer-2`...); absent for the author's. */
  reviewer?: Slot;
  startedAt: number;
  /** The newest event of the execution; null until events are recorded. */
  last: { kind: string; text: string; at: number } | null;
};

export type ControlSnapshot = Omit<PanelSnapshot, 'queue' | 'epics'> & {
  queue: (PanelSnapshot['queue'][number] & { title: string | null; queuedAt: number })[];
  labels: Labels;
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
  /** The running executions: one for each running execution of an epic, so an epic with several reviewers has several. */
  sessions: PanelSession[];
  /** The merged and cancelled epics that ended inside the finished window, newest first, with no row cap. */
  finished: PanelFinished[];
};
