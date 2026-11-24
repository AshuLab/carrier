import { LogLevel } from '@ashulab/universal-logger';
import { z } from 'zod';
import { labelRoles, stageNames } from '../orchestration/github.ts';
import { needsHumanKinds } from '../storage/schema.ts';
import { accounts } from './providers.ts';

/** `owner/name`, each part a plain folder name: the managed clone lives in `repos/<owner>/<name>`. */
export const repoNamePattern = /^(?!\.{1,2}\/)(?!.*\/\.{1,2}$)[\w.-]+\/[\w.-]+$/;

/** Who the agent of a role says it is: a one-line name (it ends up in GitHub text) and a prompt. A repo's persona replaces the global one whole. */
export const persona = z.strictObject({
  name: z.string().trim().min(1).max(40).regex(/^[^\r\n]+$/).optional(),
  prompt: z.string().trim().min(1).max(4000).optional(),
});

/** The name of a skill, as the prompt spells it after `/` or `$`: one token, no path, no blanks, no shell characters. */
const skillNamePattern = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$/;
const skillName = z.string().regex(skillNamePattern, 'must be a skill name: letters, digits, "_", ".", ":" or "-", at most 64 characters, starting with a letter or a digit');

const shipSkills = { ship: skillName.optional(), fix: skillName.optional() };
const reviewSkill = z.strictObject({ review: skillName.optional(), publish: skillName.nullable().optional() }).optional();
const reviewSkills = { review: reviewSkill };
const leadSkills = { lead: reviewSkill };
/** The skills of a repo, merged by key onto the global ones. */
const skillsLevel = z.strictObject({ ...shipSkills, ...reviewSkills, ...leadSkills });

export const efforts = ['low', 'medium', 'high', 'xhigh', 'max'] as const;

// A role keeps its GitHub identity and persona, and points at an AI provider and model.
const agentFields = {
  persona: persona.optional(),
  profile: z.string().min(1),
  provider: z.string().min(1),
  model: z.string().min(1),
  effort: z.enum(efforts).optional(),
};
// A role names only the stages it runs.
const author = z.strictObject({ ...agentFields, skills: z.strictObject(shipSkills).optional() });
const reviewer = z.strictObject({ ...agentFields, skills: z.strictObject(reviewSkills).optional() });
const leadReviewer = z.strictObject({ ...agentFields, skills: z.strictObject(leadSkills).optional() });

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

/** One place to move to: an account of `providers.json` and optionally the model to run there and how hard it thinks (left out, the effort the role was running with). */
const step = z.strictObject(
  { provider: z.string().min(1), model: z.string().min(1).optional(), effort: z.enum(efforts).optional() },
  { error: (issue) => (issue.code === 'invalid_type' && issue.expected === 'object' ? `a failover step is { "provider": "<account>", "model": "<optional>", "effort": "<optional>" }, not a name` : undefined) },
);

/** A reviewer beyond the mandatory one: the fields of any agent, the review skills and its own failover steps. A repo's list replaces the whole list, so each entry carries profile, provider and model. */
const extraReviewer = z.strictObject({ ...agentFields, skills: z.strictObject(reviewSkills).optional(), failover: z.array(step).optional() });
const extraReviewers = z.array(extraReviewer).max(3, 'at most three extra reviewers: a fourth is refused');

const failoverSchema = z.strictObject(
  {
    triggers: z.array(z.enum(failoverTriggers)).min(1).optional(),
    roles: z.strictObject({ author: z.array(step).optional(), reviewer: z.array(step).optional(), leadReviewer: z.array(step).optional() }).optional(),
  },
  { error: (issue) => (issue.code === 'unrecognized_keys' && issue.keys.some((key) => key === 'enabled' || key === 'default') ? `failover.enabled and failover.default are gone: ${newFailoverShape}` : undefined) },
);

/** A label name: one line without commas (a comma splits the GitHub query), at most 50 characters. */
const labelName = z.string().trim().min(1).max(50).regex(/^[^,\p{Cc}]+$/u, 'must be one line without commas or control characters');

