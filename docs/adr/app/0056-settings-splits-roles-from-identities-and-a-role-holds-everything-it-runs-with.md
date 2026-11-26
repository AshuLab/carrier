# 0056 - Settings splits roles from identities, and a role holds everything it runs with

- Status: proposed
- Date: 2026-11-26

## Context

The engine runs up to four reviewers and a lead ([0048](../review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md)), and the Agents page of Settings has room for three fixed roles.
Making room for more raised a question the page had blurred: an epic's role is made of who signs on GitHub (a profile), what runs (an account, a model, an effort, failover steps), who speaks (a persona) and what it runs in each stage (skills).
Several reviewers often share the same bot, or the same model, and a page that lists six roles can either repeat those choices in each role or name them once and let roles point to them.
`engine.json` declares each role inline: `agents.<role>` holds its profile, provider, model, effort, persona, skills and, for an extra reviewer, its failover steps.

## Decision

Settings has a Roles page and an Identities page, both in the Carrier group, and Providers stays in the App group.
A role holds everything it runs with: its identity, picked from the profiles; its account and model, picked from the accounts; its effort, persona, failover steps and skills.
Identities lists the GitHub profiles with the roles that sign as each one, and holds nothing a role runs with.
`engine.json` keeps the inline roles: nothing new is named in it, and the app writes the role it changed.
The page called Agents is renamed Roles, in its words and in the code named after it, as the glossary already calls them.

## Alternatives considered

A catalog of agents, each an identity, a model and a persona under a name that roles point to, lost: it glued who signs to what runs, and it needed a new shape of `engine.json`, its schema, the doctor and `carrier init`.
Named model presets on a Models page lost: changing a model once for every role that runs it is the one gain, for the same change of the file's shape, and nobody asked for that reuse.
The model as part of the bot lost: one picker per role, but running another model needs another bot, and the person's own login could run only one model.
Keeping the name Agents lost, because the glossary says role and keeps "agent" for the AI that runs one.

## Consequences

Two reviewers on the same model repeat it, and changing that model means changing each of them; named presets can be added later beside the inline roles if that repetition starts to hurt.
Identities becomes the place to see who signs where, and Create a bot… moves there.
The rename touches the page's copy keys, types, folder and search index, and a Settings window remembered on the old page opens on the default one.
