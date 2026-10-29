# macOS app: redesigned window and the data behind it

Status: spec

## Problem

The macOS app that shipped as the first version ([the macOS app spec](macos-app.md), epic #75) puts the terminal panel's contents in a plain window: a list of epics with a stage chain, a slice count, a button to open the agent's output as raw text. It shows that something runs, but not what it is doing or why it matters. Diego, who runs Carrier locally and is the only person who reads it, cannot tell from it which agent is working on what, what a review found and whether it is converging, which files an agent has changed, how the slices are going, or what he has to do next, and when an epic stops for him he has no way to go and talk to the agent from the app. The epic has no title either, only a repository and a number.

A visual design now exists that answers all of that: a window with a sidebar of epics grouped by state, an Overview with what needs him and what is running, an epic view with its pipeline fixed on top, the work of each agent as a transcript of messages and tool calls, the files changed grouped by agent session, a right panel with slices as a ring and list, review rounds with their blockers, and details, plus empty states, an About sheet, a Settings screen and a menu that lists the epics. It is final, clickable and drawn with invented data, in [`docs/research/macos-app-design/`](../research/macos-app-design/README.md) (open `diseno.html`). The problem of this epic is to build it in the app and to make every piece of data it shows real, because most of it is not in the engine's snapshot today. The research that says which is which is in [the engine data inventory](../research/macos-app-data-engine.md), [the GitHub and git inventory](../research/macos-app-data-github.md) and [the SwiftUI feasibility study](../research/macos-app-swiftui.md).

It is fixed when the app, started against a real Carrier, shows the experience of the mockup with real data: the owner can open an epic and read what each agent did, see which round of review is open and what is blocking it, see which files each agent touched, and continue a stopped session in a terminal, and where the engine has no data yet the app shows an empty state instead of nothing or something invented.

## Solution

The whole experience of the mockup is built, and the engine changes as much as it takes to feed it. Nothing in the mockup is left out: Continue in Terminal, the file-type icons and the per-session data are all in. The Overview's feed of activity, the statistics and the timeline of epics were explored and not chosen, so they are not part of this. The base is what is already committed on the `feat/macos-sidebar` branch: the mockups, the macOS 26 minimum and the first sidebar split of the window.

The architecture does not change: the engine runs on its own and the app is a client of its control socket, never reading SQLite ([0005](../adr/0005-engine-independent-of-the-macos-app.md)). The protocol stays at version 1 and every change is additive. The `hello` gains the engine's version and a list of capabilities, so a newer app can tell what an older engine can do and show an empty state for the rest. The snapshot, which the app asks for every second, stays small and gains scalars only: engine and watched-repository health, the running sessions with their newest event, and per epic the title, labels, times, branch, workspace, the kind of human intervention and the titles of the open blockers. What is per epic or per session is served by new requests that the app asks for only while that view is on screen: `sessions`, `events` with a cursor, `epic` and `files`. `tail` stays for the plain output window.

The engine records what the agents do. Each harness adapter turns its output stream into events, stored in a new `execution_events` table with bounded, redacted output and served through `events` ([0006](../adr/0006-agent-events-stored-in-sqlite-with-bounded-output.md)). The `executions` table gains the harness, model, provider, working folder and round of each run, because today an old execution would be attributed to whatever agent the epic is configured with now. The `epics` table gains the title, branch and the kind of human intervention. The reviewer's result gains an optional stable id per blocker and a list of ids it resolves, and the review prompt passes the previous blockers back, so the Review tab can say what was fixed and what carries over; without ids the app matches titles and marks the result approximate. Slices are read on every poll for each running epic and kept in `epic_slices` as a cache of GitHub, never as authority ([0008](../adr/0008-slices-are-kept-in-sqlite-as-a-cache-of-github.md)); this reverses the first spec's line that slice progress is only in memory.

From GitHub the engine reads what it already fetches or one query more per active epic. The title and labels are in the epics list it already polls and are currently dropped. Slices with their state, assignee and what blocks them, and, once it exists, the pull request with its check rollup, review decision and merge state, come from one GraphQL query per epic. The integration pull request only opens after every slice is closed, so an epic in ship has no PR and no checks: its changed files come from git, the epic branch and the lane worktrees, and its PR and checks appear afterwards. The files are never taken from GitHub: a local `git diff --numstat` matched the PR's totals exactly on a real PR, has no cap of 3,000 files, sees uncommitted work in a lane and costs tens of milliseconds. The test total of the mockup has no source anywhere and is not shown; the PR's checks take its place. The rate limit shown is the orchestrator profile's and is labelled as such, because the agents run under their own tokens with their own limits; the engine keeps the `x-ratelimit-*` headers it already receives and discards today.

Lanes are shown as read-only sections of the ship session, with their activity and their files. Carrier runs one ship execution per epic and the lanes are Claude subagents inside it, with no session of their own, so the mockup's alternative of a session per lane each with its own resume button cannot be built. The lane of an event and of a slice is a hint taken from the Claude stream (the parent call and the model's own description of the slice) and from `git worktree list`, and is labelled as one. Slots are a counter: the Overview shows the running epics as cards with their agents inside and, after them, a dashed card for the free room that names the next epic in the queue, and the sidebar pill shows how many are in use of the maximum. A numbered "Slot 1, 2, 3" was dropped because a slot has no identity and the numbers would shift when an epic ends.

