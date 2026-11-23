# 0044 - Recover continues an epic from its real state, and no command sets one

- Status: accepted
- Date: 2026-11-22

## Context

An epic ended up stuck after a quota error, in a state no supported action could move.
The person had to run an external agent to edit SQLite by hand so that Carrier would take the epic again.
The exact state it was in is not known, and why it got there is open (the quota texts the harnesses recognize are a short fixed list per CLI).

What exists today does not reach that case.
`resumeEpic` (the app's Resume, `carrier restart`) refuses unless the epic is in needs-human, and always starts again from ship with the rounds reset.
The engine's recovery runs only when it starts, and it reads the last execution and GitHub to continue each running epic from where it was.
`carrier stop` stops the whole engine, with every agent of every epic.

## Decision

We add a per-epic request, `recover`, that makes the engine do for one running epic what it does at start: read its last execution and GitHub, and continue from the real state.
It is for an epic in `running` whose agent is not alive.
It refuses when an execution of that epic is really alive, so two agents never act on one workspace, and when the epic is launching or retrying, which the engine already tracks.
Epics in needs-human keep going through Resume.

No request sets an epic's status, stage or round to a value the caller chooses.
If `recover` cannot move a real case, that case says which verb is missing, and we add that verb.

The CLI and the app use the same request, through the control socket, as for every per-epic request.

## Alternatives considered

A command that sets the state the person picks lost, because it lets a person leave SQLite in combinations the engine never produces, which is what the manual edit did, now with a button and no review.
Restarting the engine as the only answer lost, because it interrupts every other epic's agents to fix one.
A label that asks for it lost as the first channel, because the poll sees it up to five minutes later and anyone who can label issues in the repo could start agents that spend credits.
Letting Resume accept running epics lost, because it restarts from ship and resets the rounds, which is not what an epic with a cut agent needs.

## Consequences

The engine's recovery of the whole engine (`recover()`) is written for a cold start and must not run on a live one, because a launch in flight (stage claimed, no execution yet) looks like a cut one.
Recovering one epic (`recoverEpic`) already runs on a live engine for the epics a reload brings back, through `restore()`, and it checks `launching` for that reason.
The new request goes through the same per-epic path and the same guards as the launches (`launching`, `retrying`, the epic's epoch), and it needs its own tests for each of them.
A person with an unexplained stuck epic gets a safe first move that cannot invent a state.
The cause of the hang that started this is not solved by it, and stays an open question of the spec.
