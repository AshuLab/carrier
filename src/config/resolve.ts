import type { HarnessName } from '../harnesses/names.ts';
import { runtimeOf, type AccountRuntime } from './providers.ts';
import type { Config } from './schema.ts';
import { resolveReviewSkills, resolveSkills, type ResolvedSkills, type ReviewSkills } from './skills.ts';

// What an agent runs with: the role (profile, persona, model) and the provider it points at (harness, configDir, local server).
export type Agent = {
  profile: string;
  harness: HarnessName;
  model: string;
  provider?: 'lmstudio' | 'ollama';
  configDir?: string;
  persona?: Config['agents']['author']['persona'];
  effort?: Config['agents']['author']['effort'];
  option?: string;
  providerName?: string;
} & AccountRuntime;

/** The lead reviewer: an agent that also keeps whether its profile is the author's (`sharedIdentity`, saved only when it is). */
export type LeadReviewer = Agent & { sharedIdentity?: true };

/** A reviewer beyond the mandatory one, with its key (its identity in the file), name and type, the review skills it resolved, the failover steps it declared (none: the reviewer role's) and whether its profile is the author's (`sharedIdentity`, saved only when it is). */
export type ExtraReviewer = Agent & { key: string; name: string; type: string; skills: ReviewSkills; failover?: NonNullable<NonNullable<Config['failover']>['roles']>['reviewer']; sharedIdentity?: true };

// Only profile names, never credentials: Agent Forge resolves those from the profile at run time.
// `sharedIdentity` is saved with the epic so a later config change does not move it; absent on epics saved before it existed.
// `providers` is the directory of AI providers as it was when the epic was reserved, what a choice picks from.
// `failover` is saved too, for the same reason: a config edit moves no running epic.
export type EffectiveRepoConfig = {
  name: string;
  sharedIdentity?: boolean;
  providers?: Config['providers'];
  options?: Record<string, { harness: HarnessName; model?: string; configDir?: string; provider?: 'lmstudio' | 'ollama' }>;
  failover?: Config['failover'];
  /** Saved with the epic; absent on epics saved before it existed (`savedSkills` reads those as Solve's defaults). */
  skills?: ResolvedSkills;
  /** `extraReviewers` is absent on an epic saved before it existed: one reviewer. */
  agents: { author: Agent; reviewer: Agent; leadReviewer?: LeadReviewer; extraReviewers?: ExtraReviewer[] };
};

// Two names can point at the same bot or at the same `gh` login: what matters is the account that posts.
export const sameAccount = (a: Config['profiles'][string], b: Config['profiles'][string]) => a.kind === b.kind && (a.kind === 'gh' || a.agent === (b as typeof a).agent);

/** The steps a role moves through when its login runs out; none means no failover for it. */
export const failoverStepsFor = (failover: Config['failover'], role: 'author' | 'reviewer' | 'leadReviewer') =>
  failover?.roles?.[role] ?? (role === 'leadReviewer' ? failover?.roles?.reviewer : undefined) ?? []; // the lead takes the reviewer's steps when it declares none

// Each repo inherits the global value of every field it does not override.
export function resolveRepoConfig(config: Config, repo: Config['repos'][number]): EffectiveRepoConfig {
  const agentOf = (merged: Partial<Omit<Config['agents']['author'], 'skills'>>) => {
    if (!merged.profile) return undefined;
    const providerConfig = merged.provider ? config.providers[merged.provider] : undefined;
    return {
      profile: merged.profile,
      harness: providerConfig?.harness ?? ('claude' as HarnessName),
      model: merged.model ?? providerConfig?.model ?? '',
      ...(providerConfig?.provider && { provider: providerConfig.provider }),
      ...(providerConfig?.configDir && { configDir: providerConfig.configDir }),
      ...(providerConfig && runtimeOf(providerConfig)),
      ...(merged.persona && { persona: merged.persona }),
      ...(merged.effort && { effort: merged.effort }),
      option: merged.provider,
      providerName: merged.provider,
    } as Agent;
  };
  const roleOf = (role: 'author' | 'reviewer' | 'leadReviewer') => {
    const base = config.agents[role];
    const repoAgent = repo.agents?.[role];
    return base || repoAgent ? agentOf({ ...(base ?? {}), ...(repoAgent ?? {}) }) : undefined;
  };
  const authorAgent = roleOf('author')!;
  const authorProfile = config.profiles[authorAgent?.profile];
  const sharesAuthor = (profile: string) => authorProfile !== undefined && config.profiles[profile] !== undefined && sameAccount(authorProfile, config.profiles[profile]!);
  const leadAgent = roleOf('leadReviewer');
  const leadReviewer = leadAgent && { ...leadAgent, ...(sharesAuthor(leadAgent.profile) && { sharedIdentity: true as const }) };
  // A repo's map replaces the global one whole, an empty one included; the list keeps the order of the map.
  const extraReviewers = Object.entries(repo.agents?.extraReviewers ?? config.agents.extraReviewers ?? {}).map(([key, extra]): ExtraReviewer => ({
    ...agentOf(extra)!,
    key,
    name: extra.name,
    type: extra.type,
    skills: resolveReviewSkills('review', config.skills, repo.skills, extra.skills?.review),
    ...(extra.failover && { failover: extra.failover }),
    ...(sharesAuthor(extra.profile) && { sharedIdentity: true as const }),
  }));
  const agents = { author: authorAgent, reviewer: roleOf('reviewer')!, ...(leadReviewer ? { leadReviewer } : {}), ...(extraReviewers.length > 0 ? { extraReviewers } : {}) };
  const [author, reviewer] = [authorProfile, config.profiles[agents.reviewer?.profile]];
  return {
    name: repo.name,
    sharedIdentity: author !== undefined && reviewer !== undefined && sameAccount(author, reviewer),
    providers: config.providers,
    ...(config.failover && { failover: config.failover }),
    skills: {
      ...resolveSkills(config.skills, repo.skills, config.agents.author.skills, config.agents.reviewer.skills, repo.agents?.author?.skills, repo.agents?.reviewer?.skills),
      ...(leadReviewer && { lead: resolveReviewSkills('lead', config.skills, repo.skills, config.agents.leadReviewer?.skills?.lead, repo.agents?.leadReviewer?.skills?.lead) }),
    },
    agents,
  };
}
