# The Agent output tab reads as one quiet, ordered log

Status: spec

## Problem

Diego reads a session's Agent output live and after the fact, and what he is looking for is always the same three things: what failed, what the agent said, and what it changed. The tab buries them. On the engine's real runs 29 of 1,061 tool calls failed (under 3 %), yet every call carries a green tick, a duration and a coloured icon box, so the few that matter drown in the rest. A reviewer session of 23 calls is 23 identical rows. The title of a call is the first command of its chain, so every command that starts with `cd <worktree> &&` reads as the same line (`cd /Users/vemec/.solve/worktrees/carrier/the-… +6`, ten times in a row). An opened call is a block of dark glass with the whole output in red, although only `Exit code 1` is the failure. An edit shows its counts twice in the header and its absolute path.

The order is also wrong. The session shows every row of the main agent first and then every subagent stacked after, each under a glass header. The main agent announces a batch ("starting #246, #247, #248") and the next row is not those slices; an error of the main agent that happened while a slice ran sits above all the slices; and nothing marks when a slice was taken or returned, because the transcript builder drops the `task` event that says so. Found reviewing three real sessions of epic #244 and its slices with Diego, 2026-10-23.

## Solution

The log becomes one list in the order the events happened, drawn quiet. The numbers, states and colours are fixed in the design spec `docs/research/macos-app-design/explorations/agent-output-spec.html` (1 px there is 1 pt in the app; its section 4b is the alignment checklist every view must match, and section 5 lists the files). The options Diego chose from are in `agent-output-lines-options.html`. This document holds the rules; the page holds the measures and every state drawn, in dark and light.

**Calls are quiet and grouped.** A run of two or more successful calls (commands, reads, searches, other tools) folds into one group row, "Ran 4 commands · read 2 files", with the sum of its durations, folded by default; a lone call is a quiet line. A successful call shows no tick. Its duration appears on hover and keyboard focus, and always when the call took 10 s or more. A failed call is never inside a group: it breaks the run, shows a red cross, a red glyph and a red duration, and starts open as it does today. A call that has not ended is its own line with a spinner, after the group; when it ends well it joins the run. Skills (the tool `Skill`) and edits are milestones of their own: they end a run and are never grouped. A shell title skips a leading `cd` (and `cd … &&` or `;`) and shows the first real command; the "+N" for the commands chained after it is a quiet secondary count.

**The opened call is a flat grey block**, the same grey as the message bubble, with no glass and no outcome pill: a strip with the command (`❯`, or the tool's name for a read or a search), the output, and the footer with the line count, "Show N more lines" and Copy. Only the first line `Exit code N` of a failed call is red; any other failure prints plain. A call with no output says "no output".

**An edit is "name first":** the file name in bold with its folder dim after it (relative to the worktree), the counts once, no tick, no duration, and no engine summary when it worked. A failed edit shows a red cross and the reason in red under the header, with no diff; a running one a spinner. A diff of more than 30 rows is cut there with the console's "Show N more lines", and an edit that only adds lines carries a small "new" tag.

**A slice is a row of two lines with no box**, placed where it was taken. Line one is a normal row: the state (spinner, green tick or red cross), `#N` and the title, and a chevron in the same column as a call's, always visible. Line two repeats what the glass row said: the count pills, the lane, the pull request and its state, and when it ran. It opens in place, closed by default whatever its state, and what is open is remembered per subagent; its body is the subagent's own rows with the same rules (groups, quiet lines, messages, edits), under the title and behind the thin rule a group has. The state follows the latest run: running when the last `task` event is a start, else finished or failed by the last end; the times stay those of the first run and the row says `resumed once` as it does now. The glass surface, the full width with no indent and the order of appearance of `subagent-cards.md` are reversed by this; its title join with the epic's slice list, the pills, the pull request and the lane hint stay as they are.

**The list is merged in event order.** The main agent's rows and the subagents' are one list ordered by event id; a slice sits at the id of its first `task` event with no status (a subagent with no such event, at its first event). So what the main agent did and said while the slices ran sits below them, and a batch announced by the main agent is followed by its slices. The main thread's `Agent` call that launched a subagent (it shares its `callId` with that subagent's `task` start, checked on 8 of 8 launches in the real data) is not drawn: the slice row stands for it. An `Agent` call with no subagent yet stays a normal line.

Every row of the log shares one set of columns (the icon at 12, the title at 36, then the duration, status and chevron columns at the right, always reserved) so titles cut at the same place and durations line up down the whole session; the colours are the three adaptive surfaces of the spec (the card, the raised grey of bubble, detail and edit, and the near-black console for diffs only), so dark and light both read.

## Scope

