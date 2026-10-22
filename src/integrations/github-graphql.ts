import { z } from 'zod';
import type { EpicSlice, PullRequestBlock } from '../orchestration/github.ts';

// What the GraphQL answers look like, as recorded in docs/research/macos-app-github-graphql.md.
// The queries live in that note; these schemas decode what they return.

/** Slices read per epic; more than this and the reply says it is partial. */
export const SLICE_LIMIT = 100;

const rateLimit = z.object({ cost: z.int().positive(), remaining: z.int().nonnegative(), limit: z.int().positive(), resetAt: z.string() });

const slice = z.object({
  number: z.int().positive(),
  title: z.string(),
  state: z.enum(['OPEN', 'CLOSED']),
  stateReason: z.enum(['COMPLETED', 'NOT_PLANNED', 'REOPENED', 'DUPLICATE']).nullable(),
  closedAt: z.string().nullable(),
  assignees: z.object({ nodes: z.array(z.object({ login: z.string() })) }),
  // Closed blockers are listed too: a slice waits only while one of them is OPEN.
  blockedBy: z.object({
    nodes: z.array(z.object({ number: z.int().positive(), state: z.enum(['OPEN', 'CLOSED']), repository: z.object({ nameWithOwner: z.string() }) })),
  }),
  // Added after the spike: what mentions the slice. Absent in the recorded answers, so it defaults to nothing.
  timelineItems: z.object({ nodes: z.array(z.object({ source: z.object({ __typename: z.string(), number: z.int().positive().optional() }) })) }).default({ nodes: [] }),
});

export const epicSlicesResponse = z.object({
  data: z.object({
    rateLimit,
    repository: z.object({
      issue: z.object({
        number: z.int().positive(),
        title: z.string(),
        state: z.enum(['OPEN', 'CLOSED']),
        labels: z.object({ nodes: z.array(z.object({ name: z.string() })) }),
        subIssuesSummary: z.object({ total: z.int().nonnegative(), completed: z.int().nonnegative(), percentCompleted: z.int().nonnegative() }),
        subIssues: z.object({ pageInfo: z.object({ hasNextPage: z.boolean() }), nodes: z.array(slice) }),
      }),
    }),
  }),
});

const checkCountsByState = z.array(z.object({ state: z.string(), count: z.int().nonnegative() }));

/** Null when the commit has no checks at all: that is "no checks", never "pending". */
const statusCheckRollup = z
  .object({
    state: z.enum(['SUCCESS', 'FAILURE', 'ERROR', 'PENDING', 'EXPECTED']),
    contexts: z.object({
      checkRunCount: z.int().nonnegative(),
      statusContextCount: z.int().nonnegative(),
      checkRunCountsByState: checkCountsByState,
      statusContextCountsByState: checkCountsByState,
    }),
  })
  .nullable();

export const pullRequestResponse = z.object({
  data: z.object({
    rateLimit,
    repository: z.object({
      pullRequest: z.object({
        number: z.int().positive(),
        url: z.string(),
        isDraft: z.boolean(),
        state: z.enum(['OPEN', 'CLOSED', 'MERGED']),
        baseRefName: z.string(),
        headRefName: z.string(),
        headRefOid: z.string(),
        mergeable: z.enum(['MERGEABLE', 'CONFLICTING', 'UNKNOWN']),
        mergeStateStatus: z.enum(['CLEAN', 'DIRTY', 'BLOCKED', 'BEHIND', 'UNSTABLE', 'HAS_HOOKS', 'UNKNOWN']),
        reviewDecision: z.enum(['APPROVED', 'CHANGES_REQUESTED', 'REVIEW_REQUIRED']).nullable(),
        additions: z.int().nonnegative(),
        deletions: z.int().nonnegative(),
        changedFiles: z.int().nonnegative(),
        commits: z.object({ totalCount: z.int().nonnegative() }),
        lastCommit: z.object({ nodes: z.array(z.object({ commit: z.object({ statusCheckRollup }) })) }),
      }),
    }),
  }),
});

const checkContext = z.discriminatedUnion('__typename', [
  z.object({ __typename: z.literal('CheckRun'), name: z.string(), status: z.string(), conclusion: z.string().nullable() }),
  z.object({ __typename: z.literal('StatusContext'), context: z.string(), state: z.string() }),
]);

