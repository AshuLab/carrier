import { localKinds, type LocalProvider } from '../../harnesses/local.ts';
import { harnessNames, type HarnessName } from '../../harnesses/names.ts';

export type Identity = { kind: 'forge'; agent: string } | { kind: 'gh' };
export type Role = { identity: Identity; harness: HarnessName; model: string; provider?: LocalProvider };
export type Answers = { repos: string[]; author: Role; reviewer: Role };

/** `forge:<agent>` or `gh`, the form used by flags and by the prompts' values. */
export function parseIdentity(text: string): Identity {
  if (text === 'gh') return { kind: 'gh' };
  const agent = /^forge:(.+)$/.exec(text)?.[1];
  if (agent !== undefined) return { kind: 'forge', agent };
  throw new Error(`invalid identity "${text}", expected "forge:<agent>" or "gh"`);
}

export const identityText = (identity: Identity) => (identity.kind === 'gh' ? 'gh' : `forge:${identity.agent}`);

/** `<harness>:<model>`, the harness being one of `harnessNames`. */
export function parseHarnessModel(text: string): Pick<Role, 'harness' | 'model'> {
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
export function buildConfig({ repos, author, reviewer }: Answers) {
  const [a, r] = [profileName(author.identity), profileName(reviewer.identity)];
  return {
    repos: repos.map((name) => ({ name })),
    profiles: { [a]: author.identity, [r]: reviewer.identity },
    orchestratorProfile: a,
    agents: {
      author: { profile: a, harness: author.harness, model: author.model, ...(author.provider && { provider: author.provider }) },
      reviewer: { profile: r, harness: reviewer.harness, model: reviewer.model, ...(reviewer.provider && { provider: reviewer.provider }) },
    },
  };
}
