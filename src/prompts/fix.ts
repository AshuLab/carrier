import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke } from './invoke.ts';

/** Stage `fix`: answer the blockers of the last review. */
export const fix = (task: AgentTask, pr: { number: number }): string[] => [
  `Invoke ${invoke(task, 'code-resolve')} on PR #${pr.number}, answering every finding of the last review and fixing what applies.`,
  'Never merge the final PR. Leave the blockers open: the reviewer verifies them, you do not resolve them.',
  'Blockers of the last review:',
  ...(task.context.blockers ?? []).map((b) => `- ${b.title}${b.url ? ` (${b.url})` : ''}`),
];
