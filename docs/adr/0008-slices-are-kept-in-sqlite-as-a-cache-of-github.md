# 0008 - Slices are kept in SQLite as a cache of GitHub, not as authority

- Status: proposed
- Date: 2026-10-21

## Context

The first version of the app shows an epic's slice progress as two numbers, closed out of total, read from GitHub on every poll and kept in memory only ([the macOS app spec](../specs/macos-app.md)). The new window shows the slices themselves: each one's title, whether it is merged, being worked or waiting, what it waits for, its pull request and when it closed, in a list and a ring. It shows them for an epic that has finished too, and after the engine restarts, when the in-memory list is gone. The engine does not otherwise know the slices exist: Solve's `ship` works them inside one agent execution, and the engine reads only the count. GitHub is the real source, and SQLite is the authority for what Carrier decides ([0002](0002-sqlite-authority-labels-mirror.md)).

## Decision

On every poll, for each running epic, the engine reads its slices with one query (title, state, assignee, what blocks it, pull request number, closing time) and writes them to a table, `epic_slices`, replacing the epic's rows. A finished epic keeps the last list it had. The app reads them through the `epic` request; the counts stay in the snapshot as today.

The table is a cache of GitHub. The engine never uses it to decide anything: not to launch, to stop or to judge an epic. It exists only so the app can show what GitHub said the last time Carrier asked, and the app shows how old that is.

The same table pattern keeps the final pull request's review threads (`epic_review_threads`), read with the pull request block, replaced on each read and served in the `epic` reply, under the same rules.

## Alternatives considered

Keep slices in memory, as the spec said. It costs nothing and stores nothing, but a finished epic or a restart would show only the count, and the design's slice tab would be empty exactly when a person comes back to look at what happened.

The app asks GitHub for the slices itself. It would always be fresh, but the app has no token and ADR 0005 says it only talks to the socket; giving it one spreads a credential.

The engine queries GitHub each time the app asks. No table, but a request per click, slow and rate-limited, and nothing to show when GitHub is unreachable.

## Consequences

One more table and about two points of GitHub's GraphQL budget per running epic per poll, well under the limit for a handful of epics. The list can be as old as the poll interval, and for a finished epic it is frozen at its last read, which is the right thing to show. Because the table is a cache and not an authority, it can be rebuilt or dropped at no cost, and a wrong row can never change what Carrier does. This reverses the spec's line that slice progress is not stored in SQLite, and it changes the glossary entry for slice progress.
