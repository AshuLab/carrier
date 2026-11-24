# src/config

The Carrier folder (`~/.carrier`, or `CARRIER_HOME`, [ADR 0034](../../docs/adr/0034-the-carrier-folder-keeps-edited-files-at-the-top-and-splits-each-process-folder-by-lifecycle.md)) holds the engine's config at `<folder>/engine.json`, the accounts at `<folder>/providers.json` ([ADR 0020](../../docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)) and the person's projects at `<folder>/projects.json` ([ADR 0041](../../docs/adr/0041-a-project-is-an-entry-of-projects-json-identified-by-its-folder.md)).
`providers.ts` is the accounts' schema and reader, and `engine.json` refuses a `providers` key; the file's two other keys, `textGenerators` (a map by name of `{ kind, model }`) and `textGenerator` (the one in use, a key of the map), are in the same schema, read by the chat host and ignored by the engine ([ADR 0038](../../docs/adr/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md)).
The engine's files are in `<folder>/engine/`: `state/` (`carrier.db`, `control.sock`, `carrier.lock`), `logs/`, `repos/`, `reviews/` and `worktrees/`.
`places.ts` computes every path in the folder (the four files at the top, the engine's and the chat's places), and nothing else decides them; `--config` only chooses the engine's config file.
Its Swift twin is `macos/Sources/CarrierCore/CarrierPlaces.swift`, which also has the app's places.

## Adding a config field

`engine.json`:

1. `src/config/schema.ts`: the field in `configSchema`.
2. `src/config/load.ts`: its default in `defaults`.
   The JSON Schema (`json-schema.ts`, served by `carrier schema`) leaves a key out of `required` only when it has a default here.
3. `src/config/resolve.ts`: only if it is per repo or per role (`resolveRepoConfig`, `EffectiveRepoConfig`); keep it optional, older epics were stored without it.
4. `src/terminal/cli/compose.ts`: read it **inside** a closure (`settings`, `snapshot`, `timeoutMs`), never once at start: `config` is replaced by `reload` ([ADR 0023](../../docs/adr/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md)).
5. `UPDATE_FIXTURES=1 pnpm test` rewrites `macos/Tests/Fixtures/engine-config.json` (`engine-config-contract.test.ts`), and `ContractTests.swift` fails until `EngineConfig.swift` has the same defaults and refuses the same values.
6. Swift, only if the app edits it: `macos/Sources/CarrierCore/EngineConfig.swift` repeats the default, the parse (`init(json:)`) and the rule (`problems`), and `EngineConfigChange.behavior` sends it; the write is `src/config/engine-edit.ts` (`editBehavior`; the roles, personas, failover steps, lead reviewer and orchestrator profile are `role-edit.ts`, with its field rules in `role-edit.ts` and its table in `role-edit.test.ts`) and the request's schema is `editBehaviorRequest` in `src/control/server.ts`; the page is `BehaviorPage.swift` and `BehaviorTab.swift`.

`providers.json`:

1. `src/config/providers.ts`: the `account` schema, plus `AccountRuntime` and `runtimeOf` if the field reaches the agent's process.
2. Engine argv: `src/harnesses/claude.ts`, `src/harnesses/codex.ts`; a flag Carrier sets itself goes in `src/config/launch-args.ts`.
3. Chat: the `ChatLaunch` `Pick` in `src/chat/runner.ts` (a second hand-written list), filled in `src/chat/account.ts`; argv in `src/chat/claude.ts` and `src/chat/codex.ts`.
4. Swift: `macos/Sources/CarrierCore/ProvidersEdit.swift`, the `AccountDraft` property, `init(account:)`, `fields`, `draftProblems` and the `changes` of `ProvidersRequest.editAccount` (`ProvidersRequests.swift`); `providers-edit.ts` writes the key, and `chat/server.ts` has it in the `editAccount` request.

`projects.json`:

1. `src/config/projects.ts`: the `projectEntry` schema, `updateProjectsFile` for every write (it reads again, checks and renames), and the table in `projects.test.ts`.
2. `UPDATE_FIXTURES=1 pnpm test` rewrites `macos/Tests/Fixtures/projects.json`, and `ContractTests.swift` fails until `ProjectsFile.swift` repeats the rule.
3. The only writer is Node's: `src/chat/project-edits.ts` (the chat host's requests and `carrier config`), which keeps every entry and every key it does not touch and never writes over a file that does not match; the app reads the file and asks for each change.

`chat.json`:

1. `src/chat/config.ts`: `chatConfigSchema` **and** the hand-written `ChatSettings` type and what `loadChatConfig` returns.
   The chat has no reload: the host reads the file again when it needs it.
2. Swift: `macos/Sources/CarrierCore/SessionAges.swift` for the ages it edits, `WorktreeStart.swift` for `worktreeStart` and `IdleClose.swift` for `idleCloseMinutes`; the row is also listed in `SettingsIndex.swift`, or the Settings search cannot find it.

All four: `docs/configuration.md`, the Settings pages in `docs/macos/` if Settings shows it, and `CHANGELOG.md`.
The app's writers keep keys they do not know, and send `reload` after saving the parts of `engine.json` it still writes; `engine.json`'s watched repos and Behavior values are written by `engine-edit.ts` and followed by the engine's own reload.
`providers.json` is written by `providers-edit.ts` only ([ADR 0053](../../docs/adr/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md)): the chat host answers `setAccounts`, `addAccount`, `editAccount`, `removeAccount` and `setTextGenerator` and `carrier config` runs the same code, each reading the raw file again, keeping every key it does not touch, validating the whole result with `providersFileSchema` and renaming a temporary file over it; the one that wrote then asks the engine to reload (`chat/engine-reload.ts`) and the reply says what it did.
`removeAccount` reads `engine.json` and `chat.json` for who uses the account (`accountUses`) and stops when one of them is there and cannot be read.
