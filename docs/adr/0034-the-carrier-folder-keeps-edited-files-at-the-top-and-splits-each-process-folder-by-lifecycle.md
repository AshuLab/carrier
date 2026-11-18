# 0034 - The Carrier folder keeps the edited files at the top and splits each process's folder by lifecycle

- Status: accepted; supersedes the folder layout of [0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)
- Date: 2026-11-17

## Context

[0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md) put everything Carrier owns in one folder, `~/.carrier` or `CARRIER_HOME`, with a subfolder per process.
In use the folder drifted from that rule.
The engine's config sat at the top as `config.json`, while the chat's `chat.json` sat inside `chat/`, so a person looked in two places for the files they edit.
The app wrote its terminals, its dictation history and its downloaded speech models side by side in `app/`, so nothing said which of them could be deleted and which could not.
A shim moved from `terminal/` to `app/terminal/` and left the old folder behind, and a `scratch/` folder appeared that no code reads.
Each place was computed where it was used: the engine's in one TypeScript module, the chat's in three others, the app's in a dozen Swift files, so a change of place meant finding every one of them.

What lives in the folder also differs in how long it lives and what losing it costs.
A config is small and precious, a database is the authority, a log can rotate, a worktree holds work until its owner ends, and a downloaded model comes back with one click.
A backup or a cleanup can only treat these apart if they live apart.

Nobody but the author has data in the folder, so nothing is migrated and no old path is read.

## Decision

The top of the Carrier folder holds only the files a person edits: `engine.json` (the engine's config, formerly `config.json`), `chat.json` (the chat's, formerly `chat/chat.json`) and `providers.json` (the accounts both processes read, [0020](0020-accounts-live-in-a-file-both-processes-read.md)).
Next to them, one folder per process, and only that process writes in it: `engine/`, `chat/` and `app/`.
Two exceptions are accepted.
The app copies the files a person attaches into `chat/pending/`, because the chat is where they are used; the host moves each one into `chat/sessions/<session>/attachments/` when the message is sent and sweeps what was never sent after a day.
The app writes what it saw when it started a process (`app-start.log`) and ran a Homebrew upgrade (`app-upgrade.log`) into that process's `logs/`, next to the process's own logs.

Inside its folder, a process splits what it writes by lifecycle:

- `state/`: what it cannot rebuild (databases, sockets, locks, the app's terminals and dictation history), kept and backed up.
- `logs/`: what it wrote while it ran, rotated and purged.
- work (`repos/`, `worktrees/`, `reviews/`, `projects/`, `sessions/`): folders that belong to an epic, a session or a project, removed when their owner ends.
- `cache/`: what can be fetched or rebuilt (the app's speech models, downloaded again from Settings, and its terminal shim, rewritten at each start), safe to delete and left out of backups.

```
<folder>/
  engine.json, chat.json, providers.json
  engine/  state/ (carrier.db, control.sock, carrier.lock, results/, forge-cwd/), logs/, repos/, worktrees/, reviews/
  chat/    state/ (chat.db, chat.sock, carrier.lock), logs/, worktrees/, projects/, pending/, sessions/
  app/     state/ (terminals.json, dictations.jsonl, dictation-statistics.json, audio/), logs/, cache/ (models/, zsh-bottom-prompt/)
```

Every folder of this layout, and every file another process or the app reaches (the configs, the sockets, the app's start and upgrade logs), is computed from the Carrier folder in one module per language, `src/config/places.ts` and `macos/Sources/CarrierCore/CarrierPlaces.swift`.
A file only its owner touches inside its own folders (a database, a lock, `results/`, `forge-cwd/`, a log) is named where the owner writes it, from the folder those modules give.

## Alternatives considered

Keeping each config inside its process's folder (`engine/engine.json`, `chat/chat.json`).
It follows ownership to the letter, but a person edits these files and should find them in one place, and the processes' folders become pure output that can be inspected or wiped without touching a setting.

Naming the chat's folder `sessions/`.
It names what a person sees, but the folders at the top name the process that owns them, and the chat's sessions already have that word for their own subfolder.

A shared `cache/` or `workspaces/` at the top for every process.
It would make one place to exclude from backups, but today only the app has a cache and every worktree belongs to the clone of the process that made it, so a shared folder would have no shared content.

## Consequences

A person's settings are the three files at the top, and copying them is copying the setup.
`carrier init`, `--config` and the app's Settings read and write `engine.json`; a `config.json` left from before is ignored.
The app's cache can be left out of Time Machine and deleted by hand; the models are downloaded again from Settings and the shim is rewritten at the next start.
Where things go is decided in two files, so a later change of place, like the cleanup of worktrees or the rotation of logs, touches those and their callers only.
