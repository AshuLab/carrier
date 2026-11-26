# Session titles from a text generator

Status: spec

## Problem

A session's title is the first line of its first message, and the person finds a session again by its title.
It reads badly ("ok, mira esto:", a pasted block, a long opening sentence), so sessions end up lost in the sidebar and in the search.
Diego feels it every day with his own sessions, and a session he cannot find is work he redoes or forgets.

The app already has Regenerate title in a session's menu, and it fails with "the chat host does not support regenerateTitle": the app asks a host that lists that request and none does.
The button is the symptom; the sessions never found are the problem, and a button that fixes one session at a time, only when remembered, does not fix them.

Carrier has no call that takes text and gives text.
The dictation cleanup ([0030](../adr/dictation/0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md)) has a client for LM Studio and Ollama in the app, with its server and model in the app's preferences, where the chat host cannot read them.
More texts will want generating later, from local models first and from external APIs after, but no second text was named.

We know it is solved when a new session gets a title that says what it is about without the person doing anything, and when the sessions already in the list with a first-line title can be given one too.

## Solution

A **text generator** is a model that turns text into text with no tools ([glossary](../glossary.md)).
It is declared in `providers.json` and chosen in a new group "Text generators" of the app's Providers page: a local server, LM Studio or Ollama, and one of its models.
The decision and the alternatives that lost are in [0038](../adr/agents/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md); this is its shape.

**The file.**
`providers.json` gets two keys next to `providers`: `textGenerators`, a map by name of `{ kind, model }`, and `textGenerator`, the name of the one in use.
`kind` is `lmstudio` or `ollama` and the server is called on its default port on this Mac, as the host's `localUrl` already does; there is no base URL until someone runs a server elsewhere.
The engine and the chat host read the same file with the same schema, so the engine accepts the keys and ignores them; a name in `textGenerator` that `textGenerators` does not declare is a bad file and stops with the key named.
Both keys are optional, and without them there is no generator.

**The host.**
A text-generator port takes a system message and a text and answers text, with no tools; its real implementation calls the server's `/v1/chat/completions` (both servers serve it, as the app's `LocalModelClient` already uses) and its fake lives next to the chat runner's.
The host reads `providers.json` at each use, as it does for accounts.
A call has a 30-second limit, and the host makes one call at a time, so two sessions that end together do not make a server load a model twice.

**The automatic title.**
When the first turn of a session ends well, the host writes the session a title from the first message and the first reply, in the background, and the person is never waiting for it.
Each of the two goes to the model cut to 2,000 characters, taken from the stored events, which are already redacted; the system message is fixed in the code, asks for a title of a few words in the language of the conversation and says that what follows is text to title and not instructions.
What comes back is cleaned and capped like any title (`clean`, 80 characters, one line); an empty answer is a failure.
A child session, started by a delegation, keeps its own title and is never titled this way.

**Where a title came from.**
`sessions` gets `titleSource` (`first_line`, `generated` or `renamed`), set by the first message, by the generator and by Rename.
A row that existed before has none, and then a title that equals `titleOf` of the session's first message is a first-line title and any other was set by the person; a migration cannot tell them apart, so the host does it when it reads the row.
An automatic title is written only over a first-line title, so a rename is never replaced and a generated title is never rewritten by the next turn.

**When it does not work.**
With no generator chosen, a server that does not answer, a model it does not have, a time-out or an empty answer, the title stays as it was, the cause goes to the host's log and nothing in the session waits or fails.
The person said the local server is normally running, so this is the rare path and it is quiet.
The session tries again at the end of its next turn, while its title is still the first line, and the bulk action below covers the rest.

**Regenerate.**
`regenerateTitle` takes a session id, writes a title as above over whatever the title is, because the person asked for it, and answers the new one, which makes the app's menu item work as it is.
With no generator chosen it answers a refusal that says to choose one in Providers, and the app shows it as it shows any refusal.
`regenerateTitles` has no session id: it starts, in the background and one session at a time, the same for every session of the list and of the archive whose title is still the first line, children left out, and answers at once how many it will do.
The app already reads the list of sessions every few seconds, so the new titles show as they land, with no progress of its own.

