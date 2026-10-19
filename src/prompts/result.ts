import type { AgentTask } from '../execution/agent-runner.ts';
import type { CallerResult } from '../execution/caller-result.ts';

const json = (result: CallerResult) => '```json\n' + JSON.stringify(result, null, 2) + '\n```';

/** The contract: where to write the result and which JSON shapes Carrier accepts for this stage. */
export function resultContract(task: AgentTask, pr: { number: number; headSha: string }): string[] {
  const { executionId, repo, epic, stage, resultPath } = task;
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

  return [
    `Before finishing, write exactly one JSON object to ${resultPath}. That path is also in the environment variable CARRIER_RESULT_PATH: write to "$CARRIER_RESULT_PATH" instead of retyping it, because a path with one segment missing is a result nobody reads. Repeat executionId, repo, epic and stage as given. Allowed outputs:`,
    ...examples.map(json),
    ...(reviewing ? [] : ['Replace pr.number and pr.headSha with the real final PR and its current head (git rev-parse HEAD). A failing CI is not a completed result.']),
    'verification.ci is "absent" when the repo has no CI; say so in evidence.',
  ];
}
