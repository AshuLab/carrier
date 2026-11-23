import { defaultSkills } from '../config/skills.ts';
import type { AgentTask } from '../execution/agent-runner.ts';

/** How a harness spells "run this skill": Claude Code and Antigravity expand /skill, Codex $skill. */
export const invoke = (task: AgentTask, skill: string) => `${task.harness === 'codex' ? '$' : '/'}${skill}`;

/** The skills a task invokes; a task with none reads Solve's defaults. */
export const skillsOf = (task: AgentTask) => task.skills ?? defaultSkills;
