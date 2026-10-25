import type { AgentTask } from '../execution/agent-runner.ts';

/** Who the user says this role is: its name, then its prompt as written. Nothing without a persona. */
export function persona({ persona }: AgentTask): string[] {
  return [...(persona?.name ? [`Your name is ${persona.name}.`] : []), ...(persona?.prompt ? [persona.prompt] : [])];
}
