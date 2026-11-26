# Extra reviewers with a name, edited through the engine

Status: spec

## Problem

Since 0.19.0 an epic runs up to three extra reviewers beside the Reviewer, set in `engine.json` as `agents.extraReviewers`, and the only way to add, change or remove one is to edit the file by hand.
The macOS app cannot do it for the person, because the engine has no request that writes an extra reviewer or a repo's own list of them: its requests (`editRole`, `editPersona`, `editFailover`, `setLeadReviewer`, `editRepoRole`) accept only the Author, the Reviewer and the Lead reviewer.
The epic "Roles and identities in Settings" (#1513) builds the screens that need them, and two of its slices, #1527 (add, edit and remove from Roles) and #1528 (a repo's own list from Watching), are stopped until they exist.

The shape of the setting also gets in the way.
The extra reviewers are a list with no name per entry, so the engine and the app call them by their place, `reviewer-2` to `reviewer-4`, and the only name a reviewer has is its persona's, which is optional and is what it signs with.
A person who wants a security reviewer and a usability reviewer cannot say which is which, and removing the first one makes the second one `reviewer-2`, so a request that points at a place can reach the wrong reviewer.

It is felt by whoever sets up the reviewers of their epics, and by the app, which has to point at one of them.
We know it is solved when the app can add, change and remove an extra reviewer and set a repo's list through the engine, each reviewer has a name the person chose, and a request reaches the reviewer it names and no other.

## Solution

The extra reviewers become a map and not a list ([0057](../adr/review/0057-an-extra-reviewer-is-an-entry-of-a-map-with-a-key-a-name-and-a-type.md)), and the engine gets the requests that write them.

### The file

`agents.extraReviewers` is a map from a key to a reviewer, at most three, and the map keeps the order of the file.
Each entry has the fields of today's entries (`profile`, `provider`, `model`, `effort`, `persona`, `skills`, `failover`) and two more that every entry carries: `name`, the text the app shows, and `type`, a slug that says what the reviewer looks at.

```json
"extraReviewers": {
  "seguridad-api": {
    "type": "security",
    "name": "Seguridad API",
    "profile": "bot-sec", "provider": "claude", "model": "sonnet", "effort": "high",
    "persona": { "name": "Sentinel", "prompt": "Busca fallas de seguridad." },
    "skills": { "review": "code-review" },
    "failover": [{ "provider": "codex", "model": "gpt-5" }]
  },
  "usabilidad": { "type": "ux", "name": "Usabilidad", "profile": "bot-ux", "provider": "claude", "model": "sonnet" }
}
```

The key and the type are slugs that start with a letter (lowercase letters, digits and hyphens, up to 40 characters), so no key reads as a number and the order of the file holds.
The key is not `author`, `reviewer`, `lead` or `lead-reviewer`.
The name is one line of 1 to 40 characters, like a persona's name.
The key and the name are each unique among the reviewers of a map, the name compared without regard to case; the type can repeat, and it is only a label: the engine runs nothing different for it.

A reviewer signs `🤖 Reviewer [NAME] via Carrier` with its persona's name when it has one and its name when it does not.

A repo's `agents.extraReviewers` is a map of the same shape that replaces the whole map: no key means the global map, `{}` means none, and entries mean its own list.
Its entries carry `type`, `name`, `profile`, `provider` and `model`, and `effort` when they have one; their persona, failover steps and skills are the Reviewer's.

Nothing is migrated: a file, global or a repo's, whose `extraReviewers` is a list is refused when it loads, with a message that names the shape it needs.

The engine's own place for a reviewer in a round, `reviewer-2` to `reviewer-4`, does not change.
It is the position of the entry in the map when the epic starts, and the epic's saved configuration keeps the ordered list of the resolved reviewers, each now carrying its key, name and type, so the stored executions, the stage strip and the prefix of a blocker's id stay as they are.
An epic saved before has no key, name or type, and the app shows its reviewers as Reviewer 2 to Reviewer 4.

### The requests

The requests belong to the `config` capability's socket and are written the way the others are (read again, changed, checked whole, renamed), under a new capability the engine announces, `extraReviewers`, so an engine without it leaves the app's fields read only.
A reviewer is pointed at by its key; a key the file does not hold is refused, as a role with no entry is today.
After each save the running engine reloads, and an epic already running keeps the reviewers it started with.

- **`addExtraReviewer { draft }`** adds a reviewer at the end of the map, whole, in one request. The draft has the name, the type, the identity, the provider and the model, and an effort when it has one. It is refused, naming the field, when a field is missing, when the name is taken, when the identity, account or effort is not one the file knows (as `editRole` refuses them), or when the map already has three. The engine derives the key from the name: lowercase, without accents, anything that is not a letter or a digit becoming a hyphen, with an `r-` in front when it does not start with a letter, `extra` when nothing is left, and `-2`, `-3` and so on while the key is taken or reserved. The reply says what was saved, the entry under its key and the profiles.
- **`editRole`, `editPersona` and `editFailover`** accept an extra reviewer in place of a role name, written `{ "extraReviewer": "<key>" }`, and change only what they name, as they do for the Reviewer. `editFailover` writes the entry's own `failover` and takes it out when both steps are `null`, so the reviewer goes back to the Reviewer's steps. `editRole` also takes `name` and `type` for an extra reviewer (and refuses them for any other role), so a reviewer can be renamed or retyped without changing its key.
- **`removeExtraReviewer { key }`** removes that entry and nothing else: the profile it used stays in `profiles`, and a global map left empty goes out of the file.
- **`setRepoExtraReviewers { repo, reviewers }`** sets a repo's list in one request that sends the whole map: `null` takes the key out, `{}` is none, entries are its own list. It is refused for a repo the file does not watch (as `editRepoRole` is), for more than three entries, for a key, name or type that breaks the rules above, and for an entry that lacks an identity, an account or a model. It keeps nothing of the earlier map: an entry is what was sent.

A refusal carries a code and its parameters with English words as the fallback, as every other refusal of the `config` requests does ([0055](../adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)).
Each request has a golden under `macos/Tests/Fixtures`, written by the engine's contract test as the others are, and `capabilities.json` lists the new capability.
The app's `ContractTests` fail when the engine lists a request that the app does not build as its golden says, or announces a capability the app does not know, so the app's model layer (`CarrierCore`, no screen) learns each request and the capability in the same slice that adds them: a case of `EngineConfigChange` that encodes the request, its row in the golden tables of the tests, and a case of `ControlClient.Capability` for the capability that the fixture engine also announces.

### What else reads the setting

The resolver turns the map into the ordered list the engine runs, and each resolved reviewer carries its key, name and type.
The doctor names a reviewer by its name where it names it `reviewer-N`, the epic's status snapshot carries each extra reviewer's `name` and `type` beside its harness, model and provider when the epic has them, and `carrier restart`, the stage slots, the retry streaks and the profile cooldown keep working on the place of the reviewer, which does not change.
The documents that describe the setting say the map: `docs/configuration.md`, `docs/cli.md` and the `src/control` and `src/config` notes for the agents.

## Scope

1. A config file whose `agents.extraReviewers` is a map of up to three reviewers, each with a key, a name, a type and the fields of an agent, loads; a fourth, a duplicate key or name, a reserved or malformed key, a name that is empty or over 40 characters or has a line break, and a missing name or type are each refused with the path and the reason.
2. A config file, global or a repo's, whose `extraReviewers` is a list is refused when it loads, with a message that names the map it needs.
3. A repo's map replaces the global map whole, `{}` turns the extra reviewers off for it, and no key leaves the global map.
4. An epic runs the reviewers of its map in the order of the file, each in the place `reviewer-2` to `reviewer-4` that its position gives it, and one that has a persona signs with its persona's name and otherwise with its name.
5. The engine adds an extra reviewer from a complete draft in one request, derives its key from its name, and refuses an incomplete draft, a taken name or a fourth reviewer without changing the file; the app's model layer builds the request as its golden says.
6. The engine changes an extra reviewer's identity, provider, model, effort, name and type, its persona and its failover steps by its key, each request changing only what it names, and refuses a key the file does not hold; the app's model layer builds each request as its golden says.
7. The engine removes an extra reviewer by its key and changes nothing else in the file; the app's model layer builds the request as its golden says.
8. The engine sets a repo's list, takes it out or makes it empty, in one request, and refuses a repo it does not watch or an entry that breaks the rules; the app's model layer builds the request as its golden says.
9. The engine announces the capability `extraReviewers` in its hello, and the app knows it and its fixture engine announces it.
10. The epic's saved configuration and its status snapshot carry each extra reviewer's name and type, and an epic saved before them still reads, its reviewers without them.
11. The doctor names a reviewer by its name, and the documents describe the map and the new requests.

## Decisions

The shape, the key, the name and the type, the place a reviewer takes in a round, the refusal of the list, and what lost against each choice are in [0057](../adr/review/0057-an-extra-reviewer-is-an-entry-of-a-map-with-a-key-a-name-and-a-type.md).
The requests reuse the ones the Reviewer has (`editRole`, `editPersona`, `editFailover`) rather than a request of their own for each field, so an extra reviewer is edited as the Reviewer is and the app sends only what the person changed.
`name` and `type` are required in the schema for every entry, global and a repo's, so a map written by hand and one written by the app have one rule.
The wizard of `carrier init` does not read or write `extraReviewers` on `main`: the epic that adds extra reviewers to it (#1514) is still open, and whichever of the two lands second writes the map.
The three places that name the setting in the engine and keep working unchanged are `carrier restart`, the stage slots and the profile cooldown, because they read the resolved, ordered list.

Testing seams, by story:

- **1, 2, 3 (the file):** the config's loader, `src/config/load.test.ts`, which already feeds a file and reads its problems; cases for each refusal, with the wrong-typed inputs a hand-written file brings: a list, an empty map, a key of `2a` or `A` or `a_b` or 41 characters, a name that is blank or has a line break, a number where the name goes. `src/config/engine-config-contract.test.ts` keeps the contract the macOS app checks.
- **4 (running an epic):** the resolver, `src/config/resolve.test.ts`, for the order, the repo's replacement and the signature name; the existing slot tests for the place, with no new case beyond a map in the saved configuration.
- **5, 6, 7, 8 (the requests):** `src/config/role-edit.test.ts` for each request on a file in a temporary folder, including the refusals that leave the file as it was; and `src/control/config-goldens.test.ts`, whose golden of each request and reply is the contract with the app (`UPDATE_FIXTURES=1` writes it, the macOS tests compare).
- **9 (the capability):** `src/control/capabilities-contract.test.ts` and its golden `capabilities.json`.
- **10 (saved configuration and snapshot):** `src/status/snapshot.test.ts` and `snapshot-contract.test.ts` for the reviewers' name and type, with a saved configuration that lacks them.
- **11 (doctor and documents):** `src/doctor/doctor.test.ts` for the name; the documents have no test.
- **5, 6, 7, 8, 9 on the app's side (model layer only):** `macos/Tests/CarrierCoreTests/Connection/EngineConfigRequestsTests.swift` (the golden tables) and `ContractTests.swift`, which already fail until the app builds each listed request and knows each announced capability; no screen and no UI test.

## Out of scope

- Choosing another skill for an extra reviewer or any role: a later epic makes skills editable, and until then they are shown and not changed.
- Giving a type behaviour (defaults of skills or persona for a type): the type is a label.
- Migrating files that use the list: nothing migrates, and the refusal says what to write.
- Moving the engine's own place of a reviewer (`reviewer-2` to `reviewer-4`) to the key.
- Creating or removing GitHub identities, and cleaning up profiles no reviewer uses.
- The macOS screens, the fixture engine's answers to the new requests, and the rewrite of #1527 and #1528 on the new shape, which #1513 does when it resumes; this epic touches the app only where its contract tests require it.
- Changes to the wizard's flags: `carrier init` (#1514) has to write the map, but its questions and flags are its own epic.
