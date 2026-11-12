# Updates in Settings

Status: spec

The app already updates itself ([carrier-updates-itself.md](carrier-updates-itself.md)): Sparkle checks when it opens and from time to time, and asks before it installs. This is the part of the app that shows it and lets a person drive it. It also shows the engine's own update, the `brew` step that follows an app update.

## What a person sees

- A page **Updates** in the App group of Settings, after Keybindings. It reads and writes Sparkle's own preferences, so it needs no setting of ours and has no Reset.
- **This Carrier**: the version (`CFBundleShortVersionString`), the time of the last check ("Never" until the updater has checked; `updateCheckedText`) and a **Check now** button, dimmed while a check runs.
- **Updates**: *Check by itself* (on by default; Sparkle's `automaticallyChecksForUpdates`) and *Install by itself* (off by default, so Sparkle asks before it installs; `automaticallyDownloadsUpdates`, dimmed while checking is off, because Sparkle cannot install by itself without checking).
- **Check for Updates…** in the Carrier menu, under About Carrier. The updater's controller answers it, so it is dimmed when there is no updater.
- **Engine and chat host**: where the `brew upgrade` of the installed `carrier` stands (`EngineUpdateState`): "Updating Carrier…" with a spinner while it runs, "Up to date" or "Updated" when it ends, and when it fails "Could not be updated" with the notice's text (the last lines of the log, copyable on hover) and a **Try again** button. Only a Homebrew `carrier` older than the app is upgraded; any other install reads "Looked at when the app opens, for a Carrier installed with Homebrew".
- **Try again** looks at the installed `carrier` again and upgrades it if it is still older, then replaces the chat host and the engine by the rules that already exist. It is the person's click: Carrier still never retries by itself, and nothing starts a second `brew` while one runs. The failure notice of the Sessions pages stays and goes when the retry starts.
- With no updater (a fixture, `--selftest`, a `swift run` build with no feed) the page says "This build does not look for updates" and its controls are dimmed.
- The windows that say an update is found, download it and ask to install and relaunch are Sparkle's own. Ours would be a user driver of our own, a decision of its own.

## Decisions

- The page and the menu are the only owners of the controls; the updater starts before the main menu is built so the menu item has a target.
- Tests: the page's place in the rail and the "Last checked" text are pure (`SettingsPage`, `updateCheckedText`); the menu item is checked in `MainMenuShortcutsTests`. The updater itself is Sparkle's, as in the first epic.
