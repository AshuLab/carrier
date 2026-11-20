# The orchestrator's profile in init and in the failure that needs it

Status: implemented (unreleased)

Source: AshuLab/carrier#896

## Problem

`orchestratorProfile` is the GitHub identity Carrier uses to read issues and PRs and to change labels.
The issue arrived saying the macOS app has no field for it and that no page can fix a repo the author's bot cannot read.
That half is already built: Settings → Engine → GitHub identity has "Carrier acts on GitHub as" (#930, [settings-carrier](../macos/settings-carrier.md)), and [configuration](../configuration.md) says so.

What still hurts is on the terminal and in the way to the field.
`carrier init` never asks for the orchestrator: `buildConfig` writes `orchestratorProfile` equal to the author's profile without a word, so a person whose orchestrator is another bot (the case that found this: `artanis-agent` reading, `gh` authoring) sets it by hand, and the key it wrote pins the orchestrator to the first author, so changing the author later in the app does not move it.
And when the Repos page's "Carrier can read it" check fails with a 404, the doctor's fix says only "install the App on the owner".
It never says the other way out, which is to have Carrier read as another identity, so a person who does not already know the field is in Engine does not find it.

It is felt by whoever sets Carrier up with an orchestrator that is not the author, and by whoever reads a failed read check on a repo of another owner.

We know it is solved when `carrier init` asks who Carrier reads GitHub as before it asks for the author and the reviewer, and when the read check's fix names the field.

## Direction

`carrier init` asks the orchestrator's identity first, before the author and the reviewer, with the same question and the same list it already uses for the roles (the Agent Forge bots and the person's own `gh` login, and "Add a new Agent Forge bot…").
The answer is written as `orchestratorProfile`, always explicit; the old line that copied the author's profile in silently goes.
With a single identity available the question answers itself and says so, as the roles' do.
With `--yes` or the profile flags there is no one to ask, and the orchestrator is the author's identity as today, so no scripted init changes.
An edit of an existing config starts from the file's own `orchestratorProfile`.

The doctor's fix for a failed read (`fixes.read`, shown by the CLI and by the Repos page alike) gains the second way out: Carrier can read as another identity, `orchestratorProfile`, which Settings → Engine → GitHub identity sets.
Words only; the app keeps no button that jumps to Engine.

What was weighed and cut: the field on the Agents page (#778 cut it on purpose and Engine already holds it); showing it only when the default cannot read (the app would need to know that state and has no place to show it, and the pointer in the failure covers it); an advanced step at the end of init (it is asked once and the answer shapes the rest, so it comes first); a `--orchestrator-profile` flag (nobody asked for it, and `--yes` keeps the author's identity); leaving init as it is and only pointing from the doctor (the person who needs it would still hit the failure first).

It is a direct-lane change, with no epic or tickets: init's flow, the wizard's tests and the doctor's text, plus the docs and a CHANGELOG line.

## Out of scope

Anything in the macOS app: the Engine row stays as it is, and no button or link goes on the Repos page.
A per-repo orchestrator identity.
A flag for the orchestrator in `carrier init`.
Changing what the doctor checks.

## Open questions

None that need research.
