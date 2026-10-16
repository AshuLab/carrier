# 0002 - SQLite is the authority for state, labels are its mirror

- Status: accepted
- Date: 2026-10-15

## Context

The `solve:epic:ready` label is the entry signal, and Diego wants to see each epic's state on GitHub. But Carrier is interrupted with `Ctrl+C`, can crash between publishing something to GitHub and saving it, and GitHub can be down or rate-limit requests. An execution also needs to store session, round, reviewed SHA and history, which labels cannot hold.

## Decision

SQLite is the source of truth for each execution. The `solve:epic:running`, `ready-for-test` and `needs-human` labels are its visible mirror on GitHub and are reconciled at startup and after a failure. `solve:epic:ready` is enough to queue a new epic, but an already registered execution is resumed from SQLite even if the issue no longer has that label. The caller result and the state transition are saved in a single transaction and their import is idempotent.

## Alternatives considered

Using labels as the only state, with no persistence of its own. It was rejected because it cannot tell an interrupted execution from a stopped one, does not store sessions or rounds, depends on GitHub responding, and anyone can edit a label.

Using only SQLite, with no state labels. It was rejected because Diego would lose visibility from GitHub and because `ready` is already part of the contract with Solve.

## Consequences

Writing in two places requires reconciliation logic and recovery tests for each cut-off point between GitHub and SQLite, in particular an incomplete JSON or a result that was published but not imported. A label changed by hand does not alter a running execution; only closing the issue or the PR and merging the final PR have an effect, according to the brief's rules.