Continue in Terminal resumes the whole session of an execution that is not running, for an epic that needs a person or has finished ([0007](../adr/0007-continue-in-terminal-through-a-validated-descriptor.md)). The engine sends the harness, the session id and the folder where that session started, never a command; the app validates them against an allowlist, builds the command itself and opens a one-use script file in the user's terminal, as the user and not as the Forge bot. For a Codex or Antigravity session, the transcript shows the summarised `tail` lines until its parser exists.

File-type icons start as SF Symbols by category, behind one small function so the owner can swap the source later, and Material Icon Theme, under the MIT licence, is bundled in a last slice for the identity of each language. The system's own file icons are not used: they depend on the applications installed and return wrong ones (a TypeScript file comes out as a video).

The technical constraints found by the research are part of the spec. Building the app now needs Xcode: with the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode, so the Command Line Tools no longer compile the views and `macos/README.md`, which says they are enough, is corrected. The spinning rings are drawn with Core Animation at a capped 20 fps and are not built while the window is hidden, because SwiftUI's repeating animations cost between 9% and 12% of a core for eight rings and keep running with the window closed; with Reduce Motion on they are static. The ring of slice progress is a custom shape, because the chart framework gives rounded corners but not round caps with a gap. A long transcript is a scroll view with a lazy stack and pinned section headers, not a list. The window is a `NavigationSplitView` with the right panel as an inspector, hosted from AppKit, and its sidebar toggle is an explicit toolbar item because the default one does not appear in a hosted window. The pipeline fixed on top is a safe-area bar, so the content scrolls under it. The status colours are the system's: running green, needs-you orange (darker for text in light mode) and ready-for-test blue, which is not the accent colour. A whole window cannot be verified by rendering a view to an image, because lists, split views and glass buttons draw as placeholders, so the visual review stays with the owner and what is tested in code is the model and the leaf views.

The work is built contract first, in this order. A set of short spikes runs first, in parallel, because several assumptions cannot be settled by reading: real Codex and Antigravity streams, subagent attribution in the Claude stream, the GraphQL queries with the Forge bot's token, resuming a headless session interactively, starting at login with an ad-hoc signature, and a script opening in other terminals. Then a richer snapshot fixture with everything the mockup shows, and the whole window built on top of it with its empty states, so the app can be seen and reviewed from the first slice. Then the engine slices, each one lighting up one part of the window: the fields that need no migration, then the migration with `sessions`, then `epic` with rounds and the stage timeline, structured events for Claude, slices, the pull request block, files from git, the blocker contract, the rate limit, the Codex and Antigravity parsers and the language icons. The small slices that need no migration come first because they carry no risk from the agents' output formats and give most of the Overview, the Review tab and the Details tab.

What lost, besides what is said above: a session per lane with its own resume (cannot be built); keeping slices in memory only (the list of a finished epic would be gone); parsing `stdout.log` on demand instead of storing events (a full parse of a 3 MB log for every count, and no times for Codex); `NSWorkspace` file icons; AppleScript to open the terminal (a permission prompt); `MenuBarExtra` for the menu bar part (nothing new in the SDK, and the reasons of the first spec stand); the app asking GitHub itself (it has no token, and the socket is the only contract); an embedded terminal inside the app (later).

