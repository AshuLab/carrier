# 0043 - Labels are named by who writes them, and every one is configurable

- Status: accepted
- Date: 2026-11-22

## Context

Carrier reads and writes labels on an epic's issue: `solve:epic` marks it, `solve:epic:ready` queues it, and `solve:epic:running`, `solve:epic:ready-for-test` and `solve:epic:needs-human` mirror its status.
The five names were constants spread over six places in the engine, the GitHub client, the doctor and the panel, so nobody could use a vocabulary of their own, and two Carriers watching one repo could not be told apart.
All five shared the `solve:epic:` prefix although two are written by Solve and three by Carrier, so the name said nothing about who owns a label or who may remove it.
Solve's own documentation says it sets `solve:epic` and `solve:epic:ready` and that the orchestrator sets the other three; its skills do not read those three (checked against solve 0.30.0).
The person also wants to see on GitHub which stage an epic is in and why it stopped, which needs labels that do not exist today.

## Decision

We name every label by role in an `engine.json` block, `labels`, and the engine reads the names through its settings, so a reload applies them.
The roles are `epic`, `ready`, `running`, `readyForTest` and `needsHuman`, plus two optional groups, `stages` (`ship`, `review`, `fix` and `lead`) and `reasons` (one per kind of stop).
No two names may be the same label, compared without case because GitHub does, and the config is refused naming the second one.
A name is one line, at most 50 characters and no comma, because a comma splits the GitHub query.

The defaults follow who writes the label.
What Solve writes keeps `solve:*`: `solve:epic` and `solve:epic:ready`.
What Carrier writes is `carrier:*`: `carrier:status:running`, `carrier:status:ready-for-test` and `carrier:status:needs-human`, and, off until named, `carrier:stage:building`, `carrier:stage:reviewing`, `carrier:stage:fixing-review`, `carrier:stage:lead-reviewing` and `carrier:reason:<kind>`.
A stage label sits beside `running`, and a reason label beside `needs-human`.
The stage and reason groups are off by default because each stage label is one more write to GitHub at every stage change.

The new defaults ship with no migration and no cleanup: Carrier removes only the labels it names now, so an old name stays on the issues that have it.

## Alternatives considered

Keep `solve:epic:*` for all five and only make them configurable lost, because the namespace keeps lying about the writer and the person cannot tell what Solve may touch from what Carrier owns.
Make only `ready` configurable lost, because it leaves a mixed vocabulary on the issue and the same hard-coding for the other four.
One `labelPrefix` setting lost, because Solve's two labels do not follow it and a person's own names would not fit a single prefix.
Move Solve's two to `carrier:*` as well lost, because Solve puts `solve:epic:ready` at its hand-off, so the epic would stop queueing without a sound until both sides were configured.
Stage and reason labels on by default lost, because it changes what Carrier writes on every repo for something not everyone wants.

## Consequences

An epic in flight when Carrier is updated keeps the old names on its issue, because Carrier only removes the names it has now, and a board or an automation keyed on the old names stops working.
Solve's README names the old three as the orchestrator's, so that paragraph is out of date until Solve changes it; nothing in Solve breaks.
`carrier doctor` has to check the labels it can name (`epic`, `ready`) in each repo and tell the person to create one that is not a default, because Solve creates only its own.
The macOS app has to carry the same block (`EngineConfig.swift`), and the texts that name `solve:epic:ready` have to take it from the snapshot, which carries `labels`.
A reload that renames a label leaves the old name on the issues that already have it.
