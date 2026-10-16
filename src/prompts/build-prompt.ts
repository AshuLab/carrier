import type { AgentTask } from '../execution/agent-runner.ts';
import type { CallerResult } from '../execution/caller-result.ts';

// Only used when the task has no PR yet (ship); the engine validates the real PR against GitHub.
const placeholderPr = { number: 1, headSha: '0'.repeat(40) };

const json = (result: CallerResult) => '```json\n' + JSON.stringify(result, null, 2) + '\n```';

export function buildPrompt(task: AgentTask): string {
  const { executionId, repo, epic, stage, resultPath, provider, context } = task;
  const { pr = placeholderPr, blockers = [], previousSummaries, verifyStateFirst } = context;
  const invoke = (skill: string) => `${provider === 'claude' ? '/' : '$'}${skill}`;
  const reviewing = stage === 'review';
  const common = { executionId, repo, epic, stage, summary: '<what you did and concluded, in a few lines>' };

  const completed = (evidence: string): CallerResult => ({ ...common, outcome: 'completed', pr, verification: { ci: 'passed', evidence } });
  const changesRequested: CallerResult = {
    ...common,
    stage: 'review',
    outcome: 'changes_requested',
    pr,
    blockers: [{ title: '<blocker>', url: `https://github.com/${repo}/pull/${pr.number}#discussion_r123` }],
  };
  const needsHuman: CallerResult = { ...common, outcome: 'needs_human', reason: '<why a person has to step in>' };
  const examples = reviewing
    ? [completed('<which verifications you confirmed on this commit>'), changesRequested, needsHuman]
    : [completed('<which verifications you ran and their result>'), needsHuman];

  const lines: string[] = [
    `You are the ${reviewing ? 'reviewer' : 'author'} of the final integration PR of epic #${epic} in ${repo}. Execution ${executionId}, stage ${stage}.`,
    'Nobody answers questions during this run: decide, and use needs_human when you cannot.',
    'Apply the repo\'s own rules (its docs, agent instructions and conventions) to choose and evaluate tests, CI and blockers. Do not assume commands from other repos.',
  ];

  if (verifyStateFirst) {
    lines.push('A previous attempt of this stage was interrupted. Before acting, verify what is already done (branch, commits, PR, comments, threads) and continue from there instead of repeating work.');
  }
  if (previousSummaries.length > 0) {
    lines.push('Summaries of the previous turns, oldest first:', ...previousSummaries.map((s, i) => `${i + 1}. ${s}`));
  }

  if (stage === 'ship') {
    lines.push(
      `Invoke ${invoke('ship')} for epic #${epic} and leave the final integration PR open.`,
      'Never merge the final PR: a person tests it and decides the merge.',
    );
  } else if (stage === 'fix') {
    lines.push(
      `Invoke ${invoke('code-resolve')} on PR #${pr.number}, answering every finding of the last review and fixing what applies.`,
      'Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.',
      'Blockers of the last review:',
      ...blockers.map((b) => `- ${b.title}${b.url ? ` (${b.url})` : ''}`),
    );
  } else {
    lines.push(
      `Review PR #${pr.number}${context.round ? `, round ${context.round}` : ''}. First confirm the PR head is ${pr.headSha}; if it is not, return needs_human.`,
      `Invoke ${invoke('code-review')} against the epic's spec and tickets, checking that earlier findings were fixed and nothing regressed, then publish the findings with ${invoke('code-post')}.`,
      'Return changes_requested with the blockers if there are any. Return completed only if the review is conclusive, there are no blockers and the repo\'s verifications are confirmed on that same commit. If the review is inconclusive (missing context, cannot verify), return needs_human.',
    );
  }

  lines.push(
    `Before finishing, write exactly one JSON object to ${resultPath}. Repeat executionId, repo, epic and stage as given. Allowed outputs:`,
    ...examples.map(json),
    ...(reviewing ? [] : ['Replace pr.number and pr.headSha with the real final PR and its current head (git rev-parse HEAD). A failing CI is not a completed result.']),
    'verification.ci is "absent" when the repo has no CI; say so in evidence.',
  );
  return lines.join('\n');
}