## Scope

Spikes, each ending in a short recorded finding and, where it applies, a fixture:

1. A real Codex review run's stream is captured and saved as a test fixture, with a note of which items carry a command, its output and exit code, and whether a file change carries a diff.
2. A real Antigravity stream is captured and saved the same way, with a note of whether a tool step returns its result.
3. A real Claude ship stream is checked for whether the messages of a subagent can be tied to a lane and a slice, and how much of the lane view can be exact.
4. The GraphQL queries for slices with their blockers and for a PR with its checks, merge state and review decision, run with the Forge bot's token against a private repo, with their real cost.
5. For each harness, an interactive resume of a session that was started headless from another folder is tried and recorded, including which environment folder it needs.
6. Starting at login from the ad-hoc signed `Carrier.app` is tried, and a generated `.command` is opened in Terminal, iTerm2, Ghostty and Warp.

Contract and foundation:

7. The `hello` carries the engine's version and a list of capabilities, and an app that finds none behaves as if the engine had none of them, showing empty states and never failing.
8. The golden snapshot fixture contains every field the mockup shows, the engine's test writes it and the app's tests decode it, with the new fields optional.
9. Whoever clones the repo builds `Carrier.app` with the one script, with Xcode installed, and `macos/README.md` says so and says what happens with only the Command Line Tools.

The window:

10. The window is a sidebar, a detail and a right-hand inspector, with a minimum size, the sidebar and the inspector toggled from the toolbar, glass sidebar and inspector from the system, in light and dark.
11. The sidebar has an Overview row with a pill that shows epics in use of the maximum and a menu that groups the epics by status or by repository, remembered between launches, and Settings and About at the bottom. The epic of [the sidebar spec](sidebar-home-sessions-carrier.md) supersedes the part about the sidebar (Home, Sessions, Archive and the Carrier card; About leaves it).
12. Each sidebar row shows a state glyph, the repository name and the issue number, which is never cut, and a line of detail; the name and the detail end in an ellipsis when they do not fit, in a sidebar from 220 to 320 points wide, with a fourteen-epic list and very long names.
13. The state glyph of a running epic is a ring that turns, drawn with Core Animation at a capped 20 fps, that is not built while the window is hidden and is static with Reduce Motion on; needs-you is an orange mark, up-next a hollow circle and ready-for-test a blue check.
14. The Overview's Your turn lists the epics that need Diego, with the reason and its kind, the finished epics waiting to be tested with their PR, and an engine problem, each with its action, and shows an empty state when there is nothing.
15. The Overview's Running section shows a card per running epic with its progress and one row per agent working on it with its current action, and after them a dashed card that says how much room is free and names the next queued epic.
16. The Overview's Carrier box shows whether it runs, how long, the next check, the GitHub rate limit labelled as the orchestrator's, whether intake is active with the pause or resume action, and the list of watched repositories with their last check and problem.
17. An epic's view has a pipeline on one line, fixed on top with the content scrolling behind it, that shows queued, ship, review and fix, and ready, with the time of each finished stage and the round of the current one, and for a queued epic its place in the queue.
18. An epic's header shows its title, repository and number, its labels without the `solve:` ones, and the PR link; the toolbar offers Open PR and Open issue, and only Open issue while there is no PR.
19. The Agent output tab shows one section per execution, newest first, the running or stopped one open and the finished ones folded, each with the agent's avatar, role, round or lane, and a line of counts: tool calls, edits with lines added and removed, test runs and errors.
20. A session's transcript shows the agent's messages and each tool call as a card with an icon, its argument, result, duration and status, the diff of an edit, and the output of a command collapsed; it opens fast and scrolls smoothly with hundreds of calls.
21. For an epic in ship, each lane is a read-only section with what it is doing and the files it changed, labelled as a hint when it is inferred.
22. A session that stopped for a person shows its reason and a Continue in Terminal button that opens the user's terminal in the right folder with the agent's session resumed; any other finished session offers a quiet link to do the same, and a running one offers none.
23. The Files changed tab shows the files grouped by agent session, the working ones open and the merged ones folded, each with a type icon, its path cut in the middle, and lines added and removed; a file edited by two lanes at once carries a warning in both.
24. Every view that can have nothing to show shows an empty state with an icon, a title and one line: review not started, no files, no slices, waiting for a free slot, nothing waiting, nothing needs you, idle, nothing to test.
25. A queued epic has the same view as a running one, with its pipeline at queued, its slices all waiting, a plan of what each stage will do and which agent will run it, and empty states for output, files and review.
26. The right panel has the tabs Slices, Review and Details, each with a short count, remembering the chosen one between epics and opening on Slices in ship and on Review otherwise.
27. The Slices tab shows a ring of merged, in progress and waiting with round caps and a gap, a legend that selects a group, and the list of that group: in progress with its lane and activity, waiting as ready to start or after another slice, merged with its time.
28. The Review tab shows the current round as a card with three numbered steps, review, fix and verdict, with its blockers marked new, carried over or fixed and its fix commits, and the earlier rounds folded under it, newest first.
29. The Details tab shows grouped rows for timing, progress, pull request and run, including the PR's checks and branch, and which agent runs it.
30. Settings is a screen of the window with a readiness banner and four tabs: Engine, with each path marked found or not found, middle-truncated, with Choose, Reveal and Detect again; Behavior, with the seven values of the config; Repos, with the watched repos and a picker for adding one; and Notifications, with the system permission, a test and the switches. (The first design had Menu bar and General tabs instead; they were dropped, so open at login, the icon style and resetting the saved paths have no screen.)
31. The About sheet shows the icon with the connection state, the name, the version, one line, and the links, and closes by clicking outside or with Escape. The epic of [the sidebar spec](sidebar-home-sessions-carrier.md) supersedes the entry point of the sheet: it opens from About Carrier in the menu bar item's menu, not from the sidebar.
32. The menu lists the epics under its status line, each with its state glyph and a badge, rebuilt every time it opens and only when the setting asks for it.
33. The menu bar icon shows the count and bar, the count only, or the bar only, as chosen in Settings, with or without its animation.

