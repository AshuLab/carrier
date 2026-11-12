# 0023 - The engine reloads its configuration on request, and running work keeps what it started with

- Status: accepted
- Date: 2026-11-12

## Context

The engine reads `config.json` and `providers.json` once, when it starts, and holds the values as constants: the poll interval, the limits, the repos with their roles, the profiles, the orchestrator's profile, the timeout of its GitHub client, the log level and the numbers its panel shows. A person who changes any of them in the macOS app, which saves as each value is changed, or by hand, sees nothing happen until Carrier is stopped and started, and stopping interrupts the agents that are running. The app's pages already say so in their footer: "Carrier reads these when it starts."

Two things make a live change cheap to reason about. Each epic stores the configuration it started with (its roles, accounts, failover and whether the identity is shared), so what an epic is already doing never depended on the file. And the engine already has a rule for a repo that leaves the configuration and comes back: its epics are parked as `repo_removed` and restored where they were, with no GitHub call, label change, execution or retry meanwhile. That rule runs only once, at start.

## Decision

The engine reloads on request. The control socket gets a `reload` request, listed in the hello's `capabilities` like the other optional ones, and the CLI gets `carrier reload`, a client of it. The macOS app sends it after each save. The engine reads both files again from the same places it started with, validates them as a start does, and, only when they are valid, replaces its settings. When they are not, it keeps the settings it has and answers with the problem, the key named, as a start would have refused. Nothing watches the files.

Settings are read where they are used, so a change takes effect at the next decision, not inside one that has begun. The poll interval, the limits, the finished window, the repos with their roles, the profiles, the orchestrator's profile and the GitHub timeout, the log level and the numbers of the panel and of `carrier watch` all follow the settings the engine has now. An agent run keeps the agent, the account and the timeout it was launched with. An epic keeps the configuration it stored when it started; a change reaches the epics that start after it, and an epic that stops and is restarted starts again from the settings of that moment. A limit lowered below what is running stops new epics from starting and does not stop the running ones.

A reload re-arms the next poll from now with the interval then in force and asks for one at once, so a shortened interval does not wait out the old one and a repo just added is seen. The reconciliation of `repo_removed` and `repo_restored` runs again on every reload, and a repo that leaves the configuration also stops the agent runs that are active on it, which are marked interrupted as recovery marks them. The epic is parked where it was and goes on from there if the repo comes back.

A profile is looked up by name each time an execution needs a token. A profile removed while a running epic still names it fails the epic's next run with the profile's name, and the epic stops in `needs-human`; putting the profile back and restarting the epic is the way out. The clone and fetch of a running epic sign as the repo's current author profile, not the one the epic stored.

## Alternatives considered

Watching the files and reloading by itself. It also covers edits by hand with no command, and it is the same engine change, but it reacts to a half-written file, to an editor's rename and to the app saving two files one after the other, and it leaves the person with no answer when the file is wrong. A request answers at once and says why.

Reloading only the values that are plain numbers and leaving repos, roles and profiles for a restart. It is the smaller change, and it leaves the part of the configuration that people edit most, which repos are watched and who works on them, still needing the interruption that this decision exists to avoid.

Letting a running epic switch to the new roles at its next stage. A person changing the author's model while an epic is half done would be changing the mind of a run that was chosen as a whole; the epic's stored configuration is the line that already exists, and restarting an epic is how one crosses it.

Refusing a reload that drops a profile a running epic names. It prevents the failure and turns an autosaving page into one that cannot be saved without a reason the person may not see; a named failure on the epic that was using it is the smaller cost.

Copying the profiles into each epic's stored configuration. It would remove that failure and would hold a bot's name that the person has since renamed or deleted, to keep signing as an identity they meant to change.

## Consequences

A change made in the app reaches Carrier in about the time of a poll, with no restart and no interrupted agent. The footers of the pages that say Carrier reads the settings when it starts change, and stay as they are when Carrier is stopped or does not list `reload` among its capabilities, which is how an older engine keeps working with a newer app and what a stopped Carrier does with the file. With no engine to ask, a save sends nothing and is not an error; a running engine that does not list `reload` is told to the person quietly, because an older Carrier after an update of the app is a normal state and not a fault.

The engine's constants become settings that are read when used: `createEngine` and `startCarrier` take a way to read them instead of the values, and the pieces built once at start from them, the GitHub client with its profile and timeout, the runner's credentials and the workspaces' token, read the current profiles and the current orchestrator.

A reload is applied between the engine's own awaits, so a poll already running finishes with the repos it began with and the next one sees the new ones. A reload asked while a poll runs does not start a second one beside it; one more follows it when it ends, with the new repos and the new interval. A reload runs the rule for parked repos and recovers only the epics it brings back: the recovery of a start would take an epic with a launch in flight for one that was cut. Each epic has an epoch that parking it increases; the paths that wait on GitHub or on the workspace compare it after their awaits and stop when it changed, so an epic that was parked and brought back is continued by the reload and by nothing else. Bringing a repo back waits for the stop of the runs it had, so the epic is relaunched once, never beside the run that was ending. A repo that GitHub refuses (a mistyped name, no access) is shown with its error in its own check and does not stop the polling of the others; an error that is not a GitHub answer still surfaces. The paths that wait on an `await` (a workspace being prepared, a result being imported) read the epic's status again afterwards and leave it alone when its repo was parked meanwhile.

The app saves `config.json` and `providers.json` as separate files, so a reload sent between the two can see an account named by a role that is not in the file yet. It is refused with the problem and the engine goes on as it was, and the reload that follows the second save succeeds.

The chat host is not part of this: it reads `providers.json` at each request already and has no engine configuration.
