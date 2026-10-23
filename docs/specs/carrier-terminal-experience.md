# Carrier in the terminal: as clear as the app, and able to run without one

Status: spec

## Problem

Diego built the macOS app's experience with care and wants the terminal to reach the same quality. It falls short in two ways, for whoever runs Carrier from a terminal (Diego today; nobody else was asked, so this assumes it is only him).

The first is what the panel says. It shows where the epics are but not what happened to them: an epic appears as `repo #number` with no title, only the current stage is marked (not how long `ship` took, nor what a review round found), an epic that stopped for a person reads `agent needs_human` with no reason, and a repo that GitHub refused shows nowhere. This was checked by rendering the panel from the app's own sample snapshot.

The second is that Carrier holds its terminal until Ctrl+C. There is no way to start it without one, and no way to look at a Carrier that is already running from a terminal, short of opening the app.

It is fixed when Diego can start Carrier, close the terminal, open another one days later and read in a few seconds, for each epic, its title, how each stage went, why it needs him if it does, and whether each repo is healthy, and can steer it with the same keys as the foreground panel.

## Solution

The terminal gets a small set of commands and a clearer panel, and the macOS app becomes one more client of the same control socket, as [0005](../adr/0005-engine-independent-of-the-macos-app.md) intended. The words follow the glossary: what Diego called a step is a stage (`ship`, `review`, `fix`).

**Commands.** `carrier start` launches Carrier as a detached run ([0010](../adr/0010-carrier-runs-in-the-background-as-a-detached-process.md)): its own session, no terminal, its output in a log, and it returns once the control socket answers. `carrier stop` stops it through the socket. `carrier status` prints one snapshot and exits. `carrier watch` attaches to the running Carrier and shows the live panel; closing it never stops Carrier. `carrier pause`, `resume` and `check` (look at GitHub now) are one-liners over the socket. The foreground `carrier` stays as it is.

**The panel says more, from data that already exists.** The socket's snapshot is a superset of the panel's and the engine already builds it for the app: it carries each epic's title and the titles of its open blockers, the reason an epic needs a person, and one row per watched repo with its last check and error. What it does not carry is how each stage went, which the `sessions` request answers (stage, round, agent, status, start and end, and the outcome and reason of its result), the same request the app uses. So the engine needs no new data. Each epic shows its title; a line per stage with how it went (done stages with their duration and outcome, the current one marked) and, for a stopped epic, the reason it needs a person; a review stage lists its blockers by title. A repo GitHub refused shows with its error, in a section that appears only while some repo has a problem, so a healthy Carrier shows nothing extra. The rendering is indicative, to be fixed with Diego at the ticket:

```
 ┃ AshuLab/carrier #41  Add the watch command
 ┃ ship ✓ 14m · review ✓ round 1, 2 blockers · [fix] 2m · round ●●○○○
 ┃ active 10s ago · slices 3/5
 ┃ now  Edited src/terminal/cli/commands/watch.ts
```

One renderer draws the foreground panel and `watch`; they differ only in where the snapshot and the stage detail come from (the foreground process, or the socket). The stage detail of an epic is asked when the epic is first shown and again only when its stage, round, status, blocker count or latest execution changes in the snapshot, never once a second, so a refresh stays cheap and the panel never waits on a request that cannot have changed.

**`watch` keeps the foreground panel's keys** (↑↓ to select, `enter` to open the PR, `l` for the agent's output, `r` to check GitHub, `p` to pause, `?`, `q`), because it is the same component, driven through the socket (`checkNow`, `pause`, `resume`, `tail`). Only `q` differs: in `watch` it leaves and Carrier keeps running, and the help line says so; in the foreground it stops Carrier. An engine that does not advertise the `sessions` capability still gets `status` and `watch`, with the snapshot alone and no per-stage detail.

**The macOS app** gains an opt-in switch, off by default, "Start Carrier when the app opens", on the Engine tab's ready card. With it on, opening the app starts Carrier once, if the first answer of the monitor is that it is stopped and the setup is complete; never with `--fixture`. The app keeps its own Swift start until `carrier start` has proven itself, then calls it and drops the duplicate, as the ADR records.

## Scope

