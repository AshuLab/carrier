# Settings: the App group

The pages of the App group of [Settings](settings.md).

## General

The General page (`GeneralTabView` in `Carrier/SettingsTabs.swift`) changes the icon style, the animation and "Show epics in the menu" (`menu.iconStyle`, `menu.animate`, `menu.showEpics`); the keys of the App pages are read by `CarrierCore/AppPreferences.swift`.

## Providers

Settings has a Providers page (`Carrier/ProvidersTab.swift`, `SettingsPage.providers`, in the App group) that lists the AI tools of this Mac: a master-detail with Claude Code, Codex, Antigravity, LM Studio and Ollama.
The list gives each tool its state (Signed in, Signed out, Not installed, Could not check, or Found, not added for a CLI no account has); the detail gives the version and path and, for Claude, Codex and Antigravity, the accounts, each saying who uses it: a role of `config.json`, a repo's override of a role, a failover list (only while failover is enabled) or a chat agent of `chat.json` (without `chat.json` the chat's default agents `claude` and `codex` use the accounts of that name).
A local server shows its models, or that it is not running.
The state is the chat host's `providers` reply (`ProvidersStore`, asked when the page opens, when the app becomes active and on Check again); a host that is not running, one too old to list `providers`, one that fails, and a `providers.json` that does not match each say so in words in place of the page.

- **Sign in and Update** (`CarrierCore/ProviderTerminal.swift`, tested in `ProviderTerminalTests`): a signed-out account shows Sign in and a found tool shows Update beside its version and path; both open Terminal with Continue in Terminal's one-use script and opener (`openScript`, `WorkspaceTerminalOpener`).
  The command is built from a closed list, harness by action, every value single-quoted: `CLAUDE_CONFIG_DIR='<folder>' 'claude' '/login'`, `CODEX_HOME='<folder>' 'codex' 'login'`, `'agy'` (the variable only when the account has a folder), and `'claude' 'update'`, `'codex' 'update'`, `'agy' 'update'` (none of them can only check, they install).
  The account's `command`, when set, is the binary that runs; it and the folder are accepted only as absolute paths, and a harness outside the list is refused before anything is written.
  With `--fixture` the opener is `FixtureTerminalOpener`: it logs the line to stderr (`carrier: fixture terminal: ...`) and removes the script, so nothing opens.

`providers.json` is the app's to create (`CarrierCore/ProvidersFile.swift`, `ProvidersStore`).
When the app opens (once the chat host answers) and the file is missing, `createFileIfMissing` writes one account per harness the host found, named after it, and nothing when none was found; with a file there it writes nothing, so an account the person removed stays removed.
A harness found with no account is the tool's "Found, not added" row with an Add button, which writes the account and asks the host again.
Every write (`applyingAccounts`) keeps the keys the app does not know, writes the whole file in one atomic step as `chat.json` is, and never overwrites a file that is not a JSON object with a `providers` map.
Under `--fixture` the fixture home has a `providers.json` and the fake host's `providers` follows it, so Antigravity shows the row and Add makes it go.

- **Account editor** (`Carrier/ProvidersEditor.swift`; the rules and the writing are `CarrierCore/ProvidersEdit.swift`'s, tested in `ProvidersFileTests`): each account row has Edit, which opens its fields under the accounts: Display name, Binary path, Config folder (`CLAUDE_CONFIG_DIR` or `CODEX_HOME`), Auto-compact after, Launch arguments (one per line) and, for Claude only, Compact idle threads (Use default, which removes `idleCompaction`, or Never).
  Antigravity has only Display name and Binary path.
  A filled field writes its key and an emptied one removes it (`applyingEdit`), and every other key of the account stays.
  Add account (Claude Code and Codex) takes a name and a config folder and writes `{ harness, configDir }` (`applyingNewAccount`).
  Remove (`applyingRemoval`) is refused while a role, a repo's override, a failover list (even one that is off, which the engine still checks) or a chat agent names the account, and says which; `ProvidersStore` reads `config.json` and `chat.json` for that, and a `chat.json` that is there and cannot be read stops it.
  Before writing, the app applies the engine's rules for what it can check cheaply (`draftProblems`: the name's pattern, Auto-compact's range per harness, absolute paths, the flags Carrier sets itself, nothing Claude-only on Codex or Antigravity) and says what is wrong in words that name the field; it never writes a file those rules refuse.
  After a save the store asks the host for `providers` again, and a `problem` it answers is shown in place of the page with its key (the file stays as written).
  A save of `providers.json` ends by asking the engine to reload, like every other writer, so a running engine applies the accounts with no restart.
  Under `--fixture` the fake host's `providers` follows the file (a display name, binary, folder, a Remove giving the tool its "Found, not added" row back), so each of these can be done against the fixture folder.

## Notifications

The Notifications tab (`CarrierCore/NotificationsTab.swift`, the logic in `CarrierCore/Notifications.swift`) has three groups.
What to tell me: Needs you and Ready for test (user defaults `notify.needsYou` and `notify.readyForTest`, on by default) and A problem (`notify.problem`, off by default), which says once when the snapshot's `problem` text appears or changes, once when GitHub starts refusing a watched repo (until it recovers) and once when Carrier stops without the app having asked: Stop in the menu and the chat host's own start (`ChatHostStarter`) call `NotificationWatcher.expectStop()`, which lapses after 30 seconds.
How: Only when Carrier is not in front (`notify.onlyWhenAway`, on by default), which holds the banner back while the app is active (`shouldPresent`; the test notification always shows).
Play a sound (`notify.sound`, on by default) sets whether a banner plays the notification sound; the style of the banner belongs to macOS, per app, in System Settings › Notifications › Carrier.
Permission shows what macOS says (`UNNotificationSettings`: allowed with banners, alerts or None and the sound on or off, denied, not asked, or only from `Carrier.app`), Open System Settings (always, to change those), Allow (when it has not been asked) and Send a test, which says why instead when macOS would swallow it.
A click on a notification opens the window, on the epic when it is about one (the repo and issue travel in the notification's `userInfo`; the delegate is attached at launch so a click on an older notification works too).
