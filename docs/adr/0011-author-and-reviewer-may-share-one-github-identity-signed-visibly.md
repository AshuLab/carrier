# 0011 - Author and reviewer may share one GitHub identity, signed visibly

- Status: accepted
- Date: 2026-10-25

## Context

Carrier requires the author and the reviewer of a pull request to use different GitHub profiles. The schema rejects the same profile name for both, `carrier doctor` rejects two names that point to the same bot or the same login, and `gh` plus `gh` is not accepted either, so a user needs at least one Agent Forge bot ([the spec](../specs/autonomous-orchestrator.md), [configuration](../configuration.md)). The reason is that the reviewer's comments and approvals should not be the author's own, and GitHub itself does not let the author of a pull request approve it or request changes on it.

Creating a GitHub App is free on a personal account, but installing it on an organization needs an owner. A person who works in repos of an organization where they are not an owner, and whose owner will not approve the App, cannot run Carrier at all. There is no second identity they can get, and a second user or a machine account needs an invitation from the same people. This is the person this decision is for.

Two facts shape what sharing means. Carrier does not launch agents through Agent Forge: it only asks Forge for a token and spawns the harness itself, so the identity block and the per-agent `systemPrompt` that Forge injects when it launches an agent never reach Carrier's agents, in either setup. A `{kind:'gh'}` profile gets no commit identity from Carrier, so commits carry the user's own git name and email.
The engine does not depend on who posted what: it decides from the result file and SQLite ([0001](0001-separate-coordination-from-repo-evaluation.md), [0002](0002-sqlite-authority-labels-mirror.md)), and `reviewDecision` from GitHub is read only for display.

## Decision

The config gains a global choice, `identities`, with the values `separate` (the default, today's behavior) and `shared`. Under `shared`, the schema and `carrier doctor` accept the same GitHub profile for the author and the reviewer, usually the user's `gh` login, and doctor checks that the login works instead of failing on the match. The choice is global because the account and its credentials are the same for every repo; a repo that wants a bot keeps the per-repo override of the identity it already has.

Everything an agent publishes with a shared account ends with a visible signature, `🤖 <Role> [NAME] via Carrier`, where the name is the persona's. That covers review comments and review bodies, the pull request body, replies on threads and a last line of every commit message. The signature is mandatory and the user cannot turn it off. Carrier does not touch the git name or email: they belong to the session of the person using Carrier. The signature applies to an epic whose author and reviewer resolve to the same profile, so a repo that overrides one of them with a bot does not carry it.

The signature is asked for in the prompt and nothing else. Carrier does not verify it, because a comment without it cannot be told from one the user wrote with the same account, and it adds no hook to commits.

What the review and fix stages are told about the pull request being the account's own is not decided here: how solve's `code-post` and `code-resolve` behave in that case is left for when they run under a shared identity.

Each role has a persona, a name and an optional prompt, in both setups. It is the user's way of saying who the agent is, and Carrier adds it to the prompt of the role. The name only appears in the signature under a shared identity.

`carrier init` asks which setup the user wants as the first question of the identity step. For separate identities the flow is today's, with Agent Forge. For a shared one it skips Forge, asks for the persona names, and says plainly before accepting that both roles act with everything the user's `gh` token can do, the reviewer included.

## Alternatives considered

A shared identity per repo, so that a user keeps bots where they can have them. It was dropped because the account and its credentials are the same everywhere, and the per-repo override of the identity already lets a repo use a bot.

A second personal account or a machine user, a GitHub App on the user's own account, or a fork. Each one needs the organization to invite or install something, which is the wall this decision exists to get around; none of them gets a second identity into the repos in question.

A hidden marker of the role in every comment, to tell the author from the reviewer under one login. The visible signature already says the role and the name, the engine never reads who wrote a comment, and the solve skills have their own markers, so a second mechanism was not worth it.

Guaranteeing the signature, with a hook that adds it to every commit or a check of the comments after each stage. The hook only covers commits, since there is no equivalent for the text of GitHub, and the check cannot tell an agent's unsigned comment from the user's. The prompt is the only thing used.

Letting the user turn the signature off. Colleagues in the organization would read the agent's comments as the user's own words, which is the one thing the signature is for.

## Consequences

The author and reviewer of an epic can be the same account, so the rule in the original spec and in the config validation ("author and reviewer with the same profile" is invalid) changes: it holds under `separate` and is lifted under `shared`. The spec, `docs/configuration.md` and the README say so.

Everything the agents publish appears under the user's name in the organization, and only the signature says it was an agent. The signature depends on the agent following the prompt, and nothing detects the day it does not. The first runs are where to check that every kind of publication carries it, and a missing one on commits is the reason to revisit the hook.

Both roles run with the user's own token, whose reach is much wider than a Forge bot's installation token, including the reviewer, which only has to comment. Carrier does not narrow it, and the wizard has to say so.

The reviewer cannot approve or request changes, and GitHub's `reviewDecision` stays empty for these epics. That affects nothing in the engine, which reads the result file, and the person who merges is the one who approves.

Persona is a new part of every role, so the prompt builder grows a section for it, and Agent Forge's own `systemPrompt` is still not used by Carrier: a bot's personality is set in Carrier's config, not in Forge's registry.
