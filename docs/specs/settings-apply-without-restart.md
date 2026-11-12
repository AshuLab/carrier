# Settings apply without a restart

Status: spec

## Problem

Every setting that Carrier's engine uses, how often it looks for ready epics, how many epics run at once, the limits of a run, which repos it watches, who works on them and with which provider, the failover steps, the identities, the accounts, is read once, when the engine starts. A person who changes one in the macOS app, which saves as each value is changed, or in the file, sees nothing happen, and the pages say so: "Carrier reads these when it starts." To make it count they have to stop Carrier and start it, which interrupts the agents that are running.

So a settings page that looks live is not, and the cost lands on the person least able to pay it: someone adding a repo or lowering a limit while epics are working. The result is that people either do not touch settings while Carrier works or restart it and lose runs in flight.

## Solution

A reload, asked for. The control socket gets a `reload` request and the app sends it after every save, to `config.json` and to `providers.json`. The engine reads both files again from where it started, validates them as a start does, and replaces its settings only when they are valid. When they are not, it keeps the ones it has and answers with the problem, the key named, so the app can show it the way the Providers page shows a file that does not match. `carrier reload` is the same request from the terminal, for an edit by hand: it prints "Reloaded" or the problem and exits with 1 on the problem. The decision is recorded in [0023](../adr/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md), and the glossary has Reload.

What changes live is everything the engine reads from those files: the poll interval, the finished window, the limits, the GitHub timeout, the log level, the repos with their roles, effort, persona and failover, the profiles, the orchestrator's profile, and the numbers the panel and `carrier watch` show. The rule that carries it is that work in progress keeps what it started with and a change reaches what starts after it. An agent run keeps the agent, account and timeout it launched with. An epic keeps the configuration it stored when it started, which already exists, and a restarted epic takes the settings of that moment. A limit is read when the decision is made, so a retry limit or a review limit changed while an epic runs applies at its next failure or review, and a concurrency limit lowered below what is running only stops new epics from starting.

A reload re-arms the next poll from now with the interval then in force and asks for a poll, so a shortened interval does not wait out the old one and a repo just added is seen at once. A reload while a poll is running does not start a second one; the new settings are seen by the next.

A repo that leaves the configuration is handled by the rule the engine already has for it: its epics are parked as `repo_removed` where they were and come back when the repo does, and nothing touches GitHub for them meanwhile. That rule runs only at start today and runs on every reload. The agent runs active on that repo are stopped at once and marked interrupted, as recovery marks them, since the rule says no execution for a parked epic. Letting the current run end and parking the epic after it would leave Carrier writing to a repo that the person took out of the list.

A profile is looked up by name when an execution needs a token. If a person removes a profile that a running epic names, the epic's next run fails with the profile's name and the epic stops in `needs-human`; putting the profile back and restarting the epic is the way out. Copying profiles into each epic would hide that and would keep signing as an identity the person has deleted or renamed, and refusing the reload would make an autosaving page unable to save without a reason the person may not see, so neither was taken.

The pages' notes change from "Carrier reads these when it starts" to saying that Carrier applies them to the next epic, and only when the app reached an engine whose hello lists `reload`. With Carrier stopped, or with an older engine that does not list it, the app writes the file, sends nothing and keeps the old text, which is true there: that is how an older engine works with a newer app, and what a stopped Carrier does with the file. No "Restart Carrier" button is added, and the footer logic left over from when a save could restart Carrier, which no page uses, goes.

What was cut: watching the files, which would also catch edits by hand but reacts to half-written files and to the two files being saved one after the other, and answers nothing when the file is wrong; reloading only the plain numbers, which leaves the part people edit most, repos and roles, still needing an interruption; and switching a running epic to new roles at its next stage, which changes the mind of a run that was chosen as a whole.

## Scope

1. A `reload` request on the control socket makes the engine read `config.json` and `providers.json` again and, when both are valid, run on what they say.
2. When either file does not match, the engine keeps the settings it has and the reply carries the problem with the key named.
3. The hello lists `reload` among its capabilities, and an engine that does not list it is never asked.
4. `carrier reload` prints "Reloaded" or the problem, and exits with 1 on the problem.
5. The poll interval, the finished window, the three limits of a run, the concurrency limit, the GitHub timeout, the log level and the numbers the panel and `carrier watch` show follow the settings the engine has now.
6. A running agent keeps the agent, account and timeout it launched with, and an epic keeps the configuration it stored when it started; the epics that start after a reload use the new roles, effort, persona, failover and accounts.
7. A concurrency limit lowered below the epics running starts no new epic and stops none.
8. A reload re-arms the next poll with the new interval and asks for a poll, and does not start a second one while one runs.
9. A repo added by a reload is watched from the next poll, and a repo removed parks its epics as `repo_removed`, stops its active runs as interrupted and touches GitHub no more; adding it back restores them where they were.
10. The profiles and the orchestrator's profile that the engine uses for the next token, clone and GitHub call are the current ones; a profile removed while a running epic names it fails that epic's next run naming the profile and leaves the epic in `needs-human`.
11. The app sends `reload` after each successful write of `config.json` or `providers.json`, from every place that writes them (the Behavior, Repos, Agents and Providers pages), and shows the problem the reply carries.
12. With Carrier stopped, or an engine that does not list `reload`, a save sends nothing and is not an error.
13. The notes of the pages that say Carrier reads the settings when it starts say it applies them to the next epic when the engine lists `reload`, and keep the old text when it does not.
14. The unused "Save and restart" footer logic and its restart warning are removed.
15. The configuration guide, the README, `macos/README.md` and the changelog agree with all of the above.

