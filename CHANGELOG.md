# Changelog

All notable changes to Carrier are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-11-13

Settings apply without a restart, the message box dictates, and a role's model is chosen in the chat's own panel; new sessions start with the provider, model, reasoning and access set in Settings > Chat, and the chat offers every account of `providers.json`.

### Added

- Engine in Settings: the Engine page of the Mac app moves from the Legacy group to the Carrier group, after Behavior, and holds everything a person sets about running Carrier on this Mac, with no note about saving (each control is written as it is changed); its line under the title reads "How the app runs Carrier". Starting has "Start Carrier when the app opens" and "Ask before stopping Carrier", which leaves General (a person who had it off still has it off; General's Reset no longer touches that switch). Programs shows the `carrier`, the `node` and the `PATH` the app runs Carrier with, each with its path and version ("Not found" when the app does not find one); "Use another…" on `carrier` opens a file picker, in place of the advanced field "Use this carrier" (and "Use the Homebrew one" goes back); and "Look for the tools again" has a Detect button, in place of "Detect again"; the banner that says something is missing points to them. GitHub identity has "Carrier acts on GitHub as", which chooses which of the profiles in `config.json` the engine uses to read issues and PRs and change labels: choosing a profile writes `orchestratorProfile`, the default (the author's identity) takes the key out of the file, a profile the file names but does not declare shows in orange and is kept until another is picked, and the engine is asked to reload after the write so the choice applies without a restart. Files has "Carrier folder", "Logs" and "Start log", each with its path (`~` for the home folder): Reveal shows the folder in Finder and Open opens the start log, and a row whose folder or file does not exist yet has its button disabled and says "Not created yet". The page the stopped-Carrier view opens is still Engine.
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
- Settings' Behavior page moves from the Legacy group to the Carrier group, after Agents, and its line under the title reads "How Carrier runs epics"; Legacy keeps Sessions and Health.
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

[Unreleased]: https://github.com/AshuLab/carrier/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/AshuLab/carrier/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/AshuLab/carrier/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/AshuLab/carrier/compare/v0.1.4...v0.2.0
[0.1.4]: https://github.com/AshuLab/carrier/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/AshuLab/carrier/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/AshuLab/carrier/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/AshuLab/carrier/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/AshuLab/carrier/releases/tag/v0.1.0
