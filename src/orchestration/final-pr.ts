import type { GitHub } from './github.ts';

/**
 * Did the epic end outside Carrier? Only the epic issue and the final PR (the one saved when `ship`
 * was validated) count: a slice PR or slice issue never shows up here. A merge is checked first
 * because merging the final PR closes the epic issue too.
 */
export async function endOf(github: GitHub, { repo, issue, prNumber }: { repo: string; issue: number; prNumber: number | null }) {
  const pr = prNumber === null ? null : await github.getPullRequest(repo, prNumber);
  if (pr?.state === 'merged') return { status: 'merged' as const, reason: `the final PR #${prNumber} was merged` };
  if (pr?.state === 'closed') return { status: 'cancelled' as const, reason: `the final PR #${prNumber} was closed without merging` };
  if ((await github.getIssue(repo, issue)).state === 'closed') return { status: 'cancelled' as const, reason: 'the epic issue was closed without merging' };
  return null;
}
