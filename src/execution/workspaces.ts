export interface Workspaces {
  /** Path of the author's checkout for the epic. */
  prepareAuthor(repo: string, epic: number): Promise<string>;
  /**
   * A separate checkout for a reviewer slot (`reviewer` by default, then `reviewer-2` to `reviewer-4` and `lead`), at `commit` or, when none is given, the PR's
   * head, reset and cleaned of untracked files: its path and the commit it was made at. The same slot of an epic reuses its checkout; two slots never share one.
   */
  prepareReviewer(repo: string, epic: number, pr: number, options?: { slot?: string; commit?: string }): Promise<{ path: string; commit: string }>;
  /**
   * Where `branch` is checked out among the linked worktrees of the repo's clone (what `git worktree list` says), null when
   * nowhere (the clone itself does not count: it is shared by every epic of the repo). Solve decides the epic worktree's path, so the real one is read back after `ship`, never assumed.
   */
  findWorktree(repo: string, branch: string): Promise<string | null>;
  /** Whether a saved workspace path is still on disk. */
  exists(path: string): Promise<boolean>;
  /**
   * Removes what a merged or cancelled epic left: the checkouts of its reviewers, the author's worktree of `branch` and its lanes, and the
   * epic's local branches already on the remote. Returns the worktrees it kept because they hold uncommitted or unsaved work, and the
   * local branches it kept because they were not on the remote.
   */
  cleanUp(repo: string, epic: number, branch: string | null): Promise<{ kept: string[] }>;
}
