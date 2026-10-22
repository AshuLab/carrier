# macOS app: get to GitHub from slices and review threads

Status: spec

## Problem

The redesigned app shows an epic's slices and its review rounds, but neither leads anywhere. A slice row is a title and a detail line with no action, so to open the slice's issue or its pull request Diego goes to GitHub and finds it by hand. In the Review tab a blocker already carries the link to the comment that raised it, but the view never renders it, and what people wrote on the pull request is not in the app at all: the engine stores only what the reviewer agent reported, so he cannot see which threads are still unresolved or jump to one. Diego, who is the only person who reads the app, put the need as "reach GitHub fast"; it is fixed when from any slice or review item he is one click from the page on GitHub that holds the detail.

A cause found on the way: the slice cache was empty for finished or parked epics because only running epics were read (fixed in 05a27b9), and every GitHub-derived datum (progress, slices, the pull request block) had its own rule for when it is refreshed. The gap showed up as an empty tab, so the refresh rule belongs to this work.

## Solution

The app links out and does not copy GitHub in. Reading the body of an issue or the text of a comment inside the app was considered and cut: the need is to arrive at GitHub, not to read there, and storing the text would mean keeping private repositories' comments on disk for no use. For the same reason the idea of turning the slice cache into an archive that survives deletion on GitHub (upsert, a "deleted at source" mark, revising ADR 0008) was cut for now; Carrier's own record (rounds, blockers with their titles and links, executions, events) is already in SQLite, and only what people wrote on GitHub would be lost. It can come back if something is actually lost.

Slices need nothing new from the engine. `slicesTabModel` already builds each row's `issueURL` and `prURL` from the repository and the number, and the view now uses them (5c85109): the issue and the pull request show as links under the title, and a tap on the row opens the pull request, or the issue when there is none. A waiting slice names what blocks it by title, taken from the other slices in the same list, instead of the bare "after #2, #3" it shows today. A blocker that is not in the list (another repository, or past the first hundred) keeps its number.

The Review tab renders the url every blocker already carries, and gains a list of the final pull request's review threads: who wrote it, file and line, whether it is resolved, and the first line of the opening comment as a reminder, each linking to the thread. Unresolved threads come first. The reviewer agent's own threads appear too, marked as a bot, because its blockers are threads on the same pull request. This is the only new data. It is read in the query the engine already makes for the pull request block (`reviewThreads`, first hundred, first comment of each) and kept in a new table next to `epic_slices`, replaced on each read, as a cache of GitHub in the sense of ADR 0008: a failed read keeps the last rows, nothing the engine decides reads it, and the epic reply carries the list with a flag when GitHub has more than the hundred. The first line is cut to a fixed length and goes through the redaction that agent output already goes through (ADR 0006), so a token pasted in a comment is not stored.

Refresh follows one rule, the one the slice fix already applies: an epic in running, needs-human or ready-for-test is read on every poll; a finished one keeps its last read and is read once when it has none. The pull request block and the threads move to that rule, so a merged epic whose pull request was never cached still gets it. On top of the poll, opening the Review tab asks the engine to check GitHub now (the `checkNow` the socket already has), at most once every thirty seconds, so threads that changed since the last poll show up without waiting five minutes. A per-epic refresh request was considered and cut: a full poll is cheap and it is already built.

This belongs to the open epic #111 and the same branch, as new slices there, because it closes that epic's promise that every piece of data the design shows is real. It does not get an epic of its own.

## Scope

1. Clicking a slice row opens its pull request, or its issue when it has none. Done in 5c85109.
2. A slice shows its issue and, when it has one, its pull request as links that open them. Done in 5c85109.
3. A waiting slice names what blocks it by title; a blocker outside the list keeps its number.
4. A blocker in the Review tab opens the comment that raised it; one without a url (a result that predates it) is plain text.
5. The Review tab lists the final pull request's threads, unresolved first: author (a bot marked as one), file and line, resolved or outdated, the first line of the opening comment, and a link to the thread.
6. The threads are as fresh as the last poll, and opening the Review tab checks GitHub now, at most once every thirty seconds.
7. A finished epic still shows its last threads, and a finished epic that has none cached gets them from one read.
8. Against an engine that does not send threads the Review tab works as before and shows no thread section, not an empty one.

## Decisions

