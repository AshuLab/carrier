# 0038 - A text generator is declared in `providers.json`, and the chat host writes session titles with it

- Status: proposed
- Date: 2026-11-21

## Context

A session's title is the first line of its first message ([`titleOf`](../../src/chat/transcript.ts)).
It often reads badly ("ok, mira esto:", a pasted block), and the title is how the person finds a session again, so sessions end up lost in the sidebar and the search.
The app's session menu already has Regenerate title, which asks a host that lists `regenerateTitle`; no host does, so the app answers "the chat host does not support regenerateTitle".

Carrier has no call that takes text and gives text.
The nearest thing is the dictation cleanup ([0030](0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md)): a client in the app over LM Studio's and Ollama's HTTP API, whose server and model live in the app's preferences.
A title is written by the chat host, which cannot read the app's preferences, so the choice of server and model has to live where the host and the app both read it.
The person wants more texts generated later, and models behind external APIs later too, but named no second text.

## Decision

A **text generator** is a model that turns text into text with no tools: a server and a model.
It is declared in `providers.json`, the file the app writes and the engine and the chat host read ([0020](0020-accounts-live-in-a-file-both-processes-read.md)), under two new keys, `textGenerators` (a map by name of kind and model) and `textGenerator` (the name of the one in use), and the app's Providers page shows a group "Text generators" where the person picks the server and the model.
The first kinds are the local servers, LM Studio and Ollama, called on this Mac through their HTTP API.
A kind for an external API comes later and brings its own decision about where a key is kept, because Carrier keeps logins and not keys.

One generator is the one used, named by `textGenerator`, and the only use today is the title.
There is no map from a use to a generator until a second use exists.

The chat host gets a text-generator port, with a fake for its tests, and uses it in two places.
After the first reply of a session ends, the host writes the session a title from the first message and that reply, in the background and without delaying anything.
A `regenerateTitle` request writes it again on demand, and the host lists `regenerateTitle` in its hello so the app's existing menu item works; one action does it for every session whose title is still the first line.
A title the person set with Rename is never replaced by an automatic one; the host records where a title came from to know it.
Only the redacted and cut text of the session ([`transcript.ts`](../../src/chat/transcript.ts)) goes to the model, and the reply is cleaned and capped like any title.

When the generator is not chosen, the server does not answer, the model is missing or the call times out, the title stays as it is, the cause goes to the host's log and the session is never blocked.
The person's one answer that matters here is that the local server is normally running when they work, so the fallback is rare and quiet; the session tries again at the end of its next turn.

Because `providers.json` is read strictly, a host that does not know `textGenerators` refuses a file that has it.
The hello lists a capability for it and the app writes the key only while it is there, as it does for `accountIdentity` and `accountPalette`.

## Alternatives considered

Keeping the choice in the app's preferences, as the dictation cleanup does, and having the app write the title.
The app would have to be open and watching for a title to be written, a host that serves sessions to other clients (the terminal) would never get one, and the host already owns the title.

`chat.json`, the chat host's own file.
It is the host's, but a text generator is not about chats: the dictation cleanup and any later text use it too, and `providers.json` already holds what the Providers page edits.

An agent CLI, Claude or Codex, asked to write the title.
It spends the person's quota on something that is not their work, starts a process and a session per title, and gives the first message the reach of an agent with tools; the reasons of 0030 hold.

Only the manual Regenerate title.
It fixes one session at a time and only when the person remembers, and the problem is the sessions that are never found.

A general text-generation layer with a use-to-generator map from the start.
There is no second use to shape it, so it would be guessed.

## Consequences

Titles need a model running locally; a small model's quality in Spanish and English mixed, and the time a title takes, are measured before the slice is built, as 0030 did.

Every session whose title is a first line is a candidate for regeneration, and the host needs to tell a first-line title, a generated one and a renamed one apart, which the `sessions` table does not do today.

The dictation cleanup keeps its own server and model in the app's preferences for now; moving it onto the text generator is a later decision and not made here.

The first message of a session goes to a model server on this Mac and nowhere else; an external API, when it comes, sends it off the Mac, and that is the decision that comes with it.
