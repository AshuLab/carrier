import { homedir } from 'node:os';
import { join } from 'node:path';
import { z } from 'zod';

const expandHome = (path: string) =>
  path === '~' || path.startsWith('~/') ? join(homedir(), path.slice(1)) : path;

const agent = z.strictObject({
  profile: z.string().min(1),
  provider: z.enum(['claude', 'codex']),
  model: z.string().min(1),
});

export const configSchema = z
  .strictObject({
    root: z.string().min(1).transform(expandHome),
    pollIntervalMinutes: z.number().positive(),
    repos: z.array(z.looseObject({ name: z.string().min(1) })).min(1),
    profiles: z.record(z.string(), z.looseObject({})),
    orchestratorProfile: z.string().min(1),
    agents: z.strictObject({ author: agent, reviewer: agent }),
    limits: z.strictObject({
      maxConcurrentEpics: z.int().positive(),
      maxReviews: z.int().positive(),
      maxExecutionRetries: z.int().nonnegative(),
      maxExecutionHours: z.union([z.literal('unlimited'), z.int().positive()]),
      githubCallTimeoutSeconds: z.int().positive(),
    }),
  })
  .superRefine((config, ctx) => {
    const refs: [(string | number)[], string][] = [
      [['orchestratorProfile'], config.orchestratorProfile],
      [['agents', 'author', 'profile'], config.agents.author.profile],
      [['agents', 'reviewer', 'profile'], config.agents.reviewer.profile],
    ];
    for (const [path, name] of refs) {
      if (!(name in config.profiles)) {
        ctx.addIssue({ code: 'custom', path, message: `profile "${name}" is not declared in profiles` });
      }
    }
  });

export type Config = z.infer<typeof configSchema>;
