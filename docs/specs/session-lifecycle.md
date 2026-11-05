# A session has a lifecycle: it is archived and deleted by the clock

Status: spec

## Problem

A user session can be archived and deleted by the person, and deleting takes its worktree with it, but nothing ages. Sessions, worktrees and `carrier/*` branches stay until someone clears them, and a person who uses sessions as a quick way to ask an agent about a repository ends up with a pile they have to tend. The owner wants sessions nearly disposable and wants their life to be clear: the first message creates one, the person works in it, and when it is over they archive or delete it, or time does it for them.

We know it is solved when a session left alone for 15 days is archived, one left alone for 30 days is deleted, both numbers can be changed or turned off, and nothing the person had not saved is lost by it.

## Solution

The decisions, and the three that lost, are in [0019](../adr/0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md); the terms are in the glossary (Session lifecycle). The first message creating the session is another epic's.

A session is archived after 15 days of no activity and an archived session is deleted after 30, both counted from the last message or event (`lastActiveAt`), and restoring a session from the archive counts as activity. The numbers are `archiveAfterDays` and `deleteAfterDays` in the chat's `chat.json`, each a whole number of days or `"never"`. `"never"` for the first means nothing is deleted by the clock, whatever the second says. The second must be greater than the first when both are numbers, and a file that breaks that or any other rule stops the host naming the key, as any wrong value of that file does.

The chat host applies the clock in one pass when it starts and again every hour while it runs, never after it stops: a host that was not running for 40 days archives and deletes what is due the next time it starts. The pass reads the two numbers from `chat.json` each time, so a change made in Settings is used by the next pass with no restart; when the file is wrong at that moment the pass is skipped and says why in the log. A session that is working, waiting for an approval or live (open in the host) is skipped and looked at again on the next pass.

The automatic delete never removes a session whose worktree has uncommitted changes or commits that exist nowhere else. It uses the check the host makes for a delete by hand (`previewWorktree`), one session at a time and just before deleting it, so commits shared with a session deleted a moment earlier count as lost and spare the next one. A session that is spared stays archived and is marked as kept because of unsaved work until a later pass finds the worktree clean (and deletes it) or the person restores or deletes it. A worktree that git cannot read is not "unsaved work": the session is left alone, the failure is logged, and the next pass tries again. A session that works in the person's own folder has no worktree and is deleted without the check. Archiving loses nothing and has no guard. The projects folder's clones are not touched.

The host's session list says what the app needs to show the clock, so the app never reads `chat.json` for it: each row has `kept` (true while the session is spared) and `deleteAt` (the time, in milliseconds, the clock will delete it; null when it is not archived, when either number is `"never"` or when it is kept).

Settings has a Sessions section with the two numbers, each a field with a "Never" choice, saved as they are changed like the Behavior tab and written to `chat.json` the way the projects folder's change already is (the file's other keys are kept, a value equal to its default is left out). Delete is off, with the reason, while archive is "Never", and a value that breaks the rule is not saved and says why in the field. The Archive page says when each session will be deleted, and a kept session says why it is still there.

What lost, besides what 0019 lists: a lifecycle with more states (a "done" state the person sets, a trash with a way back): archive already is the way back, and a state the person has to set is the chore this tries to remove.

## Scope

1. As a person, a session I left alone for 15 days is archived by Carrier, and it is not if it was working, waiting for me, or open in the host.
2. As a person, an archived session I left alone for 30 days is deleted with its worktree and branch, and the clone of its repository stays.
3. As a person, a session whose worktree has unsaved work is not deleted by the clock: it stays archived, says it was kept because of unsaved work, and I can delete it myself with the confirmation that lists what would be lost.
4. As a person, restoring a session from the archive counts as activity, so it is not archived again at once.
5. As a person, I can change the 15 and the 30, or turn either off with "Never", in Settings, and the change is used without restarting anything.
6. As a person, I see in the Archive page when each archived session will be deleted, and why a kept one is still there.
7. As a person, a host that was off for weeks catches up on its next start, and a wrong `chat.json` stops the host at start naming the key.
8. As a person reading the docs, I find the two settings, what the clock does and what it spares.

