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

The key is the reviewer's identity wherever the engine names it: the review slot of a stored execution, the round and its retries, the prefix of a blocker's id, the folder of its checkout, the roles `carrier restart` asks about, the epic's status and the doctor's lines.
`reviewer-2` to `reviewer-4` do not exist any more, the slots `reviewer` and `lead` stay, and the epic's saved configuration keeps the resolved reviewers in the order of the map, each carrying its key, name and type.
Nothing migrates what was recorded before: the executions stored with `reviewer-2` to `reviewer-4` keep the text they have and the engine does not read it as a reviewer, and an epic that was running with extra reviewers when this lands cannot be resumed.

### The requests

The requests belong to the `config` capability's socket and are written the way the others are (read again, changed, checked whole, renamed), under a new capability the engine announces, `extraReviewers`, so an engine without it leaves the app's fields read only.
A reviewer is pointed at by its key; a key the file does not hold is refused, as a role with no entry is today.
After each save the running engine reloads, and an epic already running keeps the reviewers it started with.

- **`addExtraReviewer { draft }`** adds a reviewer at the end of the map, whole, in one request. The draft has the name, the type, the identity, the provider and the model, and an effort when it has one. It is refused, naming the field, when a field is missing, when the name is taken, when the identity, account or effort is not one the file knows (as `editRole` refuses them), or when the map already has three. The engine derives the key from the name with the function of the config module that `carrier init` uses too, so there is one rule: lowercase, accents removed, every run of characters that are not a letter or a digit becoming one hyphen, hyphens trimmed from both ends, an `r-` in front when the result does not start with a letter, `extra` when nothing is left, the result cut so that the key, suffix included, is at most 40 characters, and `-2`, `-3` and so on while the key is taken or is `author`, `reviewer`, `lead` or `lead-reviewer`. So `Seguridad API` gives `seguridad-api`, `Ñandú` gives `nandu`, `123` gives `r-123`, `!!!` gives `extra`, and `Lead` gives `lead-2`. The reply says what was saved, the entry under its key and the profiles.
- **`editRole`, `editPersona` and `editFailover`** accept an extra reviewer in place of a role name, written `{ "extraReviewer": "<key>" }`, and change only what they name, as they do for the Reviewer. `editFailover` writes the entry's own `failover` and takes it out when both steps are `null`, so the reviewer goes back to the Reviewer's steps. `editRole` also takes `name` and `type` for an extra reviewer (and refuses them for any other role), so a reviewer can be renamed or retyped without changing its key.
- **`removeExtraReviewer { key }`** removes that entry and nothing else: the profile it used stays in `profiles`, and a global map left empty goes out of the file.
- **`setRepoExtraReviewers { repo, reviewers }`** sets a repo's list in one request that sends the whole map: `null` takes the key out, `{}` is none, entries are its own list. It is refused for a repo the file does not watch (as `editRepoRole` is), for more than three entries, for a key, name or type that breaks the rules above, and for an entry that lacks an identity, an account or a model. It keeps nothing of the earlier map: an entry is what was sent.

A refusal carries a code and its parameters with English words as the fallback, as every other refusal of the `config` requests does ([0055](../adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)).
Each request has a golden under `macos/Tests/Fixtures`, written by the engine's contract test as the others are, and `capabilities.json` lists the new capability.
The app's `ContractTests` fail when the engine lists a request that the app does not build as its golden says, or announces a capability the app does not know, so the app's model layer (`CarrierCore`, no screen) learns each request and the capability in the same slice that adds them: a case of `EngineConfigChange` that encodes the request, its row in the golden tables of the tests, and a case of `ControlClient.Capability` for the capability that the fixture engine also announces.

### `carrier init`

