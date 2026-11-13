# Sessions in Settings

Status: implemented (unreleased)

## Problem

The Sessions page of the macOS app still sits in the Legacy group, under a heading that says it is about to go away, with the two ages of the session clock and nothing else. Everything else a person decides about their sessions is somewhere it does not belong: what a new session starts with (provider, model, reasoning and access) and whether the app asks before deleting a session are on the Chat page, which is about the message box and the conversation. A new session always opens on the base folder, so a person who always works in a worktree chooses it in every draft. And the page gives no hint of what the ages will do: the person has to count fifteen and thirty days from the last time they used a session to know when it goes.

We know it is solved when Sessions is a page of the Chat group, holding everything the person sets about how a session starts, ages and is deleted, the Chat page holds only the message box and the conversation, a new session can open in a worktree by default, and the page says, in dates, when a session left alone from today is archived and deleted.

## Solution

Sessions moves to the Chat group, after Sidebar and before Dictation, and leaves the Legacy group. The line under its name, in the rail and under the title of the page (one `detail`, as for every page), reads "How sessions start and age out" instead of "When sessions age out".

The page has four groups and a Reset:

- **New sessions**: "Starts with" (the row of the Chat page, moved as it is: the provider, model and reasoning, and the access, a new session opens with; the message box still changes them for that session) and "Work in", new, with the choices "The base folder" and "A new worktree" ("Where a new session opens. A new worktree is offered only for a git repository; the new session screen still changes it for that session"). "Work in" is an app preference, the base folder by default, which is what a new session does today. When the folder of a draft offers a worktree and the preference says so, the draft opens in a new worktree, with the name and branch it suggests as always; when the folder offers none (not a git repository, a bare one, one with no branch) the draft opens on the base folder as today; what the person chooses in a draft is what that session gets.
- **Archive and delete**: "Archive after" and "Delete after" as they are (a number of days or Never, written to `chat.json` as they are changed, the same checks and messages, "Delete after" off while "Archive after" is Never) and "Ask before deleting a session" ("The question says that its worktree is removed with it"), moved from the Chat page as it is.
- **With these ages**: two lines that read the ages above, in the person's words. The first, "A session you stop using today", says when it is archived and when it is deleted, as dates ("Is archived on Nov 28 and deleted on Dec 13. Both ages count from its last activity"), the year only when it is not this one; with "Archive after" at Never it says it is never archived or deleted, and with "Delete after" at Never that it is archived on a date and never deleted. The second, "Left alone", says that a session that is working, waiting for an approval or open is looked at again later. While an age is refused, the first line is not shown.
- **Reset**: "Restore the defaults", "Everything on this page goes back to how it came": "Starts with" goes back to the first provider that can work, "Work in" to the base folder, "Ask before deleting a session" to on, and the two ages to 15 and 30 days in `chat.json`.

The Chat page keeps its Message box and Conversation groups and its own Reset, which no longer touches what moved. Nothing else of the page changes.

The session clock itself, which the chat host applies when it starts and every hour, is not changed: the dates the page shows are the ones that clock will use.

## Scope

1. The rail lists Sessions in the Chat group, after Sidebar and before Dictation, with the line "How sessions start and age out", and the Legacy group no longer has it.
2. "Starts with" and "Ask before deleting a session" are on Sessions and no longer on Chat, with the same controls, titles and descriptions and the same stored preferences, so a person who changed them keeps their choice.
3. "Work in" lets the person choose The base folder or A new worktree, stored as an app preference, the base folder when none was chosen.
4. A new session's draft opens in a new worktree when the preference says so and the folder offers one, on the base folder when it does not, and what the person picks in the draft stays what that session gets.
5. "Archive after" and "Delete after" behave as they do today: Days or Never, written as they are changed, a refused value shown in orange with its reason and not written, a file that cannot be read disabling the rows with its explanation.
6. "With these ages" shows the dates for a session left alone from today, for two numbers, for Archive after at Never, for Delete after at Never, and nothing about the dates while an age is refused; "Left alone" is always shown.
7. The Reset of Sessions puts back the four things above and the two ages; the Reset of Chat leaves them as they are.
8. The README of the app, the glossary's Legacy group and the changelog agree with the new place.

## Decisions

The pages and their groups are the cases of `SettingsPage` in CarrierCore, so the move is the `group` of one case and its place in the order; the rail is built from them. The preference keys that the Chat page resets today for "Starts with" and for the delete question move to the Sessions page's keys in `AppPreferences`, so each page resets what it shows; the page's own Reset also writes the two ages to `chat.json`, through the function that writes them now with the defaults.

The dates are a pure function in CarrierCore of the two ages, a date and a calendar, that returns the text of the line or nothing; the page gives it the date of the day, so it is tested without a clock or a window. The two ages count from the last activity, as the chat host's clock counts them, so both dates are from the same day.

"Work in" is read by the new session's model when the workspace answers and the draft is still as the person found it; the model already knows whether the folder offers a worktree (`offersWorktree`), and a person's choice in a draft stays above the preference.

No new key in `chat.json`, no new request of the chat host, and nothing changes in the engine.

Testing seams, story by story:

- Story 1: `SettingsPageTests` already pins the groups, the order of the rail and the lines; it asserts the new place and the line.
- Story 2: the `AppPreferences` tests: the Chat reset no longer clears the new-session and delete-question keys, the Sessions one does, and a stored value is read from the same key as before.
- Story 3: the `AppPreferences` test for the new preference and its default.
- Story 4: the new session model's tests (`NewSession`, with its fake host): a git folder with the preference on opens in a worktree, a folder that offers none opens on the base folder, and a choice made in the draft wins.
- Story 5: `SessionAgesTests` already cover reading, checking and writing the two ages; unchanged.
- Story 6: the tests of the new dates function: two numbers, Archive never, Delete never, an age refused, a date in another year, and the end of a month.
- Story 7: the `AppPreferences` reset test above, and `SessionAgesTests` for the ages written back as the defaults.
- Story 8: no tests, a documentation change.
- The views have no unit tests; the fixture build and the smoke check cover them.

## Out of scope

The chat host's clock, a new key in `chat.json`, how long an idle session keeps its agent process, the chat's log level and GitHub timeout, the projects folder, and any other setting about sessions that the app or the host does not have today.
