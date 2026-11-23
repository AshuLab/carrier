import type { GitHub, PullRequestState } from './github.ts';

/** What the poll that asks already read about the epic: its final PR's state and whether the repo's open list had its issue. */
export type KnownOfEpic = { prState?: PullRequestState; issueOpen?: boolean };

/**
 * Did the epic end outside Carrier? Only the epic issue and the final PR (the one saved when `ship`
 * was validated) count: a slice PR or slice issue never shows up here. A merge is checked first
 * because merging the final PR closes the epic issue too.
 * GitHub is asked only for what `known` (read by the same poll, never what was stored) lacks: an epic missing from the open list may only have lost its label.
 */
export async function endOf(github: GitHub, { repo, issue, prNumber }: { repo: string; issue: number; prNumber: number | null }, known: KnownOfEpic = {}) {
  const state = prNumber === null ? null : (known.prState ?? (await github.getPullRequest(repo, prNumber))?.state ?? null);
  if (state === 'merged') return { status: 'merged' as const, reason: `the final PR #${prNumber} was merged` };
  if (state === 'closed') return { status: 'cancelled' as const, reason: `the final PR #${prNumber} was closed without merging`, cancelKind: 'pr_closed' as const };
  if (known.issueOpen !== true && (await github.getIssue(repo, issue)).state === 'closed') return { status: 'cancelled' as const, reason: 'the epic issue was closed without merging', cancelKind: 'issue_closed' as const };
  return null;
}
