import { localKinds, type Local } from '../providers/local.ts';

export type Identity = { kind: 'forge'; agent: string } | { kind: 'gh' };
export type Role = { identity: Identity; provider: 'claude' | 'codex'; model: string; local?: Local };
export type Answers = { repos: string[]; author: Role; reviewer: Role };

/** `forge:<agent>` or `gh`, the form used by flags and by the prompts' values. */
export function parseIdentity(text: string): Identity {
  if (text === 'gh') return { kind: 'gh' };
  const agent = /^forge:(.+)$/.exec(text)?.[1];
  if (agent !== undefined) return { kind: 'forge', agent };
  throw new Error(`invalid identity "${text}", expected "forge:<agent>" or "gh"`);
}

export const identityText = (identity: Identity) => (identity.kind === 'gh' ? 'gh' : `forge:${identity.agent}`);

/** `<claude|codex>:<model>`. */
export function parseProviderModel(text: string): Pick<Role, 'provider' | 'model'> {
  const match = /^(claude|codex):(.+)$/.exec(text);
  if (match === null) throw new Error(`invalid agent "${text}", expected "claude:<model>" or "codex:<model>"`);
  return { provider: match[1] as 'claude' | 'codex', model: match[2]! };
}

export function parseLocal(text: string): Local {
  const local = localKinds.find((kind) => kind === text);
  if (local === undefined) throw new Error(`invalid local server "${text}", expected ${localKinds.join(' or ')}`);
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
      author: { profile: a, provider: author.provider, model: author.model, ...(author.local && { local: author.local }) },
      reviewer: { profile: r, provider: reviewer.provider, model: reviewer.model, ...(reviewer.local && { local: reviewer.local }) },
    },
  };
}
