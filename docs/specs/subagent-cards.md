# The Agent output tab tells each slice of a ship session apart

Status: spec

## Problem

Diego opens the macOS app's Agent output tab after (or while) a ship session ran several subagents and cannot tell them apart. They appear as six identical flat rows, `SLICE #246 Lane 1 hint` to `SLICE #251 Lane 3 hint`, in order of appearance, each with a blue pill, a lane number and a grey `hint` mark. Nothing says what a row ran, how it ended, when it ran or what it cost: no slice title, no end state, no times, and the line of counts that exists is cut off. The `hint` mark repeats on every row and only explains itself in a tooltip.

What Diego wants to read is, for each slice, what ran, its final state, its name, how it ran over time, and the statistics: how many tool calls, whether there were errors, and the rest of the detail. It is a per-subagent report, read mostly after the work and also while it runs.

The lane sections were built by story 21 of the [macOS redesign spec](macos-app-redesign.md) and show an event transcript per subagent; this is not a missing feature but a section that does not use what the engine already sends. The slice list the app already holds (title, pull request) and the events of each subagent (their own start and end, the end status) are both there and ignored.

Two things in the model were also wrong. The glossary said a lane is a subagent building one slice, but a lane is a worktree that is reused (lane 1 built five of the eleven slices of epic #244, with at most three running at once), so a row that says "Lane 1" names a place, not a worker. The glossary now says so, and defines **Subagent** as the exact thing.

## Solution

Each builder subagent is one row of the ship session, drawn with what the app already has, on a glass surface like the window's own controls. The reference is the prototype `docs/research/macos-app-design/explorations/subagent-lanes-glass.html`, built from the real events of epic #244.

From left to right a row has a slice icon, the number and the title, its duration, its end state, and a round chevron on the right (the same button the session's header has). Under it, on the left, are the count pills of the session's header (tool calls, edits with their lines, test runs, errors: the same component, not a copy, with its fallback to icon and number when there is no room); on the right, as text, the lane, the pull request and when it ran. Unfolded, the calls go the full width of the row with no indent, the rows of the main thread.

The title comes from the epic's slice list, joined by the slice number the subagent is building. The end state has three values: running (a start with no end), finished (the end event completed) and failed (it did not complete); failed also covers a start with no end in a session that is no longer running. The pull request, with its state (open, draft, merged or closed), comes from the slice. One row is one slice: the runs a subagent made after its first end (a follow-up message with the same agent id) are inside the row, which says `resumed once` or `resumed N times`. The times are the first start and the end of the first run; a running subagent shows `since HH:mm` and its duration so far.

The `hint` mark stops being a pill on every row. The slice number is checked against the epic's slice list and, when it matches, is exact and unmarked. The lane is the only thing still inferred (from `--lane-N` in the worktree path the subagent touched) and keeps a discreet `≈` after it, with its explanation in the tooltip.

A subagent whose description names a slice that is not in the epic's list keeps the row, with the number and the description as its title and `no PR yet`. A subagent whose description names no slice keeps today's rendering, a section titled by its description. Rows stay in order of appearance, as today.

The data needs no engine change. The app reads the subagent events it already fetches and the slice list of the epic reply. What it needs on its own side is to decode the pull request state and merge time that the engine already sends per slice (an older engine sends neither, and the row then shows the pull request number alone), and to derive the end state, the times and the resumed runs from the events.

## Scope

1. A slice's row shows its icon, `#N` and the title of that slice in the epic's list; with no match it shows `#N` and the subagent's description; with no number it is today's section.
2. A row shows running, finished or failed: a spinner, a green tick or a red cross, and a red tint on the icon when it failed.
3. A row shows its duration (running: `since HH:mm` and the time so far) and, on the right of the second line, when it ran as `HH:mm–HH:mm`.
4. A subagent that ran again after its end is still one row, and says `resumed once` or `resumed N times`.
5. A row shows the same count pills as the session's header, for that subagent's events: all but the calls only above zero, errors in red.
6. A row shows `PR #N` and its state when the slice has a pull request, and `no PR yet` when not.
7. A row shows `Lane N ≈` when the lane was found, with its explanation as a tooltip, and no `hint` pill; the slice number carries no mark when it matches the epic's list.
8. A row folds and unfolds with the round chevron on the right; unfolded, its calls are the main thread's rows at the full width of the row.
9. The slice list's pull request state and merge time are read from the engine's epic reply, and an older engine's reply, without them, still decodes.

## Decisions

The join is by the slice number: `sessionList` takes the epic's slice list besides the sessions and the transcripts, and a lane section carries the slice's title and pull request, its end state, its first start and end, the number of runs after the first, and its counts as `SessionCounts` (the type `CountPills` takes) instead of the string it carries today.

The duration of a row is the app's `formatDuration` ("45s", "3m"), the one every other duration of the panel uses, so seconds show only under a minute. That fits the times: the engine stamps the `task_started` and `task_notification` lines with the time it received them (the stream lines carry none, checked on the real events of epic #244), which is accurate to a few seconds while it reads live. No marker says so.

The reusable parts are not rebuilt: the count pills (`CountPills`), the round chevron of the session's header, the rows of the transcript, `.glassEffect` for the surface. The slice icon is the prototype's, a pie with one slice pulled out, drawn as a shape or taken from the system symbols, as the implementer finds better; it is not a design decision to reopen.

The `hint` field of a lane section and its pill go. The lane stays a hint, read from the worktree name; `failed` means "did not complete", not a cause, since the stream tells only `completed` from anything else.

Testing seams, by story:

- Stories 1 to 7: `sessionList` in `LanesTests` and `SessionSectionsTests`, with the events of a canned stream (a start, calls, an end; two runs of one agent; an error; a start with no end in a running and in a finished session) and slices from `EpicReply`. They assert the lane sections' fields: title, state, times, resumes, counts, pull request, lane, hint-free. This is the broadest seam: the whole behaviour behind one function.
- Story 9: `RepliesTests`, decoding an epic reply with and without `prState` and `prMergedAt`.
- Story 8 and the row's look: `LaneHeaderTests`, in its existing style (`ImageRenderer` at a width): the header keeps its height folded or unfolded, running, finished or failed, with or without a pull request and at a narrow width, where the pills fall back to icon and number. The glass surface and the icon have no automated test: the prototype is the reference and the owner reviews them in the app, as with the rest of the macOS views.

## Out of scope

The timeline of lanes. A separate treatment for review subagents: a ship session has builders only. Grouping by lane. The Slices tab and the Files changed tab. A change to the engine or to what it stores. Subagents of Codex and Antigravity (they have none in this repo). Resuming a single subagent. Notifications about a subagent ending. The prototype's `invented` marks, which exist only so the running and failed states could be drawn when the real epic had neither.
