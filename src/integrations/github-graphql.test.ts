import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { epicSlicesResponse, failingCheckResponse, pullRequestOf, pullRequestResponse, sliceOf } from './github-graphql.ts';

// Recorded from the Forge bot token (docs/research/macos-app-github-graphql.md), private text replaced.
const fixture = (name: string): unknown => JSON.parse(readFileSync(new URL(`./github-graphql-fixtures/${name}.json`, import.meta.url), 'utf8'));
const rollupOf = (name: string) => pullRequestResponse.parse(fixture(name)).data.repository.pullRequest.lastCommit.nodes[0]!.commit.statusCheckRollup;

describe('recorded GraphQL answers', () => {
  test('a slice list carries the blockers, closed ones included', () => {
    const issue = epicSlicesResponse.parse(fixture('epic-slices')).data.repository.issue;
    const waiting = issue.subIssues.nodes.filter((s) => s.blockedBy.nodes.some((b) => b.state === 'OPEN'));
    expect(issue.subIssues.nodes.map((s) => s.number)).toEqual([112, 115, 118, 120, 135, 136]);
    expect(waiting.map((s) => s.number)).toEqual([120, 135, 136]);
    expect(issue.subIssues.nodes.find((s) => s.number === 135)!.blockedBy.nodes.map((b) => b.state)).toEqual(['CLOSED', 'OPEN']);
  });

  test('a PR with checks gives counts by state', () => {
    const rollup = rollupOf('pr-checks-passing')!;
    expect(rollup.state).toBe('SUCCESS');
    expect(rollup.contexts.checkRunCount).toBe(18);
  });

  test('a PR with no checks has a null rollup', () => {
    expect(rollupOf('pr-no-checks')).toBeNull();
  });

  test('a failing check is named in the rollup', () => {
    expect(rollupOf('pr-checks-failing')!.state).toBe('FAILURE');
    const rollup = failingCheckResponse.parse(fixture('pr-failing-check-detail')).data.repository.pullRequest.lastCommit.nodes[0]!.commit.statusCheckRollup!;
    expect(rollup.contexts.nodes.filter((c) => c.__typename === 'CheckRun' && c.conclusion === 'FAILURE')).toHaveLength(1);
  });

  test('slices take their state from GitHub: no blockers, closed blockers, open blockers, skipped, merged', () => {
    const states = (name: string) => Object.fromEntries(epicSlicesResponse.parse(fixture(name)).data.repository.issue.subIssues.nodes.map((n) => [n.number, sliceOf(n)]));
    const recorded = states('epic-slices');
    expect(recorded[112]).toMatchObject({ state: 'closed', closedAt: Date.parse('2026-10-21T22:18:28Z'), blockedBy: [] });
    expect(recorded[115]).toMatchObject({ state: 'in_progress', assignee: 'example-user' });
    expect(recorded[118]).toMatchObject({ state: 'ready', blockedBy: [], assignee: null });
    expect(recorded[120]).toMatchObject({ state: 'waiting' });
    expect(recorded[135]!.blockedBy).toHaveLength(1); // one blocker is closed and does not hold it
    expect(recorded[135]!.state).toBe('waiting');

    const large = states('epic-slices-large');
    expect(large[203]).toMatchObject({ state: 'skipped', prNumber: null });
    expect(large[200]).toMatchObject({ state: 'closed', prNumber: 400 }); // the issue that mentions it is not a pull request
    expect(large[261]).toMatchObject({ state: 'waiting', blockedBy: [260, 262] });
    expect(large[262]).toMatchObject({ state: 'ready', blockedBy: [] }); // blocked by a closed one only
  });

  test('an epic with more than a hundred slices reports the first hundred and that there are more', () => {
    const issue = epicSlicesResponse.parse(fixture('epic-slices-large')).data.repository.issue;
    expect(issue.subIssues.nodes).toHaveLength(100);
    expect(issue.subIssues.pageInfo.hasNextPage).toBe(true);
    expect(issue.subIssuesSummary.total).toBe(130);
  });

  test('the pull request block counts the checks, null when there are none, and carries the draft, merge state and review decision', () => {
    const block = (name: string) => pullRequestOf(pullRequestResponse.parse(fixture(name)));
    expect(block('pr-checks-passing').checks).toEqual({ passing: 18, failing: 0, pending: 0 });
    expect(block('pr-no-checks').checks).toBeNull(); // not pending
    expect(block('pr-checks-failing')).toEqual({
      number: 14035,
      url: 'https://github.com/example-owner/example-repo/pull/14035',
      draft: true,
      mergeState: 'DIRTY',
      reviewDecision: 'REVIEW_REQUIRED',
      checks: { passing: 10, failing: 1, pending: 0 },
    });
    expect(block('pr-checks-passing')).toMatchObject({ draft: false });
  });
});
