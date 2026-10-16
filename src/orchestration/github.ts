export class GitHubUnavailable extends Error {
  constructor(readonly retryAfterMs?: number) {
    super('GitHub unavailable');
  }
}

export interface GitHub {
  /** All ready epics of the repo, every page. Throws GitHubUnavailable when GitHub is down or rate limiting. */
  listReadyEpics(repo: string): Promise<{ issue: number; title: string }[]>;
}
