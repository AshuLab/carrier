# Epics

An epic in the window: its resume card, its pipeline, its slices and findings, and its Agent output; the epic's starting card is in [the app shell](app-shell.md#starting), and the session views the Agent output reuses are in [chat](chat.md).

## Resume card

An epic stopped in needs-human shows a notice as the last element of its Agent output tab, after the sessions (or the empty or starting state), in the same column (the width the person chose for the chat, Settings › Chat › Message width) (`CarrierCore/Epics/Resume.swift` builds it from the stuck kind, `Carrier/Features/Epics/ResumeCardView.swift` draws it as a `NoticeCard`, `CarrierUI/Cards/NoticeCard.swift`): the reason as the title, one line of what resuming does for that kind, tinted orange when a person's input is needed and red when something failed.
The pipeline above does not say why a step stopped; the notice does.
It has a Resume button only when the engine's hello lists `resumeEpic` (`EpicStore.canResume`, read from the connection the epic poller uses); against any other engine the card shows the reason and the words with no button.
Resume opens a sheet saying what will happen; confirming sends `resumeEpic` with the epic's repository and number on a connection of its own (the engine answers when the epic has started, up to 30 seconds), the button reads "Resuming…" until then and until the snapshot shows the epic out of needs-human, or stopped again after the answer (kept in `EpicStore.resuming`, so selecting another epic and coming back does not lose it), and a refusal (`unknown epic`, `not stopped`, `github unavailable`, `did not restart`) is shown in words, in orange, under the notice's line.

## The pipeline

The strip under the toolbar of an epic shows the steps of its pipeline, each as its state mark and its name, centred and as wide as the feed.
It does not say why a step stopped: for a needs-human stop the notice at the end of the Agent output does (see the resume card above).

## Slices and findings in an epic's log

In the builder's session each slice is a glass card of its own, in the order it happened between what the builder said and did: its state, `#730` and title, a quiet line (the step it is on while it works, calls, edits, test runs, errors, the lane, when it ran) and its pull request with a dot for its state (merged, open, draft), which opens GitHub.
Tapping the card opens that subagent's **Subagent view** over the Agent output tab, the one a subagent's row opens in a conversation (`subagentWork(lane:in:epic:)` gives it the lane's own call groups, thoughts and messages, all the runs of a resumed subagent in one view, and no brief).
The window's header then has a ‹ Back button next to the sidebar's, the slice's title as the title (the subagent's own description when the slice is not in the epic's list), "<Builder or Reviewer> · <the epic's title>" under it and the state (Running with a timer, or alone while the lane's start has not arrived; Finished with its duration; Failed) where the epic's links are, with no Stop button; Back, or the ‹ Back to Agent output button where the message box would be, returns to the tab as it was.
In a reviewer's session a second card shows the review: its verdict ("Ready", "Changes requested"), the round and the reviewer's name, its blockers first and then its suggestions, each with its kind as a word, its id, a line, whether it is new, carried (still open) or fixed (verified by the next round, dimmed), and the whole row opens the discussion on GitHub.
An approval's suggestions wait behind one line ("4 suggestions").
The reviewer's verification (CI passed or no CI) is the foot of that card and opens on its evidence, so the reviewer's session has no separate "Completed" row (a stop keeps its row); the engine sends no commit, so the foot names none.
The fixer's session shows the same round's blockers with the ones the next review verified marked fixed, under its own result row.
A note "created 946 (branch)", which Claude Code emits when the agent publishes a change (`code_change_published`), is a quiet line with the pull request as a link; a skill, the closing result and Continue in Terminal are lines of the same card family.
How they are drawn is in [the look of the app](../ui.md#cards-in-the-feed).

## Agent output

An epic's Agent output tab lists its sessions oldest first, the newest last, as centered rows with no card (how they are drawn is in [the UI guide](../ui.md#rows-of-a-feed); the words are `sessionRowText` and `sessionSummary` in `CarrierCore/Sessions/SessionRowText.swift`, `earlierSessions` in `CarrierCore/Sessions/SessionSections.swift`).
A row says who acted (the GitHub profile, an Agent Forge bot, or the tool's name when none is known), the role and place ("Builder · Ship", "Reviewer · Round 2"), and on a second line the tool, the account, the model and the effort that are known.
The engine's `sessions` reply gives the key of `profiles` the session acted as (`profile`), and the app reads `engine.json` when the tab opens to say whose account that is: a `forge` profile is named by its Agent Forge bot, a `gh` profile has no name in the file, so such a session shows the tool's name, and a key the file does not have stays as sent.
An engine that sends no key (an epic frozen before it was kept) gets the bot of `agents.author` (builder and fixer) or `agents.reviewer`, and the role's `effort` when the session ran on the role's model.
A repository's own `agents` override is not read.
Under the row one line sums the session up: while it runs "Working · since 16:09 · 62 calls"; stopped, the orange `stopped` badge and the failure's kind and detail; open, the counts (calls, edits with their lines, test runs, errors, time); folded, how it ended in bold (Completed, Changes requested, Needs a human), the CI verdict and the time, or the counts when it has no result.
The whole row is the one button that folds the session (the newest and a running or stopped one start open); there are no pinned headers.
Above five sessions the oldest ones are one row ("3 earlier sessions · Builder, Reviewer, Fixer · 45m") that opens them.

## The epic's Agent output

The Agent output tab of an epic draws the agent's work with these same views.
The engine's events (`ExecEvent`, from the harness parser) are turned into the chat's `ToolCall`s and `ToolGroup`s by `Transcript` and `flowItems` (`CarrierCore/Chat/TranscriptItems.swift`, `CarrierCore/Dictation/TranscriptFlow.swift`), so a run reads the same as in a session: one work card per run of calls, folded until opened (open already when Settings has Tool output on expanded), the agent's text as markdown, an error as the red banner.
An edit with a diff shows as a call with its diff inside the card, as in a session.
The newest run of a running session is live (shimmer, ring, glow), and a call that never ended in a session that is over shows as stopped.
A thought is drawn if the events carry one (`reasoning`; today's parsers send none) and follows Settings, Show reasoning.
What is only the epic's stays between the runs, in event order: notes (a change the agent published, "created 736 (main)", is a quiet line with the pull request as a link), skills as a row of their own, and a subagent's slice row, which opens its Subagent view.
A harness with no parser shows its summarised `tail` lines instead.
The calls are hidden when Tool output is hidden.

## Where it lives in the code

What the person sees: [the epic's Agent output](#the-epics-agent-output) and [the log's slices and findings](#slices-and-findings-in-an-epics-log); the resume card words and request are tested, the sheet, its "Resuming…" state and layout not.
The rows, words and marks are two pure functions, `sliceCard(lane:)` (`SliceCard.swift`, `SliceCardTests`) and `findingsCard(_:stage:round:)` (`FindingsCard.swift`, `FindingsCardTests`, which also reads the golden epic reply); the views only for their heights (`LaneHeaderTests`).
The words of the whole area are copy keys (`epics*` in `design/copy/`), and `EpicsSpanishTests` and `EpicViewSpanishTests` render each function that builds a sentence in Spanish.
The session row's words are `sessionRowText` and `RoleIdentities`; the epic's events become the chat's calls in `flowItems` (`EpicTranscriptAdapterTests`).