## Decisions

The request and its replies, as the control socket already shapes them:

```ts
z.strictObject({ id, cmd: z.literal('reload') }); // no fields
// { id, ok: true }
// { id, ok: false, error: string } // the lines a start would print for the file, joined with "\n"
```

Checked against the inputs it takes: `{ cmd: 'reload', file: 'x' }` is refused by the strict object like any request with a field it does not know; a reload of a file that is missing, is not JSON or is not an object gets the `error` a start would print for it; a valid file with `repos: []` is valid and makes the engine watch nothing.

The engine and `startCarrier` stop taking the settings as values and take a way to read the current ones, and `startCarrier` takes the loader that produces the next ones from the same config path and Carrier folder it started with, which is `loadConfigFile` in production and a fake in tests. The reload is a function of the engine that replaces the settings between its awaits and then does what the Solution says; its refusal is an error that carries the problem, as `ResumeRefused` carries its reason, and the server turns it into the reply. The pieces built once at start from the profiles and the orchestrator, the GitHub client, the runner's credentials and the workspaces' token, read the current ones when called.

The log level is applied with `configureUniversalLogger({ minLevel })`, which merges the new options into the library's config; the file sink installed at start stays.

The app has one function in CarrierCore that asks the engine to reload: it connects to the control socket, checks the hello's capabilities, sends `reload` and returns nothing or the problem; no socket or no capability is a silent no-op. Each writer of the two files (the Behavior and Repos tabs, `GlobalRoleSave`, `RepoRoleSave`, `RoleDetailsSave`, `LeadReviewerSwitch`, `ProvidersFile` and the workspace sources) calls it after its own successful write, so a new page that writes the files is one call from live. A reload refused between the two writes of one change is shown only if the reload after the second write is also refused.

Testing seams, story by story, with the ones that exist:

- Stories 1 to 3: the control server's tests (`server.test.ts`) with a fake `reload` control for the reply, the strict request and the hello's capabilities, and `compose.test.ts` through `startCarrier` with a fake loader that returns a valid config and then an invalid one.
- Story 4: the CLI's tests of the control commands (`main.test.ts`, `control-client.test.ts`) for the confirmation and the exit code.
- Stories 5 to 8: the engine's tests with their fake GitHub, runner and clock: after a reload the next poll uses the new interval, a lowered limit blocks the next reservation and leaves the running epic alone, an agent already launched keeps its timeout and the stored configuration of an epic is unchanged while a new epic gets the new roles; the snapshot is read through `startCarrier`'s control as the numbers a client shows.
- Story 9: the same engine tests with two repos: one removed, asserting the epic's status, the fake runner's stop and the absence of GitHub calls, then restored.
- Story 10: `credentials.test.ts` with profiles that change between two calls, and the engine's test for the run that fails naming the profile.
- Stories 11 and 12: the CarrierCore tests beside `ControlRequestsTests` and `ControlClientTests` for the request and the capability, and the tests of each writer (`GlobalRoleSaveTests` and the Repos, Providers and Behavior ones) with a fake control that records the reload after the write, none when the write fails, and nothing sent when no engine answers.
- Story 13: a pure model of the note's text with and without the capability, in the style of the other CarrierCore page models. The views have no unit tests; the fixture engine of the smoke check answers `reload`.
- Story 14: the tests of the removed functions go with them (`BehaviorSaveTests`), and the build and the suite pass without them.
- Story 15: no tests, a documentation change.

## Out of scope

Watching the files. Changing the roles of a running epic. A Restart Carrier button. Reloading the location of the Carrier folder, the `--config` path (the same path is read again) or the instance lock. The chat host, which reads `providers.json` at each request and has no engine configuration, and its own `chat.json`. A reload that applies the update of the CLIs or of Carrier. Showing in the app which values differ from the ones the engine runs with.
