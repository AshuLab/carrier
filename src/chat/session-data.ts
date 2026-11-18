import { eq } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import type { Git } from './git.ts';
import { pullRequestKey, type PullRequestChecks, type PullRequestInfo, type PullRequests, type PullRequestState } from './pull-requests.ts';
import { sessions } from './schema.ts';
import { resolveOrigin } from './workspace.ts';

const log = createScopedLogger('chat');

type Found = typeof sessions.$inferSelect;

/** What a session changed on disk: lines added and removed. */
export type DiffStat = { added: number; removed: number };
/** The pull request a session is linked to, as a row says it. */
export type SessionPullRequest = { repo: string; number: number; url: string; state: PullRequestState; checks: PullRequestChecks | null };

/** The most a list asks of git and GitHub at once, so a long list never becomes a burst of commands. */
const MAX_SESSIONS = 40;
/** The least between two sweeps of a list, however often it is asked for. */
export const SWEEP_EVERY_MS = 15_000;
/** How long a diff is believed while a list is asked for it, and how long the state of an open pull request is. */
export const DIFF_TTL_MS = 60_000;
export const STATE_TTL_MS = 60_000;
/** The least between two looks for the pull request of a session that has none: its turn ending looks at once. */
export const DISCOVER_EVERY_MS = 180_000;
const GIT_TIMEOUT_MS = 10_000;

/** What runs from the repository's own configuration (an external diff, a text filter) stays out of a read that only counts lines. */
const SAFE_DIFF = ['--no-ext-diff', '--no-textconv', '--no-renames'];

/** `git diff --numstat` output as a count: a binary file (`-`) counts 0, and no change at all is nothing to say (null). */
export function parseNumstat(out: string): DiffStat | null {
  let added = 0;
  let removed = 0;
  for (const line of out.split('\n')) {
    const [a, r] = line.split('\t');
    added += Number(a) || 0;
    removed += Number(r) || 0;
  }
  return added + removed === 0 ? null : { added, removed };
}

const isOpen = (state: string | null) => state === 'open' || state === 'draft';

/**
 * What a session's row says of its work besides the conversation: how many lines it changed (git, on this Mac) and its pull request (GitHub,
 * through the person's own `gh`). Neither is asked for in the middle of a `list`: the list answers with what is known, and a sweep it starts
 * in the background, at most every fifteen seconds, fills in the rest for the next one. A pull request is looked for once per session and then
 * kept; only its state is asked again, by number and for all the open ones in one request. A merged or closed one is final.
 */
