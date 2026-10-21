import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import { epicSlicesResponse, failingCheckResponse, pullRequestResponse } from './github-graphql.ts';

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
});
