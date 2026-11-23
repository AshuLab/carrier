import type { needsHumanKinds } from '../storage/schema.ts';

export type UnavailableKind = 'rate_limited' | 'server_error' | 'timeout' | 'network';

export class GitHubUnavailable extends Error {
  readonly kind: UnavailableKind;
  readonly retryAfterMs?: number;

  // No parameter property: Node strips types at runtime and cannot run that syntax.
  constructor(kind: UnavailableKind, detail: string, retryAfterMs?: number) {
    super(`GitHub unavailable (${kind}: ${detail})`);
    this.kind = kind;
    this.retryAfterMs = retryAfterMs;
  }
}

/** GitHub answered a call that it cannot serve (not found, no access, invalid): about that repo or object, not about GitHub being down or the profile. */
export class GitHubRejected extends Error {}

/** Forge reported an authentication error for the profile the port acts as (the orchestrator's). Thrown by any GitHub call. */
export class AuthError extends Error {
  readonly profile: string;

  constructor(profile: string) {
    super('auth error');
    this.profile = profile;
  }
}

/** The stages an epic runs in; a label can name each one while the epic is `running`. */
export const stageNames = ['ship', 'review', 'fix'] as const;
export type StageName = (typeof stageNames)[number];

/**
 * The labels by role. `epic` marks an epic and `ready` queues it (Solve and people write both); `running`, `readyForTest` and `needsHuman`
 * mirror its status and are Carrier's: it creates them and nothing else writes them. The config can name each; these are the defaults.
 * `stages` and `reasons` are optional and off by default: a label per stage while the epic runs, and one per kind of stop while it waits for a person.
 */
export const labelRoles = ['epic', 'ready', 'running', 'readyForTest', 'needsHuman'] as const;
export type Labels = Record<(typeof labelRoles)[number], string> & {
  stages?: Partial<Record<StageName, string>>;
  reasons?: Partial<Record<(typeof needsHumanKinds)[number], string>>;
};
/** Whether `labels` has `name`: GitHub compares label names without case, so Carrier does too. */
export const hasLabel = (labels: readonly string[], name: string) => labels.some((label) => label.toLowerCase() === name.toLowerCase());
export const defaultLabels: Labels = {
  epic: 'solve:epic',
  ready: 'solve:epic:ready',
  running: 'solve:epic:running',
  readyForTest: 'solve:epic:ready-for-test',
  needsHuman: 'solve:epic:needs-human',
};

/** Slices closed out of the total, as GitHub reports them. */
export type Slices = { done: number; total: number };

/** One slice of an epic as GitHub says it is now. `closed` is merged, `skipped` is closed as not planned; `blockedBy` holds only the blockers still open. `closedAt` is ms since epoch. */
export type EpicSlice = {
  number: number;
  title: string;
  state: 'closed' | 'skipped' | 'in_progress' | 'waiting' | 'ready';
  blockedBy: number[];
  assignee: string | null;
  /** The slice's own pull request: the one whose branch is `<feature>/<slice>-<name>`, never one that only mentions it. */
  prNumber: number | null;
  prState: 'open' | 'draft' | 'merged' | 'closed' | null;
  /** When that pull request was merged; `closedAt` is when the issue closed, which can be later. */
  prMergedAt: number | null;
  closedAt: number | null;
};

/** What GitHub says a pull request is: `closed` is closed without merge, a merged one is `merged`. */
export type PullRequestState = 'open' | 'closed' | 'merged';

/** A pull request as GitHub says it is now: its merge state, review decision and check counts; `checks` is null when it has none, which is not pending. */
export type PullRequestBlock = {
  number: number;
  url: string;
  draft: boolean;
  mergeState: string;
  reviewDecision: string | null;
  checks: { passing: number; failing: number; pending: number } | null;
};