export function createSessionData({ db, git, pulls, clock }: { db: ChatDb; git: Git; pulls: PullRequests; clock: Clock }) {
  const diffs = new Map<string, { stat: DiffStat | null; at: number }>();
  const discoveredAt = new Map<string, number>();
  let sweptAt = Number.NEGATIVE_INFINITY;
  let sweeping = false;

  const out = async (folder: string, args: string[]) => {
    const result = await git.run(folder, args, { timeoutMs: GIT_TIMEOUT_MS });
    return result.ok ? result.out.trim() : null;
  };

  /** The branch the session works on (null while detached) and where it was cut from or merges into, to count lines against. */
  async function whereOf(found: Found) {
    const worktree = found.workspaceKind === 'worktree';
    const originFolder = worktree ? (found.worktreeBase ?? found.folder) : found.folder;
    const origin = await out(originFolder, ['remote', 'get-url', 'origin']); // as git resolves it, `insteadOf` included
    const parsed = origin === null ? null : await resolveOrigin(git, origin);
    const branch = worktree ? found.worktreeBranch : await out(found.folder, ['rev-parse', '--abbrev-ref', 'HEAD']);
    const head = await out(originFolder, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD']);
    return {
      repo: parsed === null ? null : `${parsed.owner}/${parsed.name}`,
      branch: branch === null || branch === 'HEAD' ? null : branch,
      defaultBranch: head === null ? 'main' : head.replace(/^origin\//, ''),
    };
  }

  /** The commit the work is counted from: where a worktree was cut from, where a folder on its own branch left the default one, else what is committed. */
  async function baseOf(found: Found, where: { branch: string | null; defaultBranch: string }) {
    const from = found.workspaceKind === 'worktree' ? found.worktreeFrom : where.branch !== null && where.branch !== where.defaultBranch ? where.defaultBranch : null;
    if (from === null) return 'HEAD';
    for (const ref of [from, `origin/${from}`]) {
      const base = await out(found.folder, ['merge-base', ref, 'HEAD']);
      if (base !== null && base !== '') return base;
    }
    return 'HEAD';
  }

  // ponytail: `git diff` leaves the files git does not track out of the count; `git add -N` would change the person's index, so they are not counted
  async function refreshDiff(found: Found) {
    const where = await whereOf(found);
    const numstat = await out(found.folder, ['diff', '--numstat', ...SAFE_DIFF, await baseOf(found, where), '--']);
    diffs.set(found.id, { stat: numstat === null ? null : parseNumstat(numstat), at: clock.now() });
  }

  const link = (id: string, repo: string, info: PullRequestInfo) => {
    db.update(sessions).set({ prRepo: repo, prNumber: info.number, prUrl: info.url, prState: info.state, prChecks: info.checks, prCheckedAt: clock.now() }).where(eq(sessions.id, id)).run();
  };

  /** Looks for the pull request of the branch the session works on; a session that has one keeps it unless it is merged or closed and a newer one is open on the same branch. */
  async function discover(found: Found) {
    discoveredAt.set(found.id, clock.now());
    const where = await whereOf(found);
    if (where.repo === null) log.debug('no GitHub repository to look for a pull request in', { session: found.id }); // not the remote: it can hold a token
    if (where.repo === null || where.branch === null || where.branch === where.defaultBranch) return;
    const info = await pulls.find(where.repo, where.branch);
    if (info === null) return;
    if (found.prNumber === null) return link(found.id, where.repo, info);
    if (isOpen(found.prState) === false && isOpen(info.state) && info.number !== found.prNumber) link(found.id, where.repo, info);
  }

  /** The state of the open pull requests of these sessions, one request for all. */
  async function refreshStates(rows: Found[]) {
    const linked = rows.filter((found) => found.prNumber !== null && found.prRepo !== null && isOpen(found.prState));
    if (linked.length === 0) return;
    const states = await pulls.states(linked.map((found) => ({ repo: found.prRepo!, number: found.prNumber! })));
    for (const found of linked) {
      const info = states.get(pullRequestKey(found.prRepo!, found.prNumber!));
      if (info !== undefined) link(found.id, found.prRepo!, info);
    }
  }

  async function sweep(rows: Found[]) {
    const now = clock.now();
    for (const found of rows) {
      if (now - (diffs.get(found.id)?.at ?? Number.NEGATIVE_INFINITY) >= DIFF_TTL_MS) await refreshDiff(found);
      if (found.prNumber === null && now - (discoveredAt.get(found.id) ?? Number.NEGATIVE_INFINITY) >= DISCOVER_EVERY_MS) await discover(found);
    }
    await refreshStates(rows.filter((found) => now - (found.prCheckedAt ?? 0) >= STATE_TTL_MS));
  }

  return {
    /** What a row says: the lines changed and the pull request, as they are known now. */
    view: (found: Found): { diff: DiffStat | null; pr: SessionPullRequest | null } => ({
      diff: diffs.get(found.id)?.stat ?? null,
      pr: found.prNumber === null || found.prRepo === null || found.prUrl === null || found.prState === null ? null : { repo: found.prRepo, number: found.prNumber, url: found.prUrl, state: found.prState, checks: found.prChecks },
    }),

    /** A list was asked for: the sweep that fills the rows in starts, unless one ran a moment ago or is running. */
    kick(rows: Found[]) {
      const now = clock.now();
      // a list with no sessions has nothing to read, and must not use up the window of the first one that has some
      if (rows.length === 0 || sweeping || now - sweptAt < SWEEP_EVERY_MS) return;
      sweptAt = now;
      sweeping = true;
      void sweep(rows.slice(0, MAX_SESSIONS))
        .catch((error) => log.error('reading the work of the sessions failed', error))
        .finally(() => (sweeping = false));
    },

    /** A turn ended: the lines it changed, and the pull request it may have opened or moved on. */
    async afterTurn(sessionId: string) {
      try {
        const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
        if (found === undefined) return;
        await refreshDiff(found);
        if (found.prNumber === null || isOpen(found.prState) === false) await discover(found);
        else await refreshStates([found]);
      } catch (error) {
        log.error('reading the work of a session failed', error);
      }
    },
  };
}