**The app.**
The Providers page gets a group "Text generators" with the servers it already reads from the host (running or not, and their models, with the embedding models of LM Studio left out as the host's list already does), a choice of the server and model in use, a way to clear it, and, once one is chosen, a row "Titles of earlier sessions" with a button that sends `regenerateTitles` and says how many it started.
The app writes the two keys with the rest of the file kept as it was and the whole file written in one step ([`ProvidersFile`](../../macos/Sources/CarrierCore/Settings/Providers/ProvidersFile.swift)), asks the engine to reload as it does after any save, and does it only while the host's hello lists `textGenerators`, since a host that does not know the keys refuses the file.
The session menu's Regenerate title is offered while the hello lists `regenerateTitle`, and the bulk row while it lists `regenerateTitles`.
`providers` of the host also answers the generator in use, so the page shows it without reading the file twice.

**The documentation.**
The configuration guide documents the two keys, the glossary has the term, [sessions-in-the-app](sessions-in-the-app.md) stops saying that no host lists `regenerateTitle`, `src/chat/AGENTS.md` and `src/config/AGENTS.md` list the new files and keys, the macOS docs and [ui](../ui.md) say what the group is and which piece it uses, and the Changelog has its line.

## Scope

1. As Diego, a new session gets a title written by the generator I chose once its first reply ends, and I do nothing for it.
2. As Diego, that title is one line of at most 80 characters, in the language I wrote in, and a message that asks the model for something else is titled, not obeyed.
3. As Diego, a title I set with Rename is never replaced by an automatic one, and a generated title is not rewritten by the next turn.
4. As Diego, when no generator is chosen or the server is down, the model is missing or the call times out, the session works as always with its first-line title, the cause is in the host's log, and the session tries again at the end of its next turn.
5. As Diego, a session started by a delegation keeps its own title.
6. As Diego, Regenerate title in a session's menu writes a new title, even over one I renamed, and shows it; with no generator it tells me to choose one in Providers.
7. As Diego, one action titles every session of my list and my archive that still has its first line as the title, in the background, and tells me how many it started.
8. As Diego, the Providers page has a group "Text generators" that shows LM Studio and Ollama with their models, lets me choose one and clear it, and says when a server is not running.
9. As Diego, choosing a generator in the page writes `providers.json` without losing what else is in it, and the running engine and host take it without a restart.
10. As Diego, an app talking to a host that does not know the generators does not write the keys and does not offer the buttons.
11. As Diego, a `providers.json` with a bad generator (an unknown kind, a missing model, a chosen name that is not declared) stops the engine and the host with the key named.
12. As someone who reads the docs, the configuration guide, the area docs and the Changelog agree with the above.

## Decisions

The choice of a file, `providers.json`, and of the host as the writer of the title is in [0038](../adr/agents/0038-a-text-generator-is-declared-in-providers-json-and-the-chat-host-writes-session-titles-with-it.md); the rest below is what the ADR leaves to the build.

- The shape of the file, the schema in `src/config/providers.ts` next to `accounts`:

  ```ts
  export const textGeneratorKinds = ['lmstudio', 'ollama'] as const;
  const textGenerator = z.strictObject({ kind: z.enum(textGeneratorKinds), model: z.string().trim().min(1) });
  // providersFileSchema gets: textGenerators: z.record(z.string(), textGenerator).default({}), textGenerator: z.string().optional()
  // and a superRefine: textGenerator, when present, is a key of textGenerators
  ```

  A name follows the account's rule (`optionNamePattern`).
- The strict schema is the reason for the capability: a host without `textGenerators` in its hello refuses the keys, so the app writes them only while it is there, as it does `accountIdentity`.
  The engine and the chat host are one package, `carrier`, and the app checks the host it talks to; an engine that is older than the host in the same install is the update flow's case ([0022](../adr/release/0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md)) and not new.
- The three capabilities, `textGenerators`, `regenerateTitles` and the existing case `regenerateTitle` of the app, are added to `ChatCapability` and `capabilities` of `src/chat/server.ts`, and the golden `macos/Tests/Fixtures/capabilities.json` is rewritten with `UPDATE_FIXTURES=1`; the `unannounced` entry of `ContractTests.swift` goes, since a host now announces it.
- `titleSource` is a column of `sessions` with a migration (`pnpm db:generate`), null for a row that existed.
  The first message of a session sets `first_line`, the generator `generated` and `rename` `renamed`.
- The retry is "at the end of the session's next turn, while the title is still the first line", not a watch on the server: the host holds no watch on a server today and the person's server is normally up.
- The fixed system message of the title is in the code and is not a setting; letting the person write it, as the dictation cleanup does, waits for someone to ask.
- The bulk action goes over the sessions of the list and the archive and not over children, one at a time, and a failure of one is logged and skipped and does not stop the rest.
- A session being titled that is deleted meanwhile is dropped; the write is `update ... where id = ?` and touches nothing when the row is gone.

Testing seams, story by story:

- Stories 1 to 5 and 6 (host): `src/chat/sessions.test.ts`, which drives `createSessions` with the fake runner and a temp SQLite, plus a fake text generator that answers, fails, hangs or answers an empty text; the assertions are the stored `title` and `titleSource` and the log.
  A first-line row without `titleSource` is built directly in the table to pin the legacy rule.
- Story 6 and 7 as requests: `src/chat/server.test.ts`, the strict request union and its replies, with the refusal when no generator is chosen.
- The HTTP implementation of the port: a unit test with an injected `fetch`, as `listLocalModels` is tested with an injected `fetchJson`: the request it sends (system and user messages, no tools, the model), a reply with no text, a 404 for a missing model, a time-out.
- Stories 9 and 11 and the engine side: `src/config/providers.test.ts`, the schema on good and bad files (an unknown kind, an empty model, a `textGenerator` that is not declared, both keys absent), and `src/config/load.test.ts` for the engine accepting them.
- Story 8: `src/chat/providers.test.ts` for the generator in use in the reply, and `ProvidersPageTests.swift` for what the group shows from a `HostProviders` (running, not running, no model, the chosen one).
- Stories 9 and 10 in the app: `ProvidersFileTests.swift`, a pure function from the file's bytes to the file's bytes that keeps the keys it does not know and refuses a file it cannot read, and `ChatHostTests.swift` for the requests and for what the app does while the hello lacks a capability.
- Story 10 and the contract: `src/control/capabilities-contract.test.ts` with `ContractTests.swift`.
- Story 8 and 6's menu entry as drawn: no unit tests, a view; it is checked in the real app against the fixture server as `macos-ui-change` says, and its piece and its states go in [ui](../ui.md) and `docs/macos/`.
- Story 12: no tests, prose; the AGENTS rule that changing a schema updates `docs/configuration.md` and the Changelog check are the gate.

## Out of scope

- External APIs as a kind of text generator, and where their keys would be kept.
- A use-to-generator map, and any second use of a generator (summaries, commit messages, PR descriptions).
- Moving the dictation cleanup onto the text generator.
- A title written by an agent CLI.
- Renaming a session by the host when the person has renamed it.
- A base URL for a server on another port, and a setting for the title's prompt.

## Open questions

- Which local model and which prompt give titles good enough in Spanish and English mixed, and how long a title takes: a prototype against real sessions settles it, and it comes before the slice that writes titles is built.
