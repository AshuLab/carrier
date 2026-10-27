# A file in the Files changed tab opens to the fragment that was edited

Status: spec

## Problem

The Files changed tab of the macOS app lists what each agent session changed: one card per lane, merged slice or fix round, and in each card the files with their path, `+122 −0` and five squares. It says how much changed and nothing about what. To see the edit Diego has to leave the app: open the slice's pull request on GitHub, or open the lane's worktree in an editor. Neither works for the two cases that matter while an epic runs, because a lane in progress and a fix round that is not merged yet have no pull request, and the worktree is a path he has to find.

What he wants is the fragment of the file that was edited, next to the line that says it was edited, and nothing more. He does not want the whole file, a place to comment, or a different tab.

## Solution

Clicking a file row opens, under that row, the edited fragments of the file: each changed hunk with three lines of context around it, additions in green and removals in red, drawn with the same rows the transcript uses for an edit (`DiffView`). Hunks that are not adjacent are told apart by a quiet separator row that carries git's `@@ -a,b +c,d @@` range, so two fragments never read as one block. Clicking the row again closes it. A long diff is cut at the same 30 rows with "Show N more lines". The row is a real button: it can be reached and opened with the keyboard and says whether it is expanded.

The fragment is the file's diff over the card's own range, which is exactly the range the card's numbers are counted over (a lane against its fork point with its uncommitted work, a merged slice against its first parent, a fix round between the review's head and the fix's head), so the fragment and the `+n −n` of its row agree. A file two lanes edit shows each lane's own fragment in its own card. A new file a lane has not added yet shows every line as added. A binary file, or a new file too big to read, opens to one line that says there is no preview. A file the agent has since put back as it was opens to one line that says it has no changes.

The engine gains one optional request, `fileDiff`, announced in the hello's `capabilities` like the others. An engine without it still works: the app then shows the rows as they are today, without the affordance to open them. The request is separate from `files` because that reply is polled every ten seconds and bounded at about 400 KB; a diff per file would blow it for the sake of rows nobody opened.

A merged slice and a fix round have fixed ends, so their fragment is asked once when the row is first opened and kept for as long as the epic is on screen. A lane is alive, so an open lane row is asked again with the tab's ten second poll while the epic runs, and the previous fragment stays on screen until the new one arrives; otherwise the row would say `+20` and show nineteen lines. When the epic is not running a lane is asked once, as the `files` request is.

The scope is the tab's own: a file appears here when the tab lists it, so an epic whose worktree is gone (landed and cleaned up) shows no files and so no fragments. For that case GitHub's pull request is the record. If the request fails (the worktree vanished while the row was open, git did not answer), the row says the changes cannot be loaded and the rest of the tab keeps working.

What was cut. Opening the file or the pull request on GitHub lost because lanes and fix rounds have no pull request, and because the redesign spec already decided that the files come from git and never from GitHub. A sheet or a side panel lost because the fragment is wanted beside the line that announces it, and a sheet hides the list it came from. Showing the whole file with the edit marked lost because Diego asked for the edited fragment. Reusing the diffs already in the transcript cards lost because those are one edit of one tool call: a file an agent touched five times has five of them, the tab shows the net change of the card, and a harness without events has none. Carrying the diffs in the `files` reply lost for the size above. Comments, copy path and open in an editor are not asked for and are out.

## Scope

1. As Diego, I click a file row in a card of the Files changed tab and see, under it, the fragments of the file that were edited in that card; I click again and it closes.
2. As Diego, I see each fragment as its changed lines with three lines of context, added lines green and removed lines red, and a separator carrying the line range between fragments that are not adjacent.
3. As Diego, the lines I see add up to the `+n −n` on the row, unless the fragment says it was cut.
4. As Diego, a long diff opens at 30 rows with "Show N more lines", and an enormous one says it was cut.
5. As Diego, a file that two lanes edit shows, in each lane's card, only what that lane changed.
6. As Diego, a file that is new in a lane shows all its lines as added, before the lane has added it to git.
7. As Diego, a binary file, or a new file too big to read, opens to a line that says there is no preview, and a file the agent put back as it was says it has no changes.
8. As Diego, I never see a secret the repository's files hold: tokens, private keys and `NAME=value` secrets are redacted as they are in the transcript.
9. As Diego, a merged slice's or a fix round's fragment does not change or reload while I read it; an open lane's fragment follows the lane every ten seconds while the epic runs, without flicker.
10. As Diego, with an engine that does not answer `fileDiff` the rows look and behave as they do today.
11. As Diego, when a fragment cannot be loaded the row says so and the rest of the tab keeps working.
12. As Diego, I can open and close a file row with the keyboard, and VoiceOver says whether it is expanded.
13. As the engine's owner, `fileDiff` answers only for a file that is in the card's own list, and hands nothing the repository configures (diff drivers, external tools) a chance to run.

## Decisions

No ADR: nothing here is hard to reverse, and ADR 0008's rule (SQLite and GitHub are the authority on state) is untouched, because fragments are read from git on demand and never stored.