The engine:

34. Without a migration, the snapshot gains the engine's version and poll interval, the maximum of running epics, the times each epic was queued, started and finished, its working folder, and the agents configured for each watched repository and the last check of each, and the hello gains the version and capabilities.
35. With the first migration, each execution records its harness, model, provider, working folder and round, and each epic its title, labels, branch and the kind of human intervention, all of them in the snapshot.
36. The `sessions` request lists every execution of an epic, newest first, with its role, round, agent, status, times and, for one that is not running, the descriptor to resume it.
37. The `epic` request returns an epic's stage timeline, its review rounds with who reviewed, the blockers with their titles, durations and commits, and its worktrees.
38. On every poll the engine reads the slices of each running epic and stores them as a cache, and `epic` returns them with their state, what blocks them, their pull request and when they closed, also for a finished epic.
39. For an epic with a pull request, the engine reads its checks, review decision and merge state, and the app shows them, and shows nothing of them during ship.
40. The engine turns a Claude stream into events, stores them with the caps and the redaction, serves them through `events` with a cursor and gives each running session's newest event in the snapshot; an old log can be replayed to fill the table, and the events are purged with the logs.
41. The `files` request returns the files changed, from git, per session or per slice, with lines added and removed, before and after the PR exists, and flags files edited in two lanes.
42. The reviewer returns a stable id per blocker and the ids it resolves, receives the previous blockers in the next round, and an old result without ids still validates and is shown approximately.
43. The engine keeps the last GitHub rate-limit headers of the orchestrator profile and each watched repository's last poll and error, and serves them in the snapshot.
44. A Codex stream becomes events, and then an Antigravity stream, each from the fixture of its spike.
45. Material Icon Theme is bundled and the file icon function uses it for the languages it covers, falling back to the category symbol.

## Decisions

The wire protocol is the first spec's, extended. The new requests use the same strict schema and the same limits, and the engine rejects anything else:

