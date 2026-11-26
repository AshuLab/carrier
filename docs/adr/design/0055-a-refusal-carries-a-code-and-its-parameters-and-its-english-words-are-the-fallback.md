# 0055 - A refusal, and every text Node sends a person, carries a code and its parameters, and its English words are the fallback

- Status: proposed
- Date: 2026-11-24

## Context

When the chat host or the engine refuses a request, it answers in English words that the app shows as they are: there are 179 `new ChatRefused('...')` in `src/` (160 thrown, 19 built by factories such as `ghRefusal`), such as "This session is switching to another agent; try again in a moment" and "There is no such session", plus the engine's `ResumeRefused`, `RecoverRefused` and `ReloadRefused` and the fixed errors of both sockets (`invalid JSON`, `invalid request`, `line too long`, `internal error`, `unknown epic`, `unknown file`, `unknown execution`, `github unavailable`).
Some put values into the sentence (`This agent has no option "${id}"; it offers: ...`).
Refusals are not the only English Node sends a person: the doctor's details and fixes, the chat's notices, the details of a preparation step, the reason an epic needs a human, a provider's problem and a usage message reach the app the same way and are shown as they are.
Some of these are stored before they are shown: a failed preparation step, a clone's error, a notice and a cleanup's skipped reason are kept in the chat's events.
And the app reads some of these sentences to decide what to do (`Resume.swift` maps the engine's reason words, `isRepoNotVisible` and `signInLine` test a suffix, `WatchingList.refusalBanner` parses `ReloadRefused`'s prose with a regex), as does the CLI (`status`, `recover`, `restart`).
A translated front-end cannot translate a sentence it receives whole, and a second front-end can only repeat it.

## Decision

A text Node sends for a person to read carries a text code and its parameters next to its English words.
In a reply, a refusal keeps its words in `error` as today and adds the code: `{ id, ok: false, error: 'This session is switching to another agent; try again in a moment', code: 'session.switching', params: {} }`.
Today's reply is `{ id, ok: false, error: string }` on both sockets, so adding keys beside `error` keeps every front-end that predates the codes working unchanged.
In any other place (a doctor check's `detail` and `fix`, a notice, a step's `detail`, a stop reason, a provider's `problem`, a usage `message`), the field keeps its words and gains a sibling `code` and `params`; a stored event stores them too, so a text read back from the database still has its code.
The code is stable and named by what happened, `<area>.<what>`; the parameters are plain values (strings and numbers), never a sentence.
A config problem gives the key path and the kind of problem as parameters, so a front-end can point at the field without reading the sentence.
A front-end shows the words of its copy key for the code ([0054](0054-the-look-the-words-and-the-apps-preferences-have-one-neutral-source-generated-for-each-front-end.md)), and the English words when it does not know the code.
Code that decides by what a text says (the app's and the CLI's) decides by its code instead.
Each code is in a golden list the contract tests read, with an example of its parameters, and `docs/specs/chat-host.md` and `src/control/AGENTS.md` list them.

## Alternatives considered

The engine translates, from a language the front-end names in its hello.
It keeps the front-ends simple, but the words of the product would live in the engine and the front-ends at once, and the engine would need the catalogs.

Codes without the English words.
It is smaller, but an older front-end would show a bare code, and the logs and the CLI would lose their words.

Codes for refusals only.
It is a third of the work, but a Spanish app would still show its doctor, its notices, its preparation steps and why an epic stopped in English.

## Consequences

Every refusal and every such text in `src/` is rewritten once, with its code, file by file; `pnpm typecheck` refuses a `ChatRefused` without a code, since Node strips the types and would not.
The helpers that compute a reason elsewhere (`invalidReason`, `takenBecause`, the account and usage helpers) return a code with it.
About 91 reply assertions in the Node tests and 113 `ControlError.remote` expectations in the Swift tests change shape.
The words stay in English in `src/` for the logs, the CLI and the fallback.
