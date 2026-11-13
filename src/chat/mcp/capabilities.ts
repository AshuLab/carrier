import { z } from 'zod';
import { defineTool } from '../mcp.ts';

/** What the calling session is and what is around it: its own row and live options, the configured agents and the verdicts of `health`. Nothing here says where a binary or a login lives. */
export const capabilities = defineTool({
  name: 'capabilities',
  description: 'The current chat session (id, agent, harness, folder, model, options), the configured chat agents with whether each is found and ready, and whether git and gh are ready.',
  access: 'readsAsSession',
  input: z.strictObject({}),
  handler: async (_args, { sessionId, sessions }) => {
    const health = await sessions.health();
    return {
      session: sessions.snapshot(sessionId),
      agents: sessions.agents().map((agent) => ({ ...agent, state: health.agents.find((verdict) => verdict.name === agent.name)?.state ?? 'unknown' })),
      environment: { git: health.git, gh: health.gh },
    };
  },
});
