import { asc, eq } from 'drizzle-orm';
import type { Db } from '../storage/db.ts';
import { epics } from '../storage/schema.ts';
import type { Clock } from './clock.ts';
import { GitHubUnavailable, type GitHub } from './github.ts';

export type EngineOptions = {
  db: Db;
  github: GitHub;
  clock: Clock;
  repos: string[];
  pollIntervalMs: number;
};

export function createEngine({ db, github, clock, repos, pollIntervalMs }: EngineOptions) {
  let error: GitHubUnavailable | null = null;
  let cancel: (() => void) | null = null;

  // Returns the wait until the next poll.
  async function poll(): Promise<number> {
    try {
      // Fetch every repo before writing: a failure on any of them leaves the queue untouched.
      const found: { repo: string; issue: number }[] = [];
      for (const repo of repos) {
        for (const { issue } of await github.listReadyEpics(repo)) found.push({ repo, issue });
      }
      const queuedAt = clock.now();
      db.transaction((tx) => {
        for (const epic of found) tx.insert(epics).values({ ...epic, queuedAt }).onConflictDoNothing().run();
      });
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
    start: () => schedule(pollIntervalMs),
    stop: () => cancel?.(),
    /** Last GitHub failure, null once a poll succeeds. */
    get error() {
      return error;
    },
    /** Queued epics, oldest first. */
    queue: () => db.select().from(epics).where(eq(epics.status, 'queued')).orderBy(asc(epics.id)).all(),
  };
}