## Decisions

The ages and the sparing of unsaved work are decided in [0019](../adr/0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md); the config level in [0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md). `config.ts` documents the two keys and `docs/configuration.md` is updated (AGENTS.md: changing `chat.json`'s schema means updating that guide).

The keys, as the schema takes them. Run against the inputs the stories take: `0`, `-1`, `1.5`, `"15"` and `null` are refused for either key; `archiveAfterDays: 30, deleteAfterDays: 30` and `15, 10` are refused (delete must be greater); `"never"` and `5` are accepted together (nothing is deleted); a file with one key only takes the other's default.

```ts
const days = z.union([z.int().positive(), z.literal('never')]);
// archiveAfterDays: days (default 15), deleteAfterDays: days (default 30)
// refine on the pair: when both are numbers, deleteAfterDays > archiveAfterDays, reported on deleteAfterDays
```

What is due, as one pure rule the pass and its tests share (a session's `state` is `idle`, `working` or `waiting_approval`, and `live` is whether the host holds it open):

```ts
const DAY = 86_400_000;
const idleFor = (row, now, days) => days !== 'never' && row.state === 'idle' && !row.live && now - row.lastActiveAt >= days * DAY;
const toArchive = (row, now, ages) => !row.archived && idleFor(row, now, ages.archiveAfterDays);
const toDelete = (row, now, ages) => row.archived && ages.archiveAfterDays !== 'never' && idleFor(row, now, ages.deleteAfterDays);
```

The session row gains a nullable `keptAt` (set when the pass spares a session, cleared when it is restored), by a migration generated with `pnpm db:generate`; `list` rows gain `kept` and `deleteAt` as above, with no new capability because an older app ignores keys it does not know and an older host leaves them out, which the app reads as not kept and no date. Restoring (`archive` with `archived: false`) sets `lastActiveAt` to now.

The pass is a control of the sessions module beside `archive` and `delete`, taking the ages, and the host calls it at start and re-arms it every hour with the clock's `after` (the clock has no repeating timer, and the host's idle exit is untouched: a host that exits has no clock to run).

Testing seams, per story:

- 1, 2, 3 and 4: `createSessions` in `sessions.test.ts`, with the fake clock, the fake git and the temporary database those tests already use, calling the pass with different ages: due and not due by a day, working and waiting and live skipped, a worktree session clean and dirty and with commits only on its branch, two worktree sessions sharing a commit deleted in one pass, a git that fails, a session in the person's own folder, restore then pass. This is the broadest seam and carries most of the behaviour.
- 5 (the file): `config.test.ts` through `loadChatConfig`, with the values above, wrong-typed and empty ones included; and `host.test.ts` for the pass running at start, again after an hour of the fake clock, reading the file fresh each time and skipping a pass on a wrong file.
- 5 (Settings): the pure functions of the section in `CarrierCore` (applying the two numbers to `chat.json` keeping its other keys and leaving default values out, and the rule the fields show), in a test beside `WorkspaceSourcesTests`' `applyingProjectsFolder` cases; and `WindowShellTests` for the new section. The view has no automated test.
- 6: `list` in `sessions.test.ts` for `kept` and `deleteAt` (not archived, never, kept, due), and `ChatSessionsTests` for the decoding and the Archive page's line (`archivePage` and its row). The view has no automated test.
- 7: the host start in `host.test.ts` (a wrong file throws `ChatConfigInvalid` naming the key, a host that starts late catches up in its first pass).
- 8: no tests, docs.

## Out of scope

Deleting clones or any part of the projects folder. Sessions of the engine's epics, which have their own life. A setting for how often the clock runs, or to run it with the app closed. Warning the person before a session is archived or deleted by the clock; the Archive page says when. Changing how a session is deleted by hand. The wording of the Archive page's lines is the slice's.