One function resolves a card id to where git is asked and over which range (`{ cwd, range }`: the lane's worktree and its fork point, the epic worktree and `<sha>^1..<sha>` of a merge, the epic worktree and the two heads of a fix round). `filesOf` takes its numbers from it and `fileDiff` its fragment, so the two cannot drift apart. The card ids are the ones `filesOf` already issues: `lane-<N>`, `slice-<N>` and the execution id of a fix round.

The request and its reply:

```ts
// request: the card's id and the file's path, both checked before git is asked
z.strictObject({ id, cmd: z.literal('fileDiff'), repo, issue, section: z.string().min(1).max(100), path: z.string().min(1).max(500) })

export type FileDiffReply = {
  /** '@' is a hunk separator whose text is git's `@@ -a,b +c,d @@` header; the rest are as `ExecEvent.diff`. */
  rows: { sign: '+' | '-' | ' ' | '@'; text: string }[];
  /** the rows were cut at the cap. */
  truncated: boolean;
  /** set, with no rows, when there is nothing to draw. */
  note: 'binary' | 'too-big' | 'no-changes' | null;
};
```

`Controls.fileDiff(repo, issue, section, path)` returns `null` for an unknown epic, card or path; the server answers `{ ok: false, error: 'unknown file' }` and never git's own message. The path is accepted only when it is in the card's file list as `filesOf` builds it, and is given to git after `--` as a literal pathspec (`:(literal)<path>`). Git is run with `--no-color --no-ext-diff --no-textconv --no-renames -U3`, so a driver configured in the repository does not run; a rename is a removal and an addition, as in the numbers. For a lane the tracked diff is taken against the fork point and a file that is untracked is read the way `untracked()` reads it today (a symlink is not followed, over 1 MB or with a NUL byte is `too-big` or `binary`). The text goes through `redact` (`src/logging/redact.ts`) as a whole before it is split into rows, so a private-key block is not cut into pieces the patterns no longer match, and is then capped at 1,000 rows and 2,000 characters a line, setting `truncated`. The app already cuts a line at 2,000 characters.

On the app side `DiffSign` gains a hunk case and the file row model (`FilesChanged.swift`) a way to turn a `FileDiffReply` into the same `DiffRow`s `DiffView` draws. `ControlRequests` gets `fileDiff`, gated on the capability. `EpicFocus` gains the set of open file rows (card id and path, and whether the card is a lane); the poller asks a row that has no fragment yet, and re-asks an open lane row every ten seconds only while the epic runs and the files tab is visible, like `files`. Fragments live in the epic's data beside `files`. The fixture server answers `fileDiff` for every file of `reply-files.json` with `reply-filediff.json`, so the app run on `DevFixtures` shows a fragment.

Testing seams, per story:

- Stories 1, 2, 3, 5, 6, 7, 13 (engine): `src/control/files.test.ts`, which builds a real temporary repository with a lane, a merged slice and a fix round and calls the engine function through the same entry the server uses. The expectations are literal rows and git's own numbers, and story 3 is a test that the rows' signs add up to `filesOf`'s `added` and `removed` for the same card. The unknown card, the path outside the list, a path with `:(glob)` or `..`, a symlink, a NUL byte and an over-the-cap file are cases of the same file. Story 13's "no driver runs" is a repository whose `.gitattributes` and config name a diff driver that writes a marker file, and the marker must not appear.
- Story 8: `src/control/files.test.ts` with a file holding each shape the redaction list covers, including a private-key block spanning lines.
- Stories 4, 10 and the wire (engine): `src/control/server.test.ts`, which already checks the allowlist of requests, the hello's `capabilities` and the error replies over a real socket; `fileDiff` joins it, with `unknown file` and `internal error`.
- The contract: `src/control/replies.test.ts` writes `macos/Tests/Fixtures/reply-filediff.json` (and the DevFixtures copy) and fails when it differs, as it does for the other replies; `RepliesTests` in `CarrierCoreTests` decodes it, including a reply with `note` set and one with `@` rows.
- Stories 4 and 9, 10, 11 (app): `CarrierCoreTests`. `FilesChangedTests` for rows from a reply (hunk rows, the cut, the notes); `ControlRequestsTests` over `TestServer` for the request's fields and for not asking an engine without the capability; `EpicPollerTests` for the cadence (asked once for a merged slice and a fix round and never again, every ten seconds for an open lane while the epic runs, not again when it stops, the old fragment kept while a new one is awaited, a failure leaving the rest of the data alone).
- Stories 1, 2, 12: no unit tests: the `FilesChangedView` row is SwiftUI with no logic left once the model above is tested, and the macOS app's own workflow is to run it on the fixtures and with `--smoke-window` (a width far above 1100 means a layout blow-up). Story 12 is checked by hand with the keyboard and VoiceOver on that run, and a fragment is tried against the real engine's data too, because fixtures never carry long or odd lines.

## Out of scope

Commenting on a line, staging, reverting or any write. Showing the whole file. A diff for epics whose worktree no longer exists. Syntax highlighting. Side by side view. Diffs of the epic as a whole against the default branch (the tab shows no such card).
