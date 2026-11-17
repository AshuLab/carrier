import { z } from 'zod';
import { defineTool } from '../mcp.ts';
import { chatCaps } from '../transcript.ts';

const name = z.string().min(1).max(100);

/** Starts a child session for another configured agent. It needs the `act` capability, which a child never has ([ADR 0033](../../../docs/adr/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)). */
export const delegateStart = defineTool({
  name: 'delegate_start',
  description:
    'Starts a child session for one of the configured chat agents (see the agents tool) with the task as its first message, in this session\'s folder, and answers its id at once without waiting for it to finish. ' +
    'The child runs one task and takes no message after it, and never has more permission than this session. ' +
    'Pass requestId (up to 64 characters) so that a retry after a lost reply returns the same child. At most four children of a session can be working or waiting for an approval at once.',
  access: 'actsAsSession',
  input: z.strictObject({ agent: name, task: z.string().min(1).max(chatCaps.message), model: name.optional(), requestId: z.string().min(1).max(64).optional() }),
  handler: (args, { sessionId, sessions }) => sessions.startChild(sessionId, args),
});