The reads and the table follow [0008](../adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md), which gets one line saying the same table pattern keeps the pull request's review threads, and [0006](../adr/0006-agent-events-stored-in-sqlite-with-bounded-output.md) for the redaction. [0005](../adr/0005-engine-independent-of-the-macos-app.md) holds: the app has no token and every GitHub read is the engine's, with the orchestrator profile (the user's own `gh` login on this machine, which is why private repositories read fine). Verified on 2026-10-22 against `vemec/encaja` PR 673, a private repository: `reviewThreads(first: 100)` with the first comment of each answers, 14 threads, cost 1 point. The query goes in `docs/research/macos-app-github-graphql.md` next to the other two, with its recorded shape.

One query, one port method. `readPullRequest` returns the block and the threads together, so a poll makes the same one call per epic with a pull request as today:

```ts
type ReviewThread = {
  id: string;                  // GraphQL node id, stable: the key of the row
  path: string;
  line: number | null;         // null when the thread is outdated and GitHub no longer maps it
  resolved: boolean;
  outdated: boolean;
  author: string | null;       // null for a deleted account
  bot: boolean;                // the author's __typename is Bot
  firstLine: string;           // first line of the opening comment, redacted, at most 160 characters; '' when the comment is empty
  commentCount: number;
  url: string;                 // the opening comment's url
};
readPullRequest(repo, number): Promise<{ pr: PullRequestBlock; threads: ReviewThread[]; truncated: boolean } | null>;
```

The table is `epic_review_threads`, keyed by epic and thread id, with `readAt` and `truncated` like `epic_slices`; a new Drizzle migration through `pnpm db:generate`. A read replaces the epic's rows in one transaction and a failed read leaves them. A pull request GitHub does not know (null) leaves rows and block as they were.

The refresh rule is one function used by the slices and the pull request: live statuses (running, needs-human, ready-for-test) every poll, merged or cancelled only when nothing is cached. For the pull request "nothing cached" means `epics.pr` is null and `prNumber` is set.

`threads` is an additive field of the `epic` reply, optional on the wire (the protocol stays at version 1 and there is no new capability): the app decodes absent as "the engine does not send threads", which hides the section, and an empty list as "no threads", which shows it. The reply keeps GitHub's order; the app sorts unresolved first. A thread with no `line` is shown as its file alone and marked outdated.

Opening the Review tab calls `checkNow` through `ControlClient` and the epic poller then picks up the new reply as it does today. The thirty-second throttle lives in `CarrierCore` with an injected clock, not in the view.

Testing seams, per story:

- Stories 1, 2: no new test. `slicesTabModel` already pins both urls (`SlicesTabTests`); the change is the row's view, which the redesign spec leaves to the owner's visual review.
- Story 3: `slicesTabModel` in `SlicesTabTests`: a waiting slice with a blocker in the list, one outside it, and one with several blockers.
- Story 4: no new test. `ReviewBlocker.url` is already carried and tested in `ReviewTabTests`; the change is the view.
- Story 5: the GraphQL decoding in `github-graphql.test.ts` with a recorded answer kept as a fixture in `github-graphql-fixtures` (synthetic text, never a private repository's comments: null line, deleted author, bot author, empty comment, more than the limit); the engine with the fake `GitHub` in `engine.test.ts` for the stored rows, the redaction of a token in `firstLine` and the cut length; `epic.test.ts` for the reply; `ReviewTabTests` for the model that sorts and labels.
- Story 6: `engine.test.ts` for the poll refresh and for a failed read keeping the rows; the throttle as a pure function in `CarrierCore` with a fake clock.
- Story 7: `engine.test.ts`: a merged epic with no rows is read once and not again; one with rows is not read.
- Story 8: `RepliesTests`: a reply without `threads` decodes to "not sent", with an empty list to "none".
- Migration: the existing `migrations.test.ts` seam.
- Real GitHub: a case in `github.integration.test.ts`, gated by its variables like the others, reading the threads of a pull request of the tester's choosing.

## Out of scope

Reading issue bodies or comment text inside the app, and any panel of slice detail. An archive of GitHub content or a "deleted at source" mark. The pull request's general (non-thread) comments and formal review summaries; the decision is already in the pull request block. Checks by name with a link to each run. Replying to or resolving a thread from the app, or any other write to GitHub. A refresh request per epic.
