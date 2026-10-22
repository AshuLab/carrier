import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke } from './invoke.ts';

const item = (b: { title: string; url?: string }) => `- ${b.title}${b.url ? ` (${b.url})` : ''}`;

/** Stage `fix`: answer the blockers of the last review, or, when it only left observations, reply to them. */
export const fix = (task: AgentTask, pr: { number: number }): string[] => {
  const observations = task.context.observations ?? [];
  if (observations.length > 0) {
    return [
      `Invoke ${invoke(task, 'code-resolve')} on PR #${pr.number}, answering the observations the last review left and fixing what applies.`,
      'Reply on each thread with your decision, whether or not it changes the code. Leave every thread open: only the reviewer can say it is satisfied, you do not resolve them.',
      'Never merge the final PR.',
      'Observations of the last review:',
      ...observations.map(item),
    ];
  }
  return [
    `Invoke ${invoke(task, 'code-resolve')} on PR #${pr.number}, answering every finding of the last review and fixing what applies.`,
    'Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.',
    'Blockers of the last review:',
    ...(task.context.blockers ?? []).map(item),
  ];
};
