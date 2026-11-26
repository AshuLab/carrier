# 0012 - Sessions and epics are two separate worlds in the app

- Status: accepted
- Date: 2026-10-27

## Context

The app is going to let the person talk to an agent of their choice, and that conversation usually ends by publishing the tickets that Carrier then implements on its own. That pulls toward linking the two: one list where a conversation turns into an epic, or a chat tab inside the epic. But an epic runs unattended, for hours, in the engine's shared clone, and outlives whatever was said before it started, while a conversation is disposable once it has done its job.

## Decision

A user session and an epic are never attached. The sidebar has a Sessions world (sessions grouped by workspace, archivable) and a Carrier world (the Carrier card and its epics), visibly apart, with Home as a plain index and a page for each world (the Sessions home and the Carrier home). No session id is stored on an epic and no epic id on a session. The only thing between them is GitHub: the issues a session publishes are picked up by the engine by label, as it does for any epic.

## Alternatives considered

One list of work items whose row carries a conversation on into build and review. It tells the whole story in one place, but it gives the epic the lifecycle of a conversation and needs a link in the data model that both sides then depend on.

A chat tab inside the epic. Good for steering a stopped epic, weak as a general conversation, and it ties the conversation's life to the epic's.

A timeline across both worlds. Good for coming back after a break, poor to act from.

## Consequences

Two lists to scan instead of one, and urgency shows in two places (an orange row in Sessions, the Carrier card for the automation); there is no inbox that mixes them, and the Carrier card is the only place that carries global engine status. The hand-off between a session and an epic is visible only on GitHub. Sessions can be archived or deleted without touching any epic, and the engine needs no change. A link from a session to what it published can be added later as a courtesy; undoing a link that both sides depend on would be a migration, which is why the data model starts without one.
