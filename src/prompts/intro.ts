import type { AgentTask } from '../execution/agent-runner.ts';

/** Who the agent is, the ground rules, and what happened in earlier turns of this epic. */
export function intro(task: AgentTask): string[] {
  const { executionId, repo, epic, stage, context } = task;
  const lines = [
    `You are the ${stage === 'review' ? 'reviewer' : 'author'} of the final integration PR of epic #${epic} in ${repo}. Execution ${executionId}, stage ${stage}.`,
    'Nobody answers questions during this run: decide, and use needs_human when you cannot.',
    'Apply the repo\'s own rules (its docs, agent instructions and conventions) to choose and evaluate tests, CI and blockers. Do not assume commands from other repos.',
  ];
  if (context.verifyStateFirst) {
    lines.push('A previous attempt of this stage was interrupted. Before acting, verify what is already done (branch, commits, PR, comments, threads) and continue from there instead of repeating work.');
  }
  if (context.previousSummaries.length > 0) {
    lines.push('Summaries of the previous turns, oldest first:', ...context.previousSummaries.map((s, i) => `${i + 1}. ${s}`));
  }
  return lines;
}
