import { z } from 'zod';
import { defineTool } from '../mcp.ts';
import { chatCaps } from '../transcript.ts';

const name = z.string().min(1).max(100);

/** Starts a child session for another configured agent. It needs the `act` capability, which a child never has ([ADR 0033](../../../docs/adr/sessions/0033-an-agent-delegates-to-another-agent-through-child-sessions-and-every-delegation-asks-the-person.md)). */
export const delegateStart = defineTool({
  name: 'delegate_start',
  description:
    'Starts a child session for one of the configured chat agents (see the agents tool) with the task as its first message, in this session\'s folder, and answers its id at once without waiting for it to finish. ' +
    'Delegate only when the person asked for other agents; it needs no approval of its own. The child runs one task and takes no message after it, and never has more permission than this session: it runs at the level its agent is configured with, capped at this session\'s, and an agent configured with no permission takes this session\'s level (agents says which). ' +
    'Pass requestId (up to 64 characters) so that a retry after a lost reply returns the same child. At most four children of a session can be working or waiting for an approval at once.',
  access: 'actsAsSession',
  delegation: true,
  input: z.strictObject({ agent: name, task: z.string().min(1).max(chatCaps.message), model: name.optional(), requestId: z.string().min(1).max(64).optional() }),
  handler: (args, { sessionId, sessions }) => sessions.startChild(sessionId, args),
});

/** Waits for the caller's children and reads how each stands. The longest wait is under every MCP timeout found for Claude and Codex ([spec](../../../docs/specs/switch-and-delegate-between-agents.md)). */
export const delegateWait = defineTool({
  name: 'delegate_wait',
  description:
    'Waits for children started with delegate_start, up to timeoutMs (1000 to 45000, default 30000), and answers as soon as none of them is working; a child that waits for the person to approve something counts as stopped. ' +
    'Each child answers with its state: working, needs_approval (with waitingFor: the tool and command, or the question, of up to four things it waits for the person to approve, and more when there are others), done (with message, its last assistant text up to 4000 characters), error, usage_limit or interrupted. Call again while a child is working.',
  access: 'readsAsSession',
  input: z.strictObject({ childIds: z.array(z.string()).min(1).max(4), timeoutMs: z.int().min(1000).max(45000).optional() }),
  handler: async ({ childIds, timeoutMs = 30_000 }, { sessionId, sessions }) => ({ children: await sessions.waitChildren(sessionId, childIds, timeoutMs) }),
});