The wizard that writes `engine.json` writes the map and takes each extra reviewer by its name.
In the block of each extra reviewer it asks the name, which is required and has no suggestion (a blank answer asks again), and the type, which starts on `general`; the key is derived from the name by the rule of the request that adds a reviewer.
In edit mode each extra reviewer of the file's map is walked in the order of the map, starting from its name and type, and the file keeps each one's key and the fields the wizard does not ask.
The flags that answered a reviewer by its position (`--reviewer-2` to `--reviewer-4` and their `-profile`, `-provider`, `-effort`, `-persona-name`, `-persona-prompt` and `-failover`) are replaced by flags that name the reviewer: `--extra-reviewer "<name>=<harness>:<model>"` creates one and can be repeated, and `--extra-reviewer-profile`, `-provider`, `-effort`, `-type`, `-persona-name`, `-persona-prompt` and `-failover` each take `"<name>=<value>"`.
The name is everything before the first `=`, so a name that holds `=` can only be given in the question; a flag that names a reviewer no `--extra-reviewer` created is refused before anything is probed, naming the flag.

### What else reads the setting

The resolver turns the map into the ordered list the engine runs, and each resolved reviewer carries its key, name and type.
The round, the retry streaks, the blockers, the checkouts and the stage slots use the key where they used `reviewer-N`, the doctor names a reviewer by its name, the epic's status snapshot carries each extra reviewer's key, `name` and `type` beside its harness, model and provider, and the doctor labels its checks with the key.
`carrier restart` asks about a reviewer by its key and takes `--extra-reviewer-option "<key>=<option>"`, repeatable, where it took `--reviewer-2` to `--reviewer-4`; the `resumeEpic` request of the engine's socket takes `extraReviewers`, a map from a key to the option, where it took `reviewer2`, `reviewer3` and `reviewer4`, and the capability that announces it, `resumeReviewerOptions`, keeps its name.
An epic saved before the names, whose saved configuration holds extra reviewers without a key, is not resumed: the engine refuses it with an error that names the cause (the epic was saved before its reviewers had names and has to be started again) and goes on with the other epics, and the status snapshot of such an epic still builds, giving its extra reviewers without key, name or type.
The profile cooldown keeps working on the profiles of the resolved reviewers.
The documents that describe the setting say the map: `docs/configuration.md`, `docs/cli.md` and the `src/control` and `src/config` notes for the agents.

## Scope

1. A config file whose `agents.extraReviewers` is a map of up to three reviewers, each with a key, a name, a type and the fields of an agent, loads; a fourth, a duplicate key or name, a reserved or malformed key, a name that is empty or over 40 characters or has a line break, and a missing name or type are each refused with the path and the reason.
2. A config file, global or a repo's, whose `extraReviewers` is a list is refused when it loads, with a message that names the map it needs.
3. A repo's map replaces the global map whole, `{}` turns the extra reviewers off for it, and no key leaves the global map.
4. An epic runs the reviewers of its map in the order of the file, and one that has a persona signs with its persona's name and otherwise with its name.
5. The engine adds an extra reviewer from a complete draft in one request, derives its key from its name, and refuses an incomplete draft, a taken name or a fourth reviewer without changing the file; the app's model layer builds the request as its golden says.
6. The engine changes an extra reviewer's identity, provider, model, effort, name and type, its persona and its failover steps by its key, each request changing only what it names, and refuses a key the file does not hold; the app's model layer builds each request as its golden says.
7. The engine removes an extra reviewer by its key and changes nothing else in the file; the app's model layer builds the request as its golden says.
8. The engine sets a repo's list, takes it out or makes it empty, in one request, and refuses a repo it does not watch or an entry that breaks the rules; the app's model layer builds the request as its golden says.
9. The engine announces the capability `extraReviewers` in its hello, and the app knows it and its fixture engine announces it.
10. The epic's saved configuration and its status snapshot carry each extra reviewer's key, name and type.
11. The doctor names a reviewer by its name and labels its checks with its key, and the documents that name a reviewer by a position (`docs/configuration.md`, `docs/cli.md`, `docs/troubleshooting.md` and the notes of `src/config` and `src/control`) describe the map, the key and the new requests.
12. The engine records, retries, checks out and reports each extra reviewer by its key: its stored executions, its blockers' ids, its checkout folder, the epic's status and `carrier restart` use the key, and no name of the form `reviewer-2` to `reviewer-4` is written or read.
13. `carrier init` asks each extra reviewer's name and type, takes the reviewers by the flags that name them, writes the map, and in edit mode keeps each one's key and the fields it does not ask.

