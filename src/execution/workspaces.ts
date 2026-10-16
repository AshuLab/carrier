export interface Workspaces {
  /** Path of the author's checkout for the epic. */
  prepareAuthor(repo: string, epic: number): Promise<string>;
  /** Path of a separate checkout for the reviewer, at the PR. */
  prepareReviewer(repo: string, epic: number, pr: number): Promise<string>;
  /**
   * Where `branch` is checked out among the linked worktrees of the repo's clone (what `git worktree list` says), null when
   * nowhere (the clone itself does not count: it is shared by every epic of the repo). Solve decides the epic worktree's path, so the real one is read back after `ship`, never assumed.
   */
  findWorktree(repo: string, branch: string): Promise<string | null>;
}
