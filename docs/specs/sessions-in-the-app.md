# You can hold a session with an agent from the app

Status: spec

## Problem

The app has the final sidebar, with a Sessions half that is drawn and empty, and the chat host that runs a conversation with Claude or Codex and keeps its transcript. Between them there is nothing: the only way to talk to an agent through Carrier is `carrier chat` in a terminal, so the person who lives in the app still leaves it to think something through, and what they say and what comes back is outside the place that shows the rest of their work.

The screens for it were designed with the owner in six rounds of mockups ([in-app sessions research](../research/in-app-sessions.md), "Chat UI decisions"; the pages are `chat-ui-*.html` in `docs/research/macos-app-design/explorations/`). This epic builds them and connects them to the host. It is the macOS half of the in-app sessions: the sidebar epic left its values and a dev fixture ready, the core chat epic left the socket, and the worktrees epic (#486) adds what the "new worktree" half of the new-session screen needs.

## Solution

The app becomes a client of the chat host's socket, next to its client of the engine's, with fixtures of its own so every screen is built and checked without a provider. When the person opens their first session the app starts the host, as `carrier chat` does, with the same way of finding the user's tools that it already uses to start the engine (the settings' `carrier`, `node` and `PATH`); if the host does not come up it shows the end of its log, as it does for the engine. The sidebar's Sessions values are fed from the host's `list`, and the flag that enables the + turns on when the host answers and at least one agent has its binary; otherwise the + stays off and its tooltip says what is missing ("The chat host is not running", "No agent found: install claude or codex").

**Sessions home.** A list grouped by workspace, newest first inside a group, each row with the state glyph (working, waiting for you, idle), the title, the agent (and the branch, for a session in a worktree) and the age. The header has the title and, to its right, one glass group with Search and Filter, and on the far right New session. Search finds by title, workspace and agent, showing archived matches dimmed and tagged. Filter is one popover with the sort (workspace, age, status) and what to show by status and by agent; applied filters show as a count on the button and as chips under the header, with Clear filters. States: no sessions yet, no matches. A session is grouped under its base folder, so a session in a worktree sits with its repository and shows its branch; two groups with the same name show their parent folder to tell them apart.

**Archive.** The same list and header; Clear sessions replaces New session and asks first with an alert that names the count, Cancel being the default; it is disabled when nothing is archived. Filter here only sorts, by date archived or by project. On hover a row shows Open (the transcript, read only: the session stays archived), Resume (takes it out of the archive and opens it) and Delete. The empty state is "Nothing archived". The session row's menu has Archive, Reveal in Finder and Copy session id.

**New session.** A draft in the centre; nothing exists until the first message is sent, which opens the session and sends it. The workspace is chosen from the recent folders (the distinct base folders of the sessions the host lists, most recent first) or Open folder…, and the draft's box carries the agent as a chip to pick among the configured agents. A round mark (a placeholder until there is a logo), the question and "Pick where it works, then write." head the draft, and the toolbar takes the page's own colour. A sentence above the box says where it works: "Work in *workspace* on *Current folder*", where the workspace is a chip that opens the recent folders and where it works is a chip of two choices, Current folder and New worktree; with what #486 reports about the folder it also says the branch, warns about uncommitted changes and says when the folder is not a git repository. Its worktree half, "in a new worktree *carrier/…* from *branch*", with the generated name, ↻, the editable suffix and the branch picker with Fetch now, is the last piece: it is built against fixtures and waits for #486. The options of a session (model, effort, permissions) are what the provider lists once the session is open, so the draft cannot show them; they appear in the box after the first message, and the `options` of the agent in the config apply from the start.

**The conversation.** The title bar has the session's name, below it where it works (workspace and branch), and on the right the Open menu (Reveal in Finder, Copy path, and Copy branch name for a worktree). The feed shows the person's messages in a bubble, the agent's rendered as markdown (paragraphs, lists, inline code, code blocks with the language and Copy), and a closing line per turn with the model, the time and the usage the provider reported. Tool calls are grouped: every run of calls between two pieces of text is one row that says what was done (files read, searches, files changed, commands, with the line totals and the time), opens to its calls, and each call opens to its detail (the diff, the command's output, the lines read, the matches). A failed call turns the row's summary red and the group stays closed. An approval is a card in the feed with the provider's own choices, and once answered it collapses into a line that says what the person chose. The box has the single options pill that summarizes the options and opens a panel listing what the provider offers, and the send button, which becomes Stop while the agent answers. States of a turn: working (caret, timer), stopped by the person (a mark with Continue), a provider failure (a banner with Try again and Copy details), a closed session (it resumes when a message is sent) and a provider that is not signed in (the banner says to sign in from a terminal and never asks for a password).