```ts
const id = z.number().int().positive();
const repo = z.string().max(200).regex(/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/).refine(s => s.split('/').every(p => p !== '.' && p !== '..'));
export const request = z.union([
  z.strictObject({ id, cmd: z.enum(['snapshot', 'pause', 'resume', 'checkNow', 'stop']) }),
  z.strictObject({ id, cmd: z.literal('tail'), executionId: z.uuid(), lines: z.number().int().min(1).max(500) }),
  z.strictObject({ id, cmd: z.literal('sessions'), repo, issue: z.number().int().positive() }),
  z.strictObject({ id, cmd: z.literal('events'), executionId: z.uuid(), after: z.number().int().min(0).optional(), limit: z.number().int().min(1).max(200) }),
  z.strictObject({ id, cmd: z.literal('epic'), repo, issue: z.number().int().positive() }),
  z.strictObject({ id, cmd: z.literal('files'), repo, issue: z.number().int().positive(), executionId: z.uuid().optional() }),
  z.strictObject({ id, cmd: z.literal('availableRepos'), page: z.int().min(1).max(100).optional() }),
]);
type Hello = { event: 'hello'; protocol: 1; pid: number; startedAt: number; version: string; capabilities: ('sessions' | 'events' | 'epic' | 'files' | 'availableRepos' | 'availableReposPaged')[] };
```

The repository check rejects an empty string, three segments and a `.` or `..` part. An unknown epic gets an error reply.

`availableRepos` (added for the Settings screen's "add a repo") takes an optional `page` (GitHub's page number, an integer from 1 to 100; anything else is `invalid request`, and no `page` is page 1) and answers `{ repos: { name: 'owner/name'; private: boolean; pushedAt: string | null }[]; hasMore: boolean }`: one page of 30 of the repos the machine's `gh` login can push to (owner and organization member, sorted by latest push, archived and disabled left out after paginating so a page can hold fewer than 30 or none, names that are not `owner/name` dropped), the same query `carrier init` uses. `hasMore` follows the raw page (it came back full), not what survived the filter. The hello's `capabilities` lists `availableReposPaged` next to `availableRepos`: a client checks it before sending `page`, since the request is a strict object and an engine without it would refuse the field. It waits on GitHub, so it runs without blocking the engine, within `limits.githubCallTimeoutSeconds` for each page, and the replies of a connection still go out in the order of its requests. Any failure (no `gh`, not logged in, offline, timeout) is `{ ok: false, error: 'github unavailable' }`; the reason goes to the log, never to the client. Every reply is bounded by count and bytes and stays under the client's line limit.

The snapshot additions are optional and nullable on the Swift side, so an old engine and a new app, and the reverse, both work:

```ts
type Agent = { harness: 'claude' | 'codex' | 'agy'; model: string; provider: string | null };
type NeedsHumanKind = 'review_limit' | 'agent_needs_human' | 'retries_exhausted' | 'timeout' | 'auth' | 'workspace' | 'pr_invalid';
type SnapshotAdditions = {
  engine: { version: string; pollIntervalMs: number; maxConcurrentEpics: number;
            rateLimit: { remaining: number; limit: number; resetAt: number; profile: 'orchestrator' } | null };
  watched: { repo: string; lastCheckedAt: number | null; ok: boolean; error: string | null; agents: { author: Agent; reviewer: Agent } }[];
  sessions: { executionId: string; repo: string; issue: number; stage: 'ship' | 'review' | 'fix'; round: number | null;
              harness: Agent['harness']; model: string; startedAt: number; last: { kind: string; text: string; at: number } | null }[];
  queue: { repo: string; issue: number; title: string | null; queuedAt: number }[];
  epics: { title: string | null; labels: string[]; queuedAt: number; startedAt: number | null; finishedAt: number | null; branch: string | null;
           workspace: string | null; needsHumanKind: NeedsHumanKind | null; blockerTitles: string[]; agents: { author: Agent; reviewer: Agent } | null }[];
};
```

`repos: number` and `executionId` of an epic keep their meaning, because changing them would be a protocol bump. `blockerTitles` is capped at ten of two hundred characters. The existing fields do not change.

An event is one row, and a tool call is two immutable events joined by its call id, so a cursor that only moves forward never misses an update and the app merges them:

```ts
type ExecEvent = { id: number; at: number; kind: 'say' | 'tool_start' | 'tool_end' | 'note' | 'error' | 'task';
  text?: string; callId?: string; agentId?: string; tool?: string; arg?: string; summary?: string;
  status?: 'ok' | 'err'; durationMs?: number; output?: string[]; diff?: { sign: '+' | '-' | ' '; text: string }[] };
type ResumeDescriptor = { harness: 'claude' | 'codex' | 'agy'; sessionId: string; cwd: string; configDir?: string };
```

