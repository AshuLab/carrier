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
  /** Run on a local server through the harness's CLI instead of the cloud. */
  provider: z.enum(['lmstudio', 'ollama']).optional(),
  /** `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. Absolute once `~` is expanded. */
  configDir: z.string().min(1).transform(expandHome).optional(),
});

/** A way to run an agent. The harness's config folder holds its login, so `configDir` is what picks the account; without one the agent inherits the environment. */
const agentOption = z.strictObject({
  harness: z.enum(harnessNames),
  model: z.string().min(1),
  /** Run `model` on a local server through the harness's CLI instead of the cloud. */
  provider: z.enum(['lmstudio', 'ollama']).optional(),
  /** `CLAUDE_CONFIG_DIR` for Claude, `CODEX_HOME` for Codex. Absolute once `~` is expanded. */
  configDir: z.string().min(1).transform(expandHome).optional(),
});

/** The key of an option: stored and shown as is. */
export const optionNamePattern = /^[a-z][a-z0-9-]{0,39}$/;

// A role keeps its GitHub identity and persona, and points at an option by name, the way it points at a profile.
const agent = z.strictObject({
  persona: persona.optional(),
  profile: z.string().min(1),
  option: z.string().min(1),
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
  order: z.array(z.string()).optional(),
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
    /** The agents a chat can start with; without the block, `claude` and `codex` (see `chatAgents`). */
    chat: z
      .strictObject({
        agents: z.record(z.string().regex(chatAgentName, 'a chat agent name is lowercase letters, digits and hyphens, starting with a letter'), chatAgent),
      })
      .optional(),
    orchestratorProfile: z.string().min(1),
    providers: z.record(z.string(), aiProvider).optional(),
    agentOptions: z.record(z.string(), agentOption),
    agents: z.strictObject({ author: agent, reviewer: agent, leadReviewer: agent.optional() }),
    /** Off unless present and enabled. Moves a role to the next agent option upon usage_limit, rate_limit, or service_down. */
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

    const optionRefs: [(string | number)[], string][] = [
      [['agents', 'author', 'option'], config.agents.author.option],
      [['agents', 'reviewer', 'option'], config.agents.reviewer.option],
    ];
    if (config.agents.leadReviewer) optionRefs.push([['agents', 'leadReviewer', 'option'], config.agents.leadReviewer.option]);
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
        const option = repo.agents?.[role]?.option;
        if (option !== undefined) optionRefs.push([['repos', i, 'agents', role, 'option'], option]);
      }
    });
    for (const [path, name] of optionRefs) {
      if (!Object.hasOwn(config.agentOptions, name)) {
        ctx.addIssue({ code: 'custom', path, message: `option "${name}" is not declared in agentOptions` });
      }
    }

    if (config.failover?.enabled) {
      const hasDefault = (config.failover.default && config.failover.default.length > 0) || (config.failover.order && config.failover.order.length > 0);
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
        if (!Object.hasOwn(config.agentOptions, name)) {
          ctx.addIssue({ code: 'custom', path: p, message: `${label}: option "${name}" is not declared in agentOptions` });
        } else if (named.has(name)) {
          ctx.addIssue({ code: 'custom', path: p, message: `${label}: option "${name}" appears twice` });
        }
        named.add(name);
      });
    };

    if (config.failover) {
      checkFailoverList(config.failover.order, ['failover', 'order']);
      checkFailoverList(config.failover.default, ['failover', 'default']);
      if (config.failover.roles) {
        for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
          checkFailoverList(config.failover.roles[role], ['failover', 'roles', role]);
        }
      }
    }

    // What an option can have depends on its harness: a local provider and a config folder only where the CLI has a setting for them.
    for (const [name, option] of Object.entries(config.agentOptions)) {
      const where = `agentOptions.${name}`;
      if (!optionNamePattern.test(name)) {
        ctx.addIssue({ code: 'custom', path: ['agentOptions', name], message: `${where}: an option name is a lowercase word: letters, digits and hyphens, starting with a letter, up to 40 characters` });
      }
      if (option.provider !== undefined && !(localProvidersOf[option.harness] as readonly string[]).includes(option.provider)) {
        ctx.addIssue({ code: 'custom', path: ['agentOptions', name, 'provider'], message: `${where}: ${option.harness} cannot use the provider "${option.provider}"` });
      }
      if (option.configDir !== undefined && option.harness === 'agy') {
        ctx.addIssue({ code: 'custom', path: ['agentOptions', name, 'configDir'], message: `${where}: agy has no config folder setting, so it cannot have a configDir` });
      } else if (option.configDir !== undefined && option.configDir !== '' && !isAbsolute(option.configDir)) {
        ctx.addIssue({ code: 'custom', path: ['agentOptions', name, 'configDir'], message: `${where}: configDir must be an absolute path, or start with ~/ (got "${option.configDir}")` });
      }
    }

    if (config.providers !== undefined) {
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
    }

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
      if (resolved.author.profile === resolved.reviewer.profile) clash(['repos', i, 'agents'], `repo "${repo.name}": `, resolved.author.profile);
      else if (resolved.leadReviewer && resolved.author.profile === resolved.leadReviewer.profile) {
        clash(['repos', i, 'agents'], `repo "${repo.name}": `, resolved.author.profile, 'agents.author.profile', 'agents.leadReviewer.profile');
      }
    });
  });

export type Config = z.infer<typeof configSchema>;
