import { homedir } from 'node:os';
import { join } from 'node:path';
import { z } from 'zod';
import { resolveRepoConfig } from './resolve.ts';

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
    repos: z
      .array(
        z.strictObject({
          name: z.string().min(1),
          agents: z.strictObject({ author: agent.partial(), reviewer: agent.partial() }).partial().optional(),
        }),
      )
      .min(1),
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
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer'] as const) {
        const profile = repo.agents?.[role]?.profile;
        if (profile !== undefined) refs.push([['repos', i, 'agents', role, 'profile'], profile]);
      }
    });
    for (const [path, name] of refs) {
      if (!(name in config.profiles)) {
        ctx.addIssue({ code: 'custom', path, message: `profile "${name}" is not declared in profiles` });
      }
    }

    // Author and reviewer must differ, globally and for each repo once its overrides are applied.
    // A global clash is reported once, not again for every repo that inherits it.
    const clash = (path: (string | number)[], where: string, profile: string) =>
      ctx.addIssue({
        code: 'custom',
        path,
        message: `${where}agents.author.profile and agents.reviewer.profile must differ, both are "${profile}"`,
      });
    if (config.agents.author.profile === config.agents.reviewer.profile) {
      clash(['agents'], '', config.agents.author.profile);
      return;
    }
    config.repos.forEach((repo, i) => {
      const { author, reviewer } = resolveRepoConfig(config, repo).agents;
      if (author.profile === reviewer.profile) clash(['repos', i, 'agents'], `repo "${repo.name}": `, author.profile);
    });
  });

export type Config = z.infer<typeof configSchema>;