The caps are 1 KB for an argument, 200 characters for a result summary, 4 KB for the first and last lines of an output, and a bounded diff. The redaction covers at least GitHub tokens, private-key blocks, `Authorization` headers, well-known provider key prefixes, and `NAME=value` where the name contains `SECRET`, `TOKEN`, `PASSWORD` or `KEY`, and is tested with fixtures that include each shape. Unknown events are ignored and an adapter never throws. A session that is running has no descriptor. The app's polling is: `epic` every three seconds for the epic on screen, `events` every second while a running session's transcript is visible, `sessions` when an epic opens and every five seconds, and `files` when the tab opens and every ten seconds while the epic runs.

The SQLite changes are one migration generated with `pnpm db:generate`: the columns on `executions` and `epics` above, the tables `execution_events` (an integer id that is the cursor, the execution, time, kind, call id, agent id, tool, argument, summary, status, duration and a JSON payload, indexed by execution and id) and `epic_slices` (epic, number, title, state, the numbers that block it, assignee, pull request, closing time and when it was read), and the purge of events with the logs. The slice table is a cache and is never read to decide anything.

The app's code is organised as the research recommends. `CarrierCore` holds the model and everything derived from it as plain values: the sidebar groups and rows, the pipeline steps, the donut fractions, the review steps and their blocker marks, the details rows, the files grouped by session with their totals, the Overview sections, the resume descriptor's validation and the command it builds, and the parsing of the new replies. The views are thin mappings of those values. One observable model fed by the existing monitor is the only data source; values are kept per epic and replaced only when they change, so the sidebar and the transcript do not redraw every second. The window is a `NavigationSplitView` with `.inspector`, `.safeAreaBar(edge: .top)` for the pipeline, `ScrollView` with `LazyVStack` for the transcript, and native small segmented controls for the tabs, switching to custom ones only if the count badge is wanted. Glass is for buttons and the few floating pills; cards that hold content use fills. The menu bar item and its menu stay as they are, with the epic rows added.

The validation of a descriptor and the command it produces are fixed by [0007](../adr/0007-continue-in-terminal-through-a-validated-descriptor.md): the harness is one of the three, the session id matches a strict identifier pattern, the folder exists and is inside the engine's folder (`<folder>/engine/`), each value is single-quoted, the script has mode 0700, is opened with `NSWorkspace` and removes itself.

Testing seams, story by story:

