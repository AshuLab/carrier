import { LogLevel } from '@ashulab/universal-logger';
import { z } from 'zod';
import { accounts } from './providers.ts';

/** `owner/name`, each part a plain folder name: the managed clone lives in `repos/<owner>/<name>`. */
export const repoNamePattern = /^(?!\.{1,2}\/)(?!.*\/\.{1,2}$)[\w.-]+\/[\w.-]+$/;

/** Who the agent of a role says it is: a one-line name (it ends up in GitHub text) and a prompt. A repo's persona replaces the global one whole. */
export const persona = z.strictObject({
  name: z.string().trim().min(1).max(40).regex(/^[^\r\n]+$/).optional(),
  prompt: z.string().trim().min(1).max(4000).optional(),
});

export const efforts = ['low', 'medium', 'high', 'xhigh', 'max'] as const;

// A role keeps its GitHub identity and persona, and points at an AI provider and model.
const agent = z.strictObject({
  persona: persona.optional(),
  profile: z.string().min(1),
  provider: z.string().min(1),
  model: z.string().min(1),
  effort: z.enum(efforts).optional(),
});

// The two shapes the spike fixed (docs/research/agent-forge.md): a bot through Agent Forge, or the user's own `gh` login. No secrets here.
const profile = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('forge'), agent: z.string().min(1) }),
  z.strictObject({ kind: z.literal('gh') }),
]);

export const failoverTriggers = ['usage_limit', 'rate_limit', 'service_down'] as const;
export type FailoverTrigger = (typeof failoverTriggers)[number];

export function matchesFailoverTrigger(
  triggers: readonly FailoverTrigger[],
  failureKind: string | null | undefined,
  failureDetail?: string | null,
): boolean {
  if (!failureKind) return false;
  if (triggers.includes('usage_limit') && failureKind === 'usage_limit') return true;
  const isRateLimit = failureKind === 'api_error' && (failureDetail?.includes('429') || /rate[-_ ]?limit|overloaded/i.test(failureDetail ?? ''));
  if (triggers.includes('rate_limit') && isRateLimit) return true;
  if (triggers.includes('service_down') && (failureKind === 'spawn_error' || (failureKind === 'api_error' && !isRateLimit))) return true;
  return false;
}

const newFailoverShape = 'a role has failover when its list of steps is not empty: "failover": { "roles": { "author": [{ "provider": "<account>", "model": "<optional>" }] } }';

/** One place to move to: an account of `providers.json` and optionally the model to run there. */
const step = z.strictObject(
  { provider: z.string().min(1), model: z.string().min(1).optional() },
  { error: (issue) => (issue.code === 'invalid_type' && issue.expected === 'object' ? `a failover step is { "provider": "<account>", "model": "<optional>" }, not a name` : undefined) },
);

const failoverSchema = z.strictObject(
  {
    triggers: z.array(z.enum(failoverTriggers)).min(1).optional(),
    roles: z.strictObject({ author: z.array(step).optional(), reviewer: z.array(step).optional(), leadReviewer: z.array(step).optional() }).optional(),
  },
  { error: (issue) => (issue.code === 'unrecognized_keys' && issue.keys.some((key) => key === 'enabled' || key === 'default') ? `failover.enabled and failover.default are gone: ${newFailoverShape}` : undefined) },
);

