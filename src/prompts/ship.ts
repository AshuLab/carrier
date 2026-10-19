import type { AgentTask } from '../execution/agent-runner.ts';
import { invoke } from './invoke.ts';

/** Stage `ship`: drain the epic into its own worktree and leave the final PR open. */
export const ship = (task: AgentTask): string[] => [
  `Invoke ${invoke(task, 'ship')} for epic #${task.epic} and tell it to worktree this epic, whatever mode the repo's solve.md has: the epic must live in its own git worktree. Leave the final integration PR open.`,
  'Never merge the final PR: a person tests it and decides the merge.',
  // Carrier may run on another machine: a file on someone's disk is not a source. The remote is the only shared channel.
  'The epic\'s design artifacts (spec, ADRs, glossary) must already be on the remote, on the epic branch or the base branch. Do not look for uncommitted files in other directories of this machine. If the epic refers to a spec or ADR that is not there, return needs_human naming what is missing.',
];
