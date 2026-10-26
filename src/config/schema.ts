import { homedir } from 'node:os';
import { join } from 'node:path';
import { LogLevel } from '@ashulab/universal-logger';
import { z } from 'zod';
import { harnessNames, localProvidersOf } from '../harnesses/names.ts';
import { resolveRepoConfig } from './resolve.ts';

const expandHome = (path: string) =>
  path === '~' || path.startsWith('~/') ? join(homedir(), path.slice(1)) : path;

/** `owner/name`, each part a plain folder name: the managed clone lives in `repos/<owner>/<name>`. */
export const repoNamePattern = /^(?!\.{1,2}\/)(?!.*\/\.{1,2}$)[\w.-]+\/[\w.-]+$/;

/** Who the agent of a role says it is: a one-line name (it ends up in GitHub text) and a prompt. A repo's persona replaces the global one whole. */
export const persona = z.strictObject({
  name: z.string().trim().min(1).max(40).regex(/^[^\r\n]+$/).optional(),
  prompt: z.string().trim().min(1).max(4000).optional(),
});

const agent = z.strictObject({
  persona: persona.optional(),
  profile: z.string().min(1),
  harness: z.enum(harnessNames),
  model: z.string().min(1),
  /** Run `model` on a local server through the harness's CLI instead of the cloud. A repo override cannot unset it: override the model and harness together. */
  provider: z.enum(['lmstudio', 'ollama']).optional(),
});

// The two shapes the spike fixed (docs/research/agent-forge.md): a bot through Agent Forge, or the user's own `gh` login. No secrets here.
const profile = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('forge'), agent: z.string().min(1) }),
  z.strictObject({ kind: z.literal('gh') }),
]);

export const configSchema = z
  .strictObject({
    root: z.string().min(1).transform(expandHome),
    pollIntervalMinutes: z.number().positive(),
    finishedWindowDays: z.int().min(1).max(30),
    logLevel: z.enum(LogLevel),
    /** `shared`: the author and the reviewer may be the same GitHub profile (ADR 0011). */
    identities: z.enum(['separate', 'shared']),
    repos: z
      .array(
        z.strictObject({
          name: z.string().regex(repoNamePattern, 'must be owner/name'),
          agents: z.strictObject({ author: agent.partial(), reviewer: agent.partial() }).partial().optional(),
        }),
      )
      .min(1),
    profiles: z.record(z.string(), profile),
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

    // A local provider only for a harness that can be pointed at one, globally and per repo once overrides are applied.
    const providerCheck = (path: (string | number)[], where: string, agent: { harness: keyof typeof localProvidersOf; provider?: string }) => {
      if (agent.provider !== undefined && !(localProvidersOf[agent.harness] as readonly string[]).includes(agent.provider)) {
        ctx.addIssue({ code: 'custom', path, message: `${where}${agent.harness} cannot use the provider "${agent.provider}"` });
      }
    };
    for (const role of ['author', 'reviewer'] as const) providerCheck(['agents', role, 'provider'], '', config.agents[role]);
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer'] as const) {
        if (repo.agents?.[role]?.provider !== undefined || repo.agents?.[role]?.harness !== undefined) providerCheck(['repos', i, 'agents', role], `repo "${repo.name}": `, resolveRepoConfig(config, repo).agents[role]);
      }
    });

    // Solve's worktrees are `worktrees/<repo>/<feature>`, with no owner: same-name repos would share paths.
    const seen = new Map<string, string>();
    config.repos.forEach((repo, i) => {
      const folder = repo.name.split('/').pop()!.toLowerCase();
      const first = seen.get(folder);
      if (first === undefined) seen.set(folder, repo.name);
      else ctx.addIssue({ code: 'custom', path: ['repos', i, 'name'], message: `repo "${repo.name}" has the same folder name as "${first}"; Solve's worktree paths have no owner` });
    });

    // Under separate identities, author and reviewer must differ, globally and for each repo once its overrides are applied.
    if (config.identities !== 'separate') return;
    // A global clash is reported once, not again for every repo that inherits it.
    const clash = (path: (string | number)[], where: string, profile: string) =>
      ctx.addIssue({
        code: 'custom',
        path,
        message: `${where}agents.author.profile and agents.reviewer.profile must differ, both are "${profile}" (or set identities to "shared" to use one account for both)`,
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
