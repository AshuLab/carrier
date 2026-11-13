# src/control

The control socket (`<folder>/engine/state/control.sock`), newline-delimited JSON for a local client: the macOS app and the CLI (`status`, `watch`, ...).
`server.ts` holds the request schema and the server.
The hello's `capabilities` list the optional requests an engine answers (`sessions`, `events`, `epic`, `files`, `fileDiff`, `availableRepos`, `availableReposPaged`, `resumeEpic` and `reload`); a client checks it before asking, so an older engine still works.
`reload` makes the engine read `config.json` and `providers.json` again and run on them, or answer the problem and keep its settings ([ADR 0023](../../docs/adr/0023-the-engine-reloads-its-configuration-on-request-and-running-work-keeps-what-it-started-with.md)).
The app sends it after each save, and `carrier reload` is the same request.
`terminal/cli/compose.ts` starts the server once the engine is up.

## Adding a request to a socket

The same steps serve the engine's `control.sock` and the chat host's `chat.sock`; where they differ, the chat side is named.

1. Reply type: `src/control/replies.ts` (engine only; a `ChatControls` method returns `unknown`).
2. Handler logic: its own module under `src/control/` (like `epic.ts`, `files.ts`); for chat, `src/chat/sessions.ts`, `src/chat/projects.ts` or `src/usage`.
3. `src/control/server.ts`, in this order:
   a `z.strictObject` in `request`;
   the name in `Capability` (the `Exclude` in `control()` makes `answer()` handle it);
   a method on `Controls`;
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
7. Swift, under `macos/`:
   the case on `ControlClient.Capability` in `Sources/CarrierCore/ControlClient.swift`, shared by engine and chat (unknown names are dropped silently, so a missing case means the feature never shows);
   the request in `Sources/CarrierCore/ControlRequests.swift` (engine) or `ChatHost.swift` (chat);
   the reply type in `Sources/CarrierCore/Replies.swift` (chat replies live in `ChatHost.swift`, `UsageModels.swift` and the like);
   both hard-coded lists in `Sources/CarrierCore/FixtureServer.swift` (`chatHello` and the engine's `names`) plus its handler, and `Tests/CarrierCoreTests/FixtureServerTests.swift`;
   tests in `Tests/CarrierCoreTests/` (`ControlRequestsTests`, `ChatHostTests`, `RepliesTests`, `ControlClientTests`).
8. Docs: the capability list above, the `--fixture` paragraph of `macos/README.md` when the fixture server answers it, the feature's spec and `CHANGELOG.md`.

Rules:

- A new reply field is optional in Swift: an older engine lacks it.
- The app sends a request only when the hello announces it.
- A zod limit is mirrored by a Swift guard (`fileDiff`'s section and path limits in `ControlRequests.swift`).
- Error text never echoes git or gh output: answer a fixed sentence.
- JSON field names are the same camelCase in TypeScript and Swift.
