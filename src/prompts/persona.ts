import type { AgentTask } from '../execution/agent-runner.ts';
import { slotOf, type Slot } from '../storage/executions.ts';

/** What the role is called to the person: the author, a reviewer (any of the extra ones too) or the lead. */
const roleTitle = (role: 'author' | Slot) => (role === 'author' ? 'Author' : role === 'lead' ? 'Lead reviewer' : 'Reviewer');

export const signatureOf = (role: 'author' | Slot, name?: string) => `🤖 ${roleTitle(role)}${name ? ` [${name}]` : ''} via Carrier`;

/** Who the user says this role is: its persona's name (the name line stays the persona's alone), then its prompt as written. Under a shared identity, the rule to sign what it publishes. */
export function personaLines(task: AgentTask): string[] {
  const { persona, sharedIdentity } = task;
  const signature = signatureOf(slotOf(task) ?? 'author', persona?.name || task.reviewerName); // an extra reviewer with no persona name signs with its own (`reviewerName` is set for extra reviewers only)
  return [
    ...(persona?.name ? [`Your name is ${persona.name}.`] : []),
    ...(persona?.prompt ? [persona.prompt] : []),
    ...(sharedIdentity
      ? [`The GitHub account you publish with is shared with the person running Carrier and with the other role. End everything you publish on GitHub with this signature on its own last line: review comments and bodies, the pull request body, replies on threads, and any other comment, issue or issue body you post. In a commit message make it the last line of the body, before any trailers such as Co-Authored-By: ${signature}`]
      : []),
  ];
}
