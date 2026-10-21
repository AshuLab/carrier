export class GitHubUnavailable extends Error {
  readonly retryAfterMs?: number;

  // No parameter property: Node strips types at runtime and cannot run that syntax.
  constructor(retryAfterMs?: number, cause?: string) {
    super('GitHub unavailable', { cause });
    this.retryAfterMs = retryAfterMs;
  }
}

/** Forge reported an authentication error for the profile the port acts as (the orchestrator's). Thrown by any GitHub call. */
export class AuthError extends Error {
  readonly profile: string;

  constructor(profile: string) {
    super('auth error');
    this.profile = profile;
  }
}

// Labels Carrier owns (it creates them) and the one Solve owns (it never does).
export const ownedLabels = ['solve:epic:running', 'solve:epic:ready-for-test', 'solve:epic:needs-human'] as const;
export const readyLabel = 'solve:epic:ready';
export const epicLabel = 'solve:epic';

/** Slices closed out of the total, as GitHub reports them. */
export type Slices = { done: number; total: number };

export type LabelStyle = { color: string; description: string };
/** How Carrier creates its labels (GitHub limits a description to 100 characters). `needs-human` is the loud one: it is the state that most needs to be seen. */
export const labelStyles = {
  'solve:epic:running': { color: '0969da', description: 'An orchestrator is building this epic' },
  'solve:epic:ready-for-test': { color: '8957e5', description: 'Reviewed on the current head; a person tests and merges' },
  'solve:epic:needs-human': { color: 'd93f0b', description: 'Stopped: a person has to step in (reason in the issue or PR)' },
} as const satisfies Record<(typeof ownedLabels)[number], LabelStyle>;
export const runningLabel = ownedLabels[0];
export const readyForTestLabel = ownedLabels[1];
export const needsHumanLabel = ownedLabels[2];

export interface GitHub {
  /** All ready epics of the repo, every page, with their title and labels. Throws GitHubUnavailable when GitHub is down or rate limiting. */
  listReadyEpics(repo: string): Promise<{ issue: number; title: string; labels: string[] }[]>;
  /** The open `solve:epic` issues of the repo, every page, each with its title, labels and the slice progress GitHub reports (`null` when it sends none). Throws GitHubUnavailable like the call above. */
  listOpenEpics(repo: string): Promise<{ issue: number; title: string; labels: string[]; slices: Slices | null }[]>;
  /** Throws GitHubUnavailable like every call below. */
  getIssue(repo: string, issue: number): Promise<{ state: 'open' | 'closed'; labels: string[] }>;
  /** Null when the PR does not exist; `closed` is closed without merge, a merged PR is `merged`. `headRef` is the branch it comes from. */
  getPullRequest(repo: string, number: number): Promise<{ state: 'open' | 'closed' | 'merged'; body: string; headSha: string; headRef: string } | null>;
  /** The PR whose body closes the epic issue, null when there is none. Read only: used to check what a failed execution left behind. */
  findPullRequest(repo: string, issue: number): Promise<{ number: number; state: 'open' | 'closed' | 'merged'; headSha: string } | null>;
  /** Idempotent: adding a label the issue has, or removing one it lacks, changes nothing. */
  setLabels(repo: string, issue: number, change: { add: string[]; remove: string[] }): Promise<void>;
  listLabels(repo: string): Promise<string[]>;
  /** Idempotent: a label that exists is left as it is, colour and description included. */
  createLabel(repo: string, name: string, style: LabelStyle): Promise<void>;
}
