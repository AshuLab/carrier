# src/control

The control socket (`<folder>/engine/state/control.sock`), newline-delimited JSON for a local client: the macOS app and the CLI (`status`, `watch`, ...).
`server.ts` holds the request schema and the server.
The hello's `capabilities` list the optional requests an engine answers (`sessions`, `events`, `epic`, `files`, `fileDiff`, `availableRepos`, `availableReposPaged`, `resumeEpic`, `resumeFromStage` (`resumeEpic` takes `from` and `extraRounds`), `resumeReviewerOptions` (`resumeEpic` takes `reviewer2`, `reviewer3`, `reviewer4` and `lead`), `recoverEpic`, `reload` and `config`); a client checks it before asking, so an older engine still works.
`config` covers the requests that change `engine.json` (`setWatchedRepos`, `editBehavior` and the six role requests `editRole`, `editRepoRole`, `editPersona`, `editFailover`, `setLeadReviewer` and `setOrchestratorProfile`, which reach `Controls` through one method, `editEngineFile`, and `config/role-edit.ts`; [ADR 0053](../../docs/adr/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md)): `config/engine-edit.ts` reads the raw file again, applies the change, checks the whole result with the engine's schema and renames a temporary file over it, a refusal is `config.problem` with the key `path` and the kind of `problem` and leaves the file as it was, and `carrier config` ([cli](../../docs/cli.md#carrier-config); exit 0 saved, 1 refused, 2 could not run) forwards the request here when the engine answers and runs `config/engine-edit.ts` itself when it does not, and the reply is `{ saved, engine }` where `engine` is `applied`, `refused` (with a `reason` of `code`, `params` and `error`: the reload kept the settings, the file is saved) or, from `carrier config` with no engine running, `notRunning`.
`reload` makes the engine read `engine.json` and `providers.json` again and run on them, or answer the problem and keep its settings ([ADR 0023](../../docs/adr/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md)).
The app sends it after a save of `providers.json` or of a part of `engine.json` it still writes itself, and `carrier reload` is the same request; a save of the watched repos or the Behavior values through `config` makes the engine reload itself.
A refused reply is `{ id, ok: false, error, code, params }` on both sockets ([ADR 0055](../../docs/adr/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)): the words stay in `error`, and `refused(...)` in `server.ts` builds it.
The fixed errors are `request.invalidJson`, `request.invalid`, `request.extraRounds` (an invalid `extraRounds` of `resumeEpic`), `request.tooLong`, `request.internal`, `epic.unknown`, `file.unknown`, `execution.unknown` and `github.unavailable`.
`ResumeRefused`, `RecoverRefused` and `ReloadRefused` take their code first, so `pnpm typecheck` refuses one without it.
The chat host's `ChatRefused(code, words, params)` (`src/chat/runner.ts`) is the same on `chat.sock`: a code matches `textCode` (`<area>.<what>`) and a param is a string or a number, never a sentence or an object; the chat's `config` requests are in [the chat host spec](../../docs/specs/chat-host.md#refusals-and-config-requests-in-the-code).
A reload refused for a config problem of a known kind answers `config.problem` with `path` and `problem` (`src/config/problems.ts`: `notARepo`, `stepRepeated`, `stepOwnRole`, `providerNotDeclared`), any other `config.invalid`.
Every code is in `macos/Tests/Fixtures/text-codes.json` (`UPDATE_FIXTURES=1 pnpm test` rewrites it, `src/chat/text-codes.test.ts` checks it against the sources).
`terminal/cli/compose.ts` starts the server before the engine recovers its running epics: until the first check is armed the snapshot has no `nextCheckAt` (the app and the panel show it as starting), and a check asked meanwhile waits for that recovery.

## Adding a request to a socket

The same steps serve the engine's `control.sock` and the chat host's `chat.sock`; where they differ, the chat side is named.

1. Reply type: `src/control/replies.ts` (engine only; a `ChatControls` method returns `unknown`).
2. Handler logic: its own module under `src/control/` (like `epic.ts`, `files.ts`); for chat, `src/chat/sessions.ts`, `src/chat/projects.ts` or `src/usage`.
3. `src/control/server.ts`, in this order:
   a `z.strictObject` in `request`;
   the name in `Capability` (the `Exclude` in `control()` makes `answer()` handle it);
   a method on `Controls` (one that waits on git or GitHub returns a promise: `epic`, `files`, `fileDiff` and `availableRepos` do, and `answer()` replies when it settles, in the order of its connection, with the engine running meanwhile; the `git` of `epic.ts` runs at most four processes at once, and `files.ts` asks what git says about commits once, `fact`);
   the `if (parsed.data.cmd === ...)` branch in `answer()`;
   the name in the hello's `capabilities` in `startControlServer`.
   Chat: `src/chat/server.ts`, a `z.strictObject` in `chatRequest`, the name in **both** `ChatCapability` and the `capabilities` array, a method on `ChatControls` and a `case` in `run()`.
4. Wiring: the `controls` object in `src/terminal/cli/compose.ts`; chat: the `startChatServer` call in `src/chat/host.ts`.
5. TS tests:
   handler, refusal and invalid-field tables in `src/control/server.test.ts` (chat: `src/chat/server.test.ts`);
   the hello lists in `src/control/server.test.ts`, `src/terminal/cli/control-client.test.ts` and `src/chat/server.test.ts`;
   a stub in every fake `Controls`: `src/control/server.test.ts`, `epic-slices.test.ts`, `events.test.ts`, `sessions.test.ts`, `src/terminal/cli/control-client.test.ts` and the three in `src/terminal/cli/commands/status.test.ts` (chat: `controls()` in `src/chat/server.test.ts`).
6. Golden reply: `golden(...)` in `src/control/replies.test.ts`, written by `UPDATE_FIXTURES=1 pnpm test` to `macos/Tests/Fixtures/reply-<name>.json` (and `macos/DevFixtures/` when it passes `dev`).
   The `chat-*.json` fixtures are written by hand.
   A request of the `config` capability has a golden `chat-*.json` or `engine-*.json` with its request and reply; `config-requests.test.ts` fails for one without a golden or one its schema refuses, `UPDATE_FIXTURES=1 pnpm test` rewrites `config-requests.json`, and `ContractTests` then fails until the app encodes it as its golden says.
   A new capability changes `macos/Tests/Fixtures/capabilities.json` (`capabilities-contract.test.ts`); `ContractTests.swift` then fails until Swift has its case.
7. Swift, under `macos/`:
   the case on `ControlClient.Capability` in `Sources/CarrierCore/Connection/ControlClient.swift`, shared by engine and chat (unknown names are dropped silently, so a missing case means the feature never shows);
   the request in `Sources/CarrierCore/Connection/ControlRequests.swift` (engine) or `ChatHost.swift` and `SocketChatHost.swift` (chat);
   the reply type in `Sources/CarrierCore/Chat/Replies.swift` (chat replies live in `ChatHostModels.swift`, `ChatHostReplies.swift`, `UsageModels.swift` and the like);
   both hard-coded lists in `Sources/CarrierCore/Fixtures/FixtureServer.swift` (`chatHello` and the engine's `names`) plus its handlers (`FixtureServer+Chat.swift`, `FixtureServer+ChatRequests.swift`), and `Tests/CarrierCoreTests/Fixtures/FixtureServerTests.swift`;
   tests in `Tests/CarrierCoreTests/` (`ControlRequestsTests`, `ChatHostTests`, `RepliesTests`, `ControlClientTests`).
8. Docs: the capability list above, the request's line in [configuration](../../docs/configuration.md#who-writes-each-file) and [cli](../../docs/cli.md#carrier-config) when it is a `config` request, the `--fixture` paragraph of `macos/README.md` when the fixture server answers it, the feature's spec and `CHANGELOG.md`.

Rules:

- A new reply field is optional in Swift: an older engine lacks it.
- The app sends a request only when the hello announces it.
- A zod limit is mirrored by a Swift guard (`fileDiff`'s section and path limits in `ControlRequests.swift`).
- Error text never echoes git or gh output: answer a fixed sentence.
- JSON field names are the same camelCase in TypeScript and Swift.
