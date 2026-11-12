# Behavior in Settings

Status: spec

## Problem

The Behavior page of the macOS app is the last page of the engine's own settings that still sits in the Legacy group, with the pages that existed before the Settings rail had groups. Providers, Repos and Agents were redesigned into the Carrier group and say what they configure in the person's words, and Behavior still reads like the config file: its eight values are spread over four groups, Rhythm, Finished epics, Capacity and Agent runs, in which a number that decides how many epics run and a number that decides how long a GitHub call may take sit at the same level, and the Settings design (the prototype's Carrier, Behavior page) has already regrouped them by the question each one answers.

So a person who opens Behavior to make Carrier slower, faster or more careful has to know which of the four groups holds the value, and the page sits under a heading that says it is about to go away. The Carrier group, which now says "what Carrier watches" and "who works", has no page for "how it runs".

## Solution

The Behavior page moves to the Carrier group, after Agents, so the group reads Repos, Agents and Behavior, and the Legacy group keeps Engine, Sessions and Health. Its line under the title is "How Carrier runs epics".

The eight values, which are the same keys of `config.json` with the same rules and the same defaults, are shown in three groups and a reset:

- **Pace**: "Look for ready epics every" (minutes, `pollIntervalMinutes`) and "Epics at once" (`limits.maxConcurrentEpics`, "Running at the same time").
- **When something goes wrong**: "Review rounds before asking you" (`limits.maxReviews`, "Then the epic waits for a person (needs-human)"), "Retries after a technical failure" (`limits.maxExecutionRetries`, "Of an agent run") and "Time per agent run" (`limits.maxExecutionHours`, hours, with the Limit and Unlimited choice the page has today).
- **Housekeeping**, always shown: "Show finished epics for" (`finishedWindowDays`, "1 to 30 days"), "GitHub call timeout" (`limits.githubCallTimeoutSeconds`, seconds, "Each short call") and "Log level" (`logLevel`).
- **Reset**: one card, "Restore the defaults", "Everything on this page goes back to how it came", with a Reset button that does what "Reset to defaults" does today.

The page keeps what it does now: each value is written to `config.json` as it is changed, a value the engine would refuse is shown in orange with its reason and is not written, every other key of the file is left as it is, and the file is read again when the app comes back to the front if it was unreadable. The controls stay the app's number fields with their steppers and unit, a Limit or Unlimited choice for the run time, and a menu for the log level. (Superseded: the standing line "Saved as you change them · Carrier reads these when it starts" was dropped from the header; only "Saved" and the failures are said there.) The line "Saved as you change them" and what follows it moves from the bottom of the page to its header, like the line that Providers shows there, and says what is true of the engine at that moment: today "Carrier reads these when it starts", and what [the reload epic](https://github.com/AshuLab/carrier/issues/854) makes of it when it lands; this epic does not decide that text.

Nothing is added or removed from the engine's config: the page shows no wait for a provider's choice (the engine has none since the Agents epic), no per-repo limits and no new key.

## Scope

1. The rail lists Repos, Agents and Behavior under the Carrier heading, in that order, and Engine, Sessions and Health under Legacy.
2. The page's header says "Behavior" and "How Carrier runs epics", with the note about saving beside it.
3. The eight values appear under Pace, When something goes wrong and Housekeeping, with the titles and descriptions above, and no other group.
4. Each value is edited with the control it has today, keeps its validation and its message, and is written as it is changed.
5. Time per agent run still takes a number of hours or Unlimited.
6. The Reset card puts the eight values back to the engine's defaults, writing them to the file.
7. A file that cannot be read still leaves the page disabled with its explanation, and a value that is not a number yet is not written.
8. The README of the app and the changelog agree with the new place and groups.

## Decisions

The pages and their groups are the cases of `SettingsPage` in CarrierCore, so the move is one line of `group` and the order of the cases; the rail is built from them.

The page's groups and rows, their titles and descriptions, and which key each one edits are a pure model in CarrierCore, in the style of the Agents and Providers pages' models, and the view only draws it, so a title or a group can change without touching the view and the grouping is tested.

Testing seams, story by story:

- Story 1: `SettingsPageTests` already pins the groups and the order of the rail; it asserts the new ones.
- Stories 2 to 3: the page model's test, listing the groups, titles, descriptions and keys, and asserting that every one of the eight keys of `EngineConfig` appears exactly once.
- Stories 4, 6 and 7: `EngineConfigTests` already cover reading, validating and writing the eight values and keeping the rest of the file; they gain the reset to the defaults.
- Story 5: `EngineConfigTests` for `"unlimited"` and a number.
- Story 8: no tests, a documentation change.
- The view has no unit tests; the fixture build and the smoke check cover it.

## Out of scope

Any new setting, a per-repo limit, and the wait for a provider's choice. The text of the note about when Carrier reads the settings, which belongs to the reload epic. Moving Engine, Sessions or Health out of the Legacy group. The setup wizard of the app. Showing which values differ from the engine's.
