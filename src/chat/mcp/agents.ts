import { z } from 'zod';
import { childOptions, isScaleHarness, levelOf, scaleOptions } from '../levels.ts';
import { defineTool } from '../mcp.ts';
import { createScopedLogger } from '@ashulab/universal-logger';

const log = createScopedLogger('chat');

/** The configured agents with their state, the level each would have as a child of the calling session and, when asked, what each one's harness lists as models and reasoning efforts. */
export const agents = defineTool({
  name: 'agents',
  description:
    'Lists the configured chat agents: each one\'s name, harness, whether it is found, its state, and childLevel, the permission level (0 reads only, 1 changes and asks before each change, 2 edits without asking) it would run at as a child of this session. ' +
    'When this session\'s own options are off the permission scale, notOffered says why and there is no childLevel. ' +
    'Pass models: true to also get each agent\'s models and reasoning efforts; it starts each agent briefly, so it is slower.',
  access: 'readsAsSession',
  input: z.strictObject({ models: z.boolean().optional() }),
  handler: async ({ models = false }, { sessionId, sessions }) => {
    const caller = sessions.snapshot(sessionId);
    const callerLevel = isScaleHarness(caller.harness) ? levelOf(caller.harness, caller.options) : undefined;
    const notOffered =
      callerLevel === undefined
        ? `This session's options (${Object.entries(isScaleHarness(caller.harness) ? scaleOptions(caller.harness, caller.options) : caller.options).map(([id, value]) => `${id} ${value}`).join(', ')}) are off the permission scale, so a child cannot be given a level`
        : undefined;
    const health = await sessions.health();
    return {
      agents: await Promise.all(
        sessions.agents().map(async ({ name, harness, found }) => {
          const level = callerLevel !== undefined && isScaleHarness(harness) ? childOptions(harness, sessions.agentOptions(name), callerLevel).level : undefined;
          const offered = models ? await listModels(sessions.offer, name, found) : {};
          return { name, harness, found, state: health.agents.find((verdict) => verdict.name === name)?.state ?? 'unknown', ...(level !== undefined && { childLevel: level }), ...(notOffered !== undefined && { notOffered }), ...offered };
        }),
      ),
    };
  },
});

/** What the option probe lists for one agent; a probe that fails, or an agent that is not found, leaves them out and says so (the cause stays in the log). */
async function listModels(offer: (name: string) => Promise<{ id: string; values: { id: string; label: string }[] }[]>, name: string, found: boolean) {
  if (found === false) return { modelsUnavailable: 'This agent is not found on this machine' };
  try {
    const options = await offer(name);
    return { models: options.find((option) => option.id === 'model')?.values.map(({ id, label }) => ({ id, label })) ?? [], efforts: options.find((option) => option.id === 'effort')?.values.map(({ id }) => id) ?? [] };
  } catch (error) {
    log.error(`listing the models of the agent ${name} failed`, error);
    return { modelsUnavailable: 'The models of this agent could not be listed' };
  }
}
