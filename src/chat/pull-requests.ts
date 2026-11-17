import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { createScopedLogger } from '@ashulab/universal-logger';

const log = createScopedLogger('chat');

export type PullRequestState = 'open' | 'draft' | 'merged' | 'closed';
export type PullRequestChecks = 'passing' | 'failing' | 'pending';
/** A pull request as a session's row says it: where it is, what state it is in and how its checks went (null when it has none). */
export type PullRequestInfo = { number: number; url: string; state: PullRequestState; checks: PullRequestChecks | null };

/** What the host takes of GitHub for the pull requests of its sessions, so a test injects a fake. Both go through the person's own `gh` login (ADR 0015) and say nothing when GitHub cannot be reached. */
export interface PullRequests {
  /** The pull request whose head is `branch` of `repo` (`owner/name`): the newest open one, else the newest. Null when there is none, or GitHub did not answer. */
  find(repo: string, branch: string): Promise<PullRequestInfo | null>;
  /** The state of each pull request, by `repo#number`; the ones GitHub did not answer for are left out. One request for all of them. */
  states(refs: { repo: string; number: number }[]): Promise<Map<string, PullRequestInfo>>;
}

export const pullRequestKey = (repo: string, number: number) => `${repo.toLowerCase()}#${number}`;

const FIELDS = `number url state isDraft commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }`;

type Node = { number?: unknown; url?: unknown; state?: unknown; isDraft?: unknown; headRepository?: { nameWithOwner?: unknown } | null; commits?: { nodes?: { commit?: { statusCheckRollup?: { state?: unknown } | null } }[] } };

const checksOf = (rollup: unknown): PullRequestChecks | null => {
  if (rollup === 'SUCCESS') return 'passing';
  if (rollup === 'FAILURE' || rollup === 'ERROR') return 'failing';
  if (rollup === 'PENDING' || rollup === 'EXPECTED') return 'pending';
  return null;
};

/** One GraphQL pull request node as the row says it; null for a node that is not one. */
export function infoOf(node: Node | null | undefined): PullRequestInfo | null {
  if (node === null || node === undefined || typeof node.number !== 'number' || typeof node.url !== 'string') return null;
  const state: PullRequestState = node.state === 'MERGED' ? 'merged' : node.state === 'CLOSED' ? 'closed' : node.state === 'OPEN' ? (node.isDraft === true ? 'draft' : 'open') : 'closed';
  return { number: node.number, url: node.url, state, checks: state === 'merged' || state === 'closed' ? null : checksOf(node.commits?.nodes?.[0]?.commit?.statusCheckRollup?.state) };
}

/** Of the pull requests a branch has had, the one to show: the newest open one (they come newest first), else the newest. Those from a fork of the repository are not the branch's. */
export function pickPullRequest(repo: string, nodes: Node[]): PullRequestInfo | null {
  const own = nodes.filter((node) => String(node.headRepository?.nameWithOwner ?? '').toLowerCase() === repo.toLowerCase());
  const infos = own.map(infoOf).filter((info): info is PullRequestInfo => info !== null);
  return infos.find((info) => info.state === 'open' || info.state === 'draft') ?? infos[0] ?? null;
}

const OWNER_NAME = /^([\w.-]+)\/([\w.-]+)$/;

/** `gh api graphql`, whose answer is read even when GitHub says some part of it failed (a pull request that is gone), which gh reports as a failure. */
async function graphql(query: string, variables: Record<string, string | number>, timeoutMs: number): Promise<any | null> {
  const args = ['api', 'graphql', '-f', `query=${query}`];
  for (const [name, value] of Object.entries(variables)) args.push(typeof value === 'number' ? '-F' : '-f', `${name}=${value}`);
  try {
    const { stdout } = await promisify(execFile)('gh', args, { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024 });
    return JSON.parse(stdout).data ?? null;
  } catch (error) {
    const { stdout, code, killed } = error as { stdout?: unknown; code?: unknown; killed?: boolean };
    // not logged with what gh printed: only that it failed
    log.debug('a pull request lookup failed', { code: typeof code === 'number' || typeof code === 'string' ? code : null, killed: killed === true });
    try {
      return typeof stdout === 'string' && stdout !== '' ? (JSON.parse(stdout).data ?? null) : null;
    } catch {
      return null;
    }
  }
}

/** The pull requests of GitHub as `gh` reads them for the person who is signed in. */
export function ghPullRequests(timeoutMs: number): PullRequests {
  return {
    async find(repo, branch) {
      const found = OWNER_NAME.exec(repo);
      if (found === null) return null;
      const data = await graphql(
        `query($owner: String!, $name: String!, $branch: String!) { repository(owner: $owner, name: $name) { pullRequests(headRefName: $branch, first: 10, orderBy: { field: CREATED_AT, direction: DESC }) { nodes { ${FIELDS} headRepository { nameWithOwner } } } } }`,
        { owner: found[1]!, name: found[2]!, branch },
        timeoutMs,
      );
      return pickPullRequest(repo, data?.repository?.pullRequests?.nodes ?? []);
    },

    async states(refs) {
      const valid = refs.filter((ref) => OWNER_NAME.test(ref.repo));
      const result = new Map<string, PullRequestInfo>();
      if (valid.length === 0) return result;
      // one alias per pull request, so a batch is one request and one that is gone leaves out only its own
      const declared = valid.map((_, i) => `$o${i}: String!, $n${i}: String!, $p${i}: Int!`).join(', ');
      const body = valid.map((_, i) => `r${i}: repository(owner: $o${i}, name: $n${i}) { pullRequest(number: $p${i}) { ${FIELDS} } }`).join(' ');
      const variables: Record<string, string | number> = {};
      valid.forEach((ref, i) => {
        const [, owner, name] = OWNER_NAME.exec(ref.repo)!;
        Object.assign(variables, { [`o${i}`]: owner!, [`n${i}`]: name!, [`p${i}`]: ref.number });
      });
      const data = await graphql(`query(${declared}) { ${body} }`, variables, timeoutMs);
      valid.forEach((ref, i) => {
        const info = infoOf(data?.[`r${i}`]?.pullRequest);
        if (info !== null) result.set(pullRequestKey(ref.repo, ref.number), info);
      });
      return result;
    },
  };
}
