# 0021 - An epic starts on its three roles, and a role's failover chain names a provider and a model

- Status: accepted
- Date: 2026-11-11

## Context

[0014](0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md) made two things at once. A reserved epic waits, up to `limits.optionChoiceSeconds` (60 by default), for a person to choose the agent option of each of its roles when two or more are declared, over the terminal panel or the control socket, and picks the defaults when nobody answers. And a `failover` block, off by default, moves a role to the next option of a list when its login runs out. The wait was the manual answer to a login running out of credits, and failover the automatic one.

Carrier's runs are unattended: nobody is at the keyboard when an epic is reserved. With two or more accounts, which the app's detection of the installed CLIs now makes common ([0020](0020-accounts-live-in-a-file-both-processes-read.md)), every epic holds its slot for the whole wait and then starts on the defaults it would have started on anyway. Failover already covers the case the wait was made for.

The failover list names accounts only, so the model a role moves to comes from the account's default or the harness's, which a person cannot say. A person describing what should happen when the author runs out of tokens says where it goes and on which model. The config also asks for `identities`, separate or shared, which the engine can already tell from the roles: it computes `sharedIdentity` for every repo from whether the author and the reviewer resolve to the same account. And `effort`, how hard the model thinks, is a setting of the three CLIs that the engine never passes.

Nobody but the author has data in the old shapes, so nothing is migrated.

## Decision

An epic starts at once on the three roles of the config. The wait is removed with `limits.optionChoiceSeconds`, the epics' `choiceDeadline`, the choice in the terminal panel and in `carrier watch`, the control socket's `chooseOptions` and its `agentOptions` capability, and the `enabled` key that [0020](0020-accounts-live-in-a-file-both-processes-read.md) gives an account to keep detection from triggering the wait. What `carrier restart` asks of a stopped epic stays, with no timer, and offers every declared account. The epic still records the account each role ran on, because resuming a session and moving a role on failover both need it.

A role has an `effort`: not set, or one of `low`, `medium`, `high`, `xhigh` and `max`, in the global role and in a repo's override of it. The engine passes it as `--effort` to Claude and Antigravity and as `-c model_reasoning_effort` to Codex. Permissions stay what they are, fixed to the unattended mode of each CLI, and are not a setting.

Failover is a list of steps for each role, and a step names a provider, an account of `providers.json`, and optionally a model. A role with a non-empty list has failover on and an empty or missing one does not, so there is no global switch and no default list. The triggers, `usage_limit`, `rate_limit` and `service_down`, stay as they are and are not shown anywhere. A step without a model uses the account's, then the harness's, as the options did.

The `identities` key goes. An epic is shared when its author and reviewer resolve to the same account, which is how [0011](0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md) already treats it once it knows, and the rule that the two must differ is dropped, because choosing the same identity twice is the choice. The app says so when it happens, as the signature of each agent will say it.

`orchestratorProfile`, who moves the labels and reads the repos, becomes optional and is the author's profile when it is missing. `carrier init` still sets it, and the app does not show it.

A config with the old `failover`, with `identities` or with `limits.optionChoiceSeconds` is refused with a message that says what took its place.

## Alternatives considered

Keeping the wait and the accounts' `enabled` key. It leaves a manual choice that is never made and a key whose only job is to avoid its cost, and the page that sets it is one more thing for a person to learn.

Shortening the wait to a few seconds. Every epic is still delayed, for a question nobody is there to answer.

Letting a role's failover offer the epic's choice, so the person picks among the role's own chain. It keeps the interaction and gives it a better list, but the interaction is what is not needed.

Keeping the failover as names of accounts, with the model coming from each account's default. It is the least change, and it makes the model of a step a property of the account, which a person cannot set from the page that describes the role.

Keeping `identities` and only hiding it, with the app writing it from the roles. Two sources for one fact can drift, and the engine already derives it.

## Consequences

An epic no longer waits, however many accounts there are, and detection can write accounts freely. A person who wants a particular provider for one epic changes the role's, or restarts it after it stops.

The code and the documentation that mention the choice, `optionChoiceSeconds`, `enabled`, `identities` and the old failover change with this: the engine's reservation and its columns, the control socket and its capability list, the terminal panel, the wizard's questions, the configuration guide and the specs of ADR 0014. A migration drops the epics' `choiceDeadline` column.

Choosing the same identity for the author and the reviewer is no longer refused by the config. The doctor and the page still say that the signature will show it, and the safeguard moves from a validation to a visible choice.

A failover that moves to a model the person never ran an epic on is a decision the person made on the page, with the model named, and no longer a default they may not know.

The orchestrator may be unable to read a repo of another owner when the author's bot is not installed there. Until a page offers the orchestrator's profile, the person sets it in the file, and the Repos page says that Carrier cannot read the repo.
