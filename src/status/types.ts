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
  done: { repo: string; issue: number; prNumber: number | null; finishedAt: number | null; executionId: string | null }[];
};
