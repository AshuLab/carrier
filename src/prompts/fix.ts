import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke, skillsOf } from './invoke.ts';

// With several reviewers each finding says whose it is, as `seguridad-api:B1` (the reviewer's own id, when it gave one).
const item = (b: { id?: string; title: string; url?: string; reviewer?: string }) => `- ${b.reviewer ? `${[b.reviewer, b.id].filter(Boolean).join(':')}: ` : ''}${b.title}${b.url ? ` (${b.url})` : ''}`;
const contradict = (kind: 'blockers' | 'observations') =>
  `When the ${kind} of two reviewers contradict each other, you decide: say in your summary which one you did not follow and why, because the reviewers read your summary in their next round.`;

/** Stage `fix`: answer the blockers of the last review, or, when it only left observations, reply to them. */
export const fix = (task: AgentTask, pr: { number: number }): string[] => {
  const observations = task.context.observations ?? [];
  if (observations.length > 0) {
    return [
      `Invoke ${invoke(task, skillsOf(task).fix.name)} on PR #${pr.number}, answering the observations the last review left and fixing what applies.`,
      'Reply on each thread with your decision, whether or not it changes the code. Leave every thread open: only the reviewer can say it is satisfied, you do not resolve them.',
      'Never merge the final PR.',
      'Observations of the last review:',
      ...observations.map(item),
      ...(observations.some((o) => o.reviewer) ? [contradict('observations')] : []),
    ];
  }
  const blockers = task.context.blockers ?? [];
  return [
    `Invoke ${invoke(task, skillsOf(task).fix.name)} on PR #${pr.number}, answering every finding of the last review and fixing what applies.`,
    'Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.',
    'Blockers of the last review:',
    ...blockers.map(item),
    ...(blockers.some((b) => b.reviewer) ? [contradict('blockers')] : []),
  ];
};
