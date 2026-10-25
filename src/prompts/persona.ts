import type { AgentTask } from '../execution/agent-runner.ts';

export const signatureOf = (role: 'author' | 'reviewer', name?: string) =>
  `🤖 ${role === 'author' ? 'Author' : 'Reviewer'}${name ? ` [${name}]` : ''} via Carrier`;

/** Who the user says this role is: its name, then its prompt as written. Under a shared identity, the rule to sign what it publishes. */
export function persona({ persona, sharedIdentity, stage }: AgentTask): string[] {
  const signature = signatureOf(stage === 'review' ? 'reviewer' : 'author', persona?.name);
  return [
    ...(persona?.name ? [`Your name is ${persona.name}.`] : []),
    ...(persona?.prompt ? [persona.prompt] : []),
    ...(sharedIdentity
      ? [`The GitHub account you publish with is shared with the person running Carrier and with the other role. End every review comment, every review body, the pull request body and every reply on a thread with this signature on its own last line, and make it the last line of every commit message: ${signature}`]
      : []),
  ];
}
