import { z } from 'zod';
import type { AgentTask } from '../execution/agent-runner.ts';
import type { GitHubProfile } from '../integrations/github.ts';
import type { HostRunnerOptions } from './host-runner.ts';

export interface CredentialsOptions {
  profiles: Record<string, GitHubProfile>;
  /** A fresh token of the profile; Forge picks the App installation from the owner of `repo`. */
  mint: (profile: GitHubProfile, repo: string) => Promise<string>;
  /** Numeric GitHub id of the bot `<agent>[bot]`: the noreply commit email carries it. */
  botId?: (agent: string, token: string) => Promise<number>;
}

const botUser = z.object({ id: z.int().positive() });

/** The id of a bot account from GitHub's public users endpoint (as Forge computes it), asked once per agent. */
export function botIdFromGitHub(fetchImpl: typeof fetch = fetch): (agent: string, token: string) => Promise<number> {
  const known = new Map<string, number>();
  return async (agent, token) => {
    const cached = known.get(agent);
    if (cached !== undefined) return cached;
    const response = await fetchImpl(`https://api.github.com/users/${encodeURIComponent(`${agent}[bot]`)}`, {
      headers: { authorization: `Bearer ${token}`, accept: 'application/vnd.github+json' },
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) throw new Error(`GitHub answered HTTP ${response.status} for the user ${agent}[bot]`);
    const { id } = botUser.parse(await response.json());
    known.set(agent, id);
    return id;
  };
}

/**
 * What each execution gets: the token of its profile (minted for this execution, handed to the child process
 * only) and, for a Forge bot, the commit identity `<agent>[bot]`, which Forge exports only in its interactive
 * mode. A `{kind:'gh'}` profile is the user's own login: `gh` as it is, no identity override.
 * Any failure rejects; the runner reports that as `auth_failed`, since the run cannot start without a token.
 */
export function profileCredentials({ profiles, mint, botId = botIdFromGitHub() }: CredentialsOptions): HostRunnerOptions['credentials'] {
  return async (task: AgentTask) => {
    const profile = profiles[task.profile];
    if (!profile) throw new Error(`profile "${task.profile}" is not declared`);
    const githubToken = await mint(profile, task.repo);
    if (profile.kind === 'gh') return { githubToken };
    const name = `${profile.agent}[bot]`;
    return { githubToken, gitIdentity: { name, email: `${await botId(profile.agent, githubToken)}+${name}@users.noreply.github.com` } };
  };
}
