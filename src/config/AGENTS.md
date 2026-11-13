# src/config

The Carrier folder (`~/.carrier`, or `CARRIER_HOME`, [ADR 0016](../../docs/adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)) holds the engine's config at `<folder>/config.json` and the accounts at `<folder>/providers.json` ([ADR 0020](../../docs/adr/0020-accounts-live-in-a-file-both-processes-read.md)).
`providers.ts` is the accounts' schema and reader, and `config.json` refuses a `providers` key.
The engine's files are in `<folder>/engine/`: `state/` (`carrier.db`, `control.sock`, `carrier.lock`), `logs/`, `repos/`, `reviews/` and `worktrees/`.
`engine-places.ts` computes them from the folder, and nothing else decides them; `--config` only chooses the config file.

## Adding a config field

`config.json`:

1. `src/config/schema.ts`: the field in `configSchema`.
2. `src/config/load.ts`: its default in `defaults`.
   The JSON Schema (`json-schema.ts`, served by `carrier schema`) leaves a key out of `required` only when it has a default here.
3. `src/config/resolve.ts`: only if it is per repo or per role (`resolveRepoConfig`, `EffectiveRepoConfig`); keep it optional, older epics were stored without it.
4. `src/terminal/cli/compose.ts`: read it **inside** a closure (`settings`, `snapshot`, `timeoutMs`), never once at start: `config` is replaced by `reload` ([ADR 0023](../../docs/adr/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md)).
5. `UPDATE_FIXTURES=1 pnpm test` rewrites `macos/Tests/Fixtures/engine-config.json` (`engine-config-contract.test.ts`), and `ContractTests.swift` fails until `EngineConfig.swift` has the same defaults and refuses the same values.
6. Swift, only if the app edits it: `macos/Sources/CarrierCore/EngineConfig.swift` repeats the default, the parse (`init(json:)`), the rule (`problems`) and the write (`applied(to:)`); the page is `BehaviorPage.swift` and `BehaviorTab.swift`.

`providers.json`:

1. `src/config/providers.ts`: the `account` schema, plus `AccountRuntime` and `runtimeOf` if the field reaches the agent's process.
2. Engine argv: `src/harnesses/claude.ts`, `src/harnesses/codex.ts`; a flag Carrier sets itself goes in `src/config/launch-args.ts`.
3. Chat: the `ChatLaunch` `Pick` in `src/chat/runner.ts` (a second hand-written list), filled in `src/chat/account.ts`; argv in `src/chat/claude.ts` and `src/chat/codex.ts`.
4. Swift: `macos/Sources/CarrierCore/ProvidersEdit.swift`, the `AccountDraft` property, `init(account:)`, `fields`, `draftProblems` and `applyingEdit`.

`chat.json`:

1. `src/chat/config.ts`: `chatConfigSchema` **and** the hand-written `ChatSettings` type and what `loadChatConfig` returns.
   The chat has no reload: the host reads the file again when it needs it.
2. Swift: `macos/Sources/CarrierCore/SessionAges.swift`, only for the ages it edits.

All three: `docs/configuration.md`, the Settings pages in `docs/macos/` if Settings shows it, and `CHANGELOG.md`.
The app's writers keep keys they do not know, and send `reload` after saving `config.json` or `providers.json`.