1. `carrier start` launches Carrier detached, waits up to 15 seconds for the control socket and returns, printing where the log is. If a Carrier already runs for that root it says so and does nothing. If it does not come up, it prints the end of the log and exits with an error.
2. `carrier stop` stops a running Carrier through the socket and returns when it is gone. With none running it says so and exits successfully.
3. `carrier status` prints the panel once and exits 0 when Carrier runs; when it does not, it says so and exits 1. Colour only when the output is a terminal.
4. `carrier watch` shows the live panel of a running Carrier with the foreground panel's keys; `q` or Ctrl+C leaves it and Carrier keeps running. With none running it says so and exits 1 without waiting.
5. `carrier pause`, `carrier resume` and `carrier check` do what their keys do in the panel and confirm in one line; with none running they say so and exit 1.
6. Each epic in the panel shows its title next to `repo #number`, in the foreground panel and in `watch`.
7. Each epic shows how each of its stages went: done stages with duration and outcome, the current stage marked.
8. A stopped epic shows the reason it needs a person, and a review stage shows its blockers by title.
9. A repo GitHub refused shows with its error in a section that appears only while one does.
10. The foreground panel gets the same content as `watch`, drawn by the same code.
11. Against an engine without the `sessions` capability, `status` and `watch` work with the snapshot alone.
12. In the macOS app, the opt-in switch "Start Carrier when the app opens" (off by default) starts Carrier on open under the conditions above.

## Decisions

**The socket client is one small module** in the CLI (connect, read the hello, send one request with its id, read the matching reply, close), used by every command; its replies are typed with the types the engine already exports for them (`src/control/replies.ts`, `src/status/types.ts`), so it cannot drift from the server.

**`start` re-runs the same program.** It spawns the same Node and script with `--config`, detached into its own session with its output going to `<root>/orchestrator/logs/start.log` (replaced at each start, as the app's `app-start.log` is) and `unref`ed, and inherits the caller's environment, so the `PATH` is the user's own. The child takes the existing foreground path; with no terminal that path already writes plain lines, so there is no second way to start the engine. The parent then asks the socket (connect and hello) every quarter of a second for up to 15 seconds, the same limit as the app, and gives up early if the child exited. The instance lock is what refuses a second Carrier.

**Exit codes.** `status`, `watch`, `pause`, `resume`, `check`: 0 on success, 1 when Carrier is not running or does not answer, 2 for a Carrier whose protocol this CLI does not speak. `stop`: 0 also when none runs, since stopping what is stopped has nothing to fail. `start`: 0 when it is running afterwards, including when it already was; 1 otherwise.

**One renderer, a detail provider.** `renderDashboard` takes the control snapshot and a provider of stage history per epic, instead of reading anything itself; the foreground gives it the in-process answer and `watch` the socket's. The refresh rule above lives in a small cache around the provider, keyed by the epic and the fields that invalidate it, so it is the same for both.

**`watch` implements the panel's existing `Controls`** (`poll`, `setPaused`, `open`, `quit`, `logs`) over the socket and passes a label for `q`, so `ui-state` and `interactive` do not change.

**The app's switch** is the user default `engine.startOnOpen`, false when unset. The decision is a pure function of the switch, the monitor's first state, whether Start Carrier is enabled, the fixture flag and whether it already tried this launch; the app calls `StartController.start()` when it says yes.

Testing seams, per story:

- Stories 1 to 5: the end-to-end style of `src/terminal/cli/main.test.ts`, which runs the real process with a fake `agent-forge` and a temporary root, so `start`, `status`, `pause`, `resume`, `check` and `stop` run against a real engine without GitHub or an agent. The socket client is also tested against `startControlServer` with fake controls, as `server.test.ts` does, including a server that answers late, errors, or is not there. `parseCli` in `args.test.ts` covers the command line.
- Stories 6 to 9: `renderDashboard` in `dashboard.test.ts`, the broadest pure seam, with a snapshot and a fake detail provider. It already checks colour is only styling and that no line is wider than the terminal; the new lines are held to the same two rules, with long titles and reasons.
- The refresh rule (story 7): the same seam with a provider that counts its calls across repeated renders of an unchanged and a changed snapshot.
- Story 10: `interactive.test.ts` with a fake output, keys and controls, plus one assertion in `compose.test.ts` that the foreground panel is fed the stage detail.
- Story 4's keys and the `q` difference: `ui-state.test.ts` and `interactive.test.ts`, with `watch`'s `Controls` over a fake client.
- Story 11: the client and `renderDashboard` against a fake engine that does not advertise `sessions`.
- Story 12: the pure function in `CarrierCoreTests`. Its wiring in the app's launch has no automated test, for the same reason the app's spawn has none: it would start the real Carrier.

## Out of scope

Rewriting the engine natively, or bundling Node into the app. The launchd service. `carrier config` and `carrier repos`. Notifications from the engine without the app. A `carrier logs` command. Editing profiles, identities or agents. A way to restart Carrier automatically after a crash or a reboot.