**How it talks to the host.** The sidebar polls `list` once a second and the archived list every few seconds and after any archive, restore or delete. An open conversation polls `events` by cursor about every 250 ms and draws the `streaming` text as the message in progress. The host refuses a message while the agent is answering and one for a closed session, so the app queues what the person types during a turn, shows it above the box with a way to cancel it, and sends it when the turn ends; and it resumes a closed session before sending to it. Approvals, options, interrupt, archive and delete are the host's requests as they are; the host has no rename and no "done" state, so neither is offered, and a session that is not working or waiting is idle.

What was cut. The changes panel and any diff: another epic; the Open menu stays because it needs nothing from the backend. Cloning, repositories from Carrier's list and an empty folder in the workspace picker. System notifications for a session that waits for the person. A push channel: polling is what the app does already. Renaming a session. The last thing said on each row: the host's list does not carry it, and adding it is a small change to the host for later. Searching inside a transcript. The `done` state of the sidebar values, which the host has no way to say.

## Scope

1. As Diego, I click Sessions and see my sessions grouped by workspace, newest first, each with its state, title, agent and age; one that waits for me is orange.
2. As Diego, I search sessions by title, workspace or agent and archived matches show dimmed and tagged.
3. As Diego, I filter and sort the list from one popover and the button says how many filters are on, with chips to clear them.
4. As Diego, with no sessions I read "No sessions yet", with a filter that matches none I read "No sessions match" and can clear it.
5. As Diego, the + and New session are always on; opening the draft starts the chat host when it is not running (a later decision: a + that waited for the host could never start it).
6. As Diego, the + starts a draft where I pick a workspace and an agent, write a message and send it, and the session opens with my message and the answer streaming.
7. As Diego, the draft tells me where the session works, warns me about uncommitted changes in the base folder, and says when the folder is not a git repository.
8. As Diego, I read the agent's answer as it streams, with its markdown drawn and a Copy button on code blocks.
9. As Diego, I see the tools of a run as one row that I can open to its calls and open again to each call's diff or output; a failed call turns the row red and stays closed.
10. As Diego, an approval shows as a card with the provider's choices, my answer is honoured, and the card becomes a line that says what I chose.
11. As Diego, I change the model, effort or permissions of a running session from one pill that lists what the provider offers.
12. As Diego, what I type while the agent answers waits above the box and is sent when it finishes; I can cancel it, and Stop interrupts the turn.
13. As Diego, I see a mark when I stopped a turn, a banner when the provider failed with Try again, and a closed session picks up when I send a message.
14. As Diego, when the provider is not signed in the banner says to sign in from a terminal and the app never asks for a password.
15. As Diego, the title bar tells me where the session works and its Open menu reveals the folder in Finder, copies its path and, for a worktree, copies its branch name.
16. As Diego, the Archive page lists archived sessions that I can search, sort by date or project, open to read, resume or delete, and Clear sessions asks first and names how many.
17. As Diego, a session can be archived and restored, and the Archive row's count is right.
18. As Diego, opening my first session starts the chat host, and when it does not come up I read the end of its log.
19. As Diego, the new-session sentence offers a new worktree, with a generated name I can roll or edit, a branch picker with local and remote branches and Fetch now, and the delete confirmation says what a worktree holds that would be lost (blocked by #486).

## Decisions

The pure parts go in `CarrierCore` and are tested with Swift Testing; the AppKit and SwiftUI views that draw them are not. The values the sidebar epic left (`SessionRow`, `SessionGroup`, `sessionGroups`, `SessionSort`, the Sessions flag and the selections `.sessions`, `.session(id:)`, `.archive`) are used as they are and extended only where this epic needs more; the `done` state stays in the type and nothing produces it.

```swift
/// What the app needs from the chat host's socket; the real one speaks to the socket, tests use a fake.
protocol ChatHost {
  func agents() async throws -> [ChatAgent]            // name, harness, whether its binary was found
  func list(archived: Bool) async throws -> [ChatSession]
  func open(agent: String, folder: String, options: [String: String]) async throws -> ChatSession
  func resume(_ id: String) async throws
  func send(_ id: String, _ text: String) async throws
  func events(_ id: String, after: Int, limit: Int) async throws -> ChatEvents   // events, cursor, summary, streaming, approvals, options
  func answer(_ id: String, approval: String, choice: String) async throws
  func interrupt(_ id: String) async throws
  func setOption(_ id: String, option: String, value: String) async throws
  func archive(_ id: String, _ archived: Bool) async throws
  func delete(_ id: String) async throws
  // for the worktree slice, once #486 lands: workspace(_:), fetch(_:), suggestName(_:), checkName(_:_:), deletePreview(_:), and open(worktree:)
}
```

The classification of a tool call for the grouped row is a table by the provider's tool name: reads (Read), searches (Grep, Glob), changes (Edit, Write, MultiEdit, apply_patch), commands (Bash, shell) and anything else as "other"; the summary is the non-zero counts in that order joined by " · " ("2 files read · 1 search · 2 files changed · 1 command"), singular where the count is one; "files changed" counts distinct paths; the group's title is Explored when it has only reads and searches, Changed when it has a change, and Worked otherwise. A message the agent wrote is drawn with the app's markdown rendering and a code block with its own view, reusing the transcript views the app already has for epics where they fit; a recorded conversation settles what is left.

The draft sends in two steps, `open` and then `send`; if the second fails the session exists, is selected and shows the failure with Try again. The queue of the typed message is in the app and holds one message at a time; typing again replaces it. Resume before send is decided by the session's `live` flag from `list`. The chat host is started by the app the way the engine is, in its own session with output to a log under the chat folder, never when running under `--fixture`; the decision and the command line are code with a test, the spawn and the alert are not. The sidebar groups by the session's base folder (its `workspace.base` for a worktree, its folder otherwise), titled with the last component, with the parent shown when two groups share it. Recent folders for the picker come from the same lists, not from a store of the app's own.

The fixtures. `FixtureServer` also answers a chat socket in `--fixture` mode from golden files in `Tests/Fixtures` (`chat-agents.json`, `chat-list.json`, `chat-events-*.json`) covering a working session, one waiting for an approval, an idle one, a failed one, a closed one and archived ones, with a long conversation behind a flag as the engine's has; `--smoke-window` selects a session and prints what it sees, and the dev sample sessions of the sidebar epic are replaced by these. Visual review is the person's: the agents cannot take screenshots.

Testing seams, by story:

- Stories 1, 2, 3, 4 and 16, 17: pure code in `CarrierCore` over `ChatSession` values: the groups and their titles, the order, the search across active and archived, the filters, the sorts by workspace, age, status, date and project, the counts and the empty states, in `SessionsSidebarTests` and a new `ChatSessionsTests`.
- Story 5: the flag from the host's answer and the agents' binaries, as a pure function with its reasons.
- Stories 6, 12 and 13: a `ConversationModel` driven by a fake `ChatHost`: the draft's open and send and its failure, the polling cursor, the streaming text, the queue (one message, replaced, cancelled, sent when the turn ends), Stop, resume before send, and the states of a turn.
- Stories 8, 9, 10, 11 and 14: the feed built from a list of events as a pure function, tested against the golden conversations: markdown blocks, the grouped rows and their summaries by the classification table, the failed call, the approval card and its collapse, the options and the not-signed-in and failure banners; the same golden files serve the fixture server.
- Stories 7 and 15: the sentence and the Open menu as pure values over what the host reports (the dirty count, git or not, the branch and the path).
- Story 18: the start decision and command line of the chat host, like `StartCarrier`'s; no test for the spawn.
- Story 19: pure code over the `workspace`, `suggestName` and `checkName` replies and the preview, against golden files, once the epic #486 has defined them.
- The client over the socket: a test of the real client against the fixture server, as `ControlClient` has, for requests, replies, errors and a host that goes away.
- No automated tests: the AppKit and SwiftUI views and the wiring in `AppDelegate`; they are checked with `--fixture`, `--smoke-window` and the person's eyes.

## Out of scope

The changes panel and the diff. The Home page. Take over of a stopped epic. Clone, new repository and empty-folder workspaces, and repositories from Carrier's list in the picker. Notifications for sessions. Images, attachments, checkpoints, forks and switching provider mid-session. Renaming a session. Searching inside a transcript. The worktree backend (#486), though the screens for it are here. Any change to the chat host except what #486 adds. A way to configure agents from the app: the `chat` block of the config file as it is.

## Open questions

Whether SwiftUI's own markdown rendering (`AttributedString`) covers what the agents write (paragraphs, lists, inline code), and how the code blocks, which it does not draw, are done. Settled by #496, against a recorded conversation (`chat-events-finished.json`): `AttributedString` covers what is inside a line (bold, italics, inline code, links); the blocks, the bullets and the code are read by `markdownBlocks`, the reader the epics' Agent output already had, extended to read fenced code as a block of its own with its language, drawn by `CodeBlockView` with a Copy button. Numbered lists and tables are not read as blocks (a numbered item shows as a line with its number): a block parser is the step if agents write them a lot.
