# Changelog

All notable changes to Carrier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Keep awake: stop the Mac from sleeping from the menu bar (30 min to 5 hours, or until you turn it off), with a small cup on the icon while it holds.
  It can also stay on while agents work and for a few minutes after, pauses on a low battery and tells you when it stops by itself.
  Set it on the new Keep awake page of Settings, with an optional shortcut for any app.

## [0.13.1] - 2026-11-18

Fixes after 0.13.0: starting from the app with a late PATH, pull requests of SSH-alias remotes, the draft's reasoning levels and choosing a repository to clone.

### Fixed

- Carrier no longer fails to start from the app for a folder you added to your shell's PATH after the app first read it (pnpm's, where `agent-forge` lives): when a start ends with `spawn agent-forge ENOENT`, the app reads the PATH from your shell again and starts once more, and if the tool is still not there the alert says so.
- A session whose `origin` is an SSH alias of GitHub (`git@github.com-work:owner/repo.git`) shows its pull request and its changed lines again, and the worktrees you make from it go under its `owner/repo`, like any GitHub repository.
- In a new session, the Reasoning slider lists the levels of the model you chose and not those of the agent's default one, and the reasoning set in Settings is kept when that model takes it (a draft on GPT-6.1 Terra showed only Low and dropped High).
- Choosing a GitHub repository to clone no longer fails when only your GitHub login could not be read, a `gh` that is too slow to answer is no longer reported as signed out, a folder that cannot be made is no longer called "already there", and a cancelled clone leaves no empty owner folder behind.

## [0.13.0] - 2026-11-18

Settings gets a page of its own for About, with the update delay, and the app's rough edges after 0.12.0 are smoothed: subagent views, account marks, the dictation widget and the timeline's cards.

### Added

- Settings › About, kept at the foot of the rail, replaces Updates: the app's icon and version, links to the release notes, the documentation and GitHub, a Star Carrier on GitHub row, and the updates with the engine's own.
- Settings › About › Update delay (None, 1, 3, 7, 14 or 30 days): Carrier waits that long after a release before it offers it by itself; Check now and a critical update ignore it.

### Changed

- Settings: Dictation is in the App group, after Keybindings, since it is global; the Legacy group is gone and Health is the last page of Carrier.
- Settings › Dictation › Cleanup: the switch turns the whole group on and off (the server, model, prompt and test are dimmed while it is off), and you choose the server after turning it on. The test is a Try it box: a sample dictation with fillers in English under Dictated, a button, and what the model gave back under Cleaned, with a shimmer while it works and an orange box with the cause when it fails.
- The sliders of Settings › Dictation › Sounds and Settings › Terminal have no tick marks under them.
- "Use a worktree", in the notice about uncommitted files, is in the color of the text and not the accent, so it reads over the orange.
- The card of a turn in the conversation's timeline has larger text, more contrast and more room.
- The line that closes a turn says the context it ended with ("181.2k context") and not the sum of what each model call read; a turn stored without it says "N in".

### Fixed

- A subagent's view replaces the conversation instead of showing it through, and its state, Stop and the terminal button sit at the right of the window's header.
- The model menu, the message box and the session's card show an account's own mark in its color and not a letter ("C Lu"), also for an account named by you.
- The dictation widget no longer grows as tall as the screen when it holds a text that was only copied or a failure, and the reasons over a copied text no longer squeeze it.

## [0.12.0] - 2026-11-18

A new layout for the Carrier folder, and what it holds stops growing without end: the configs sit at the top as `engine.json` and `chat.json`, the logs rotate, a message's files go with their session, and the folders of finished epics and of idle sessions' worktrees are cleaned up.
Old paths are not read: move `config.json` to `engine.json` and `chat/chat.json` to `chat.json`.

### Added

- When an epic is merged or cancelled, the engine removes its reviewer checkout, its worktrees (not one with uncommitted files or commits on no branch) and its local branches already on the remote, also for epics that ended earlier.
- `worktreeCleanup` in `chat.json` (off by default) removes the folder of a session's worktree once its pull request is merged or it is archived and has had no activity for `afterInactiveDays`, keeping the branch; the next message brings the folder back.

### Changed

- The Carrier folder has a new layout ([ADR 0034](docs/adr/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)): the engine's config is `engine.json` (was `config.json`) and the chat's is `chat.json` at the top (was `chat/chat.json`), next to `providers.json`; the app keeps its terminals and dictation history in `app/state/`, its speech models and terminal shim in `app/cache/`. Old paths are not read: move or recreate the files.
- What the Carrier folder holds no longer grows without end: `orchestrator.log` and `chat-host.log` rotate at 10 MB and keep 10 files; a file dropped in a message waits in `chat/pending/` and moves into `chat/sessions/<id>/attachments/` when the message is sent, so deleting the session deletes it, and one left in the box for more than a day is swept, and is copied again from where you dropped it when you send (if the original is gone too, the send waits and its chip says so); the execution results in `engine/state/results/` go with the execution logs 30 days after the epic ends; and the app's `cache/` is kept out of Time Machine.

## [0.11.0] - 2026-11-18

Dictation that is live and fast: the microphone starts at the press, the words that will not change are drawn as normal text, and the speech model can stay loaded in the background so the first dictation does not wait for it.

### Added

- Settings › Dictation: Keep the speech model ready (on by default) loads the model you chose in the background when Carrier opens, when you turn Dictation on and when you change the model or language, so the first dictation does not wait for it; Release the model after (5, 15, 30 or 60 minutes without dictating, or Never; 15 by default) frees the memory of a model nobody is using, and the next dictation loads it again.
  Both are dimmed with Dictation off.
- Each dictation writes one line to `dictation.log`, with no text, saying where its time went: from the press to the microphone running, to the first audio, to the model ready and to the first word, and from the stop to the final text.

### Changed

- Dictation: the microphone starts at the press even when the speech model is not ready.
  The box and the widget show the listening line and the clock with "Getting the model ready…", the words you say meanwhile are kept and appear once the model is ready, and the start sound plays when the first audio arrives.
  A model that is not ready after 30 seconds fails as a dictation that could not start.
