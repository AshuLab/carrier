# Baseline: how the macOS app performs today

Numbers for the performance work on `Carrier.app`, taken once with the instrumentation of #1115, so that each fix can show a before and an after.
It writes no production code.
Every figure is one machine and one run unless it says three; read them as orders of magnitude, not as decimals.

## The answer

- **The pending-update pill costs about 38 points of CPU.**
  With `--fixture-update` the app with its window visible and in the background uses 40.6% CPU, against 2.8% without the pill.
- **Listening for global dictation costs about 40 points of CPU.**
  The app listening in front of another app uses 42.2% CPU and 215 idle wake-ups, against 2.8% and 28 with its window open and nothing else on.
- **The app's memory grows by itself.**
  Idle under `--fixture`, with nobody touching it, the footprint went from 53 MB to 118 MB in one hour, about 1.1 MB a minute, in a straight line.
- **Opening the window is most of the launch.**
  `makeWindow` takes about 186 ms of the 232 ms that `applicationDidFinishLaunching` takes, and the first commit of the run loop comes about 424 ms after it starts.
- **A long dictation history slows the launch.**
  10,000 entries take 84 ms to read (0.1 ms with none) and add about 64 ms to the launch.
- **Work deferred with `main.async` does not help the first frame.**
  It runs before the first commit in all nine launches (about 92 ms before in the fixture run).
- **A chat's feed is rebuilt from every event.**
  One new event in a session of 5,005 costs 5,006 units of work, where 1 is the least.
- **`usage` in a cold chat host takes 10.8 s**, and 0.39 s the second time.
  About 3.4 s of the host's CPU goes to reading the Claude logs.

## How it was measured

- Machine: Mac14,13 (Apple M2 Max), macOS 27.0.
- App: `main` at `0e4952ee` (0.13.1), built with `./build-app.sh` and no version, so "Carrier Dev".
  One event, `main.async after open`, was added to the launch for the last row of the launch table and is not in `main`.
- CPU, idle wake-ups and energy: `macos/scripts/perf-sample.sh`, that is `top` over 30 s of one process, as `cpu`, `idlew` and `power`; the footprint is `footprint`'s.
- Launch: three recordings of 14 s each with `xctrace record --instrument os_signpost --all-processes`, and the intervals of the `launch` category read from the exported table.
  The times are the median of the three; the first commit and `main.async` are measured from the start of `didFinishLaunching`.
- The Mac was in use: another Carrier (the installed one) was running at about 26% CPU while the rest was measured.
- Fixtures: `--fixture` for the app with a fake engine; for the history, `CARRIER_PERF_FIXTURES` wrote 10,000 dictations and a scratch chat host ran next to the app on a throwaway Carrier folder (`--fixture` replaces `CARRIER_HOME`, so it cannot carry them).
  The dictation history was compared with the same folder with the history moved aside.

## The table

| Measure | Scenario | Result |
|---|---|---|
| Idle CPU and wake-ups | `--fixture`, window visible, app in the background | 2.8% CPU, 28 idlew, power 2.9, footprint 51 MB |
| | window minimized | 2.2% CPU, 64 idlew, power 2.3 |
| | window closed, app in the background | 0.2% CPU, 73 idlew, power 0.2 |
| Pending update | `--fixture --fixture-update`, window visible | **40.6% CPU**, 82 idlew, power 40.7 |
| Global dictation | `--fixture --fixture-dictation-at-the-end`, shortcut pressed in TextEdit, listening | **42.2% CPU**, 215 idlew, power 42.4 |
| Footprint over time | `--fixture`, idle, an hour | 53 MB, 56 at 5 min, 75 at 10, 95 at 35, 118 at 60 |
| Feed work | a session of 5,005 events, one new event | 5,006 (the least is 1) |
| Work of the other counters | 5,000 dictations of one day; 2,000 files | 12,502,500 units to group the day; 2,000 icon lookups for 10 icons |
| Snapshot | a snapshot that only moves its clock | it is published (the test says it should not be) |
| `usage` | a chat host just started, a fresh Carrier folder | 10.77 s; 0.39 s the second time |
| Engine socket | `carrier start` with live epics | not measured |

### Launch

All in milliseconds, the median of three launches.

| Interval | Fixture | No history | 10,000 dictations |
|---|---|---|---|
| `didFinishLaunching` | 232 | 252 | 316 |
| `makeWindow` | 186 | 201 | 185 |
| `dictation` (the controller, with its history) | 7 | 17 | 101 |
| `dictation records` | 0.4 | 0.1 | 84 |
| terminal store | 3.9 | 4.1 | 4.4 |
| `main.async` after `open`, from the start | 332 | 337 | 400 |
| first commit, from the start | 424 | 380 | 441 |

"No history" and "10,000 dictations" run against a real chat host, "Fixture" against the fake engine, so the first column is not comparable with the other two.
The updater, the window controller and the model store take 1 ms or less in every run.

## What stands out

- **The update pill and the dictation widget burn CPU for as long as they are on screen.**
  The pill stays until the update is installed.
  The numbers are those of the fixture's pill and widget; Instruments' SwiftUI "View Body" would say which view is behind them and was not run.
- **A window that is closed or minimized has more idle wake-ups than one that is visible.**
  The CPU is lower, 0.2% and 2.2% against 2.8%, but the wake-ups are 73 and 64 against 28.
  With one 30 s sample each, the cause is not known.
- **Memory grows with nobody using the app.**
  The fixture's engine answers its polls with the same data, so the growth is in the app or its polling and not in what it is shown.
  Visiting epics in a cycle was not done: it needs clicks on the sidebar, so this is the idle figure and the least.
- **The installed Carrier, read only, with one active chat session building a Swift package:** the app at 43.4% CPU and 340 MB, and its chat host with 11 processes and 3.3 GB resident, 2.1 GB of it the compiler's.
  That is not the "three idle sessions" that was planned, so it says nothing about the idle cost of a session; the chat host alone, with its Claude process and the tools it started, is about 0.8 GB.

## What was not measured

- **The engine's start with live epics.**
  A real engine takes `solve:epic:ready` epics and runs agents; it needs throwaway repositories, so it stays for the work on the engine's start-up.
- **Which view burns the CPU of the pill and the widget.**
  It needs Instruments' SwiftUI template.
- **Memory after visiting epics.**
  Only idle memory was measured.
- **The cost of the signposts.**
  CPU with and without them was not compared; a signpost is meant to cost next to nothing while nobody records.
- **MetricKit.**
  Not added yet; whether macOS delivers reports to an ad hoc signed app is still to be found.

## To repeat it

```sh
cd macos
./build-app.sh
(trap '' PIPE; exec ./Carrier.app/Contents/MacOS/Carrier --fixture) &
./scripts/perf-sample.sh $! "" 30
```

The recipe for the signposts and the large fixtures is in [`macos/README.md`](../../macos/README.md#measuring-performance).
The `usage` run is `node --cpu-prof src/terminal/cli/main.ts chat-host` and `time node src/terminal/cli/main.ts usage`, both with `CARRIER_HOME` on a scratch folder under `/tmp`.
