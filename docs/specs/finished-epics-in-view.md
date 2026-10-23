# Finished epics in view

Status: spec

## Problem

When an epic's final PR is merged, or the epic is closed without merging, it disappears from Carrier. The terminal panel and the macOS app list only queued, running, needs-human and ready-for-test epics (the snapshot's `done` is ready-for-test only, five at most), so the moment Diego merges, the epic he was just testing is gone from the screen. The cycle never closes in view, and an epic that fell (final PR closed, issue closed) vanishes the same way, with its reason out of sight. Nothing is lost underneath: the epic's row stays in SQLite forever, the retention purge deletes only logs, sessions and events after 30 days, and the control socket's `epic` and `sessions` requests already answer for a merged epic. It is a missing view, not missing data. Diego is the only reader.

## Solution

Epics that ended are shown for a window after they end, in two new groups: Done (merged) and Cancelled (closed without merge, with the reason Carrier stored). Ready for test stays its own group, because it still waits for a person and Done does not; mixing them would erase that signal.

The snapshot gains one additive field, `finished`: the merged and cancelled epics whose `finishedAt` falls inside the window, newest first, each with repo, issue, title, labels, PR number, `finishedAt`, its status (`merged` or `cancelled`), the stored cancel reason when cancelled, and the last execution id. The existing `done` field keeps its name and meaning (ready-for-test, five at most). The protocol does not change: an older app ignores the new field, and a newer app reading an engine that does not send it treats it as empty. The engine sends every epic in the window, with no row cap; the window is the bound.

The window is `finishedWindowDays`, a whole number of days from 1 to 30, 15 by default, counted from `finishedAt`. For a merged or cancelled epic `finishedAt` is set at the moment the engine sees the end, so the window starts at most one poll after the merge. It is a top-level engine value like `pollIntervalMinutes`, added to the config schema and to `docs/configuration.md`, and it is global, not per repo. The ceiling of 30 is the retention purge: past 30 days the logs, sessions and events of an epic are gone, so a listing would open an empty epic. After the window the epic is reachable only by its issue and PR on GitHub; its row stays in SQLite.

In the terminal panel there are two new sections, DONE and CANCELLED, below READY FOR TEST. Each shows the ten most recent epics of its kind and a "+N more" line when there are more; the ten is not configurable, because the fixed height of a terminal is the limit and a second option for it earns nothing. A Done row reads like a Ready for test row (repo, issue, PR, how long ago, title); a Cancelled row adds its reason. The plain output of a non-interactive terminal lists the same rows. The "Idle" message depends only on live work: finished epics do not suppress it.

In the macOS app Done and Cancelled are sidebar groups like the others. Every sidebar group can be collapsed, and Done and Cancelled start collapsed. What the user opened or closed is kept while the app runs and across snapshot refreshes, and is not remembered across launches. There is no cap on rows. Selecting a finished epic opens the epic view it opens for any other, fed by the `epic` and `sessions` requests that already answer for a merged epic. The Settings Behavior tab gets `finishedWindowDays` as one more value, with the same validation as the schema.

