import { isObject } from '../../config/engine-edit.ts';

// What the wizard asks of a role; the rest of the role (its `skills`) stays as the file has it.
const askedOfRole = ['profile', 'provider', 'model', 'effort', 'persona'];
const askedOfExtra = [...askedOfRole, 'type', 'name', 'failover'];
const failoverRoles = ['author', 'reviewer', 'leadReviewer'];

const keepRole = (old: unknown, next: Record<string, unknown>, asked = askedOfRole) => ({ ...next, ...Object.fromEntries(Object.entries(isObject(old) ? old : {}).filter(([key]) => !asked.includes(key))) });

/**
 * The config an edit writes: `file` as it is, with only the keys the wizard owns replaced by `built` (what `buildConfig` makes from the answers).
 * Owned: `repos` (a repo that stays keeps its entry), `profiles` (set over the file's), `orchestratorProfile`, the failover of the author, the reviewer and the lead reviewer, and those three roles' profile, provider, model, effort and persona. `agents.extraReviewers` is owned too: replaced by the answers (each extra, found by its key, keeping the keys the wizard does not ask, such as its `skills`) and removed when there are none.
 */
export function keepRest(file: Record<string, unknown>, built: Record<string, unknown>): Record<string, unknown> {
  const kept = Array.isArray(file.repos) ? file.repos.filter(isObject) : [];
  const repos = (built.repos as { name: string }[]).map((repo) => kept.find((entry) => entry.name === repo.name) ?? repo);
  const [oldAgents, agents] = [isObject(file.agents) ? file.agents : {}, built.agents as Record<string, Record<string, unknown>>];
  const { leadReviewer: _removed, extraReviewers: oldExtras, ...otherAgents } = oldAgents;
  const [oldFailover, failover] = [isObject(file.failover) ? file.failover : {}, isObject(built.failover) ? built.failover : {}];
  const oldRoles = isObject(oldFailover.roles) ? oldFailover.roles : {};
  const roles = { ...Object.fromEntries(Object.entries(oldRoles).filter(([key]) => !failoverRoles.includes(key))), ...(isObject(failover.roles) ? failover.roles : {}) };
  const { roles: _old, ...failoverRest } = { ...failover, ...oldFailover }; // the file's triggers win over the answers'
  const nextFailover = { ...failoverRest, ...(Object.keys(roles).length > 0 && { roles }) };
  const { failover: _failover, ...rest } = file;
  return {
    ...rest,
    repos,
    profiles: { ...(isObject(file.profiles) ? file.profiles : {}), ...(built.profiles as Record<string, unknown>) },
    orchestratorProfile: built.orchestratorProfile,
    ...(Object.keys(nextFailover).length > 0 && { failover: nextFailover }),
    agents: {
      ...otherAgents,
      author: keepRole(oldAgents.author, agents.author!),
      reviewer: keepRole(oldAgents.reviewer, agents.reviewer!),
      ...(agents.extraReviewers && { extraReviewers: Object.fromEntries(Object.entries(agents.extraReviewers as Record<string, Record<string, unknown>>).map(([key, extra]) => [key, keepRole(isObject(oldExtras) ? oldExtras[key] : undefined, extra, askedOfExtra)])) }),
      ...(agents.leadReviewer && { leadReviewer: keepRole(oldAgents.leadReviewer, agents.leadReviewer) }),
    },
  };
}
