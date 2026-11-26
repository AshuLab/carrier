# 0057 - An extra reviewer is an entry of a map with a key, a name and a type

- Status: proposed; amends [0048](0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md) (the shape of `extraReviewers`)
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

The place a reviewer takes in a round, `reviewer-2` to `reviewer-4`, stays as the engine's own: it is the position of the entry in the map when the epic starts, kept in the epic's saved configuration, so the stored executions, the stage strip and the prefix of a blocker's id do not change.
The app shows a reviewer by its name, read from the saved configuration of the epic.

The list is not read any more.
A file whose `extraReviewers` is a list is refused when it loads, with a message that names the shape the file needs, and nothing migrates it.
The epic's saved configuration is the engine's own record and stays an ordered list of the resolved reviewers, each now carrying its key, name and type; one saved before has none of them, and the app shows its reviewers as Reviewer 2 to Reviewer 4.

## Alternatives considered

The list with a unique `name` on each entry lost, because it keeps the position as the way to address a reviewer in the file, and removing one still renumbers the rest; it would have kept every file of 0.19.0 valid, and the person chose to give that up.
A map whose key is the type lost, because it allows one reviewer of each type and a person who wants two security reviewers, one for the API and one for the front, would have to invent a type for the second.
A map whose key is the name lost, because a name is text a person edits, and renaming a reviewer would then change the key that requests, files and a repo's override point at; the key stays put while the name changes.
One `setExtraReviewers` request that replaces the whole map lost for the global map, because the app would have to send back the skills, the failover steps and any key it does not edit, or the engine would lose them; a request for each reviewer changes only what it names.
Making the key the engine's own place, replacing `reviewer-2` to `reviewer-4` in the executions, lost because it renames what the database already stores for no gain: the person never sees the place.

## Consequences

A file of 0.19.0 or 0.20.0 with extra reviewers stops loading until its list is rewritten as a map; this is accepted, and the refusal says what to write.
The wizard of `carrier init`, the engine's snapshot, the app's roles page and its Watching screens, and the goldens of the app have to speak the map, and the epics that are building on the list adapt to this one.
A reviewer has a name the person chooses and a type that can group them later, and skills that each reviewer can have of its own become a field of the entry rather than a shape of the file.
The type carries no behaviour, so it costs nothing to add one, and a later epic can give a type its defaults without changing the file.
