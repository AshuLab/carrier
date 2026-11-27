import { localKinds, type LocalProvider } from '../../harnesses/local.ts';
import type { Providers } from '../../config/providers.ts';
import type { Config } from '../../config/schema.ts';
import { harnessNames, type HarnessName } from '../../harnesses/names.ts';

export type Identity = { kind: 'forge'; agent: string } | { kind: 'gh' };
export type Persona = NonNullable<Config['agents']['author']['persona']>;
export type AIProvider = Providers[string];
export type Failover = NonNullable<Config['failover']>;
export type Effort = NonNullable<Config['agents']['author']['effort']>;
export type Role = { identity: Identity; provider: string; model: string; effort?: Effort; persona?: Persona };
/** An extra reviewer: its key in the file (the one the file has for it, or one derived from its name when it is new), what it is called and what it looks at, a role, and its own failover steps (none meaning the Reviewer's). */
export type Extra = { key: string; name: string; type: string; role: Role; failover?: { provider: string; model?: string }[] };
export type Answers = { repos: string[]; orchestrator?: Identity; author: Role; reviewer: Role; extraReviewers?: Extra[]; leadReviewer?: Role; failover?: Failover };

/** `forge:<agent>` or `gh`, the form used by flags and by the prompts' values. */
export function parseIdentity(text: string): Identity {
  if (text === 'gh') return { kind: 'gh' };
  const agent = /^forge:(.+)$/.exec(text)?.[1];
  if (agent !== undefined) return { kind: 'forge', agent };
  throw new Error(`invalid profile "${text}", expected "forge:<agent>" or "gh"`);
}

export const identityText = (identity: Identity) => (identity.kind === 'gh' ? 'gh' : `forge:${identity.agent}`);

/** `<harness>:<model>`, the harness being one of `harnessNames`. */
export function parseHarnessModel(text: string): { harness: HarnessName; model: string } {
  const match = new RegExp(`^(${harnessNames.join('|')}):(.+)$`).exec(text);
  if (match === null) throw new Error(`invalid agent "${text}", expected "<harness>:<model>" with harness one of ${harnessNames.join(", ")}`);
  return { harness: match[1] as HarnessName, model: match[2]! };
}

export function parseProvider(text: string): LocalProvider {
  const local = localKinds.find((kind) => kind === text);
  if (local === undefined) throw new Error(`invalid provider "${text}", expected ${localKinds.join(' or ')}`);
  return local;
}

// A forge profile is named after its agent; the user's own login is just "gh".
const profileName = (identity: Identity) => (identity.kind === 'gh' ? 'gh' : identity.agent);

/** The user config (what goes in the file): only what has no default, and not the accounts, which go in `providers.json`. Without an `orchestrator` answer the author's profile acts as orchestrator. */
export function buildConfig({ repos, orchestrator, author, reviewer, extraReviewers = [], leadReviewer, failover }: Answers) {
  const [a, r] = [profileName(author.identity), profileName(reviewer.identity)];
  const o = profileName(orchestrator ?? author.identity);
  const l = leadReviewer ? profileName(leadReviewer.identity) : undefined;
  return {
    repos: repos.map((name) => ({ name })),
    profiles: {
      [a]: author.identity,
      [r]: reviewer.identity,
      [o]: orchestrator ?? author.identity,
      ...Object.fromEntries(extraReviewers.map(({ role }) => [profileName(role.identity), role.identity])),
      ...(l && leadReviewer ? { [l]: leadReviewer.identity } : {}),
    },
    orchestratorProfile: o,
    ...(failover && { failover }),
    agents: {
      author: {
        profile: a,
        provider: author.provider,
        model: author.model,
        ...(author.effort && { effort: author.effort }),
        ...(author.persona && { persona: author.persona }),
      },
      reviewer: {
        profile: r,
        provider: reviewer.provider,
        model: reviewer.model,
        ...(reviewer.effort && { effort: reviewer.effort }),
        ...(reviewer.persona && { persona: reviewer.persona }),
      },
      ...(extraReviewers.length > 0 && {
        extraReviewers: Object.fromEntries(
          extraReviewers.map(({ key, name, type, role, failover: steps }) => [
            key,
            {
              type,
              name,
              profile: profileName(role.identity),
              provider: role.provider,
              model: role.model,
              ...(role.effort && { effort: role.effort }),
              ...(role.persona && { persona: role.persona }),
              ...(steps && steps.length > 0 && { failover: steps }),
            },
          ]),
        ),
      }),
      ...(leadReviewer && l ? {
        leadReviewer: {
          profile: l,
          provider: leadReviewer.provider,
          model: leadReviewer.model,
          ...(leadReviewer.effort && { effort: leadReviewer.effort }),
          ...(leadReviewer.persona && { persona: leadReviewer.persona }),
        },
      } : {}),
    },
  };
}
