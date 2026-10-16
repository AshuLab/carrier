export class GitHubUnavailable extends Error {
  constructor(readonly retryAfterMs?: number) {
    super('GitHub unavailable');
  }
}

// Labels Carrier owns (it creates them) and the one Solve owns (it never does).
export const ownedLabels = ['solve:epic:running', 'solve:epic:ready-for-test', 'solve:epic:needs-human'] as const;
export const readyLabel = 'solve:epic:ready';
export const runningLabel = ownedLabels[0];
export const readyForTestLabel = ownedLabels[1];
export const needsHumanLabel = ownedLabels[2];

export interface GitHub {
  /** All ready epics of the repo, every page. Throws GitHubUnavailable when GitHub is down or rate limiting. */
  listReadyEpics(repo: string): Promise<{ issue: number; title: string }[]>;
  /** Throws GitHubUnavailable like every call below. */
  getIssue(repo: string, issue: number): Promise<{ state: 'open' | 'closed'; labels: string[] }>;
  /** Null when the PR does not exist; `closed` is closed without merge, a merged PR is `merged`. */
  getPullRequest(repo: string, number: number): Promise<{ state: 'open' | 'closed' | 'merged'; body: string; headSha: string } | null>;
  /** The PR whose body closes the epic issue, null when there is none. Read only: used to check what a failed execution left behind. */
  findPullRequest(repo: string, issue: number): Promise<{ number: number; state: 'open' | 'closed' | 'merged'; headSha: string } | null>;
  /** Idempotent: adding a label the issue has, or removing one it lacks, changes nothing. */
  setLabels(repo: string, issue: number, change: { add: string[]; remove: string[] }): Promise<void>;
  listLabels(repo: string): Promise<string[]>;
  createLabel(repo: string, name: string): Promise<void>;
}
