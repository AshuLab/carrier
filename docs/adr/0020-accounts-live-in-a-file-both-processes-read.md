# 0020 - Accounts live in a file both processes read

- Status: accepted; its `enabled` key is superseded by [0021](0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)
- Date: 2026-11-10

## Context

An account, one login of an agent CLI, is declared today in the engine's `config.json` under `providers`, with the folder where its login lives. The chat knows nothing of them: its agents in `chat.json` name only a harness and, optionally, a `command`, so the chat cannot use a second login, and the binary a person points Carrier at is a key that only the chat reads. The settings the app wants to offer for an account (where its binary is, how its CLI compacts, extra launch arguments) are the same for an agent working an epic and for a chat, and a person expects to write them once.

[0016](0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md) keeps three levels of configuration and says no process reads another's. Both the engine and the chat host have to read the accounts, and the chat host must still start with only the Carrier folder.

Detecting the agent CLIs on the Mac would be a natural thing for the app and for `carrier init` to do. If it wrote every account it finds into the engine's `providers`, the engine would count them all as offered, and with two or more it makes each epic wait `limits.optionChoiceSeconds` for a choice that nobody needs to make ([0014](0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md)).

Nobody but the author has data in the old shape, so nothing is migrated.

## Decision

We keep the accounts in one optional file, `providers.json` in the Carrier folder, next to `config.json`. It holds a single key, `providers`, the map of account names that `config.json` held, and each account gains optional keys for its display name, its binary, its compaction, its launch arguments and `enabled`. The engine and the chat host both read it; the app writes it. It is the one exception to "no process reads another's level", and it is a level of its own that belongs to neither process.

`config.json` loses `providers`: a role, a failover list and a repo override keep naming an account by its name, now declared in `providers.json`. `chat.json` loses `harness` and `command`: a chat agent names an `account`. Without the file there is one account per harness, with this Mac's own login and `enabled: false`, so both processes still start from the folder alone.

`enabled` says only whether the account is offered when an epic's agent option is chosen. It does not stop a role, a failover list or a chat agent from naming the account. An account written by hand without it is offered, as every declared provider is today; the ones that detection writes are not, so finding a CLI never changes how an epic starts.

The engine reads the file when it starts, as it reads `config.json`; the chat host reads it each time it opens a session or checks health, so a change reaches the chat without a restart. A file that does not match stops the process that reads it, with the key named.

One detector, in the core, tells which agent CLIs are on the Mac and whether each account is signed in. The app asks the chat host for it, and `carrier init` calls it directly.

## Alternatives considered

Keeping the accounts in `config.json` and letting the chat host read it. It is the least to write and it undoes the reason for 0016: the chat host would need the engine's file to start, and its schema.

Declaring accounts twice, in `config.json` and `chat.json`. Each process stays alone, and the person, or the app, keeps two lists in step; the binary and the compaction would be written twice.

Renaming `providers` to `accounts` everywhere. It matches the word the app uses, and it changes the key of every role, failover list and repo override for a name that is only clearer; the glossary settles the word instead.

Letting detection write nothing and showing only an Add row. Nothing changes for an existing setup, but a new Mac starts with an empty page and a person adding by hand what the Mac already has.

One file per account. Editing one account is simpler and listing them is not, and the names would live in file names.

## Consequences

The chat can use any account of the engine, with its login and binary, and the runtime of an account is written once. There is a fourth place a setting can live, and the glossary and the configuration guide name it.

A `config.json` that still has `providers`, or a `chat.json` agent with `harness` or `command`, is refused with a message that names `providers.json`; the author moves their own block by hand.

The engine does not see an edit of `providers.json` until it restarts. The app's Save footer already says so for `config.json`, and it says it here too.

The file holds paths, names and flags, never a secret; launch arguments are not a place for a token, and a log names an account and a flag, not the values.

`--config` chooses another engine config and not another `providers.json`, which stays in the Carrier folder. `carrier init --out` therefore writes its accounts to the folder's file and says so in its recap.
