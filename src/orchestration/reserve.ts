import { and, asc, count, eq, inArray } from 'drizzle-orm';
import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { Db } from '../storage/db.ts';
import { epics } from '../storage/schema.ts';

// Atomic: the check of free slots, the pick of the oldest queued epic and the move to `running`
// happen in one write transaction, so two connections to the same file can never reserve the
// same epic or exceed the limit. Only queued epics are picked, so a running one is never reserved again.
// With two or more options the epic is also marked as waiting for its choice for `choiceMs`; each role starts on its configured option.
export function reserve(db: Db, { maxConcurrent, now, repos, choiceMs }: { maxConcurrent: number; now: number; repos: EffectiveRepoConfig[]; choiceMs: number }) {
  return db.transaction(
    (tx) => {
      const running = tx.select({ n: count() }).from(epics).where(eq(epics.status, 'running')).get()!.n;
      if (running >= maxConcurrent) return null;
      const next = tx
        .select()
        .from(epics)
        .where(and(eq(epics.status, 'queued'), inArray(epics.repo, repos.map((r) => r.name))))
        .orderBy(asc(epics.id))
        .get();
      if (!next) return null;
      const config = repos.find((r) => r.name === next.repo)!;
      return tx
        .update(epics)
        .set({
          status: 'running', startedAt: now, config, labelPending: true,
          authorOption: config.agents.author.option ?? null, reviewerOption: config.agents.reviewer.option ?? null,
          choiceDeadline: Object.keys(config.options ?? {}).length >= 2 ? now + choiceMs : null,
        })
        .where(eq(epics.id, next.id))
        .returning()
        .get();
    },
    { behavior: 'immediate' },
  );
}