export const configSchema = z
  .strictObject({
    pollIntervalMinutes: z.number().positive(),
    /** The labels by role. `epic` and `ready` are written by Solve and people, `running`, `readyForTest` and `needsHuman` by Carrier. Each one differs from the others. */
    labels: z.strictObject({
      epic: labelName,
      ready: labelName,
      running: labelName,
      readyForTest: labelName,
      needsHuman: labelName,
      /** A label per stage while an epic runs, written by Carrier; a stage left out has none. */
      stages: z.partialRecord(z.enum(stageNames), labelName).optional(),
      /** A label per kind of stop while an epic waits for a person, written by Carrier; a kind left out has none. */
      reasons: z.partialRecord(z.enum(needsHumanKinds), labelName).optional(),
    }),
    finishedWindowDays: z.int().min(1).max(30),
    logLevel: z.enum(LogLevel),
    repos: z
      .array(
        z.strictObject({
          name: z.string().regex(repoNamePattern, 'must be owner/name'),
          agents: z.strictObject({ author: author.partial(), reviewer: reviewer.partial(), extraReviewers, leadReviewer: leadReviewer.partial().optional() }).partial().optional(),
          skills: skillsLevel.optional(),
        }),
      ),
    profiles: z.record(z.string(), profile),
    /** Left out, it is the author's profile (ADR 0021). */
    orchestratorProfile: z.string().min(1).optional(),
    /** Not a key of `engine.json`: the loader puts here what `providers.json` declares (ADR 0020). */
    providers: accounts,
    agents: z.strictObject({ author, reviewer, extraReviewers: extraReviewers.optional(), leadReviewer: leadReviewer.optional() }),
    /** The skill each stage runs: ship, review (with the one that publishes, or `null` for a review skill that publishes by itself) and fix. */
    skills: z.strictObject({
      ship: skillName,
      review: z.strictObject({ review: skillName, publish: skillName.nullable() }),
      fix: skillName,
      /** The lead reviewer's skill; what it leaves out is taken from `review`. */
      lead: reviewSkill,
    }),
    /** A role with a non-empty list of steps moves to the next one upon usage_limit, rate_limit, or service_down. */
    failover: failoverSchema.optional(),
    limits: z.strictObject({
      maxConcurrentEpics: z.int().positive(),
      maxReviews: z.int().positive(),
      /** Reviews of the lead reviewer's own exchange with the author before the epic goes to a person. */
      maxLeadRounds: z.int().positive(),
      maxExecutionRetries: z.int().nonnegative(),
      maxExecutionHours: z.union([z.literal('unlimited'), z.int().positive()]),
      githubCallTimeoutSeconds: z.int().positive(),
      idleMinutes: z.int().positive().optional(),
      autoResume: z.boolean(),
      autoResumeMaxHours: z.number().positive(),
    }, { error: (issue) => (issue.code === 'unrecognized_keys' && issue.keys.includes('optionChoiceSeconds') ? 'limits.optionChoiceSeconds is gone: an epic starts at once on its roles and waits for no choice. Remove it' : undefined) }),
  })
  .superRefine((config, ctx) => {
    // GitHub compares labels without case: two roles on one label would make an epic's status unreadable.
    const named: [(string | number)[], string][] = [
      ...labelRoles.map((role) => [['labels', role], config.labels[role]] as [(string | number)[], string]),
      ...Object.entries(config.labels.stages ?? {}).map(([stage, name]) => [['labels', 'stages', stage], name] as [(string | number)[], string]),
      ...Object.entries(config.labels.reasons ?? {}).map(([kind, name]) => [['labels', 'reasons', kind], name] as [(string | number)[], string]),
    ];
    const taken = new Map<string, string>();
    for (const [path, name] of named) {
      const first = taken.get(name.toLowerCase());
      if (first === undefined) taken.set(name.toLowerCase(), path.join('.'));
      else ctx.addIssue({ code: 'custom', path, message: `is the same label as ${first}: each role needs its own` });
    }
    const refs: [(string | number)[], string][] = [
      ...(config.orchestratorProfile === undefined ? [] : ([[['orchestratorProfile'], config.orchestratorProfile]] as [(string | number)[], string][])),
      [['agents', 'author', 'profile'], config.agents.author.profile],
      [['agents', 'reviewer', 'profile'], config.agents.reviewer.profile],
    ];
    if (config.agents.leadReviewer) refs.push([['agents', 'leadReviewer', 'profile'], config.agents.leadReviewer.profile]);
    config.agents.extraReviewers?.forEach((extra, j) => refs.push([['agents', 'extraReviewers', j, 'profile'], extra.profile]));
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
        const profile = repo.agents?.[role]?.profile;
        if (profile !== undefined) refs.push([['repos', i, 'agents', role, 'profile'], profile]);
      }
      repo.agents?.extraReviewers?.forEach((extra, j) => refs.push([['repos', i, 'agents', 'extraReviewers', j, 'profile'], extra.profile]));
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
    config.agents.extraReviewers?.forEach((extra, j) => providerRefs.push([['agents', 'extraReviewers', j, 'provider'], extra.provider]));
    config.repos.forEach((repo, i) => {
      for (const role of ['author', 'reviewer', 'leadReviewer'] as const) {
        const provider = repo.agents?.[role]?.provider;
        if (provider !== undefined) providerRefs.push([['repos', i, 'agents', role, 'provider'], provider]);
      }
      repo.agents?.extraReviewers?.forEach((extra, j) => providerRefs.push([['repos', i, 'agents', 'extraReviewers', j, 'provider'], extra.provider]));
    });
    for (const [path, name] of providerRefs) {
      if (!Object.hasOwn(config.providers, name)) {
        ctx.addIssue({ code: 'custom', path, message: `provider "${name}" is not declared in providers` });
      }
    }

    // The steps of a list, each against the account it moves from: `path` is where the list is, `label` how the message names it.
    const checkSteps = (steps: z.infer<typeof step>[] | undefined, own: { provider: string; model: string } | undefined, path: (string | number)[], label: string) => {
      const seen = new Set<string>();
      steps?.forEach(({ provider, model }, i) => {
        if (provider === '') return; // already refused by the step's own shape
        const key = JSON.stringify([provider, model]);
        const at = [...path, i];
        if (!Object.hasOwn(config.providers, provider)) ctx.addIssue({ code: 'custom', path: [...at, 'provider'], message: `${label}.${i}.provider: "${provider}" is not declared in providers` });
        else if (seen.has(key)) ctx.addIssue({ code: 'custom', path: at, message: `${label}.${i}: step repeats another step of the list` });
        else if (own?.provider === provider && own.model === model) ctx.addIssue({ code: 'custom', path: at, message: `${label}.${i}: step is the role's own provider and model, so it would move nowhere` });
        seen.add(key);
      });
    };
    for (const role of ['author', 'reviewer', 'leadReviewer'] as const) checkSteps(config.failover?.roles?.[role], config.agents[role], ['failover', 'roles', role], `failover.roles.${role}`);
    config.agents.extraReviewers?.forEach((extra, j) => checkSteps(extra.failover, extra, ['agents', 'extraReviewers', j, 'failover'], `agents.extraReviewers.${j}.failover`));
    config.repos.forEach((repo, i) => repo.agents?.extraReviewers?.forEach((extra, j) => checkSteps(extra.failover, extra, ['repos', i, 'agents', 'extraReviewers', j, 'failover'], `repos.${i}.agents.extraReviewers.${j}.failover`)));

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
