import { homedir } from 'node:os';
import { isAbsolute, join } from 'node:path';
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

/** An AI provider account / connection without a model. */
export const aiProvider = z.strictObject({
  harness: z.enum(harnessNames),
  /** Optional default model for this provider connection. */
  model: z.string().min(1).optional(),
  /** Run on a local server through the harness's CLI instead of the cloud. */
  provider: z.enum(['lmstudio', 'ollama']).optional(),
  /** `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. Absolute once `~` is expanded. */
  configDir: z.string().min(1).transform(expandHome).optional(),
});

/** The key of a provider or option: stored and shown as is. */
export const optionNamePattern = /^[a-z][a-z0-9-]{0,39}$/;

// A role keeps its GitHub identity and persona, and points at an AI provider and model.
const agent = z.strictObject({
  persona: persona.optional(),
  profile: z.string().min(1),
  provider: z.string().min(1),
  model: z.string().min(1),
});

// The two shapes the spike fixed (docs/research/agent-forge.md): a bot through Agent Forge, or the user's own `gh` login. No secrets here.
const profile = z.discriminatedUnion('kind', [
  z.strictObject({ kind: z.literal('forge'), agent: z.string().min(1) }),
  z.strictObject({ kind: z.literal('gh') }),
]);

/** An agent a chat can start with. Narrower than the engine's harnesses: Antigravity is not offered. */
const chatAgent = z.strictObject({
  harness: z.enum(['claude', 'codex']),
  /** The binary, when it is not the one on the path. */
  command: z.string().min(1).optional(),
  model: z.string().min(1).optional(),
  /** Default options of the provider, by the provider's own option id. */
  options: z.record(z.string(), z.string()).optional(),
});

const chatAgentName = /^[a-z][a-z0-9-]*$/;

export const failoverTriggers = ['usage_limit', 'rate_limit', 'service_down'] as const;
export type FailoverTrigger = (typeof failoverTriggers)[number];