1. A run of two or more consecutive finished, successful calls of kind shell, read, search or other is one group row whose label counts them by kind (first-call order, two parts at most, "+N more" after) and whose duration is the sum of theirs.
2. A single successful call between other items is a quiet line, not a group.
3. A failed call is never inside a group: it ends the run, shows a red glyph, a red cross and a red duration that stay visible, shows its chevron whether open or not, and starts open. What the user opens or closes is kept.
4. A call that has not ended is its own line with a spinner and no duration; when it ends successfully it joins the run, and the group's count goes up by one.
5. A successful call shows no tick. Its duration shows on hover and keyboard focus, and always at 10 s or more; the right-hand columns are reserved so nothing moves.
6. A group is folded by default, and what the user opens is kept by the id of its first call, which does not change when calls are appended to it.
7. A shell command's title skips a leading `cd …` (alone, before `&&` or before `;`) and shows the first real command, with the rest as "+N"; with nothing else after it, the title is the `cd` itself.
8. A skill call (tool `Skill`) is a row of its own with its name, and a skill or an edit ends a run.
9. An opened call is a flat grey block with a strip (the command, or the tool's name), the output cut at 7 lines with "Show N more lines" and "Show less", and a footer with the line count and Copy; no glass and no outcome pill.
10. In a failed call the first output line, when it starts with `Exit code`, is red and the rest is normal text; a call with no output says "no output".
11. An edit's header shows the file name bold, its folder dim and relative to the worktree, and the added and removed counts once; it shows no tick, no duration and no summary text.
12. A failed edit shows a red cross and its reason (two lines at most) and no diff; a running one a spinner; one the engine sent with no diff shows the header without counts.
13. A diff of more than 30 rows shows the first 30 and "Show N more lines"; an edit with only added lines carries a "new" tag.
14. A session's rows, the main agent's and the subagents', are one list in event-id order, each subagent at its first `task` start (or, with none, its first event); a main-agent row that happened while a slice ran appears after that slice's row.
15. The `Agent` call of the main thread that has a subagent (same `callId` as its `task` start) is not shown; one with no subagent stays a line.
16. A slice row has two lines and no surface: state, `#N` and title, and a chevron in the call lines' column; and under the title the count pills, lane, pull request with its state and the times.
17. A slice row is closed by default in every state, opens in place on the subagent's own rows under a thin rule, and what the user opened is kept per subagent.
18. A slice row's state follows its latest run (running again when the last `task` event is a start); its times are those of the first run and it says `resumed once` or `resumed N times`.
19. A subagent with no slice number keeps its description as the title and no `#N`; one with a slice that is not in the epic's list keeps the description and `no PR yet`, as `subagent-cards.md` set.
20. Every row of the log sits on the same columns and at the heights of the spec (call line 26, group 28, slice line one 28), in dark and in light.
21. A call line says its state and duration to VoiceOver whether the duration is drawn or not; a group says its count, duration and whether it is open; a slice row says its slice, lane, state, pull request and counts.

## Decisions

**The model.** `SessionSection` stops carrying the main rows and the subagents apart (`body` and `lanes`) and carries the one list. The grouping and the merge are a pure function over what `Transcript` already builds, computed when the section is built; an appended event must not rebuild the transcript (the existing counter of events processed keeps being asserted). The shape:

```swift
public enum FlowItem: Equatable, Identifiable {
    /// A message, note, error, skill, edit or a call that is a line of its own.
    case item(TranscriptItem)
    /// Two or more successful calls in a row; its id is the id of the first.
    case group(id: Int, calls: [TranscriptItem])
    /// A subagent, at the id of its first `task` start.
    case slice(LaneSection)
}
```

A harness with no parser keeps `TranscriptBody.tail`, unchanged. `LaneSection` gains its start id and its running-again state; `Lanes.swift` still routes the events by `agentId`, and the main thread's `Agent` call is matched to a subagent by `callId`.

**What the card carries.** `TranscriptCard` gains `isSlow` (10 s or more) and `isSkill` (tool `Skill`), and the title and its "+N" become two values so the view can style the count; an edit's folder is relative to the worktree (the path after the worktree folder's name, else the last two folders after "…/"). The 30-row cut is a value of the card, as the 7-line cut of the output already is.

**Settled on the real data** (`carrier.db`, 63 `task` events, 1,061 calls): the skill tool is `Skill`; `Exit code N` is the first output line in 22 of 29 failed calls and the rest have another shape; every launch has an `Agent` call with the same `callId` as its `task` start; two subagents were resumed once; edits often have no diff.

**ADRs.** None: nothing here is hard to reverse. The glossary gains **Call group** and **Slice row**.

**Testing seams, by story:**

- Stories 1 to 6, 8 and 14 to 18: `sessionList` in `SessionSectionsTests` and `LanesTests`, with canned events (runs of successful calls, one failure in the middle, a pending call at the end, a skill and an edit in a run, two subagents started together with main events between, a subagent resumed and running again, a subagent with no start, a late event with a lower id). They assert the one list of the section: its kinds in order, the group's label, count, duration and id, the slice's position, state, times and resumes. This is the broadest seam: the whole behaviour behind one function, with the transcript's own `work` counter asserted on an append.
- Story 7: `CommandTitleTests`, with `cd x`, `cd x && cmd`, `cd x; cmd`, `VAR=1 cd x && cmd`, quoted paths and nothing after the `cd`.
- Stories 9 to 13: `TranscriptItemsTests`, on the card: the strip, the cut at 7, `Exit code` as the first line, no output, the counts once, the relative folder, failed and running edits, the cut at 30, the "new" mark, an edit with no diff.
- Story 15: `LanesTests`, with a main `Agent` call and a subagent sharing a `callId`, and one without.
- Stories 16, 19 and 20 (the look and the heights): `LaneHeaderTests` in its existing style (`ImageRenderer` at a width), now for the slice row and the group row: the height does not change folded or open, running, finished or failed, with or without a pull request, at a narrow width where the pills fall back to icon and number. Colours, spacing and the alignment checklist of the spec have no automated test: the page is the reference and the owner reviews them in the app, as with the rest of the macOS views.
- Story 21: no tests: the labels are built in the view from values the seams above already pin; the owner checks them with VoiceOver.

## Out of scope

Messages, notes, the JSON message card and the markdown inside a bubble; the session header, its count pills and the stopped badge; the result card and Continue in Terminal; the Slices, Files changed and Review tabs; the harnesses with no parser (the `tail` lines); any change to the engine or to what it stores; notifications; and a timeline or Gantt view of the lanes. The "Earlier sessions" row was already moved off glass in the app; its spec `earlier-sessions.md` still says glass and is a separate tidy-up.
