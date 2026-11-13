# Engine in Settings

Status: spec

## Problem

The Engine page of the macOS app still sits in the Legacy group, under a heading that says it is about to go away. It holds a readiness banner, a button "Detect again", the switch "Start Carrier when the app opens" and an advanced text field "Use this carrier", and not much else. The rest of what a person needs to run Carrier on this Mac is scattered or missing: "Ask before stopping Carrier" is in General, which is about the app and not about Carrier; the `PATH` the engine runs with, which is what fails in a stale start (`agent-forge ENOENT`), cannot be seen anywhere; the GitHub identity the engine reads issues with, `orchestratorProfile`, can only be set by editing `config.json`; and to read a log or open the Carrier folder the person has to find them in Finder.

We know it is solved when Engine is a page of the Carrier group with everything the person sets about running Carrier, and a person who cannot start Carrier can see which `carrier`, `node` and `PATH` the app uses, change them, and open the logs, from Settings.

## Solution

Engine moves to the Carrier group, after the pages it already has, and leaves the Legacy group. The line under its name, in the rail and under the title of the page (one `detail`, as for every page), reads "How the app runs Carrier" instead of "How the app starts Carrier". The page that the stopped-Carrier view opens stays Engine.

The page has no note about saving: each control is written as it is changed. It has four groups:

- **Starting**: "Start Carrier when the app opens" ("Carrier starts working on ready epics as soon as the app opens", off by default, disabled while the engine is not configured, as today) and "Ask before stopping Carrier" ("Only when stopping would interrupt epics that are running"), which leaves General. Both are the app's own preferences, as they are today.
- **Programs**: `carrier`, with the path the app uses and its version, and the button "Use another…" that opens a file picker (a path ending in `.ts` or `.js` still runs under `node`; while one is set, the row says it is the person's own and offers "Use the Homebrew one" to clear it); `node`, with its path and version; `PATH`, the one the engine and the chat host run with, read only; and "Look for the tools again" ("Asks your shell where node and the PATH are. Use it after installing a tool while the app was open") with the button Detect, which does what "Detect again" does today.
- **GitHub identity**: "Carrier acts on GitHub as", a choice among the profiles declared in `profiles` of `config.json`, "Reads issues and PRs and changes labels. Default is the author's identity". The default, which is the engine's when the key is left out, removes `orchestratorProfile` from the file instead of writing the author's name into it. A file that already names a profile that is not declared shows it in orange, as the Agents page does for a role, and keeps it until the person picks another.
- **Files**: "Carrier folder", "Logs" (`<folder>/engine/logs`) and "Start log" (`<folder>/engine/logs/app-start.log`, "What the app saw the last time it started Carrier"). The first two have Reveal, which shows the folder in Finder; the last has Open, which opens the file. A row whose folder or file does not exist yet is disabled and says "Not created yet".

The readiness banner and the rest of the app's start-up stay as they are, except its text: when something is missing it now says to use "Use another…" and then Detect under Programs, in place of "Use this carrier" under Advanced. The shell stays where it is: the app still asks it for `node` and the `PATH` once, saves them, and asks again only when the person presses Detect.

What is not in Engine: the engine's start and stop (the menu and the window have them), its live state and a reload button (the reload epic decided there is none).

## Scope

1. The rail lists Engine in the Carrier group, after the pages already there, and the Legacy group no longer has it.
2. Engine's header and its rail row say "Engine" and "How the app runs Carrier", with no note about saving.
3. Starting has the two switches, with the titles and descriptions above; "Ask before stopping Carrier" is gone from General and keeps its preference, so a person who turned it off still has it off.
4. Programs shows the `carrier` the app uses with its version, the `node` with its version and the `PATH`, read only; a `carrier` or `node` the app does not find says "Not found" instead of a path.
5. "Use another…" opens a file picker and sets the path; "Use the Homebrew one" clears it; the Start Carrier button of the app uses it as it does today.
6. Detect looks for `node` and the `PATH` again, shows that it is working, and shows the message it has today when the shell does not answer.
7. "Carrier acts on GitHub as" lists the declared profiles with the default first; choosing a profile writes `orchestratorProfile`, choosing the default removes the key, and every other key of the file is left as it is.
8. A profile named by the file but not declared is shown in orange and kept; a file that cannot be read leaves the row disabled with its explanation, as the other pages do.
9. Files shows the three rows; Reveal and Open act on an existing path and a missing one is disabled with "Not created yet".
10. The banner's text, when something is missing, names Programs on this page.
11. The README of the app, the glossary's Legacy group and the changelog agree with the new place.

## Decisions

The pages and their groups are the cases of `SettingsPage` in CarrierCore, so the move is the `group` of one case and its place in the order; the rail is built from them.

Engine's groups, rows, titles and descriptions are a pure model in CarrierCore, in the style of the models of the other Settings pages, and the view only draws it: the paths, versions and existence of the files are inputs of the model, so what a row says with `carrier` missing, a `.ts` override, no `PATH` yet or no log yet is tested without a window.

`orchestratorProfile` is written by a function in CarrierCore that takes the file's bytes and returns the new bytes, like the other `applying…` functions that edit `config.json`; the page writes it as the Behavior page writes its values, and after its own successful write it asks the engine to reload as every other writer does (the `AfterWrite` of `EngineReload.swift`), showing a problem the engine answers where the page shows a failure to save. So the choice applies to the next epic with no restart, and the row does not need to say when.

The readiness banner stays a pure function of what is missing and whether the shell is working (`readinessBanner`); only its text changes, and it shows where it shows today.

No new default, no key in `config.json` besides `orchestratorProfile`, and no new engine request.

Testing seams, story by story:

- Story 1: `SettingsPageTests` already pins the groups and the order of the rail; it asserts the new place and the line.
- Stories 2 to 4 and 9: the Engine page model's test, listing the groups, titles, descriptions and rows for a found `carrier`, a missing one, a script with `node`, a missing `node`, and for logs that exist and that do not.
- Story 3: `AppPreferences` tests already read the stop confirmation; the General page model's test asserts the row is no longer there.
- Stories 5 and 6: `SetupDetection` and `SetupController` tests already cover the override, `carrierPath`, `enginePath` and the detector with a fake shell.
- Stories 7 and 8: `EngineConfigTests`-style tests of the new function: a profile written, the default removing the key, an undeclared profile kept, every other key and its order left as it is, a file that is not an object refused.
- Story 10: the banner model's test (`readinessBanner`) asserts the new text.
- Story 11: no tests, a documentation change.
- The views have no unit tests; the fixture build and the smoke check cover them.

## Out of scope

Defining or creating profiles (identities) from Engine: they are Agent Forge's, and the Agents page lists them. Starting and stopping the engine from Settings, a reload button, and live status of the engine. Detecting `node` and the `PATH` by itself at every start, which is a change of the app's behavior. A per-repo identity for the orchestrator.
