import { and, asc, eq } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { Db } from '../storage/db.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';
import { GitHubUnavailable, ownedLabels, readyLabel, runningLabel, type GitHub } from './github.ts';
import { reserve } from './reserve.ts';

export type EngineOptions = {
  db: Db;
  github: GitHub;
  clock: Clock;
  repos: EffectiveRepoConfig[];
  pollIntervalMs: number;
  maxConcurrentEpics: number;
};

export function createEngine({ db, github, clock, repos, pollIntervalMs, maxConcurrentEpics }: EngineOptions) {
  let error: GitHubUnavailable | null = null;
  let cancel: (() => void) | null = null;
  const labelledRepos = new Set<string>();

  // Creates the owned labels a repo lacks; never touches existing ones nor creates `ready`.
  async function ensureLabels() {
    for (const { name } of repos) {
      if (labelledRepos.has(name)) continue;
      const existing = await github.listLabels(name);
      for (const label of ownedLabels) if (!existing.includes(label)) await github.createLabel(name, label);
      labelledRepos.add(name);
    }
  }

  const markRunning = async (repo: string, issue: number) => {
    await github.setLabels(repo, issue, { add: [runningLabel], remove: [readyLabel] });
    db.update(epics).set({ labelPending: false }).where(and(eq(epics.repo, repo), eq(epics.issue, issue))).run();
  };

  // SQLite is the authority: a running epic whose label did not reach GitHub is retried here.
  async function reconcileLabels() {
    const pending = db.select().from(epics).where(and(eq(epics.status, 'running'), eq(epics.labelPending, true))).orderBy(asc(epics.id)).all();
    for (const epic of pending) await markRunning(epic.repo, epic.issue);
  }

  // Starts the oldest queued epics until the concurrency limit or the queue is exhausted.
  async function fillSlots() {
    for (;;) {
      const epic = reserve(db, { maxConcurrent: maxConcurrentEpics, now: clock.now(), repos });
      if (!epic) return;
      const cancelWith = (cancelReason: string) =>
        db.update(epics).set({ status: 'cancelled', cancelReason }).where(eq(epics.id, epic.id)).run();
      let issue;
      try {
        issue = await github.getIssue(epic.repo, epic.issue);
      } catch (e) {
        // Could not check it: give the slot back, the epic keeps its place in the queue.
        db.update(epics).set({ status: 'queued', startedAt: null, config: null, labelPending: false }).where(eq(epics.id, epic.id)).run();
        throw e;
      }
      if (issue.state === 'closed') cancelWith('cerrada antes de iniciar');
      else if (!issue.labels.includes(readyLabel)) cancelWith('ready removido');
      else await markRunning(epic.repo, epic.issue); // GitHubUnavailable here leaves it reserved, labelPending
    }
  }

  // Returns the wait until the next poll.
  async function poll(): Promise<number> {
    try {
      // Fetch every repo before writing: a failure on any of them leaves the queue untouched.
      const found: { repo: string; issue: number }[] = [];
      await ensureLabels();
      for (const { name: repo } of repos) {
        for (const { issue } of await github.listReadyEpics(repo)) found.push({ repo, issue });
      }
      const queuedAt = clock.now();
      db.transaction((tx) => {
        for (const epic of found) tx.insert(epics).values({ ...epic, queuedAt }).onConflictDoNothing().run();
      });
      await reconcileLabels();
      await fillSlots();
      error = null;
      return pollIntervalMs;
    } catch (e) {
      if (!(e instanceof GitHubUnavailable)) throw e;
      error = e;
      return Math.max(pollIntervalMs, e.retryAfterMs ?? 0);
    }
  }

  const schedule = (ms: number) => {
    cancel = clock.after(ms, async () => schedule(await poll()));
  };

  return {
    async start() {
      try {
        await ensureLabels();
      } catch (e) {
        if (!(e instanceof GitHubUnavailable)) throw e;
        error = e; // retried every cycle until it works
      }
      schedule(pollIntervalMs);
    },
    stop: () => cancel?.(),
    /** Last GitHub failure, null once a poll succeeds. */
    get error() {
      return error;
    },
    /** Queued epics, oldest first. */
    queue: () => db.select().from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all(),
  };
}
