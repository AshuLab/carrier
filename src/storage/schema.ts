import type { EffectiveRepoConfig } from '../config/resolve.ts';
import type { PullRequestBlock } from '../orchestration/github.ts';
import { integer, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core';

export const needsHumanKinds = ['review_limit', 'agent_needs_human', 'retries_exhausted', 'timeout', 'auth', 'workspace', 'pr_invalid', 'usage_limit', 'engine_error', 'skill_missing', 'reviewers_failed', 'lead_limit'] as const;
export const unansweredReasons = ['already_taken', 'last_round'] as const;
// Why an epic was cancelled; the poll decides by it. `ready_removed` and `issue_closed` before any execution go back to the queue when `ready` returns. A cancel with no kind is never requeued.
export const cancelKinds = ['ready_removed', 'issue_closed', 'pr_closed', 'issue_gone'] as const;
export const epicStates =['queued', 'running', 'ready_for_test', 'needs_human', 'cancelled', 'merged', 'repo_removed'] as const;

export const epics = sqliteTable(
  'epics',
  {
    // Autoincrement id is the stable queue order: rows are never reused or reordered.
    id: integer().primaryKey({ autoIncrement: true }),
    repo: text().notNull(),
    issue: integer().notNull(),
    status: text({ enum: epicStates }).notNull().default('queued'),
    queuedAt: integer().notNull().default(0), // ms since epoch, when the epic entered the queue (new, resumed or requeued); the queue is ordered by it, then by id. Never equal for two queued epics: see `queuePosition`
    startedAt: integer(), // ms since epoch, when the scheduler reserved it
    // Effective repo config frozen at reservation: later config changes do not touch a running epic.
    config: text({ mode: 'json' }).$type<EffectiveRepoConfig>(),
    cancelReason: text(),
    cancelKind: text({ enum: cancelKinds }), // set together with cancelReason; null on an epic cancelled before kinds existed
    // The running label is a reflection of SQLite: true while it has not reached GitHub yet.
    labelPending: integer({ mode: 'boolean' }).notNull().default(false),
    stage: text({ enum: ['ship', 'review', 'fix'] }), // null until the author is launched
    stageStartedAt: integer(), // ms since epoch, when the epic entered its current stage
    // Where the author's epic worktree really is (read back from `git worktree list` after ship); fix turns run there.
    workspace: text(),
    lastActivityAt: integer(), // ms since epoch of the agent's last output, written at most every 10 s
    lastError: text(), // the last technical failure of a stage; cleared when a result is imported
    round: integer(), // review round, from 1 once the final PR is validated
    prNumber: integer(),
    prHeadSha: text(),
    pr: text({ mode: 'json' }).$type<PullRequestBlock>(), // what GitHub said about the PR the last time the poll asked: a cache, never read to decide anything
    reviewedSha: text(), // head the reviewer approved, set when the epic becomes ready_for_test
    verification: text({ mode: 'json' }).$type<{ ci: 'passed' | 'absent'; evidence: string }>(), // what the reviewer reported about the checks
    observationsPassAt: integer(), // ms since epoch, when the observations pass started (once per epic); null until then
    needsHumanReason: text(),
    needsHumanKind: text({ enum: needsHumanKinds }), // what kind of stop the reason is; set together with it
    title: text(), // the issue's title and labels as the poll last read them
    labels: text({ mode: 'json' }).$type<string[]>(),
    branch: text(), // the final PR's branch, set when ship is validated
    // Set while `repo_removed`: where the epic was and why it stopped, so it goes back there when the repo returns.
    removedFrom: text({ enum: epicStates }),
    removedReason: text(),
    finishedAt: integer(), // ms since epoch, when the epic left `running`
    cleanedAt: integer(), // ms since epoch, when the worktrees and branches of a merged or cancelled epic were removed; null until then
    // The agent option each role runs on, set when the epic is reserved and replaced by a choice at a restart; null on epics from before options existed.
    authorOption: text(),
    reviewerOption: text(),
    // Recoveries by the poll in a row (ADR 0046): back to 0 when an execution of the epic ends or its stage changes; the fourth failure parks it in `engine_error`.
    recoveries: integer().notNull().default(0),
    // The stage a resume asked for (`review` or `fix`): kept while the epic waits in the queue, so a restart of the engine in between keeps it. Null: start from ship.
    resumeStage: text({ enum: ['review', 'fix'] }),
    // The cap of review rounds a resume granted this epic; null: the live `maxReviews`. A restart from ship clears it with the rounds.
    roundLimit: integer(),
    // ms since epoch: when the provider says the window an epic stopped on (`usage_limit`) comes back, with `limits.autoResume` on; cleared by any change of status. Null: no wake-up.
    resumeAt: integer(),
    // Automatic resumes in a row (ADR 0049): back to 0 when one of the epic's executions ends with anything but `usage_limit`; the stop after the third stays in needs-human.
    autoResumes: integer().notNull().default(0),
    // Reviews made again in a row because the pull request's head moved while one ran (ADR 0047): back to 0 when a review completes on its own head or the epic starts a new attempt; a third move stops it in `pr_invalid`.
    headRepeats: integer().notNull().default(0),
    // The observations left unanswered when the epic went to ready for test, and why (glossary: Unanswered observations); both null when none were left, set together.
    unansweredObservations: integer(),
    unansweredReason: text({ enum: unansweredReasons }),
    // When the retry of an `api_error` may start (ms since epoch); null when none waits. A due time and not a sleep: a restart of the engine finds it.
    retryAt: integer(),
  },
  (table) => [uniqueIndex('epics_repo_issue').on(table.repo, table.issue)],
);
