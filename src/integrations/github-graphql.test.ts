import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { epicSlicesResponse, failingCheckResponse, pullRequestOf, pullRequestResponse, sliceOf, threadsOf } from './github-graphql.ts';

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

  test("a slice's own pull request is found by its branch, not by who mentions it", () => {
    const pr = (number: number, headRefName: string, state: 'OPEN' | 'MERGED', extra = {}) => ({ source: { __typename: 'PullRequest', number, headRefName, state, isDraft: false, mergedAt: null, ...extra } });
    const read = (number: number, nodes: unknown[], state: 'OPEN' | 'CLOSED' = 'CLOSED') =>
      sliceOf({ number, title: 't', state, stateReason: state === 'CLOSED' ? 'COMPLETED' : null, closedAt: null, assignees: { nodes: [] }, blockedBy: { nodes: [] }, timelineItems: { nodes: nodes as never } });
    // carrier #75: slice 81 is mentioned by slice 76's PR (95) and by the final PR (110), and owns 97.
    const mentions = [pr(95, 'feat/f/76-shutdown', 'MERGED'), pr(97, 'feat/f/81-stop', 'MERGED', { mergedAt: '2026-10-20T01:59:32Z' }), pr(110, 'feat/f/epic', 'MERGED')];
    expect(read(81, mentions)).toMatchObject({ prNumber: 97, prState: 'merged', prMergedAt: Date.parse('2026-10-20T01:59:32Z') });
    expect(read(76, mentions)).toMatchObject({ prNumber: 95 });
    expect(read(90, mentions)).toMatchObject({ prNumber: null, prState: null, prMergedAt: null }); // a mention is not a pull request of its own
    expect(read(7, [pr(1, 'feat/f/7-a', 'MERGED'), pr(2, 'feat/f/7-a', 'OPEN')], 'OPEN')).toMatchObject({ prNumber: 2, prState: 'open' }); // the newest one
    expect(read(7, [pr(3, 'feat/f/7-a', 'OPEN', { isDraft: true })], 'OPEN')).toMatchObject({ prState: 'draft', state: 'in_progress' });
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

  test('review threads: null line, deleted author, bot, empty comment, a token and a long first line; more than the limit is partial', () => {
    const { threads, truncated } = threadsOf(pullRequestResponse.parse(fixture('pr-review-threads')));
    expect(truncated).toBe(true);
    expect(threads.map((t) => t.id)).toEqual([1, 2, 3, 4, 5, 6, 7].map((n) => `PRRT_example${n}`));
    expect(threads[0]).toEqual({
      id: 'PRRT_example1',
      path: 'src/example-1.ts',
      line: 11,
      resolved: true,
      outdated: false,
      author: 'example-user',
      bot: false,
      firstLine: 'Rename this variable.', // the first line only
      commentCount: 3,
      url: 'https://github.com/example-owner/example-repo/pull/167#discussion_r1',
    });
    expect(threads[1]).toMatchObject({ line: null, outdated: true });
    expect(threads[2]).toMatchObject({ author: null, bot: false });
    expect(threads[3]).toMatchObject({ author: 'example-reviewer-bot', bot: true });
    expect(threads[4]!.firstLine).toBe('');
    expect(threads[5]!.firstLine).toBe('Do not paste [redacted] into the config.');
    expect(threads[6]!.firstLine).toHaveLength(160);
    expect(threads[6]!.firstLine.startsWith('This first line is long. This first line')).toBe(true);
  });

  test('an answer recorded before the threads were asked has none and is not partial', () => {
    expect(threadsOf(pullRequestResponse.parse(fixture('pr-no-checks')))).toEqual({ threads: [], truncated: false });
  });
});
