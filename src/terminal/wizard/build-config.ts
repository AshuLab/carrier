import { localKinds, type LocalProvider } from '../../harnesses/local.ts';
import type { Config } from '../../config/schema.ts';
import { harnessNames, type HarnessName } from '../../harnesses/names.ts';

export type Identity = { kind: 'forge'; agent: string } | { kind: 'gh' };
export type Persona = NonNullable<Config['agents']['author']['persona']>;
export type AgentOption = Config['agentOptions'][string];
export type Failover = NonNullable<Config['failover']>;
export type Role = { identity: Identity; option: string; persona?: Persona };
export type Identities = 'separate' | 'shared';
export type Answers = { repos: string[]; author: Role; reviewer: Role; options: Record<string, AgentOption>; failover?: Failover; identities?: Identities };

/** `forge:<agent>` or `gh`, the form used by flags and by the prompts' values. */
export function parseIdentity(text: string): Identity {
  if (text === 'gh') return { kind: 'gh' };
  const agent = /^forge:(.+)$/.exec(text)?.[1];
  if (agent !== undefined) return { kind: 'forge', agent };
  throw new Error(`invalid identity "${text}", expected "forge:<agent>" or "gh"`);
}

export const identityText = (identity: Identity) => (identity.kind === 'gh' ? 'gh' : `forge:${identity.agent}`);

/** `<harness>:<model>`, the harness being one of `harnessNames`. */
export function parseHarnessModel(text: string): Pick<AgentOption, 'harness' | 'model'> {
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

/** The user config (what goes in the file): only what has no default. The author's profile also acts as orchestrator. */
export function buildConfig({ repos, author, reviewer, options, failover, identities }: Answers) {
  const [a, r] = [profileName(author.identity), profileName(reviewer.identity)];
  return {
    repos: repos.map((name) => ({ name })),
    ...(identities === 'shared' && { identities }), // the default, separate, is not written
    profiles: { [a]: author.identity, [r]: reviewer.identity },
    orchestratorProfile: a,
    agentOptions: options,
    ...(failover && { failover }),
    agents: {
      author: { profile: a, option: author.option, ...(author.persona && { persona: author.persona }) },
      reviewer: { profile: r, option: reviewer.option, ...(reviewer.persona && { persona: reviewer.persona }) },
    },
  };
}
