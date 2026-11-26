# 0057 - An extra reviewer is an entry of a map with a key, a name and a type

- Status: proposed; amends [0048](0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md) (the shape of `extraReviewers` and the names of the places in a round)
- Date: 2026-11-26

## Context

ADR 0048 made the extra reviewers a list, `agents.extraReviewers`, up to three, and the engine names each by its position: `reviewer-2` to `reviewer-4`.
The list has no name for an entry, so a person who wants a security reviewer and a usability reviewer cannot say which is which: the app can only call them Reviewer 2 and Reviewer 3, and the only name a reviewer has is its persona's, which is optional and is what it signs with.
Removing the first entry makes the second one `reviewer-2`, so anything that addresses a reviewer by its place, a request from the app included, can reach the wrong one.
The app needs requests to add, change and remove a reviewer and to set a repo's own list, and those requests need something steadier than a position to point at.

## Decision

`agents.extraReviewers` is a map, at most three entries, from a key to the entry, and a repo's `agents.extraReviewers` is a map of the same shape that replaces the whole map.
The key is a lowercase slug that starts with a letter, so no key reads as a number and the map keeps the order of the file, and it is not one of the words the file already uses for a role.
The entry keeps every field the list's entries have (profile, provider, model, effort, persona, skills, failover) and adds two, both required in the schema: `name`, the text the app shows, and `type`, a slug that says what the reviewer looks at.
The key and the name are each unique among the extra reviewers of the map; the type is open, any slug, and several reviewers can share one.
The type is only a label: the engine runs nothing different for it.

The signature of an extra reviewer is `🤖 Reviewer [NAME] via Carrier`, with the persona's name when it has one and the entry's name when it does not.
The engine's requests address a reviewer by its key.

The key is the reviewer's identity wherever the engine names it: the review slot of a stored execution, the round and its retries, the prefix of a blocker's id, the folder of its checkout, the roles `carrier restart` asks about, the epic's status and the doctor's lines.
`reviewer-2` to `reviewer-4` do not exist any more; the slots `reviewer` and `lead` stay, and no key is one of them or `author`.
The epic's saved configuration is the engine's own record and keeps the resolved reviewers in the order of the map, each carrying its key, name and type, and the app shows a reviewer by its name, read from there.

The list is not read any more.
A file whose `extraReviewers` is a list is refused when it loads, with a message that names the shape the file needs, and nothing migrates it.
Nothing migrates what was recorded either: the executions stored with `reviewer-2` to `reviewer-4` keep the text they have and the engine does not read it as a reviewer, and an epic that was running with extra reviewers when this lands cannot be resumed.

## Alternatives considered

The list with a unique `name` on each entry lost, because it keeps the position as the way to address a reviewer in the file, and removing one still renumbers the rest; it would have kept every file of 0.19.0 valid, and the person chose to give that up.
A map whose key is the type lost, because it allows one reviewer of each type and a person who wants two security reviewers, one for the API and one for the front, would have to invent a type for the second.
A map whose key is the name lost, because a name is text a person edits, and renaming a reviewer would then change the key that requests, files and a repo's override point at; the key stays put while the name changes.
One `setExtraReviewers` request that replaces the whole map lost for the global map, because the app would have to send back the skills, the failover steps and any key it does not edit, or the engine would lose them; a request for each reviewer changes only what it names.
Keeping `reviewer-2` to `reviewer-4` as the engine's own place, derived from the position of the entry, lost, because it gives one reviewer two names, its key in the file and in the requests and its place in the executions, the blockers and the checkouts, and anyone reading one has to map it to the other; it would have spared the stored executions a rename, which the person gave up with the migration.

## Consequences

A file of 0.19.0 or 0.20.0 with extra reviewers stops loading until its list is rewritten as a map; this is accepted, and the refusal says what to write.
The engine's storage, rounds, retries, blockers and checkouts, `carrier restart`, the snapshot and the doctor name a reviewer by its key, the wizard of `carrier init` asks each extra reviewer's name and takes it by flags that name it, and the app's roles page, its Watching screens and its goldens have to speak the map; the epics that are building on the list adapt to this one.
A reviewer has a name the person chooses and a type that can group them later, and skills that each reviewer can have of its own become a field of the entry rather than a shape of the file.
The type carries no behaviour, so it costs nothing to add one, and a later epic can give a type its defaults without changing the file.