export const failingCheckResponse = z.object({
  data: z.object({
    rateLimit,
    repository: z.object({
      pullRequest: z.object({
        number: z.int().positive(),
        state: z.enum(['OPEN', 'CLOSED', 'MERGED']),
        mergeStateStatus: z.string(),
        lastCommit: z.object({
          nodes: z.array(
            z.object({
              commit: z.object({
                statusCheckRollup: z
                  .object({
                    state: z.string(),
                    contexts: z.object({
                      checkRunCount: z.int().nonnegative(),
                      statusContextCount: z.int().nonnegative(),
                      pageInfo: z.object({ hasNextPage: z.boolean() }),
                      nodes: z.array(checkContext),
                    }),
                  })
                  .nullable(),
              }),
            }),
          ),
        }),
      }),
    }),
  }),
});

/** The epic's slices with their blockers and the pull requests that mention them; the schemas above decode its answer. Cost 2 for 52 slices. */
export const epicSlicesQuery = `query($owner: String!, $name: String!, $number: Int!) {
  rateLimit { cost remaining limit resetAt }
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number title state
      labels(first: 20) { nodes { name } }
      subIssuesSummary { total completed percentCompleted }
      subIssues(first: ${SLICE_LIMIT}) {
        pageInfo { hasNextPage }
        nodes {
          number title state stateReason closedAt
          assignees(first: 3) { nodes { login } }
          blockedBy(first: 20) { nodes { number state repository { nameWithOwner } } }
          timelineItems(first: 10, itemTypes: [CROSS_REFERENCED_EVENT]) { nodes { ... on CrossReferencedEvent { source { __typename ... on PullRequest { number } } } } }
        }
      }
    }
  }
}`;

type SliceRead = z.infer<typeof slice>;

/**
 * Closed as completed is merged (`closed`), closed any other way is skipped; open and assigned or with a pull request is working,
 * open with an open blocker is waiting, otherwise ready to start. A closed blocker does not hold a slice back.
 */
export function sliceOf(s: SliceRead): EpicSlice {
  const blockedBy = s.blockedBy.nodes.filter((b) => b.state === 'OPEN').map((b) => b.number);
  // ponytail: the first pull request that mentions the slice; a later one that only cites it is not told apart.
  const prNumber = s.timelineItems.nodes.find((n) => n.source.__typename === 'PullRequest')?.source.number ?? null;
  const assignee = s.assignees.nodes[0]?.login ?? null;
  let state: EpicSlice['state'];
  if (s.state === 'CLOSED') state = s.stateReason === 'NOT_PLANNED' || s.stateReason === 'DUPLICATE' ? 'skipped' : 'closed';
  else if (assignee !== null || prNumber !== null) state = 'in_progress';
  else state = blockedBy.length > 0 ? 'waiting' : 'ready';
  return { number: s.number, title: s.title, state, blockedBy, assignee, prNumber, closedAt: s.closedAt === null ? null : Date.parse(s.closedAt) };
}

/** A pull request with its checks, merge state and review decision; the schema above decodes its answer. Cost 1. */
export const pullRequestQuery = `query($owner: String!, $name: String!, $number: Int!) {
  rateLimit { cost remaining limit resetAt }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number url isDraft state baseRefName headRefName headRefOid
      mergeable mergeStateStatus reviewDecision
      additions deletions changedFiles commits { totalCount }
      lastCommit: commits(last: 1) { nodes { commit { statusCheckRollup { state
        contexts(first: 1) { checkRunCount statusContextCount
          checkRunCountsByState { state count } statusContextCountsByState { state count } } } } } }
    }
  }
}`;

const failingStates = new Set(['ACTION_REQUIRED', 'CANCELLED', 'FAILURE', 'STARTUP_FAILURE', 'STALE', 'TIMED_OUT', 'ERROR']);
const passingStates = new Set(['SUCCESS', 'NEUTRAL', 'SKIPPED', 'COMPLETED']);

/** Check runs and status contexts counted together: a state that is neither passing nor failing is still running or waiting. A commit with no rollup has no checks (null), never pending. */
export function pullRequestOf(response: z.infer<typeof pullRequestResponse>): PullRequestBlock {
  const pr = response.data.repository.pullRequest;
  const rollup = pr.lastCommit.nodes[0]?.commit.statusCheckRollup ?? null;
  let checks: PullRequestBlock['checks'] = null;
  if (rollup !== null) {
    checks = { passing: 0, failing: 0, pending: 0 };
    for (const { state, count } of [...rollup.contexts.checkRunCountsByState, ...rollup.contexts.statusContextCountsByState]) {
      checks[failingStates.has(state) ? 'failing' : passingStates.has(state) ? 'passing' : 'pending'] += count;
    }
  }
  return { number: pr.number, url: pr.url, draft: pr.isDraft, mergeState: pr.mergeStateStatus, reviewDecision: pr.reviewDecision, checks };
}
