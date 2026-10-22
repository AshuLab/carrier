# Spike: GitHub GraphQL queries with the Forge bot token

> Spike of 2026-10-21 for [#115](https://github.com/AshuLab/carrier/issues/115), epic [#111](https://github.com/AshuLab/carrier/issues/111). It checks sections 2 and 3 of [the GitHub and git inventory](macos-app-data-github.md), which ran GraphQL only with a personal token. Read-only queries, run as `agent-forge gh artanis-agent api graphql` from a clone under `AshuLab` (the same call shape as `GhGitHub.api`, `src/integrations/github.ts`). The token was never printed or stored. Scratch files lived under the system temp directory and were deleted.

## Short answer

All three queries work with the Forge bot token, and no permission was missing. The cost is 2 points for a 52-slice epic with its blockers and 1 point for a pull request with its checks, merge state and review decision, out of a separate GraphQL bucket of 5,000 an hour. A repository with no checks answers `statusCheckRollup: null` and must be shown as "no checks", not as pending.

One gap: both private repositories the bot can reach (`AshuLab/financial`, `AshuLab/ashulab-landing`) have no issues and no pull requests, and a spike must not write, so the epic and PR queries ran on public repositories. On the private ones the bot's read access was proven (`isPrivate: true`, counts 0, cost 1). The permissions involved (Issues, Pull requests, Checks, Commit statuses: read) are the same on a private repo and the bot holds them, but nobody has seen a private slice list or rollup come back. The first real run on a private repo should confirm it. The repos this machine's config watches that hold private data (`vemec/encaja`, `vemec/sass-blueprint`) were not touched, as the ticket says.

The local config (`~/.carrier/config.json`) sets `orchestratorProfile` to `gh` (the user's login) and uses the Forge bot `artanis-agent` for the reviewer. The epic query was run with both identities and cost 2 with both.

## What ran

| Query | Run against | Identity | `rateLimit.cost` | Worked |
|---|---|---|---|---|
| Slices with blockers | `AshuLab/carrier` epic 111 (52 slices, 3 closed) | Forge bot `artanis-agent` | 2 | yes |
| Slices with blockers | same | `gh` profile (user) | 2 | yes |
| Pull request, no checks | `AshuLab/carrier` PR 167 (merged) | bot | 1 | yes |
| Pull request, checks passing | `cli/cli` PR 14784 (open) | bot | 1 | yes |
| Pull request, checks failing | `cli/cli` PR 14035 (open, draft) | bot | 1 | yes |
| Failing check by name (up to 100 contexts) | `cli/cli` PR 14035 | bot | 1 | yes |
| Private repo read | `AshuLab/financial`, `AshuLab/ashulab-landing` | bot | 1 each | yes (empty repos) |

`cli/cli` is public and is used only because `AshuLab/carrier` has no CI, so it has no PR with checks. The bot's installation token reads public repositories of other owners.

The bot's minted scopes (printed by `agent-forge` on stderr) were `issues:write contents:write pull_requests:write checks:read actions:read statuses:read metadata:read` plus three more; nothing beyond them was needed. `viewer` answered `artanis-agent[bot]`, and the headers said `X-Ratelimit-Resource: graphql`, limit 5000: the bot's own GraphQL bucket.

## Query 1: an epic's slices with what blocks them

```graphql
query($owner: String!, $name: String!, $number: Int!) {
  rateLimit { cost remaining limit resetAt }
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number title state
      labels(first: 20) { nodes { name } }
      subIssuesSummary { total completed percentCompleted }
      subIssues(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          number title state stateReason closedAt
          assignees(first: 3) { nodes { login } }
          blockedBy(first: 20) { nodes { number state repository { nameWithOwner } } }
        }
      }
    }
  }
}
```

Variables: `owner`, `name`, `number` (the epic). Per slice it returns `number`, `title`, `state` (`OPEN`, `CLOSED`), `stateReason` (`COMPLETED` when closed, null while open), `closedAt`, `assignees`, and `blockedBy` with each blocker's `number`, `state` and `repository.nameWithOwner`. On the epic: `title`, `labels`, `subIssuesSummary { total completed percentCompleted }` and `subIssues.pageInfo.hasNextPage`.

Cost 2 for 52 slices. Things this settled:

- `blockedBy` lists the closed blockers too (slice 135 had a closed and an open one). A slice is waiting only while one blocker is `OPEN`; a non-empty list does not mean blocked.
- `blockedBy` carries the blocker's repository, so a blocker in another repository can be named. None occurred in this epic, so it was not seen live.
- `first: 20` on `blockedBy` was enough (the longest list had 3; GitHub limits a relationship type to 50).

## Query 2: a pull request with checks, merge state and review decision

```graphql
query($owner: String!, $name: String!, $number: Int!) {
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
}
```

Returns `number`, `url`, `isDraft`, `state` (`OPEN`, `CLOSED`, `MERGED`), the branch names and head SHA, `mergeable` (`MERGEABLE`, `CONFLICTING`, `UNKNOWN`), `mergeStateStatus` (seen `BLOCKED`, `DIRTY`, `UNKNOWN`), `reviewDecision` (seen `REVIEW_REQUIRED` and null), the totals, and the last commit's `statusCheckRollup` with its `state` and the counts by state of check runs and of status contexts. Cost 1.

Seen: a merged PR answers `mergeable: UNKNOWN`, `mergeStateStatus: UNKNOWN`, `reviewDecision: null`. An open draft with a conflict answers `CONFLICTING` and `DIRTY`. A PR with 18 check runs answered `SUCCESS` with 12 `SUCCESS` and 6 `SKIPPED`. The rollup `state` is `SUCCESS`, `FAILURE`, `ERROR`, `PENDING` or `EXPECTED`; the counts list every state of the enum, zeros included.

## Query 3: which check failed

```graphql
query($owner: String!, $name: String!, $number: Int!) {
  rateLimit { cost remaining limit resetAt }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number state mergeStateStatus
      lastCommit: commits(last: 1) { nodes { commit { statusCheckRollup { state
        contexts(first: 100) { checkRunCount statusContextCount pageInfo { hasNextPage }
          nodes { __typename
            ... on CheckRun { name status conclusion }
            ... on StatusContext { context state } } } } } } }
    }
  }
}
```

Cost 1 for up to 100 contexts (11 here, `hasNextPage` false). Each node is a `CheckRun` (`name`, `status`, `conclusion`) or a `StatusContext` (`context`, `state`). On PR 14035 exactly one run had `conclusion: FAILURE` and the rollup `state` was `FAILURE`. This query only names the failing check; the counts in query 2 are enough for a "1 failing" label.

The engine's query for the pull request block (`pullRequestQuery`, `src/integrations/github-graphql.ts`) is query 2. The poll runs it once for each running, ready-for-test or needs-human epic that has a pull request number, none for one without, and caches the block on the epic's row. Check runs and status contexts are counted together: `SUCCESS`, `NEUTRAL`, `SKIPPED` and `COMPLETED` pass; `FAILURE`, `ERROR`, `CANCELLED`, `TIMED_OUT`, `STARTUP_FAILURE`, `ACTION_REQUIRED` and `STALE` fail; everything else is pending.

## Query 4: a pull request's review threads

Verified on 2026-10-22 with the orchestrator profile (`gh`, the user's own login) against a private repository's pull request with 14 threads: it answers, cost 1. It is part of the pull request query of the engine (`pullRequestQuery`), so the block and the threads are one call.

```graphql
query($owner: String!, $name: String!, $number: Int!) {
  rateLimit { cost remaining limit resetAt }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) { totalCount pageInfo { hasNextPage }
        nodes { id isResolved isOutdated path line
          comments(first: 1) { totalCount nodes { url body author { login __typename } } } } }
    }
  }
}
```

Per thread: `id` (node id), `isResolved`, `isOutdated`, `path`, `line` and the opening comment (`comments(first: 1)`) with its `url`, `body`, `author { login __typename }` and `comments.totalCount` for the whole conversation. Recorded shape:

- `line` is null when the thread is outdated and GitHub no longer maps it.
- `author` is null for a deleted account; `__typename` is `Bot` for a bot, `User` for a person.
- `body` can be empty. The engine keeps only its first line, redacted and cut to 160 characters, never the text.
- `pageInfo.hasNextPage` is true when there are more than the hundred asked for; the engine flags the list as partial.

## A repository with no checks

`AshuLab/carrier` has no workflow, so PR 167 answers `statusCheckRollup: null` on its last commit. REST says the opposite: the combined status of such a commit is `pending` with `total_count: 0` (inventory, section 3). The app must read the null as "no checks" and show it as such (a dash or the words "No checks"), never as pending. `PENDING` with check runs counted is the only pending that means something is still running.

## Cost and polling

An epic query is 2 points and a PR query is 1, as the inventory estimated. For 5 active epics every 5 minutes: 5 x (2 + 1) x 12 = 180 points an hour, 3.6% of 5,000. They fit in one request (the inventory's combined query cost 2). GraphQL has no conditional requests, so every poll pays its cost.

## Fixtures

Recorded answers in `src/integrations/github-graphql-fixtures/`, decoded by the schemas in `src/integrations/github-graphql.ts` and checked by `github-graphql.test.ts`. Titles, logins, branch names, SHAs, repository names and check names are placeholders. The slice list is trimmed to six real slices (closed, assigned, free, one open blocker, closed plus open blocker, three blockers) and its summary recomputed.

| File | Case |
|---|---|
| `epic-slices.json` | slice list with blockers |
| `epic-slices-large.json` | generated, not recorded: 100 slices of a 130-slice epic (`hasNextPage` true), skipped, blocked by two, blocked by a closed one only, with pull request mentions |
| `pr-checks-passing.json` | PR with checks (18 runs, success and skipped) |
| `pr-no-checks.json` | PR with no checks (`statusCheckRollup: null`) |
| `pr-checks-failing.json` | PR with one failing check, counts |
| `pr-failing-check-detail.json` | the same PR, with the failing run named |
| `pr-review-threads.json` | generated, not recorded: seven synthetic review threads (resolved, outdated with a null line, deleted author, bot, empty comment, a token in the first line, a first line over 160 characters), `hasNextPage` true |

## Not verified

- A slice list, blockers or a rollup on a private repository with data (see above).
- A blocker in another repository, and a sub-issue in another repository than its epic.
- A rollup with status contexts (the old commit-status API): the schema covers them but every recorded PR had check runs only.
- A `PENDING` or `EXPECTED` rollup, an `APPROVED` or `CHANGES_REQUESTED` review decision, and the `mergeStateStatus` values `CLEAN`, `BEHIND`, `UNSTABLE`, `HAS_HOOKS`: the schemas list them from the introspection in the inventory, none was recorded.

The engine's query (`epicSlicesQuery`, `src/integrations/github-graphql.ts`) is query 1 plus `timelineItems(first: 10, itemTypes: [CROSS_REFERENCED_EVENT])` per slice, which gives the slice's pull request: `closedByPullRequestsReferences` answered empty for slices closed by a pull request into the epic branch, because it only follows closing keywords into the default branch. The first pull request among the mentions is taken.
