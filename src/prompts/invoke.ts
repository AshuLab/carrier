import type { AgentTask } from '../execution/agent-runner.ts';

/** How a harness spells "run this skill": Claude Code and Antigravity expand /skill, Codex $skill. */
export const invoke = (task: AgentTask, skill: string) => `${task.harness === 'codex' ? '$' : '/'}${skill}`;