## Decisions

The shape, the key, the name and the type, the key as the one identity of a reviewer in the engine, the refusal of the list, and what lost against each choice are in [0057](../adr/review/0057-an-extra-reviewer-is-an-entry-of-a-map-with-a-key-a-name-and-a-type.md).
The requests reuse the ones the Reviewer has (`editRole`, `editPersona`, `editFailover`) rather than a request of their own for each field, so an extra reviewer is edited as the Reviewer is and the app sends only what the person changed.
`name` and `type` are required in the schema for every entry, global and a repo's, so a map written by hand and one written by the app have one rule.
The wizard of `carrier init` on `main` writes and reads `extraReviewers` as a list, so the slice that moves the config to the map moves the wizard with it, and the flags that name a reviewer follow in the next one.
The key replaces `reviewer-2` to `reviewer-4` in every place that named a reviewer, and nothing reads the old names; a key is never `reviewer` or `lead`, so the slots of the Reviewer and the Lead cannot collide with an extra reviewer's.
The flags of an extra reviewer in `carrier init` name the reviewer (`--extra-reviewer "<name>=<harness>:<model>"` and a flag for each field that takes `"<name>=<value>"`), because a free name cannot be a flag of its own.

Testing seams, by story:

- **1, 2, 3 (the file):** the config's loader, `src/config/load.test.ts`, which already feeds a file and reads its problems; cases for each refusal, with the wrong-typed inputs a hand-written file brings: a list, an empty map, a key of `2a` or `A` or `a_b` or 41 characters, a name that is blank or has a line break, a number where the name goes. `src/config/engine-config-contract.test.ts` keeps the contract the macOS app checks.
- **4 (running an epic):** the resolver, `src/config/resolve.test.ts`, for the order, the repo's replacement and the signature name.
- **12 (the key everywhere):** the storage tests of executions, the orchestration tests of the round, the retries, the blockers and the slots, the workspace tests of the checkout folder and `carrier restart`'s tests, each with a reviewer named by a key such as `seguridad-api` and an epic of two extra reviewers.
- **13 (`carrier init`):** the wizard's tests (the builder of the config, the reader of the existing file, the keep-the-rest edit, the flags and their validation, and the wizard flow), with the flags that name a reviewer and the refusal of one that names none.
- **5, 6, 7, 8 (the requests):** `src/config/role-edit.test.ts` for each request on a file in a temporary folder, including the refusals that leave the file as it was; and `src/control/config-goldens.test.ts`, whose golden of each request and reply is the contract with the app (`UPDATE_FIXTURES=1` writes it, the macOS tests compare).
- **9 (the capability):** `src/control/capabilities-contract.test.ts` and its golden `capabilities.json`.
- **10 (saved configuration and snapshot):** `src/status/snapshot.test.ts` and `snapshot-contract.test.ts` for the reviewers' name and type, with a saved configuration that lacks them.
- **11 (doctor and documents):** `src/doctor/doctor.test.ts` for the name; the documents have no test.
- **5, 6, 7, 8, 9 on the app's side (model layer only):** `macos/Tests/CarrierCoreTests/Connection/EngineConfigRequestsTests.swift` (the golden tables) and `ContractTests.swift`, which already fail until the app builds each listed request and knows each announced capability; no screen and no UI test.

## Out of scope

- Choosing another skill for an extra reviewer or any role: a later epic makes skills editable, and until then they are shown and not changed.
- Giving a type behaviour (defaults of skills or persona for a type): the type is a label.
- Migrating files, recorded executions or running epics that use the list or `reviewer-2` to `reviewer-4`: nothing migrates, and the refusal says what to write.
- Creating or removing GitHub identities, and cleaning up profiles no reviewer uses.
- The macOS screens, the fixture engine's answers to the new requests, and the rewrite of #1527 and #1528 on the new shape, which #1513 does when it resumes; this epic touches the app only where its contract tests require it.