/** A conversation on a line of the final pull request's diff, as GitHub says it is now. */
export type ReviewThread = {
  /** GraphQL node id: the key of the row. */
  id: string;
  path: string;
  /** Null when the thread is outdated and GitHub no longer maps it. */
  line: number | null;
  resolved: boolean;
  outdated: boolean;
  /** Null for a deleted account. */
  author: string | null;
  /** The author's __typename is Bot. */
  bot: boolean;
  /** First line of the opening comment, redacted, at most 160 characters; '' when the comment is empty. */
  firstLine: string;
  commentCount: number;
  /** The opening comment's url. */
  url: string;
};

export type LabelStyle = { color: string; description: string };
/** How Carrier creates its labels (GitHub limits a description to 100 characters). `needs-human` is the loud one: it is the state that most needs to be seen. */
export const labelStyles = {
  running: { color: '0969da', description: 'An orchestrator is building this epic' },
  readyForTest: { color: '8957e5', description: 'Reviewed on the current head; a person tests and merges' },
  needsHuman: { color: 'd93f0b', description: 'Stopped: a person has to step in (reason in the issue or PR)' },
  stage: { color: 'c5def5', description: 'Carrier: the stage this epic is in' },
  reason: { color: 'fbca04', description: 'Carrier: why this epic stopped' },
} as const satisfies Record<'running' | 'readyForTest' | 'needsHuman' | 'stage' | 'reason', LabelStyle>;

/** The REST limit of the orchestrator's credential at its latest answer; `resetAt` is ms since epoch. */
export type RateLimit = { remaining: number; limit: number; resetAt: number };

export interface GitHub {
  /** From the headers of the latest call, no request of its own; null before any call carried them. */
  rateLimit(): RateLimit | null;
  /** All open issues of the repo that carry `label` (the ready label), every page, with their title and labels. Throws GitHubUnavailable when GitHub is down or rate limiting. */
  listReadyEpics(repo: string, label: string): Promise<{ issue: number; title: string; labels: string[] }[]>;
  /** The open issues of the repo that carry `label` (the epic marker), every page, each with its title, labels and the slice progress GitHub reports (`null` when it sends none). Throws GitHubUnavailable like the call above. */
  listOpenEpics(repo: string, label: string): Promise<{ issue: number; title: string; labels: string[]; slices: Slices | null }[]>;
  /** The first hundred slices of an epic in one query; `truncated` when it has more. Throws GitHubUnavailable like the call above. */
  readSlices(repo: string, issue: number): Promise<{ slices: EpicSlice[]; truncated: boolean }>;
  /** One query: the pull request's merge state, review decision and checks, and its first hundred review threads (`truncated` when it has more); null when it does not exist. Throws GitHubUnavailable like the call above. */
  readPullRequest(repo: string, number: number): Promise<{ pr: PullRequestBlock; threads: ReviewThread[]; truncated: boolean; state: PullRequestState } | null>;
  /** Throws GitHubUnavailable like every call below. */
  getIssue(repo: string, issue: number): Promise<{ state: 'open' | 'closed'; labels: string[] }>;
  /** Null when the PR does not exist; `closed` is closed without merge, a merged PR is `merged`. `headRef` is the branch it comes from. */
  getPullRequest(repo: string, number: number): Promise<{ state: PullRequestState; body: string; headSha: string; headRef: string } | null>;
  /** The PR whose body closes the epic issue, null when there is none. Read only: used to check what a failed execution left behind. */
  findPullRequest(repo: string, issue: number): Promise<{ number: number; state: PullRequestState; headSha: string } | null>;
  /** Idempotent: adding a label the issue has, or removing one it lacks, changes nothing. */
  setLabels(repo: string, issue: number, change: { add: string[]; remove: string[] }): Promise<void>;
  listLabels(repo: string): Promise<string[]>;
  /** Idempotent: a label that exists is left as it is, colour and description included. */
  createLabel(repo: string, name: string, style: LabelStyle): Promise<void>;
}
