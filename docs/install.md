# Install, upgrade and uninstall

## Requirements

- A Mac with [Homebrew](https://brew.sh). The install below brings Node.js 22 or newer, `git` and the GitHub CLI (`gh`) if they are missing. The app needs an Apple Silicon Mac on macOS 26 or later. Working from a clone needs Node.js 26 and pnpm 12.
- At least one of the `claude`, `codex` and `agy` (Antigravity) CLIs, installed and logged in from the terminal where you run Carrier. For local models, LM Studio or Ollama running.
- A GitHub identity for each role: [Agent Forge](https://github.com/AshuLab/agent-forge) bot profiles, or your own `gh` login. Two different ones is the clean way; if you cannot get a second one, pick the same for both and they share it: what they publish is signed with their role, and both then act with everything that login's token can do.
- The target repos use the [Solve](https://github.com/AshuLab/skills) flow (see [preparing a repo](preparing-a-repo.md)).

## Install

```bash
brew install ashulab/tap/carrier          # the `carrier` command
brew install --cask ashulab/tap/carrier   # the app, in /Applications (optional)
```

The first installs the `carrier` command (with `node`, `git` and `gh` if they are missing). A formula and a cask have the same name, so the app needs `--cask`; it depends on the command, and Homebrew installs that first if it is missing. Open the app with a double click: it finds `carrier` by itself, so there is nothing to fill in. Use the full names: it trusts only that formula under Homebrew's tap trust ([ADR 0017](adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)). The app is signed ad hoc, not notarized, and the cask clears the quarantine attribute for you; if macOS still refuses to open it, see [troubleshooting](troubleshooting.md#macos-will-not-open-the-app).

Without Homebrew, the command alone installs with `pnpm add -g @ashulab/carrier` (or `pnpm dlx @ashulab/carrier` to run it without installing). To work on Carrier itself, clone the repo and run `pnpm install`; the app is built from the clone as [`macos/README.md`](../macos/README.md) says.

## Upgrade

```bash
brew upgrade carrier          # the command: the engine and the chat host
brew upgrade --cask carrier   # the app
```

Both move to the same release. They can be upgraded at different moments, and when they speak different protocols the app says which one to update and does not connect until you do ([troubleshooting](troubleshooting.md#the-app-asks-to-update-carrier-or-itself)).

If you have the app you do not have to type these. It checks for updates by itself (with [Sparkle](https://sparkle-project.org), once a day and each time it opens), asks before it installs, and relaunches. When it opens at the new version and the installed `carrier` is older, it runs `brew update` and `brew upgrade` for `carrier` (the log is `~/.carrier/engine/logs/app-upgrade.log`), and then replaces the chat host and the engine that were running, each only when it is free to replace: the host when no session is working or waiting for an approval, the engine when it has no execution in flight (an engine you had stopped stays stopped). If Homebrew fails, the app keeps what you had and says why on the Sessions home. Whether the app checks and whether it installs by itself are Sparkle's own preferences and have no page in Settings yet. What Sparkle compares is the app's build number, derived from the version (`X.Y.Z` is `X*10000 + Y*100 + Z`). The update flow, the update key (its public half is `macos/update-key.pub`) and what to do if something fails are in [releasing](releasing.md) and [troubleshooting](troubleshooting.md#the-app-never-shows-an-update). Without the app, Homebrew tells nobody there is a new version: run the two commands.

## Uninstall

```bash
brew uninstall --cask carrier   # the app first: it depends on the command
brew uninstall carrier          # the command
```

This leaves `~/.carrier` (or your `CARRIER_HOME`), with your config, sessions and clones. Add `--zap` to the cask (`brew uninstall --zap --cask carrier`) to remove also the app's own preferences (`~/Library/Preferences/dev.ashulab.carrier.plist`) and its cache, where the updater keeps what it downloads (`~/Library/Caches/dev.ashulab.carrier`), and nothing else.

To remove the Carrier folder as well, stop Carrier first (`carrier stop` and `carrier chat --stop`), then delete it by hand:

```bash
rm -rf ~/.carrier
```

That deletes everything in it, for good: `config.json`; `providers.json`; `engine/` (its `state/` with `carrier.db`, the control socket and the lock, its `logs/`, the managed clones in `repos/`, the reviewer's checkouts in `reviews/` and the epics' `worktrees/`); and `chat/` (its `state/` with `chat.db`, the chat socket and the lock, its `logs/`, the repositories it cloned in `projects/`, the session `worktrees/` and `chat.json`). Commit and push any work you want to keep from those worktrees first. See [Where it keeps things](#where-it-keeps-things).

## Where it keeps things

Carrier's folder is `~/.carrier/` (override it with `CARRIER_HOME`). The engine's config is `~/.carrier/config.json`. The accounts, one per login of an agent CLI, are in `~/.carrier/providers.json` ([ADR 0020](adr/0020-accounts-live-in-a-file-both-processes-read.md)): the one file besides `config.json` that both the engine and the chat host read (the engine when it starts, the chat host at each request), and the app writes it. The engine's schema is `src/config/schema.ts`, the accounts' is `src/config/providers.ts` and the chat's is `src/chat/config.ts`. The chat keeps everything else it owns in `~/.carrier/chat/`:

- `chat/state/` — the chat host's `chat.db`, `chat.sock` and lock; `chat/logs/` — its logs; `chat/projects/` — the repositories it clones; `chat/worktrees/` — the worktrees of the sessions that ask for one; `chat/chat.json` — its optional settings ([configuration](configuration.md#chat-configuration)).

The engine keeps its files in `~/.carrier/engine/`, in the same Carrier folder; only Carrier writes there, and `--config` changes which config file is read, never this folder:

- `engine/state/` — `carrier.db` (SQLite), `control.sock` and `carrier.lock`.
- `engine/logs/` — `orchestrator.log`, `executions/<id>/` with each agent's full output, and `start.log`. Logs and sessions of a finished or cancelled epic are deleted after 30 days; SQLite and worktrees are never touched.
- `engine/repos/<org>/<repo>/` — managed clones; `engine/reviews/<repo>/<epic>/` — the reviewer's separate checkout.
- `engine/worktrees/<repo>/<feature>/` — where Carrier keeps an epic's worktree by default; any other place works, since Carrier finds a worktree with git.
