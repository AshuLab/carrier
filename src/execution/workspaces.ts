export interface Workspaces {
  /** Path of the author's checkout for the epic. */
  prepareAuthor(repo: string, epic: number): Promise<string>;
  /** Path of a separate checkout for the reviewer, at the PR. */
  prepareReviewer(repo: string, epic: number, pr: number): Promise<string>;
}