- Dictation: only the words still forming are drawn as partial text (dotted underline, accent colour); the words that will not change are normal text, so the text no longer reads as a guess from the first word to the last.
- Dictation: "Transcribing…" shows only when the final text takes more than a quarter of a second after the stop.
- Dictation: Apple's recognizer no longer trades accuracy for speed, Whisper skips word timestamps when it gives its text at the end and cuts a recording longer than 30 seconds at its pauses, and Parakeet TDT v3 and Ultra warm up when they load, so the first dictation does not pay for the first pass.

## [0.10.0] - 2026-11-17

Switch a session to another agent and hand work to child sessions, and see what the agent waits on: the conversation shows its subagents, its background tasks and what each call is doing, and the sidebar's cards show pull requests and lines changed.

### Added

- In `carrier chat`, `/agent <name>` switches an idle session to another configured agent: the new agent starts a fresh conversation and can read the old one through the `history` tool, so you go on where you were when a quota runs out or you want a second opinion.
- When Claude or Codex hits a usage limit, the chat host reports it as its own error that names the agent and its reset time, so a client can offer another agent.
- A session's agent can start child sessions on other agents or models with `delegate_start`, wait for them with `delegate_wait` and read their results, and each delegation asks you first, saying what will be sent; a child takes no messages, and a parent and its children are archived, deleted and aged as one.
- The live line of a conversation says what the agent is waiting on with a chip (Thinking, Read, Search, Edit, Shell, the MCP server's name, N subagents, Needs you), its timer counts the running call and not the whole turn, and a Shell or MCP call that runs past 30 seconds turns it amber; an MCP call reads as its tool and server, not as raw JSON, and a finished run counts MCP calls and subagents apart.
- Each subagent a session starts is a row of the conversation (its type, title, current step, count of steps and timer, with a tick, a red mark or a square when it ends), and its calls, thoughts and messages no longer land in the main agent's message.
- In an epic's Agent output tab, a slice card shows the step its subagent is on now.
- A session stays working while its subagents run, even after the main agent's turn ended: the sidebar and the header show it working, Archive is off, and Stop in the message box stops the running subagents as well as the turn; a subagent that never ended in a session that is no longer working shows as stopped.
- Stop a running subagent from its own view: a Stop button next to its state in the window's header ends only that subagent, not the main agent, and the row and the view show Stopped once it has; a chat host from before this change does not offer it.
- Tap a subagent's row in a conversation to open its own view: its brief from the main agent, then its calls, thoughts and messages as the main agent's are drawn, with ‹ Back in the window's header (title, "Explore · Subagent of <session>" and its state in place of the worktree pill) and a read-only note where the message box is.
- In an epic's Agent output tab, tapping a slice card opens the same subagent view (its calls, thoughts and messages, all its runs in one view) with ‹ Back in the window's header, the slice's title, "Builder · <epic>" and its state, instead of unfolding the card in place.
- A session in the sidebar that has a pull request, or lines it changed, shows them on a third line: the pull request's number and how it stands (draft, open with its checks, merged, closed), the lines the session changed and the providers (either of the first two alone when it has only that). A click on the chip opens it on GitHub. The pull request is found once by the session's branch with your own `gh` login and then only its state is asked again.
- While the agent waits for something it started, the conversation has a line over the message box that names the tasks one after another, shows how long the oldest has run, opens to the list of them and has Stop, for all of them or, in the list, for each one.
- Settings › Sidebar › Session rows has switches for the pull request and for the lines changed, both on.
- The card that opens on a session's row says its state in the row's colours, its pull request and the lines it changed, and what the agent waits for in the background.
- A session whose turn ended while the agent waits for a build, a monitor or a subagent shows as working (a cyan ring and its clock) and not as idle or "Done"; it can be stopped and cannot be archived until the tasks end. The turn the agent starts on its own when one of those tasks ends shows as working too, and not as idle.

### Changed

- The cards that open when the pointer rests on a session or an epic in the sidebar are tidier: a long folder or branch is one line cut in the middle (the whole of it in its tooltip) instead of breaking over several lines, the branch has its own line, the agent shows its account's mark and name, and a session's state has the color of its row and says Done, as the row does, for a turn you have not opened.
- Usage: where an account has a header of its own (several accounts of a tool, or one that needs a look), it wears its icon and color before its name, as it does everywhere else in the app.
- The banner of a turn that failed or was refused ("Lu couldn't continue") names the account by its label or display name, and wears its icon and color when it has them, so two accounts of one tool are told apart there too.
- An account with no label is called by its display name, and not by its key, in the provider tabs of the message box and in the sidebar's tooltip.
- Settings › Providers: each account shows its mark large, as an avatar at the left of its row, and saving, removing or adding an account closes its editor at once instead of waiting for Carrier to confirm; if Carrier refuses what was saved, the page says so afterwards.
- Settings › Providers › Edit an account: every field, pop-up and picker is one width, so the form reads as a column; the icon and the color pickers are the same grid, and there are 11 more icons and 5 more colors to tell accounts apart. The new ones need an up-to-date `carrier`; with an older one the editor keeps offering the earlier set.
- The rows of the sidebar have more room around their lines, and the branch is in monospace.
- "Done" in a row of the sidebar and of the Sessions list has how long ago the turn ended beside it, in the place where the time was.
- The notices over the message box (errors, uncommitted files, a held message, a question) have no edge: the colour of their glass and their badge say what they are.
- The rows of the Sessions list say what the sidebar's do: the state at the right (Needs you, the clock, Done), a cyan ring while the agent waits for something it started, what it waits for, the branch in monospace, and the pull request with the lines changed.

### Fixed

- The first click on a session in the sidebar, or on its Archive button, works while the card that opens on hover is showing: that card used to swallow the click that closed it, and a second click was needed.
- The sidebar no longer shuffles the sessions that work: with two of them at work their rows swapped places with every event of their agents. A session that works keeps the place it had when its turn began and takes its place once, when it stops.

## [0.9.0] - 2026-11-16

Dictate in any app: a global shortcut opens a widget over whatever you are in and pastes what you say, with optional cleanup by a local model, a history of your dictations with their audio and statistics on how much you dictate.

### Added

- Dictate in any app: ⌥⇧ Space opens a small widget over the app you are in, without taking its focus, and shows what you say; the same keys again paste it once at the cursor and put your clipboard back, and Esc cancels. Settings › Dictation › Global dictation has the Dictate in any app switch, which follows the Dictation switch.
- When a dictation cannot be pasted (no text field has the cursor, the field is secure, or Accessibility is off), the text stays in the widget, complete and scrollable, and on the clipboard, with Copy, Dismiss and, for Accessibility, Open System Settings; the first time you turn on Dictate in any app the page explains what Accessibility is for before macOS asks.
- Settings › Dictation › Sounds: the global dictation plays a start sound when it begins to listen and an end sound when you stop it, each on or off and chosen among three of macOS's sounds, at one volume (60 by default); Esc plays no end sound.
- Settings › Dictation › Cleanup: choose LM Studio or Ollama running on this Mac, one of its models and a prompt (it starts by removing filler words and fixing punctuation in the language you spoke), and try it with Test with a sample. It is off until a server and a model are chosen, and the message boxes use it.
- Dictate in any app: with Carrier in front on a session, ⌥⇧ Space focuses the message box and dictates into it, with no widget, and the same keys end it; in Settings or an epic it opens the widget as everywhere else.
- Settings › Dictation has two segments, General and History. History keeps every dictation (the widget's and the message boxes') with its text, speech model, how long it took to transcribe, where it went and how it ended (pasted, copied, cancelled or failed), grouped by day with a search and an outcome filter; a row opens to its detail, copies its text or deletes it. Keep the text of my dictations turns it off, and the text is kept in plain text on your Mac until you delete it.
- Cleanup in the message boxes: with it on, a dictation ends with the box saying Cleaning… and then holding the cleaned text in place of what you dictated, with the rest of the box as it was; Esc or a click on the microphone skips it and keeps the raw text, and if the server is down, the model is missing or it times out, the raw text stays, the cause shows under the box and goes to `dictation.log`.
- Settings › Dictation › Global dictation: record your own shortcut (it starts at ⌥⇧ Space and needs ⌃, ⌥ or ⌘ with the key) and choose Toggle or Hold; in Hold you speak while the keys are down and releasing them pastes, and Esc while they are down cancels.
- Settings › Dictation › History: Keep the audio (off by default) saves the audio of each dictation next to its text, an entry with audio plays and pauses it from its detail, Delete audio older than (7, 30 or 90 days, or Never; 30 by default) deletes the old audio when Carrier starts and once a day, Audio on disk shows how much there is, and Delete all audio removes it and keeps the transcripts; deleting an entry deletes its audio.
- Settings › Dictation › Global dictation: choose the widget's style (Pill, Small, Medium or Large; Medium by default) and its position (Top under the menu bar or Bottom above the Dock; Bottom by default), with a preview that follows your choice. The Small, Medium and Large boxes hold 2, 3 and 4 lines of text; the Pill is a badge with a microphone that turns into a spinner, a check when pasted and an x when cancelled, and opens as the Small box when a text or a button is needed.
- Settings › Dictation › Statistics: how much you dictate, from counters of their own that hold no text and that deleting history or turning it off never changes. Pick 7 days, 30 days, 90 days or All time to see the dictations, words, speaking time and time saved with the change against the period before, and a chart of words or dictations by day; at the bottom, set your typing speed (40 words a minute by default) and Reset statistics, which asks first and leaves the history alone.
- Settings › Dictation › Statistics also shows the hours of the day you dictate in (with the hour you dictate most), a weekly summary that compares the last 7 days with the 7 before (words, dictations, change in percent, busiest day and time saved, with a small chart by day) and your records: most dictations and most words in a day, the longest dictation and the longest streak of days in a row.
- The dictation widget is glass in your accent colour and, while it listens, draws the same glowing line as the message box around it, following your voice. Its text starts at the top and, once it fills the box, scrolls so the newest words are on the last line while the older lines fade out at the top.
- Cleanup in the dictation widget: with it on, ending a dictation in any app makes the widget shimmer over what you said (a sparkle in the Pill) while the model cleans it, and the cleaned text is what gets pasted. Esc skips the cleanup and pastes the raw text; if the server is down, the model is missing or it times out, the raw text is pasted anyway, the widget shows a warning that it was not cleaned and why (a warning in the Pill), and the cause goes to `dictation.log`. The history keeps both texts, the cleanup model and its time.
- Settings › Dictation › Global dictation shows whether Accessibility is allowed, with a button to open System Settings. A text that was only copied can be reached from the keyboard (Return copies it, Esc dismisses it), a failed dictation no longer shows a clock, deleting one dictation from the History asks first, and Copy there says Copied.

### Changed

- Add account and the account editor say, in a quiet line, when another account of the same tool already uses the config folder you typed, since it is the same login and not a new one.

### Fixed

- Settings > Updates no longer leaves Check now dimmed once an update is found: the row says which version is available and has the same Update, Restart or Retry button as the sidebar's pill, with the percent while it downloads.

## [0.8.0] - 2026-11-16

The app tells the accounts of one tool apart with a label, an icon and a color, the sidebar shows when a session is Done and gets Pin and Archive on hover, archiving is immediate, and the message box and Settings get a round of fixes.

### Added

- An account of `providers.json` can have a label, an icon and a color (Settings › Providers, Edit an account), so two logins of one tool are told apart where the app names them: the message box's button and its provider tabs, a session's row in the sidebar, the footer of an answer, the account rows of Settings and the corner of an epic session's avatar. All three are optional; with none, the app looks as it did. They need an up-to-date `carrier` (the editor says so and writes nothing while it is older), because an older one refuses a `providers.json` that has them.
- Pin and Archive appear on a session's row in the sidebar when the pointer is on it, in place of the age.
- A session whose turn ended says "Done" in green in the place of its time until you open it, and the icon's glow turns green and goes round once, fast, as the turn ends. It is not "Needs you", which stays orange for a permission or a question.

### Changed

- Archiving a session is immediate: its row goes as soon as you ask, the chat host no longer waits for the agent to end, and the lists are read again at once. A refusal brings the row back with the reason.
- Archive is off for a session that is working or waiting for an answer (the button on its row, the one on the Sessions home and the menu item), with a tooltip that says to stop it first.
- The sidebar stacks Home, Sessions, Terminal and Carrier in that order, and the open section takes all the room left: Terminal no longer sits under the list of Sessions, the sections above the open one are folded at the top, the ones under it at the foot, and Archive closes the Sessions panel. The open section's row stays at the top while its list scrolls, with a soft fade under it once rows slide beneath.
- The sidebar opens at 360 points wide, can be 260 to 800, and the width you drag it to is remembered.
- Settings > Sidebar previews three sessions (idle, Done and Needs you) so each switch is seen against them, says on Age that those states and the hover buttons take its place, and Reset also takes the sidebar back to 360 points wide on the next launch.

### Fixed

- In the message box, ⌘↓ takes the caret to the end of the text (the window's shortcut for Jump to the Latest Message took it before the text saw it; with the caret already at the end, or the box empty, it still jumps), and Home and End go to the start and the end of the text instead of only scrolling.
- The notices over the message box (errors, uncommitted files, a held message, a question) are glass filled with their own colour, like the one of a session that is asleep, and not dark grey with an edge.
- The block under the message box that says what sending does follows Settings > Chat > Surfaces: it stayed glass when Flat was chosen.
- The note that the folder's branch will change when the message is sent is now a step of the block under the message box that says what sending does, with an icon and a title, and not a line under the sentence.
- Settings now follows the Text size: the titles, details, notes and fields of every page grew and shrank only for the parts that set a size by hand, and now all of them do.

## [0.7.0] - 2026-11-16

The chat gets a flat look as an option, files attached to a message that open in a preview, a wider message width and a handful of fixes to code blocks, accent colors, updates and usage-limit errors.

### Added

- Settings › Chat › Surfaces: Glass or Flat. Flat draws the conversation's cards, your bubble, code blocks, attachments, notices and the message box as a quiet solid fill instead of glass.
- Message width has a fifth choice, Widest (1280 pt).
- A file attached to a message can be looked at in the app: a click on its chip opens a Quick Look preview (images, PDFs, text) with arrows, ← and → to go through all the files of the message, and Show in Finder.
- A file dropped on the message box is copied into Carrier's own folder (`chat/attachments`), so the conversation keeps it when the original is moved or deleted; taking its chip out before sending removes the copy.

### Fixed

- Code blocks wrap long lines when Wrap long lines is on (a command in a tool call no longer runs off the card): a block that wraps has no horizontal scroll, which offered the text no width to break at.
- Choosing an accent color no longer changes the tint of the windows: with Tint the windows on, the backgrounds keep the theme's own color and the accent only colors the elements.
- The agent's work card lines up: the icon of its line sits over the steps' nodes and the first line of a thought is level with its icon; thoughts read a little larger and looser.
- An update whose restart was held up (the app did not close) no longer leaves the pill stuck on Restarting…: clicking it asks Carrier to quit again.
- What you type in a session's message box and have not sent is kept when you go to another session, the terminal or another view, and is there when you come back.
- A Claude turn that fails on a usage limit (the 5-hour session or the weekly one) or another API error now says why in the chat ("You've hit your session limit · resets 12:40pm"), no longer "The turn failed", and its footer names the model that ran, not `<synthetic>`.
- The line of the agent's work in the chat no longer grows past the message width when a command or a summary is long: it fades out at the edge.

### Changed

- The toolbar of a session shows only the terminal icon where it said Show Terminal / Hide Terminal.
- The Message width preview in Settings › Chat draws a short conversation (your message, the agent's work and its answer) with the feed's own rows, centered.
- Message width and the Code and output settings (font, size, line height, ligatures, wrapping, line numbers) moved from Appearance to Chat, with their Reset; the Terminal page now says "Same as Chat".
- Settings › Appearance › Accent color: a line separates the theme's own accent from the seven colors, and a multicolor disc at the end opens the Mac's color panel for a color of your own.
- The message box's send button is tinted glass like the New session pill, no longer the loud solid accent.
- Settings stops growing at 1300 pt wide on a large window; its height still follows the window.
- The provider menu of the message box names each provider under its mark, as the Settings picker does, and scrolls sideways when there are many.

## [0.6.0] - 2026-11-15

Carrier gets embedded terminals with their own Settings page, a redesigned epic view, and an update pill in the sidebar in place of Sparkle's window.

### Added

- Embedded Ghostty terminals in the sidebar, overview, and session drawer with bottom tabs, split panes, middle-click close, menu commands, and **Settings › Terminal** options (including opt-in bottom-anchored Zsh prompts).

### Changed

- Epic "Continue in Terminal" now opens an integrated Ghostty drawer inside the epic view (keeping non-zero exit errors open until Return is pressed) and matches the app's light and dark themes.
- Unified terminal empty states, workspace headers, and toolbar controls with the app's glass styling.
- An epic's Agent output reads like the chat: one centred column, each agent a centred row with the account it acted as, the agent's work as the chat's tool cards, and the stop and Resume as a notice at the end.
- An epic's slices and a review's findings are cards: a slice per subagent in the order it happened, and one card for a review with its findings, the reviewer's verification as its foot, and the whole row a link to the discussion.
- Updating the app no longer opens a window: a glass pill at the top of the sidebar, after the window's buttons, shows the new version; clicking it downloads the update right there, with its percent, and then it says Restart, which installs it and relaunches the app. A failed download leaves Retry. Check now in Settings and Check for Updates… show what they find in the same pill, and say so in an alert when there is nothing new.

## [0.5.0] - 2026-11-13

Settings gain an Engine page and a Sessions page, the chat's agent can reach back into Carrier, and Usage shows Claude's limits on a Mac with a clearer layout and a bigger price table.

### Added

- Usage shows Claude on a Mac: when an account has no `.credentials.json`, the probe reads the login Claude Code keeps in the macOS Keychain (read only, never refreshed, never logged; macOS asks once to allow it), so the 5h and weekly windows appear. The price table is now LiteLLM's (MIT, copied into the engine; `pnpm prices:update` refreshes it), so far fewer models show `Unpriced · Map`.
- The Usage page is easier to read: it uses the whole width, with its title and a smaller Check again in the toolbar; provider rows only open their drawer and the provider is a filter beside the others (with 90 days, and the search at the right); quota bars are bigger and show the percent; the drawer has a panel per heading and the marks of LM Studio and Ollama; the chart has a column for every day (days with no use are marked and weekends tinted); the tables have the provider's logo, a total, and the top 10 workspaces by tokens; thousands are separated.

- Engine in Settings: the Engine page of the Mac app moves from the Legacy group to the Carrier group, after Behavior, and holds everything a person sets about running Carrier on this Mac, with no note about saving (each control is written as it is changed); its line under the title reads "How the app runs Carrier". Starting has "Start Carrier when the app opens" and "Ask before stopping Carrier", which leaves General (a person who had it off still has it off; General's Reset no longer touches that switch). Programs shows the `carrier`, the `node` and the `PATH` the app runs Carrier with, each with its path and version ("Not found" when the app does not find one); "Use another…" on `carrier` opens a file picker, in place of the advanced field "Use this carrier" (and "Use the Homebrew one" goes back); and "Look for the tools again" has a Detect button, in place of "Detect again"; the banner that says something is missing points to them. GitHub identity has "Carrier acts on GitHub as", which chooses which of the profiles in `config.json` the engine uses to read issues and PRs and change labels: choosing a profile writes `orchestratorProfile`, the default (the author's identity) takes the key out of the file, a profile the file names but does not declare shows in orange and is kept until another is picked, and the engine is asked to reload after the write so the choice applies without a restart. Files has "Carrier folder", "Logs" and "Start log", each with its path (`~` for the home folder): Reveal shows the folder in Finder and Open opens the start log, and a row whose folder or file does not exist yet has its button disabled and says "Not created yet". The page the stopped-Carrier view opens is still Engine.
- Settings > Sessions moves from the Legacy group to the Chat group, after Sidebar, with the line "How sessions start and age out", and holds everything about how a session starts, ages and is deleted: "Starts with" and "Ask before deleting a session" move there from the Chat page, which keeps the message box and the conversation, with the choices a person made kept, next to "Archive after" and "Delete after". The page has its own Reset ("Restore the defaults"), which puts back those two preferences and the ages to 15 and 30 days in `chat.json`; the Reset of Chat no longer touches them.
- Settings > Sessions has a "With these ages" group under Archive and delete that says, in dates, when a session left alone from today is archived and deleted ("Is archived on Nov 28 and deleted on Dec 13. Both ages count from its last activity", with the year only when it is not this one): with "Archive after" at Never it says the session is never archived or deleted, with "Delete after" at Never that it is archived and never deleted, and while an age is refused the line is not shown. It also says, always, that a session that is working, waiting for you or open is looked at again later. The README of the app and the glossary's Legacy group now agree with Sessions being in the Chat group.
- Settings > Sessions has a "Work in" row in the New sessions group, with the choices "The base folder" (the default, so a new session opens as before) and "A new worktree": a new session whose folder is a git repository with a working folder and a branch opens in a new worktree, with the name and branch it suggests as always, and any other folder opens on the base folder. What you choose in the new session screen stays what that session gets, and the Reset of Sessions puts it back to the base folder.
- The agent of a chat session can reach back into Carrier: the chat host serves an MCP of its own (`carrier-chat`, loopback only, on by default) to the Claude and Codex agents of its sessions, each with a token that stops working when the session closes, and its first tool, `capabilities`, tells the agent which session it is in, which agents are configured and ready, and whether `git` and `gh` work. The agents of an epic never see it.

### Changed

- The toolbar's buttons (Search, Filter, New session, Check again, Check now, Pause, Stop) are smaller glass capsules, Archive is laid out like Sessions (its title and count in the toolbar, rows with the project's tile), Settings' list shows only the pages' names, and Start Carrier is a glass button.

### Fixed

- A long pasted text is sent when it is all there is in the message box (the card stayed and nothing went), and saving a setting with an older Carrier running no longer says that it will read the file when it starts.

## [0.4.0] - 2026-11-13

Settings apply without a restart, the message box dictates, and a role's model is chosen in the chat's own panel; new sessions start with the provider, model, reasoning and access set in Settings > Chat, and the chat offers every account of `providers.json`.

### Added

- Usage and limits: `Carrier.app` has a Usage page below Settings, and `carrier usage` prints the same in the terminal. It shows the live quota of each Claude, Codex and Antigravity account (5h and weekly windows, resets, extra credits where the tool exposes them) and the local servers, and the consumption of epics, chats and outside sessions by day, model and workspace, as tokens or as an estimated API cost. A model with no known price shows `Unpriced · Map` and can be priced locally. Epic runs now record their tokens and cost. The chat host collects it all (`usage` and `usageOverride` on `chat.sock`), and a Claude login is only read from its `.credentials.json`, never refreshed (a login kept only in the macOS Keychain is not read yet).
- Settings > Chat has a New sessions group that chooses the provider, model and reasoning a new session opens with, in the same panel as the message box; with none chosen it takes the first provider that can work and that provider's own model and level. It also chooses what the agent may do (its access), as far as the provider lists it. The message box still changes all of it for one session.
- Dictation: a microphone icon in the message box listens and writes what you say at the caret, in a lighter colour while it is still a guess, with a line round the box that moves with your voice; a typed key or Enter stops it and keeps the text, Escape cancels it and keeps what was already on the screen, Tab leaves the box for the microphone, a partial is underlined as well as tinted, minimizing the window stops it, and VoiceOver announces each state. Settings > Dictation chooses the model (Apple's recognizer, which needs no download; Parakeet, Nemotron and the other FluidAudio models; Whisper through WhisperKit) and the language, and downloads, cancels and deletes the models, which live under `~/.carrier/app/models` and are never bundled with the app (the licences of what is linked do ship, in the app's `Resources/Licenses`). The only permission it asks for is the microphone's. Parakeet TDT v3 shows words while you speak; the models that cannot keep up say "When you stop" and show the text at the end.
- Settings > Agents chooses a role's model in a panel, as the chat's message box does, and nobody types a model name any more: the providers that can work as tabs (a signed-out one is left out unless the role already uses it), a search over their models (a name the list lacks can be used as typed), the reasoning slider, and a note that a role has full access because epics run on their own. The steps of "When it runs out of tokens" use the same panel, with "Default model" as the first choice and, for the second step, "No second step". A role's list on the left shows the provider's mark, the model and the reasoning.
- A step of a role's failover can name its own `effort` (`{ "provider": "codex", "model": "gpt-5", "effort": "low" }`); without it the step keeps the effort the role was running with, as before. Settings > Agents sets it from the same panel as the model.
- The dialog that adds repos from GitHub has filters (all, private, public; one owner; hide the ones already watched) and a search with a magnifying glass.
- `docs/macos-ui.md` is the guide to how the Mac app is drawn: the buttons, the line between rows, fields, selects, rows that open a form, lists, menus and empty states, with the mistakes already made. `AGENTS.md` points to it.
- `carrier reload` (and a `reload` request on the control socket) makes a running Carrier read `config.json` and `providers.json` again and run on them without a restart; it prints "Reloaded", or the problem with the key named and exit 1 when a file is wrong, and then changes nothing. Running work keeps what it started with; a repo removed from the config parks its epics and stops its runs, and adding it back resumes them ([configuration](docs/configuration.md#changing-the-config-while-carrier-runs)).
- The Mac app asks a running Carrier to reload after every save of `config.json` or `providers.json`, and shows what Carrier answers where the page shows a failure to save; with Carrier stopped it says nothing, and with one too old to reload it says quietly that Carrier will read it when it starts.

### Changed

- Settings rail: Providers moves up to the first group, with General, because the engine and the chat both use its accounts; Chat, Sidebar and Dictation get a Chat group of their own; Carrier keeps Repos, Agents and Behavior.
- Settings pages share one design. Selects are the Mac's own pop-up in the neutral colour and not the violet menu; text fields have a quiet fill and the theme's accent as their ring; the line between two rows is lighter; buttons that do something have an icon (Save, Cancel, Remove, Add, Reset, Check again, Open on GitHub, Send a test and the others); a row that opens an editor shows a chevron and opens when clicked anywhere on it (Providers' accounts, Repos' roles). Settings closes with an ✕ at the top right, or Esc: the Done button and the foot are gone.
- Providers: empty states for a tool that is not installed or a server that is not running; the editor of an account has more room between its fields, and Auto-compact after is a choice (Use default, auto, 100,000 to 1,000,000 tokens) in place of a text.
- Repos: a role shows the mark of its provider and its settings with a label on each (Identity, Account, Model, Effort); Defaults is an item of its own under the roles; Add repo is the last row of the list; the cards of Ready for Carrier turn a spinner each while the doctor runs, and the note under them is gone; the form of a role chooses its provider, model and reasoning from the same panel as Agents ("Same as everywhere" is its first choice), and it, the search and the dialog that adds repos use the new fields and rows; the menu of a repo and the buttons over its page have icons.
- Settings > Agents shows Author, Reviewer and Lead reviewer side by side as cards, with a double arrow between the author and the reviewer, in place of the list at the left; Antigravity's models, which the chat host does not list, are read from `agy models` and listed by family, and the reasoning slider picks the level of the family (it is part of the model's id).
- A value that is not valid (a binary path, a number of Behavior) says so in orange, with a warning mark in its line and in its field, and no longer turns the whole row red; Settings' Behavior and Sessions pages use the same pop-ups, number field, buttons with icons and problem mark as the other pages.
- Keybindings shows each shortcut as a key cap, with the theme's accent and "Press the keys…" while it waits; Updates shows the state of the engine with a mark (a check, a cross or a spinner); a Persona prompt in Agents is a text area the width of the card.
- Settings' Behavior page moves from the Legacy group to the Carrier group, after Agents, and its line under the title reads "How Carrier runs epics"; Legacy keeps Engine, Sessions and Health.
- Settings' Behavior page regroups its eight values by the question each answers: Pace, When something goes wrong and Housekeeping, with new titles and descriptions; the values, their rules and what is written to `config.json` do not change.
- Settings' Behavior page ends with a Reset group, a card "Restore the defaults" with a Reset button that puts the eight values back to the engine's defaults, in place of the "Reset to defaults" button of its footer; the page's header says "Saved" beside the title when a value is written, and a failed save or an unreadable file shows its message there, in orange; the standing note "Saved as you change them · Carrier reads these when it starts" is gone.
- Settings notes say whether a change is applied now, waits for the next start (Carrier stopped or too old to reload) or was refused, and the last answer stays on the page when you leave it and come back.

### Fixed

- The chat offers every account of `providers.json` but Antigravity's as a provider, so a second Claude login is there to start a session on; before, only `claude` and `codex` were, unless `chat.json` listed more. An `agents` key in `chat.json` still says exactly which.
- Antigravity's Reasoning slider runs from Low to High, left to right; it followed the order `agy models` printed the levels in, which put High first.
- A repo that GitHub refuses (a mistyped name, no access) no longer stops Carrier from polling the other repos; its error shows in its own check.
- A long message in the header of a Settings page goes under the title when it does not fit, and VoiceOver reads it.
- Settings > Providers opens with the tools already listed, since the Mac is looked at when the app opens and not when the page does.
- The row "Tool output" in Settings > Chat was missing its line, and the pop-ups of a row switched off (Quiet hours, From and Until) did not look off.
- A chat session whose Claude conversation is gone from Claude Code's own folder (so it answered "Claude could not resume that conversation" on every try) now opens a new conversation in the same folder, with a plain line in the history saying that the agent does not remember what came before (the banner of a failed turn is for failures).
- Carrier no longer asks GitHub about the labels of every repo it watches before it answers on its socket: a repo's `solve:epic:running`, `solve:epic:ready-for-test` and `solve:epic:needs-human` are created when an epic is first labelled in that repo, no longer at start, so starting takes the same with six repos or a hundred.
- The release waits about 8 minutes (it waited 1) for npm to serve a version it has just been given before it takes the formula's checksum, so it no longer stops at that step while npm is still validating.

## [0.3.0] - 2026-11-12

The Mac app has an Updates page and its sidebar tells a session's state at a glance; Settings' Providers, Repos and Agents pages share one design.

### Added

- Settings has an Updates page: the version, when Carrier last looked for a newer one, a Check now button, and the two choices (look by itself, install by itself). The Carrier menu has Check for Updates… under About Carrier. The page also says where the update of Carrier's engine stands (updating, up to date, or why it failed) and, when it failed, has a Try again button.

### Changed

- The Mac app builds with no compiler warnings: the models store, the chat host starter and the joined texts of a lane and of a new session no longer use what Swift 6 will refuse; nothing looks or works differently.
- The place pill in a session's toolbar ("In the folder", "Worktree") has room on its right, so it lines up with the window's corner.
- A project's icon in the sidebar shows up to three letters (the first letters of its first three words), so projects that share their first two words are easier to tell apart.
- A session's row in the sidebar opens a card when the pointer rests on it, like an epic's: the whole title, what the agent last wrote, where it works, the agent and model, the turns and when it last moved.
- A session that is working shows how long its turn has run ("42s", "12m 05s", "2h 03m") in place of the time of its last activity, in the sidebar's row. A session that waits for a permission or an answer says "Needs you", in orange, in that place too, and its second line goes back to where it works.
- The icon of a project whose agent is working has a violet arc that goes round its edge (the one on a run's card in the chat) in place of the blue pulse, and the stopwatch next to it is violet too.
- The models, reasoning and access each provider offers are read when the app opens and kept (in memory and in the app's cache folder), so a new session's provider menu lists them at once instead of reading them each time; they are read again in the background, and dropped when the accounts change.
- The sidebar's foot is tidier: Archive shows only while Sessions (or Archive itself) is open, and Carrier is a row under it at the foot until you open it, when it moves up under Sessions with its epics. Opening Archive leaves the sessions above it in place, and its row has a chevron to open and fold its list. The lists of Sessions, Carrier and Archive slide open and shut, and a menu to group it by workspace or by age. The buttons of the Sessions, Archive and Carrier rows fade in while the pointer is over the row.
- Sessions grouped by state, in the sidebar and on the Sessions page, are told apart in five: Needs you (it asked for a permission or an answer), Working, Unread (it answered and you have not opened it since), Idle and Asleep (its agent was closed by the host; it wakes where it left off when you write). The Sessions filter offers the same five.
- On the Providers page, Update and Check again are text on the line of the chosen tool's name, on the right, and a pill shows behind each while the pointer is over it; the explanatory lines are gone. An account shows its state with a dot and, when it asks for an action (Signed out), in orange; what it is (its folder or login) is a line of its own under who uses it; the tool's version is quieter, the list has labels for the AI tools and the local servers, and the spacing is two distances instead of four. The account editor is titled with the account's name as the page shows it, refuses to open a blank form for an account providers.json does not have, takes any text for the config folder (one that is not absolute is written from the home folder) and no longer shows the system's writing-tools button on the arguments box.
- The Agents page of Settings follows the Providers and Repos pages: the roles are a card of rounded rows with a neutral selection, the chosen role's name is a title, its choices are the system's pop-up buttons and fields of one width (the pop-ups no longer take the theme's accent), a role with nothing chosen says "Choose…" instead of showing the first option, and the standing sentence at the foot is gone.
- The Repos page of Settings follows the Providers page: the list is a card of light rounded rows (the logo with the repo's health, the name, and a small orange count when something needs you) with a neutral selection, and what the rows used to say (the last check or the error, the epics) is on the page, the epics as colored chips with readable words, the chosen repo's name is a title with Open on GitHub, Reveal clone and Check again as text on its line, Status is a label and a value per line, the checks and the roles are more compact with small buttons, and the standing sentence at the foot and the "Saved" after a change are gone (it only says when it could not save). The small uppercase titles of the groups of Settings are a notch brighter, so they read on the dark window. Repos shows each repo's project icon, the letters of the sidebar, in its list and on its title, and the paths, the URL, the errors and the fixes of the page have a copy button that appears while the pointer is over them (Providers has it on a tool's path). The form that changes a role of a repo is a grid with the same edges all the way down, in three blocks (identity; provider, model and effort; persona), with the system's pop-up buttons and fields, neutral and not in the theme's accent. The main button of a form (Save, Add) has a darker fill so its white label reads on every theme.
- The buttons of Settings that are not the main one (Check again, Update, Sign in, Edit, Add account, Cancel...) are quiet neutral capsules, so Done and Save are the only ones in the accent.
- Settings groups Providers with Repos and Agents under the Carrier heading, in place of leaving it alone between the App pages and Carrier with a gap of its own.
- A session that changes group in the sidebar (working to needs you, an answer to unread) or moves up as it gets newer slides to its place instead of jumping.
- The app asks the chat host and the engine how things are every 2 seconds while you are looking at its window and every 5 otherwise, where it was every second, so it uses less of the Mac.
- `carrier init` opens by saying what it will ask, names the accounts "accounts" like the rest of Carrier, and ends with the label to put on an epic. Pressing Enter no longer adds another account, a lead reviewer or a failover: the optional extras answer No. At the recap you can choose "Change an answer" to go back and ask again from the same answers, and an existing failover is kept only if you say so. It says how many accounts it added for you, explains what a GitHub identity is before asking for one, and shows a spinner while it waits for the machine or for GitHub.
- A config may have no repos yet: `carrier init` offers "None for now" when it asks for the repos, `repos` may be `[]` in the file, and in the Mac app's Repos page the last repo can be removed. Carrier then runs and watches nothing until one is added.

### Fixed

- Opening an archived session no longer lays the window out taller than the screen, which pushed the sidebar's Home and Settings and the notice at the bottom of the conversation out of view.
- The macOS app check on a pull request no longer hangs now and then in its tests (two tests asked AppKit for the system colours from different threads at once and deadlocked); if a test run ever hangs again it stops after 7 minutes and prints where it is stuck, and the job gives up after 15 minutes instead of 40.

## [0.2.0] - 2026-11-11

Carrier's Mac app now updates itself, and Settings grows pages for Providers, Agents and Repos.

### Added

- The macOS app updates itself: it checks for updates with Sparkle, asks before it installs (or installs by itself if you choose), and relaunches. After an update it upgrades `carrier` with Homebrew and replaces the chat host and the engine when they are free to replace. See [releasing](docs/releasing.md).
- Settings in the macOS app has three new pages under Carrier. Providers: the tools found on this Mac with their state, version and path, and each tool's accounts (add, edit, remove, sign in, update). Agents: the three roles of every epic (Author, Reviewer, Lead reviewer) with their identity, provider, model, effort, persona and what to do when tokens run out. Repos: each repo's status, four checks (Carrier can read it, the Author and the Reviewer can sign in, Solve is set up) and who works there.
- The effort of an agent can be chosen, a role can fail over from one account to the next in steps, and `carrier init` asks for the effort.
- The release signs the app's zip with an update key and attaches an `appcast.xml` to the GitHub Release, which is published last so the feed never points at a version the tap does not have yet.

### Changed

- The accounts of the agent CLIs moved out of `config.json` into `providers.json` in the Carrier folder, which the engine and the chat host read and the app writes ([ADR 0020](docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)).
- An epic starts at once on its three roles, with no wait at the start ([ADR 0021](docs/adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)).
- The chat in the macOS app looks better: even spacing in the model pill, a copy button that stays usable, and a run's steps that fold and open smoothly.
- The Homebrew cask declares `auto_updates true`, and `brew uninstall --zap` also removes the app's cache folder.
- An app that is older than the installed `carrier` tells you to update it instead of only refusing to talk to it.

## [0.1.4] - 2026-11-11

The chat in the Mac app got friendlier: the agent can now ask you things and you can answer.

### Added

- Chat in the macOS app: a card for the agent's questions (`AskUserQuestion`) so you can answer them instead of only allowing or denying, one card for each run of reasoning and tool calls, a notice card, and markdown tables.

### Changed

- About in the macOS app is the system's About window, with the real app icon.

## [0.1.3] - 2026-11-10

Settings and the chat in the Mac app got a big polish, and the app builds again with the macOS 26 SDK.

### Added

- Settings in the macOS app has an App group (General, Notifications, Appearance, Sidebar, Chat, Keybindings) next to the existing pages, with themes, previews and quiet hours.
- Session list, session header and chat polish in the macOS app, and dropping files into a chat.

### Fixed

- The macOS app builds again with the macOS 26 SDK (the session menu used an API that only the macOS 27 SDK has).

## [0.1.2] - 2026-11-08

A quick fix so the Mac app opens and stays open.

### Fixed

- The macOS app no longer quits at launch when it draws its first provider or file icon (it could not find its resource bundle in the app built by the release workflow).

## [0.1.1] - 2026-11-06

Housekeeping after the first release: Homebrew 7 syntax and npm publishing without a token.

### Fixed

- The Homebrew cask uses Homebrew 7's syntax for the macOS minimum and the quarantine step.

### Changed

- npm publishes through trusted publishing, with no token.
- The docs say the app is installed with the cask.

## [0.1.0] - 2026-11-05

First release. Carrier picks up your ready epics, builds them with one agent, reviews them with another, and never merges the last pull request for you.

### Added

- The engine: it polls the GitHub repos you list for `solve:epic:ready` epics, runs an author agent and a reviewer agent with another identity, and leaves each epic `ready-for-test` or `needs-human`. It never merges the final pull request.
- Agent runners for Claude Code, Codex and Antigravity, with a choice of agent option per role and switching when one runs out of credits.
- A command line: `init`, `doctor`, `schema`, `start`, `status`, `watch`, `stop`, `pause`, `resume`, `check` and `restart`, with a terminal panel.
- A chat host and `carrier chat` to talk to an agent, with sessions that can work in their own worktree.
- The macOS app: epics with their stages, slices and agent output, a stopped epic can be resumed, Settings, and sessions with an agent.
- Everything lives in one Carrier folder (`~/.carrier`, or `CARRIER_HOME`).
- Installation with Homebrew (`brew install ashulab/tap/carrier` for the command, `brew install --cask ashulab/tap/carrier` for the app) and from npm as `@ashulab/carrier`.

[Unreleased]: https://github.com/AshuLab/carrier/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/AshuLab/carrier/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/AshuLab/carrier/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/AshuLab/carrier/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/AshuLab/carrier/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/AshuLab/carrier/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/AshuLab/carrier/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/AshuLab/carrier/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/AshuLab/carrier/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/AshuLab/carrier/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/AshuLab/carrier/compare/v0.1.4...v0.2.0
[0.1.4]: https://github.com/AshuLab/carrier/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/AshuLab/carrier/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/AshuLab/carrier/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/AshuLab/carrier/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AshuLab/carrier/releases/tag/v0.1.0
