# 0053 - A config file of the Carrier folder is written only by Carrier's Node code, through its owner process or `carrier config`

- Status: proposed
- Date: 2026-11-24

## Context

The top of the Carrier folder holds the files a person edits: `engine.json`, `chat.json`, `providers.json` and `projects.json` ([0034](0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)).
Today the app writes them itself: [0020](0020-accounts-live-in-a-file-both-processes-read.md) says the app writes `providers.json`, and [0041](0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md) says both the app and the host write `projects.json`, as both write `engine.json`.
About fifteen Swift files read, check and write these files (`ProjectsFile`, `ProvidersFile`, `ProvidersPage`, `RepoRoleSave`, `RoleDetailsSave`, `GlobalRoleSave`, `LeadReviewerSwitch`, `EngineReload.saveConfig` and others), then ask the engine to `reload`.
The rules of each file therefore live twice, in zod (`src/config/`, `src/chat/config.ts`) and in Swift, kept in step by `ContractTests` and the shared fixtures.
The control socket has no request that writes config; the chat socket has none for most of it.
A web front-end runs in a browser, which cannot write a file of the Carrier folder at all: as things are, it could show Settings but change nothing.
And the app edits `engine.json` today while Carrier is stopped, on purpose: Watching, Behavior and Agents save to the file, and "Carrier reads it when it starts" (`docs/macos/settings-carrier.md`); `carrier init` writes the first `engine.json` and `providers.json` before any engine exists.

## Decision

Every write of a config file at the top of the Carrier folder is done by Carrier's Node code, once, in the module that already owns that file's schema: `src/config/` for `engine.json`, `providers.json` and `projects.json`, `src/chat/config.ts` for `chat.json`.
Nothing else writes the files: not the app, not a future web front-end.

A front-end asks for one change at a time (add a project, save a role, set an account), as a request with its own name and fields.

- When the process that reads the file answers on its socket (the engine for `engine.json`; the chat host for `chat.json`, `projects.json` and `providers.json`), the request goes there, and the process writes and applies it at once.
- When it does not answer (Carrier stopped, the host not started yet, the first run), the front-end runs `carrier config <request>` with the same request as JSON on its standard input; the command forwards it to the socket if one answers by then, and otherwise writes the file itself with the same code, and prints the reply as JSON.
- `carrier init` writes through the same code.

The writing code edits the file's raw JSON, not the loaded config (which mixes in the defaults): it reads the file again just before writing, applies the change, validates the whole result with the file's zod schema, writes it atomically (a temporary file and a rename), and answers the saved part of the file, or a refusal with its code ([0055](0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)).
For `engine.json` and `providers.json` the reply also says what the running engine did with it: applied, refused with the engine's reason, or not running.
A person may still edit the files by hand; a file broken by hand is fixed by hand, as the engine and the host refuse to start on it today.
The app's preferences (the user defaults, one of the [config levels](../glossary.md)) are not part of this: they stay per device and per front-end.

## Alternatives considered

The owner process is the only writer, so editing needs it running.
It is the simplest rule, but Settings could not change Watching, Behavior or Agents while Carrier is stopped, and nothing could write the first `engine.json`.

Keep writing the files from the app when the owner is not running.
Settings keeps working with Carrier stopped, but the rules stay in Swift, and a web front-end needs a third copy.

Keep writing the files from the app, and give the web front-end a small file-writing endpoint.
It moves less today, but the rules stay in two languages, a third copy is needed for the web, and an endpoint that writes any file is a wider door than a request per change.

One merged config served by the engine, the app's preferences included.
It would let a person's preferences follow them between front-ends, which is wanted later, but it mixes what is per device with what is per Carrier folder and is not needed for a web front-end to start.

## Consequences

This amends [0020](0020-accounts-live-in-a-file-both-processes-read.md) (the app no longer writes `providers.json`) and [0041](0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md) (only Carrier's Node code writes `projects.json` and `engine.json`).
New requests on both sockets, behind one capability per socket (`config`), as the `projects` capability already covers several requests, and a `carrier config` command that takes any of them.
Saving with Carrier stopped starts a short Node process for each save, a few hundred milliseconds; a page that saves on each keystroke (Behavior) keeps its pause before saving, and saving and applying stay one request.
The app, the engine and the chat host are released together, so the app keeps no write of its own to fall back on; a host or engine that was busy during an update answers the change after it is replaced, as it is replaced today.
The Swift writers go once the app uses the requests; the Swift checks that a form runs while the person types (`draftProblems`, `repoProblem`, `RoleFields.problems`, `EngineConfig.problems`) stay, and `ContractTests` gain tests that what the app sends is what Node accepts.
A web front-end is TypeScript, so it can run the zod schemas directly for the same checks.
Later, the same requests are where a person's preferences could be kept, if that is ever wanted.