- Spikes (1 to 6): no tests. Each leaves a recorded finding in `docs/research/` and, for the streams, a fixture file that stories 40 and 44 use as input.
- Stories 7 and 8: the engine's golden snapshot test (`snapshot-contract.test.ts`, regenerated with `UPDATE_FIXTURES=1`) writes `macos/Tests/Fixtures/snapshot.json` and fails when it differs; the app's `SnapshotTests` decode it, including an old fixture without the new fields. `server.test.ts` checks the hello over a real socket.
- Story 9: no tests; a checklist in the ticket.
- Stories 11 to 13, 17, 19, 23, 26 to 29 and 32: pure code in `CarrierCore` with Swift Testing, in the existing `macos/Tests/CarrierCoreTests/`: the grouping and ordering of the sidebar by status and by repository, the glyph and detail line of each state, the truncation rule that never drops the number, the pipeline steps and their time labels for each state including queued, the donut fractions and the legend's selection, the review steps and blocker marks for approved, fixing and limit reached, the details rows, the files grouped by session with their totals and the overlap flag, and the menu's item values. The windows themselves have no automated tests; each UI ticket carries a short checklist of what Diego looks at (light and dark, narrow and wide, the long and the empty case), and leaf views such as the donut, a tool-call card, an empty state and a settings row may be rendered to an image in a test to check a pixel, never the whole window.
- Story 13: the occlusion gate and the reduced-motion branch are small pure decisions tested in `CarrierCore`; the rate and the cost are measured once, by hand, and noted in the ticket.
- Stories 14 to 16, 18, 20, 21, 24, 25, 30, 31 and 33: the values behind them are derived in `CarrierCore` and tested as above (what Your turn lists and in what order, the running cards, the health lines, the header's labels, the event merging that joins a call's two events, the empty-state choice, the settings readiness); the layout is a human check.
- Story 22: the descriptor validation and the command construction in `CarrierCore` with hostile inputs (quotes, newlines, `$()`, backticks, spaces, unicode, path traversal, a folder outside the engine's folder, an id that is not an identifier), and a test that the generated script's text is exactly the expected one. Opening a real terminal is a human check, once per terminal the spike found to work.
- Stories 34, 35 and 43: the engine's seams, `snapshot.test.ts` for the fields, `engine.test.ts` with the fake GitHub in `src/orchestration/fake.ts` and the fake runner for the columns and the last poll, `migrations.test.ts` for the migration, and the golden file.
- Stories 36 and 37: `server.test.ts` over a real socket with a database filled by the engine's fakes, for each reply and for the rejected inputs of the schema above (empty, wrong-typed, a path in `repo`, an oversize `limit`, an unknown epic).
- Stories 38 and 39: `src/integrations/github.test.ts` against recorded GraphQL responses, including a slice with no blockers, a PR with no checks (shown as no checks, not pending) and a failing read that keeps the last values; and the engine's fake for the poll.
- Stories 40 and 44: the adapter tests (`claude.test.ts`, `codex.test.ts`, `agy.test.ts`) feeding recorded streams to `parseEvents` and checking the events, the pairing of a call with its result, the caps, the redaction of each secret shape and that unknown lines are ignored; `host-runner.integration.test.ts` with the fake CLIs for the insert path; `retention.test.ts` for the purge; a test that replays an old `stdout.log`.
- Story 41: `git-workspaces.integration.test.ts` style, on a temporary repository with an epic branch, merged slices and two lane worktrees with an overlapping file, checking the numbers against `git` itself.
- Story 42: `caller-result.test.ts` for a result with and without ids and for an old result, and the prompt's text for the previous blockers.
- Story 45: a test that the icon function returns a bundled icon for each covered extension and the category symbol otherwise.
- What is only checked by Diego with real tools, outside the suite: the animation's feel and cost in a real window, the glass and the edge blur, Continue in Terminal in his terminal, and a real run of each harness once its parser is in.

## Out of scope

The activity feed, the statistics and the timeline of epics that were explored for the Overview; they were not chosen and nothing in the design needs them.

An internal terminal inside the app. Continue in Terminal opens the user's own terminal for now; an embedded one is a later possibility.

Giving the app a GitHub token or letting it read SQLite. Everything the app shows reaches it through the control socket.

Resuming a single lane on its own, because a lane has no session. Numbered slots. A test count the engine cannot produce.

Pushed events from the engine. The app keeps pulling, now with a cursor for events, as the first version does.

Changing how the engine runs epics, stages and rounds, and the terminal panel. Only what is recorded and what is served changes.

## Open questions

What Codex and Antigravity actually emit. No real stream of either exists in the repository, so their event shapes, whether a command's output and exit code are included, whether a file change carries a diff, and whether Antigravity returns a tool's result, are only known from notes and fixtures. Spikes 1 and 2 answer it.

Whether the events of a Claude subagent can be reliably tied to a lane and a slice. The stream carries the parent call and an agent id on subagent messages, and the description of the call names the slice in the model's own wording, which is not a contract. Spike 3 decides how much of the lane view can be exact.

Whether an interactive resume finds a session that was created by a headless run from another folder, for the three harnesses, and which configuration folder it needs. Spike 5.

Whether the GitHub GraphQL queries for slices, their dependencies and the check rollup work with the Forge bot's token and what they cost, which was measured with a personal token only. Spike 4.

Whether starting the app at login works with an ad-hoc signature and what the user sees in System Settings, and whether a generated `.command` opens correctly in iTerm2, Ghostty and Warp or only in Terminal. Spike 6.

The real size and write cost of the events table. The estimate comes from twelve Claude executions and has to be measured on the real insert path before the retention and the caps are trusted. Story 40.

The cost of detecting a file edited in two lanes at once on a large repository. It was cheap on a repository of 2,764 files; it has to be measured on a bigger one, and it stays a hint. Story 41.