const failoverSchema = z.strictObject({
  enabled: z.boolean(),
  triggers: z.array(z.enum(failoverTriggers)).min(1).optional(),
  default: z.array(z.string()).optional(),
  roles: z
    .strictObject({
      author: z.array(z.string()).optional(),
      reviewer: z.array(z.string()).optional(),
      leadReviewer: z.array(z.string()).optional(),
    })
    .partial()
    .optional(),
});

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
          agents: z.strictObject({ author: agent.partial(), reviewer: agent.partial(), leadReviewer: agent.partial().optional() }).partial().optional(),
        }),
      )
      .min(1),
    profiles: z.record(z.string(), profile),
    /** The agents a chat can start with (without them, `claude` and `codex`, see `chatAgents`) and the folder it brings projects into (without it, `<root>/chat/projects`). */
    chat: z
      .strictObject({
        agents: z.record(z.string().regex(chatAgentName, 'a chat agent name is lowercase letters, digits and hyphens, starting with a letter'), chatAgent).optional(),
        projectsFolder: z.string().min(1).transform(expandHome).refine(isAbsolute, 'must be an absolute path, or start with ~/').optional(),
      })
      .optional(),
    orchestratorProfile: z.string().min(1),
    providers: z.record(z.string(), aiProvider),
    agents: z.strictObject({ author: agent, reviewer: agent, leadReviewer: agent.optional() }),
    /** Off unless present and enabled. Moves a role to the next AI provider upon usage_limit, rate_limit, or service_down. */
    failover: failoverSchema.optional(),
    limits: z.strictObject({
      maxConcurrentEpics: z.int().positive(),
      maxReviews: z.int().positive(),
      maxExecutionRetries: z.int().nonnegative(),
      maxExecutionHours: z.union([z.literal('unlimited'), z.int().positive()]),
      githubCallTimeoutSeconds: z.int().positive(),
      /** How long a reserved epic waits for its choice of agent options when there are two or more. */
      optionChoiceSeconds: z.int().positive(),
    }),
  })
  .superRefine((config, ctx) => {
    const refs: [(string | number)[], string][] = [
      [['orchestratorProfile'], config.orchestratorProfile],
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

    if (config.failover?.enabled) {
      const hasDefault = config.failover.default && config.failover.default.length > 0;
      const hasRoles = config.failover.roles && Object.values(config.failover.roles).some((r) => r && r.length > 0);
      if (!hasDefault && !hasRoles) {
        ctx.addIssue({ code: 'custom', path: ['failover'], message: 'failover is enabled but has neither a default nor role-specific fallback order' });
      }
    }

    const checkFailoverList = (list: string[] | undefined, basePath: (string | number)[]) => {
      if (!list) return;
      const named = new Set<string>();
      list.forEach((name, i) => {
        const p = [...basePath, i];
        const label = basePath.join('.');
        if (!Object.hasOwn(config.providers, name)) {
          ctx.addIssue({ code: 'custom', path: p, message: `${label}: provider "${name}" is not declared in providers` });
        } else if (named.has(name)) {
          ctx.addIssue({ code: 'custom', path: p, message: `${label}: provider "${name}" appears twice` });
        }
        named.add(name);
      });
    };

    if (config.failover) {
      checkFailoverList(config.failover.default, ['failover', 'default']);
      if (config.failover.roles) {
        for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
          checkFailoverList(config.failover.roles[role], ['failover', 'roles', role]);
        }
      }
    }

    for (const [name, p] of Object.entries(config.providers)) {
      const where = `providers.${name}`;
      if (!optionNamePattern.test(name)) {
        ctx.addIssue({ code: 'custom', path: ['providers', name], message: `${where}: a provider name is a lowercase word: letters, digits and hyphens, starting with a letter, up to 40 characters` });
      }
      if (p.provider !== undefined && !(localProvidersOf[p.harness] as readonly string[]).includes(p.provider)) {
        ctx.addIssue({ code: 'custom', path: ['providers', name, 'provider'], message: `${where}: ${p.harness} cannot use the provider "${p.provider}"` });
      }
      if (p.configDir !== undefined && p.harness === 'agy') {
        ctx.addIssue({ code: 'custom', path: ['providers', name, 'configDir'], message: `${where}: agy has no config folder setting, so it cannot have a configDir` });
      } else if (p.configDir !== undefined && p.configDir !== '' && !isAbsolute(p.configDir)) {
        ctx.addIssue({ code: 'custom', path: ['providers', name, 'configDir'], message: `${where}: configDir must be an absolute path, or start with ~/ (got "${p.configDir}")` });
      }
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

    // Under separate identities, author and reviewer must differ, globally and for each repo once its overrides are applied.
    if (config.identities !== 'separate') return;
    // A global clash is reported once, not again for every repo that inherits it.
    const clash = (path: (string | number)[], where: string, profile: string, role1 = 'agents.author.profile', role2 = 'agents.reviewer.profile') =>
      ctx.addIssue({
        code: 'custom',
        path,
        message: `${where}${role1} and ${role2} must differ, both are "${profile}" (or set identities to "shared" to use one account for both)`,
      });
    if (config.agents.author.profile === config.agents.reviewer.profile) {
      clash(['agents'], '', config.agents.author.profile);
      return;
    }
    if (config.agents.leadReviewer && config.agents.author.profile === config.agents.leadReviewer.profile) {
      clash(['agents'], '', config.agents.author.profile, 'agents.author.profile', 'agents.leadReviewer.profile');
      return;
    }
    config.repos.forEach((repo, i) => {
      const resolved = resolveRepoConfig(config, repo).agents;
      if (!resolved.author || !resolved.reviewer) return;
      if (resolved.author.profile === resolved.reviewer.profile) clash(['repos', i, 'agents'], `repo "${repo.name}": `, resolved.author.profile);
      else if (resolved.leadReviewer && resolved.author.profile === resolved.leadReviewer.profile) {
        clash(['repos', i, 'agents'], `repo "${repo.name}": `, resolved.author.profile, 'agents.author.profile', 'agents.leadReviewer.profile');
      }
    });
  });

export type Config = z.infer<typeof configSchema>;