export const configSchema = z
  .strictObject({
    pollIntervalMinutes: z.number().positive(),
    finishedWindowDays: z.int().min(1).max(30),
    logLevel: z.enum(LogLevel),
    repos: z
      .array(
        z.strictObject({
          name: z.string().regex(repoNamePattern, 'must be owner/name'),
          agents: z.strictObject({ author: agent.partial(), reviewer: agent.partial(), leadReviewer: agent.partial().optional() }).partial().optional(),
        }),
      )
      .min(1),
    profiles: z.record(z.string(), profile),
    /** Left out, it is the author's profile (ADR 0021). */
    orchestratorProfile: z.string().min(1).optional(),
    /** Not a key of `config.json`: the loader puts here what `providers.json` declares (ADR 0020). */
    providers: accounts,
    agents: z.strictObject({ author: agent, reviewer: agent, leadReviewer: agent.optional() }),
    /** A role with a non-empty list of steps moves to the next one upon usage_limit, rate_limit, or service_down. */
    failover: failoverSchema.optional(),
    limits: z.strictObject({
      maxConcurrentEpics: z.int().positive(),
      maxReviews: z.int().positive(),
      maxExecutionRetries: z.int().nonnegative(),
      maxExecutionHours: z.union([z.literal('unlimited'), z.int().positive()]),
      githubCallTimeoutSeconds: z.int().positive(),
    }, { error: (issue) => (issue.code === 'unrecognized_keys' && issue.keys.includes('optionChoiceSeconds') ? 'limits.optionChoiceSeconds is gone: an epic starts at once on its roles and waits for no choice. Remove it' : undefined) }),
  })
  .superRefine((config, ctx) => {
    const refs: [(string | number)[], string][] = [
      ...(config.orchestratorProfile === undefined ? [] : ([[['orchestratorProfile'], config.orchestratorProfile]] as [(string | number)[], string][])),
      [['agents', 'author', 'profile'], config.agents.author.profile],
      [['agents', 'reviewer', 'profile'], config.agents.reviewer.profile],
    ];
    if (config.agents.leadReviewer) refs.push([['agents', 'leadReviewer', 'profile'], config.agents.leadReviewer.profile]);
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
        const profile = repo.agents?.[role]?.profile;
        if (profile !== undefined) refs.push([['repos', i, 'agents', role, 'profile'], profile]);
      }
    });
    for (const [path, name] of refs) {
      if (!(name in config.profiles)) {
        ctx.addIssue({ code: 'custom', path, message: `profile "${name}" is not declared in profiles` });
      }
    }

    const providerRefs: [(string | number)[], string][] = [
      [['agents', 'author', 'provider'], config.agents.author.provider],
      [['agents', 'reviewer', 'provider'], config.agents.reviewer.provider],
    ];
    if (config.agents.leadReviewer) providerRefs.push([['agents', 'leadReviewer', 'provider'], config.agents.leadReviewer.provider]);
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
        const provider = repo.agents?.[role]?.provider;
        if (provider !== undefined) providerRefs.push([['repos', i, 'agents', role, 'provider'], provider]);
      }
    });
    for (const [path, name] of providerRefs) {
      if (!Object.hasOwn(config.providers, name)) {
        ctx.addIssue({ code: 'custom', path, message: `provider "${name}" is not declared in providers` });
      }
    }

    for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
      const own = config.agents[role];
      const label = `failover.roles.${role}`;
      const seen = new Set<string>();
      config.failover?.roles?.[role]?.forEach(({ provider, model }, i) => {
        if (provider === '') return; // already refused by the step's own shape
        const key = JSON.stringify([provider, model]);
        const path = ['failover', 'roles', role, i];
        if (!Object.hasOwn(config.providers, provider)) ctx.addIssue({ code: 'custom', path: [...path, 'provider'], message: `${label}.${i}.provider: "${provider}" is not declared in providers` });
        else if (seen.has(key)) ctx.addIssue({ code: 'custom', path, message: `${label}.${i}: step repeats another step of the list` });
        else if (own?.provider === provider && own.model === model) ctx.addIssue({ code: 'custom', path, message: `${label}.${i}: step is the role's own provider and model, so it would move nowhere` });
        seen.add(key);
      });
    }

    // Solve's worktrees are `worktrees/<repo>/<feature>`, with no owner: same-name repos would share paths.
    const seen = new Map<string, string>();
    config.repos.forEach((repo, i) => {
      const folder = repo.name.split('/').pop()!.toLowerCase();
      const first = seen.get(folder);
      if (first === undefined) seen.set(folder, repo.name);
      else ctx.addIssue({ code: 'custom', path: ['repos', i, 'name'], message: `repo "${repo.name}" has the same folder name as "${first}"; Solve's worktree paths have no owner` });

      if (repo.agents?.leadReviewer && !config.agents.leadReviewer) {
        for (const field of ['provider', 'profile', 'model'] as const) {
          if (!repo.agents.leadReviewer[field]) {
            ctx.addIssue({
              code: 'custom',
              path: ['repos', i, 'agents', 'leadReviewer', field],
              message: `repo "${repo.name}": agents.leadReviewer.${field} is required when no top-level agents.leadReviewer is configured`,
            });
          }
        }
      }
    });
  })
  .transform((config) => ({ ...config, orchestratorProfile: config.orchestratorProfile ?? config.agents.author.profile }));

export type Config = z.infer<typeof configSchema>;
