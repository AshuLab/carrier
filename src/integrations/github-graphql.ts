import { z } from 'zod';

// What the GraphQL answers look like, as recorded in docs/research/macos-app-github-graphql.md.
// The queries live in that note; these schemas decode what they return.

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
