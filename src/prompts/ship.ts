import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke } from './invoke.ts';

/** Stage `ship`: drain the epic into its own worktree and leave the final PR open. */
export const ship = (task: AgentTask): string[] => [
  `Invoke ${invoke(task, 'ship')} for epic #${task.epic} and tell it to worktree this epic, whatever mode the repo's solve.md has: the epic must live in its own git worktree. Leave the final integration PR open.`,
  'Never merge the final PR: a person tests it and decides the merge.',
];
