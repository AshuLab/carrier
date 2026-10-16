import { execFileSync } from 'node:child_process';
import { describe, expect, test } from 'vitest';
import { ownedLabels, readyLabel, runningLabel } from '../orchestration/github.ts';
import { GhGitHub } from './github.ts';

// Runs against a real repo through Forge, so it only runs when all three are set explicitly:
//   CARRIER_IT_REPO=owner/name  CARRIER_IT_FORGE_AGENT=<agent in the Forge registry>
//   CARRIER_IT_CWD=<a clone whose origin is under the same owner; Forge picks the installation from it>
// It creates one throwaway issue and any missing labels, and closes/deletes them at the end.
const { CARRIER_IT_REPO: repo, CARRIER_IT_FORGE_AGENT: agent, CARRIER_IT_CWD: cwd } = process.env;
const enabled = Boolean(repo && agent && cwd);
if (!enabled) console.warn('GitHub integration test skipped: set CARRIER_IT_REPO, CARRIER_IT_FORGE_AGENT and CARRIER_IT_CWD to run it.');

describe.skipIf(!enabled)('GhGitHub against a real repo', () => {
  test(
    'lists a ready epic, creates the missing labels and swaps ready for running',
    async () => {
      const github = new GhGitHub({ profile: { kind: 'forge', agent: agent! }, cwd: () => cwd!, timeoutMs: 30_000 });
      const forge = (args: string[]) => execFileSync('agent-forge', ['gh', agent!, ...args], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
      const created: string[] = [];
      let issue: number | undefined;
      try {
        const existing = await github.listLabels(repo!);
        for (const label of [readyLabel, ...ownedLabels]) {
          if (existing.includes(label)) continue;
          await github.createLabel(repo!, label);
          created.push(label);
        }
        const labels = await github.listLabels(repo!);
        for (const label of [readyLabel, ...ownedLabels]) expect(labels).toContain(label);
        // Creating one that exists is a no-op.
        await github.createLabel(repo!, runningLabel);

        const title = '[carrier spike] adapter test - safe to close';
        issue = (JSON.parse(forge(['api', '-X', 'POST', `repos/${repo}/issues`, '-f', `title=${title}`, '-f', 'body=Throwaway issue from the Carrier adapter integration test.'])) as { number: number }).number;
        await github.setLabels(repo!, issue, { add: [readyLabel], remove: [] });
        expect(await github.getIssue(repo!, issue)).toEqual({ state: 'open', labels: [readyLabel] });
        expect(await github.listReadyEpics(repo!)).toContainEqual({ issue, title });

        await github.setLabels(repo!, issue, { add: [runningLabel], remove: [readyLabel] });
        await github.setLabels(repo!, issue, { add: [runningLabel], remove: [readyLabel] });
        expect(await github.getIssue(repo!, issue)).toEqual({ state: 'open', labels: [runningLabel] });
        expect((await github.listReadyEpics(repo!)).map((epic) => epic.issue)).not.toContain(issue);

        expect(await github.getPullRequest(repo!, 999_999)).toBeNull();
        expect(await github.findPullRequest(repo!, issue)).toBeNull();
      } finally {
        if (issue !== undefined) {
          forge(['api', '-X', 'PATCH', `repos/${repo}/issues/${issue}`, '-f', 'state=closed', '-f', 'state_reason=not_planned']);
        }
        for (const label of created) forge(['api', '-X', 'DELETE', `repos/${repo}/labels/${encodeURIComponent(label)}`]);
      }
    },
    120_000,
  );
});
