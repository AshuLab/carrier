import type { AgentTask } from '../execution/agent-runner.ts';
import { fix } from './fix.ts';
import { intro } from './intro.ts';
import { resultContract } from './result.ts';
import { review } from './review.ts';
import { ship } from './ship.ts';

// Only used when the task has no PR yet (ship); the engine validates the real PR against GitHub.
const placeholderPr = { number: 1, headSha: '0'.repeat(40) };

/** The prompt of one run: who you are, what this stage asks, and how to hand the result back. */
export function buildPrompt(task: AgentTask, { forgeAgent }: { forgeAgent?: string } = {}): string {
  const pr = task.context.pr ?? placeholderPr;
  const stage = task.stage === 'ship' ? ship(task) : task.stage === 'fix' ? fix(task, pr) : review(task, pr);
  return [...intro(task, forgeAgent), ...stage, ...resultContract(task, pr)].join('\n');
}
