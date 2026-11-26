import type { AgentTask } from '../execution/agent-runner.ts';
import { solveSkills } from '../config/skills.ts';
import { invoke, skillsOf } from './invoke.ts';

/** Stage `ship`: drain the epic into its own worktree and leave the final PR open. */
export const ship = (task: AgentTask): string[] => {
  const skill = skillsOf(task).ship.name;
  const solves = skill === solveSkills.ship; // the sentences that name Solve's own files hold only for Solve's skill
  return [
    solves
      ? `Invoke ${invoke(task, skill)} for epic #${task.epic} and tell it to worktree this epic, whatever mode the repo's solve.md has: the epic must live in its own git worktree. Leave the final integration PR open.`
      : `Invoke ${invoke(task, skill)} for epic #${task.epic}. The epic must live in its own git worktree, and the body of the final integration PR must close the epic (Closes #${task.epic}). Leave the final integration PR open.`,
    'Never merge the final PR: a person tests it and decides the merge.',
    // The headless CLI ends with the agent's turn and stops what is still running; the same for every harness.
    'Do not end your turn while a subagent or a background task of yours is still running: wait for it in the foreground. The run ends with your turn, and anything still running is stopped with it.',
    // Carrier may run on another machine: a file on someone's disk is not a source. The remote is the only shared channel.
    ...(solves
      ? ['The epic\'s design artifacts (spec, ADRs, glossary) must already be on the remote, on the epic branch or the base branch. Do not look for uncommitted files in other directories of this machine. If the epic refers to a spec or ADR that is not there, return needs_human naming what is missing.']
      : []),
  ];
};