Two cancel reasons are written in Spanish today (`cerrada antes de iniciar` and `ready removido`, in the engine's start path). They become visible in a Cancelled row, and the repo's rule is that all content is English, so they are rewritten in English. Rows already stored keep their old text.

What was considered and lost: one group holding ready-for-test and merged together (loses the signal that something is waiting for a person); merged and cancelled in one group with a marker (a fallen epic would sit among delivered ones, and Diego asked for it apart); reusing and widening `done` (the name already means ready-for-test in the snapshot, the CLI and the app's model); a count-based limit instead of a window (a busy week would push out an epic that ended yesterday); a separate history request and view (it answers "what was done in this repo", which nobody asked for, and GitHub already is that record); showing nothing and relying on GitHub (what Diego wants is the cycle closed on the screen he already watches); a per-repo window (Diego is the only reader and only the agents are per-repo today).

## Scope

1. The snapshot carries `finished`: merged and cancelled epics whose `finishedAt` is inside the window, newest first, with the fields above and the cancel reason on cancelled ones. Epics in any other status, and finished ones older than the window, are not in it.
2. The window is read from the config: `finishedWindowDays` defaults to 15, accepts whole numbers from 1 to 30 and refuses 0, 31, a fraction and a non-number with an error that names the field. It is documented in `docs/configuration.md`.
3. The macOS app decodes a snapshot with `finished` and one without it (an older engine), the latter as an empty list.
4. The terminal panel shows DONE and CANCELLED sections under READY FOR TEST with at most ten rows each and a "+N more" line, shows the reason on cancelled rows, shows nothing for an empty section, and keeps the Idle message tied to live work only. Keys that act on a row (open the PR, the logs) work on finished rows. The plain output lists them.
5. The macOS sidebar shows Done and Cancelled groups after Ready for test; every group collapses and expands; Done and Cancelled start collapsed; a collapsed or expanded state survives snapshot refreshes.
6. Selecting a finished epic in the app opens its epic view from the existing `epic` and `sessions` replies, with nothing live on it (no running lane, no activity).
7. The Settings Behavior tab shows, validates and saves `finishedWindowDays`.
8. The two Spanish cancel reasons are English.

## Decisions

The config value, in the schema and in `defaults` (`src/config/load.ts`):

```ts
finishedWindowDays: z.int().min(1).max(30),   // schema.ts, next to pollIntervalMinutes
finishedWindowDays: 15,                       // load.ts defaults
```

`z.int()` already refuses fractions and non-numbers, so `0`, `31`, `7.5` and `"7"` are all errors.

The window test is `finishedAt >= now - days * 86_400_000` on the injected clock; `buildSnapshot` receives the window as an input like `maxReviews` and reads `merged` and `cancelled` rows ordered by `finishedAt` descending. No new table, no migration: the data is the epics row.

The `finished` field is additive and is not a rename of `done`. A single field carries both statuses, and each group is the client filtering by `status`, so the engine runs one query.

The snapshot is asked for every second and now carries up to a window of rows. The ceiling is acceptable for one reader (tens of small rows); if it ever is not, the field moves to a request behind a capability, which the `hello` already supports.

Retention does not change, and no ADR is written: the change is additive and reversible.

Testing seams, per story:

- Stories 1 and 2: `src/status/snapshot.test.ts` over a temp SQLite with the injected `now` (inside, at the edge and outside the window; merged, cancelled and other statuses; order; reason), and `src/config/load.test.ts` for the default and the refused values. `snapshot-contract.test.ts` regenerates the shared fixture `macos/Tests/Fixtures/snapshot.json` with a finished epic of each kind.
- Story 3: `macos/Tests/CarrierCoreTests/SnapshotTests.swift` decodes that fixture, and a copy without `finished`.
- Story 4: `src/terminal/dashboard/dashboard.test.ts` and `plain.test.ts` render a snapshot (eleven merged, cancelled with reason, none finished, none live and some finished); `ui-state.test.ts` for the keys on a finished row.
- Story 5: `macos/Tests/CarrierCoreTests/SidebarTests.swift`, the pure grouping model (group order, collapsed by default, state kept across a new snapshot). The window itself has no automated test; Diego checks the collapse in light and dark, narrow and wide.
- Story 6: a case for a merged epic in the existing control `epic` tests (the reply has no live data), plus `EpicViewTests.swift` for a finished epic's view. No test for the click itself.
- Story 7: `EngineConfigTests.swift` and `BehaviorSaveTests.swift` (read, refuse out of range, save).
- Story 8: `src/orchestration/engine.test.ts`, which already covers the cancel paths; the assertions change to the English text.

## Out of scope

A history view with search, filters or pagination. Reactivating, re-running or acting on a finished epic from the panel. Changing retention (the 30-day purge stays as it is). Counting finished epics in the menu bar icon or in notifications. A configurable row cap in the terminal panel. Epics in `repo_removed`, which keep their own state and are not finished.
