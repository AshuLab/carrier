import { eq } from 'drizzle-orm';
import { createScopedLogger } from '@ashulab/universal-logger';
import type { Clock } from '../orchestration/clock.ts';
import type { ChatDb } from './db.ts';
import type { Git } from './git.ts';
import { pullRequestKey, type PullRequestChecks, type PullRequestInfo, type PullRequests, type PullRequestState } from './pull-requests.ts';
import { sessions } from './schema.ts';
import type { GithubWork } from './shell-effects.ts';
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
/** The same two, for an idle session whose last activity has not moved since they were read: nothing the agent did can have changed them. */
export const IDLE_DIFF_TTL_MS = 600_000;
export const IDLE_DISCOVER_EVERY_MS = 1_800_000;
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
  // `activeAt`: the session's `lastActiveAt` when it was read; an idle session that has not moved since has nothing new to read
  const diffs = new Map<string, { stat: DiffStat | null; at: number; activeAt: number }>();
  const discoveredAt = new Map<string, { at: number; activeAt: number }>();
  let sweptAt = Number.NEGATIVE_INFINITY;
  let sweeping = false;

  const out = async (folder: string, args: string[]) => {
    const result = await git.run(folder, args, { timeoutMs: GIT_TIMEOUT_MS });
    return result.ok ? result.out.trim() : null;
  };

  /**
   * The branch the session works on and where it was cut from or merges into, to count lines against.
   * The branch is the one checked out now (null while detached); a worktree then falls back to the one it was cut with.
   */
  type Where = Awaited<ReturnType<typeof whereOf>>;
  async function whereOf(found: Found) {
    const worktree = found.workspaceKind === 'worktree';
    const originFolder = worktree ? (found.worktreeBase ?? found.folder) : found.folder;
    const origin = await out(originFolder, ['remote', 'get-url', 'origin']); // as git resolves it, `insteadOf` included
    const parsed = origin === null ? null : await resolveOrigin(git, origin);
    // what is checked out now: an agent may have moved a worktree to another branch than the one it was cut with.
    // Trade-off: a branch it checks out only for a while (`gh pr checkout` of another pull request) links that one if a sweep lands then, and the link stays.
    const current = await out(found.folder, ['rev-parse', '--abbrev-ref', 'HEAD']);
    const checkedOut = current === null || current === 'HEAD' ? null : current;
    const branch = checkedOut ?? (worktree ? found.worktreeBranch : null);
    const head = await out(originFolder, ['symbolic-ref', '--short', 'refs/remotes/origin/HEAD']);
    return {
      repo: parsed === null ? null : `${parsed.owner}/${parsed.name}`,
      branch,
      defaultBranch: head === null ? 'main' : head.replace(/^origin\//, ''),
    };
  }

  /** The commit the work is counted from: where a worktree was cut from (the closer to its head of the local and the remote copy of the start branch), where a folder on its own branch left the default one, else what is committed. */
  async function baseOf(found: Found, where: { branch: string | null; defaultBranch: string }) {
    const from = found.workspaceKind === 'worktree' ? found.worktreeFrom : where.branch !== null && where.branch !== where.defaultBranch ? where.defaultBranch : null;
    if (from === null) return 'HEAD';
    // the local and the remote copy of the start branch (a name that already says `origin/` has only itself)
    const refs = from.startsWith('origin/') ? [from] : [from, `origin/${from}`];
    let closest: string | null = null;
    for (const ref of refs) {
      const base = await out(found.folder, ['merge-base', ref, 'HEAD']);
      if (base === null || base === '') continue;
      // both are ancestors of HEAD, so the one that descends from the other is the closer to it
      if (closest === null || (base !== closest && (await out(found.folder, ['merge-base', '--is-ancestor', closest, base])) !== null)) closest = base;
    }
    if (closest !== null) return closest;
    return 'HEAD';
  }

  // ponytail: `git diff` leaves the files git does not track out of the count; `git add -N` would change the person's index, so they are not counted
  async function refreshDiff(found: Found, family: Family, known?: Where) {
    const where = known ?? (await whereOf(found));
    const numstat = await out(found.folder, ['diff', '--numstat', ...SAFE_DIFF, await baseOf(found, where), '--']);
    diffs.set(found.id, { stat: numstat === null ? null : parseNumstat(numstat), at: clock.now(), activeAt: family.activeAt });
  }

  const link = (id: string, repo: string, info: PullRequestInfo) => {
    db.update(sessions).set({ prRepo: repo, prNumber: info.number, prUrl: info.url, prState: info.state, prChecks: info.checks, prCheckedAt: clock.now() }).where(eq(sessions.id, id)).run();
  };

  /** Looks for the pull request of the branch the session works on; a session that has one keeps it unless it is merged or closed and a newer one is open on the same branch. */
  async function discover(found: Found, family: Family, known?: Where) {
    discoveredAt.set(found.id, { at: clock.now(), activeAt: family.activeAt });
    const where = known ?? (await whereOf(found));
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

  type Family = ReturnType<typeof familyOf>;
  /** A session and its children as one, as the lifecycle clock ages them (ADR 0033): a child works in the parent's folder, so its work is the parent's diff. */
  function familyOf(found: Found) {
    const kids = db.select({ state: sessions.state, lastActiveAt: sessions.lastActiveAt }).from(sessions).where(eq(sessions.parentSessionId, found.id)).all();
    return { activeAt: Math.max(found.lastActiveAt, ...kids.map((kid) => kid.lastActiveAt)), resting: found.state === 'idle' && kids.every((kid) => kid.state === 'idle') };
  }

  /** Whether what was read at `read` is due again: after `base`, or after `idle` when the family is idle and has done nothing since. */
  const due = (family: Family, read: { at: number; activeAt: number } | undefined, base: number, idle: number) =>
    read === undefined || clock.now() - read.at >= (family.resting && family.activeAt === read.activeAt ? idle : base);

  async function sweep(rows: Found[]) {
    const now = clock.now();
    for (const found of rows) {
      const family = familyOf(found);
      const needsDiff = due(family, diffs.get(found.id), DIFF_TTL_MS, IDLE_DIFF_TTL_MS);
      const needsPull = found.prNumber === null && due(family, discoveredAt.get(found.id), DISCOVER_EVERY_MS, IDLE_DISCOVER_EVERY_MS);
      if (needsDiff === false && needsPull === false) continue;
      const where = await whereOf(found); // once for both
      if (needsDiff) await refreshDiff(found, family, where);
      if (needsPull) await discover(found, family, where);
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

    /**
     * A turn ended: what it did says what to read again, so nothing is asked that it cannot have changed.
     * The lines are read (a local `git diff`, cheap) when anything ran in it, since any command can write a file, and not for a turn that only talked.
     * GitHub is asked only for what its shell commands may have moved (`githubWorkOf`): the pull request of the branch after a push, a new branch or
     * a `gh pr create`, the state of the one the session has after a push, a merge or a rerun. Without `work` (a turn nobody recorded) everything is read.
     */
    async afterTurn(sessionId: string, work?: { acted: boolean; github: GithubWork }) {
      try {
        const found = db.select().from(sessions).where(eq(sessions.id, sessionId)).get();
        if (found === undefined) return;
        const family = familyOf(found); // before any read: what happens meanwhile is newer than what is read
        const open = found.prNumber !== null && isOpen(found.prState);
        if (work === undefined || work.acted) await refreshDiff(found, family);
        if ((work === undefined || work.github.find) && open === false) await discover(found, family);
        else if ((work === undefined || work.github.states) && open) await refreshStates([found]);
      } catch (error) {
        log.error('reading the work of a session failed', error);
      }
    },
  };
}
