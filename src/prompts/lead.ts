import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke, skillsOf } from './invoke.ts';

/** Stage `lead`: the final review of the PR, after the reviewers agreed, ending with its formal approval when it finds no blocker. */
export const lead = (task: AgentTask, pr: { number: number; headSha: string }): string[] => {
  const skills = skillsOf(task);
  const { review: reviewing, publish } = skills.lead ?? skills.review;
  const { reviewerSummaries = [] } = task.context;
  return [
    `Review PR #${pr.number} as the final reviewer: the reviewers of this epic agreed on it, and nobody reviews after you. First confirm the PR head is ${pr.headSha}; if it is not, return needs_human.`,
    ...(reviewerSummaries.length > 0 ? ['What the reviewers concluded, by reviewer:', ...reviewerSummaries.map((r) => `- ${r.reviewer}: ${r.summary}`)] : []),
    `Invoke ${invoke(task, reviewing.name)} against the epic's spec and tickets, taking what the reviewers concluded into account and checking that nothing regressed${publish ? `, then publish the findings with ${invoke(task, publish.name)}` : ''}.`,
    `When you find no blocker, give the pull request its formal approval with your own identity (gh pr review ${pr.number} --approve), and say in "approval" of the result whether you submitted it, with the link of the review when you have one.`,
    task.sharedIdentity
      ? 'Your GitHub account is the author\'s, and GitHub does not let an account approve its own pull request: do not try, and return "approval" with "submitted" false.'
      : 'The approval is not required: when you cannot give it, return "approval" with "submitted" false and the epic goes on all the same.',
    'Give every blocker you return a short stable id (for example "token-expiry").',
    'Findings that do not stop approval (what you would post as a nitpick or a suggestion) are observations: list them in "observations" of a completed result, each with a title, a link when you have one and a short stable id. Leave the field out when there are none.',
    'Return changes_requested with the blockers if there are any. Return completed only if the review is conclusive, there are no blockers and the repo\'s verifications are confirmed on that same commit. If the review is inconclusive (missing context, cannot verify), return needs_human.',
  ];
};
