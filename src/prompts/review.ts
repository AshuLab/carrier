import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke } from './invoke.ts';

/** Stage `review`: judge the final PR with a different identity than the author's. */
export const review = (task: AgentTask, pr: { number: number; headSha: string }): string[] => [
  `Review PR #${pr.number}${task.context.round ? `, round ${task.context.round}` : ''}. First confirm the PR head is ${pr.headSha}; if it is not, return needs_human.`,
  `Invoke ${invoke(task, 'code-review')} against the epic's spec and tickets, checking that earlier findings were fixed and nothing regressed, then publish the findings with ${invoke(task, 'code-post')}.`,
  ...(task.context.blockers?.length
    ? [
        'Blockers of the previous round (id and title):',
        ...task.context.blockers.map((b) => `- ${b.id ?? '(no id)'}: ${b.title}`),
        'Give every blocker you return a short stable id. When a finding above persists, reuse its id; never reuse an id for a different finding. List in "resolved" the ids of the blockers above that are now fixed.',
      ]
    : ['Give every blocker you return a short stable id (for example "token-expiry"), so a later round can say whether it persists or was fixed.']),
  'Findings that do not stop approval (what you would post as a nitpick or a suggestion) are observations: list them in "observations" of a completed result, each with a title, a link when you have one, and a short stable id by the same rule as blockers (reuse it when the finding persists; never reuse an id for a different finding). Leave the field out when there are none.',
  'Return changes_requested with the blockers if there are any. Return completed only if the review is conclusive, there are no blockers and the repo\'s verifications are confirmed on that same commit. If the review is inconclusive (missing context, cannot verify), return needs_human.',
];
