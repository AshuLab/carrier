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
    /** The agents a chat can start with (without them, `claude` and `codex`, see `chatAgents`) and the folder it brings projects into (without it, `<root>/chat/projects`). */
    chat: z
      .strictObject({
        agents: z.record(z.string().regex(chatAgentName, 'a chat agent name is lowercase letters, digits and hyphens, starting with a letter'), chatAgent).optional(),
        projectsFolder: z.string().min(1).transform(expandHome).refine(isAbsolute, 'must be an absolute path, or start with ~/').optional(),
      })
      .optional(),
    orchestratorProfile: z.string().min(1),
    agentOptions: z.record(z.string(), agentOption),
    agents: z.strictObject({ author: agent, reviewer: agent }),
    /** Off unless present and enabled. `order` is an allowlist: a role that runs out of credits only ever moves to a name in it. */
    failover: z.strictObject({ enabled: z.boolean(), order: z.array(z.string()) }).optional(),
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

    const optionRefs: [(string | number)[], string][] = [
      [['agents', 'author', 'option'], config.agents.author.option],
      [['agents', 'reviewer', 'option'], config.agents.reviewer.option],
    ];
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer'] as const) {
        const option = repo.agents?.[role]?.option;
        if (option !== undefined) optionRefs.push([['repos', i, 'agents', role, 'option'], option]);
      }
    });
    for (const [path, name] of optionRefs) {
      if (!Object.hasOwn(config.agentOptions, name)) {
        ctx.addIssue({ code: 'custom', path, message: `option "${name}" is not declared in agentOptions` });
      }
    }

    const named = new Set<string>();
    config.failover?.order.forEach((name, i) => {
      if (!Object.hasOwn(config.agentOptions, name)) ctx.addIssue({ code: 'custom', path: ['failover', 'order', i], message: `failover.order: option "${name}" is not declared in agentOptions` });
      else if (named.has(name)) ctx.addIssue({ code: 'custom', path: ['failover', 'order', i], message: `failover.order: option "${name}" appears twice` });
      named.add(name);
    });

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
