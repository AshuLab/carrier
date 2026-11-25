# Settings: the App group

The pages of the App group of [Settings](settings.md).

## General

The General page (`GeneralTabView` in `Carrier/Features/Settings/GeneralTab.swift`) changes the icon style, the animation and "Show epics in the menu" (`menu.iconStyle`, `menu.animate`, `menu.showEpics`); the keys of the App pages are read by `CarrierCore/AppPreferences.swift`.
The bar of the menu icon bounces only while the setting is on, the screens and the Mac are awake and Low Power Mode is off (`iconAnimates`).
The window hiding does not stop it, as it is there to be seen with the window closed, but it costs the window server about four points of a core.
The row says "except in Low Power Mode", so a switch that is on with no bounce is explained.

## Providers

Settings has a Providers page (`Carrier/Features/Settings/Providers/ProvidersTab.swift`, `SettingsPage.providers`, in the App group) for the AI providers of this Mac: Claude Code, Codex, Antigravity and the local servers LM Studio and Ollama.
It is three screens of one form, each a place of the window's history, so ‹ › and the toolbar's title follow them (`SettingsPlace`, `SettingsTitle`): the list, one provider, one account.
The list (`providersDirectory`, `ProvidersDirectoryTests`) has a filter that finds a provider, an account or a server by its name, then **Accounts that need attention**, **AI providers**, **Local servers** and **Text generators**.
An account needs attention when it is signed out or at 90 % or more of its 5h window (a provider that is not installed has none: there is nothing to sign in to); the first five are listed, the rest behind Show N more, and one opens straight at its account, with back going to its provider.
A provider only says how many accounts it has and whether any needs attention (All signed in, 1 account needs attention, Could not check), or its own state when it has none (Not installed, Found, not added); usage and sign-in are an account's, never pooled by provider.
A provider screen has its **Accounts**, each saying who uses it (a role of `engine.json`, a repo's override of a role, a failover list (only while failover is enabled) or a chat agent of `chat.json`; without `chat.json` the chat's default agents `claude` and `codex` use the accounts of that name), where its login lives and, at the right, its **own usage**: the 5h and Weekly bars of the Usage page (`QuotaBar`, the hatched part is what the next reset gives back, orange from 90 %), when the 5h resets and Stale when the numbers are the last known (`accountUsage`, from the host's quotas of that account; a window of a model or a limit, such as Claude's Opus weekly or Codex's Spark, is left to the Usage page).
A signed-out account has Sign in in the place of its bars, and tokens and cost stay on the Usage page (Open Usage, under Details, which also has the version and path with Update, and Check again).
A local server shows its models, or that it is not running.
An account's screen is its editor: Display name, Label, Icon and Color (a button that opens its choices in a popover), Binary path, Config folder and, for Claude and Codex, Advanced; Save, or Add on the form that adds one, is the toolbar's and is on only while something changed and nothing is wrong, and Remove is the last row.
The Settings search also finds the providers, accounts and servers of this Mac (`providersSearchEntries`) and opens their screen.
The state is the chat host's `providers` reply (`ProvidersStore`, asked when the page opens, when the app becomes active and on Check again, with the quotas of `UsageStore`); a host that is not running, one too old to list `providers`, one that fails, and a `providers.json` that does not match each say so in words in place of the page.

- **Sign in and Update** (`CarrierCore/ProviderTerminal.swift`, tested in `ProviderTerminalTests`): a signed-out account shows Sign in and a found tool shows Update beside its version and path; both open Terminal with the app's one-use script and opener (`openScript`, `WorkspaceTerminalOpener`).
  The command is built from a closed list, harness by action, every value single-quoted: `CLAUDE_CONFIG_DIR='<folder>' 'claude' '/login'`, `CODEX_HOME='<folder>' 'codex' 'login'`, `'agy'` (the variable only when the account has a folder), and `'claude' 'update'`, `'codex' 'update'`, `'agy' 'update'` (none of them can only check, they install).
  The account's `command`, when set, is the binary that runs; it and the folder are accepted only as absolute paths, and a harness outside the list is refused before anything is written.
  With `--fixture` the opener is `FixtureTerminalOpener`: it logs the line to stderr (`carrier: fixture terminal: ...`) and removes the script, so nothing opens.

- **Text generators** (the last group of the list, hidden while the filter has text; `textGeneratorsGroup` in `Carrier/Features/Settings/Providers/ProvidersTextGenerators.swift`, the rows in `providersPage`, tested in `ProvidersPageTests`): the model that writes text for Carrier, a model of LM Studio or Ollama.
  The first row, In use, says which one the host reports (`qwen3:8b on Ollama`, from the `textGenerator` of the `providers` reply) or "None chosen", and has Clear while one is.
  Under it each server has a row: "Not running" (it answers nothing; it cannot be chosen) or "No model loaded" (it runs with none) and nothing to choose, or a select with Not used and the models the server lists (LM Studio's embedding models left out, as in Local servers).
  The select shows the model in use on its server, even one the server no longer lists, and choosing another model replaces the choice; Not used on the server in use clears it.
  A choice is the `setTextGenerator` request, which writes `textGenerators.<server>` (`{ kind, model }`, the entry named after the server) and `textGenerator` in `providers.json`, in place of the entry the app wrote before, and Clear removes both (`ProvidersStore.chooseTextGenerator`, `ProvidersRequestsTests`).
  An entry the person wrote by hand stays, and so does every other key; a file that is not a JSON object, or whose `textGenerators` is not a map, is never overwritten.
  The reply says what the engine did with the file (`engine`), and a refusal shows under the group with the key it names.
  Nothing is written, and no choice is offered, while the host's hello does not list `textGenerators` (an older `carrier` would refuse the whole file): the group says to update carrier and restart the chat host.
  Once a generator is chosen and the host's hello lists `regenerateTitles`, the group also shows "Titles of earlier sessions" with a Write titles button (`ProvidersStore.regenerateTitles`) that starts titling every active and archived session whose title is still its first line in the background, and says how many it started, that nothing needed a title, or the host's refusal.
  The new titles appear in the sidebar as the host writes them, with no progress bar of its own.

The app reads `providers.json` (`CarrierCore/ProvidersFile.swift`) and never writes it: each change is a request that Carrier's own code answers (`ProvidersStore`, `ProvidersRequest`), over the chat host's socket when its hello lists `config` and through `carrier config` otherwise, and the reply says what the engine did with the file, which the page shows as it shows any save.
When the app opens (once the chat host answers) and the file is missing, `createFileIfMissing` asks (`setAccounts`) for one account per harness the host found, named after it, and nothing when none was found; with a file there it asks for nothing, so an account the person removed stays removed.
A harness found with no account is the tool's "Found, not added" row with an Add button, which asks for the account and then asks the host again.
Every write keeps the keys the app does not know, writes the whole file in one atomic step as `chat.json` is, and never overwrites a file that is not a JSON object with a `providers` map.
Under `--fixture` the fixture home has a `providers.json` and the fake host's `providers` follows it, so Antigravity shows the row and Add makes it go.

- **Account editor** (`Carrier/ProvidersEditor.swift`; the checks while typing are `CarrierCore/ProvidersEdit.swift`'s, tested in `ProvidersFileTests`; the writing is the `editAccount` request): an account's screen (a row of the provider's accounts opens it) has its fields: Display name, Binary path, Config folder (`CLAUDE_CONFIG_DIR` or `CODEX_HOME`), Auto-compact after, Launch arguments (one per line) and, for Claude only, Compact idle threads (Use default, which removes `idleCompaction`, or Never).
  Antigravity has only Display name and Binary path.
  A filled field writes its key and an emptied one removes it (`editAccount`), and every other key of the account stays.
  Add account (Claude Code and Codex) takes a name and a config folder and writes `{ harness, configDir }` (`addAccount`).
  When another account of the same tool already has that config folder (`~` expanded, a trailing slash ignored; an account with no folder has the tool's own, `~/.claude` or `~/.codex`), the form says so in a quiet line (`accountSharingFolder`), naming the account by its display name, because it is the same login and not a new one.
  The editor says it only once the folder field differs from what is saved, so an account that shares a login on purpose is not told so every time it is opened.
  It is not a problem and does not stop the save, since two accounts may share a login for another model or other arguments.
  Remove (`removeAccount`) is refused while a role, a repo's override, a failover list (even one that is off, which the engine still checks) or a chat agent names the account, and says which; the host reads `engine.json` and `chat.json` for that just before it writes, and a `chat.json` (or `engine.json`) that is there and cannot be read stops it.
  Before asking, the app applies the engine's rules for what it can check cheaply (`draftProblems`: the name's pattern, Auto-compact's range per harness, absolute paths, the flags Carrier sets itself, nothing Claude-only on Codex or Antigravity) and says what is wrong in words that name the field; it never asks for what those rules refuse; Node checks the whole file again and refuses with the key path and kind.
  Save, Remove and Add account close their editor when the reply comes (`ProvidersStore.change` gives back then, with the engine's answer in it); the new look at the host happens after, in the background (`ProvidersStore.settled` waits for it), and a `problem` the host answers is shown in place of the page with its key (the file stays as written).
  The editor also has a Label, an Icon and a Color for the account (`ProviderIdentity`, read by `ProviderIdentityStore` and drawn by `AccountMark` in the message box's button and tabs, the sidebar rows, the footer of an answer, the banner of a failed turn, the account blocks of Usage that have a header of their own, the account rows and the epics' avatar corner). An account with no icon shows its tool's mark, looked up by the agent's harness (`AgentAccounts.harness(of:)`, from the host's `agents`) and not by the name the person gave the account, in the color it was given; only a tool with no mark shows a letter. They are offered only while the host's hello lists `accountIdentity` (`ProvidersStore.identityEditable`): an older `carrier` refuses a `providers.json` that has them, accounts and all, so with one the editor says to update it and writes none of the keys.
  Where there is little room an account is called by its label, else its display name, else its key (`ProviderIdentityStore.shortName`).
  The editor offers 24 icons (the tool's mark, a letter and 22 glyphs) and 13 colors; the first 12 icons and 8 colors are the ones every `accountIdentity` host knows, and the rest only while the hello also lists `accountPalette` (`ProvidersStore.paletteEditable`, `AccountIcon.offered(palette:)`), since the older host refuses the whole file with one. A later value already in the file stays on the list. Every control of the form is one width (`AccountEditor.controlWidth`, the selects' 210 pt), and Icon and Color open their choices in a popover, in the same eight-column grid of 30 pt tiles.
  A save of `providers.json` ends by asking the engine to reload, like every other writer, so a running engine applies the accounts with no restart.
  Under `--fixture` the fake host's `providers` follows the file (a display name, binary, folder, a Remove giving the tool its "Found, not added" row back), so each of these can be done against the fixture folder.

## Notifications

The Notifications tab (`CarrierCore/NotificationsTab.swift`, the logic in `CarrierCore/Notifications.swift`) has four groups (Carrier, Chat, Delivery and Permission).
What to tell me: Needs you and Ready for test (user defaults `notify.needsYou` and `notify.readyForTest`, on by default) and A problem (`notify.problem`, off by default), which says once when the snapshot's `problem` text appears or changes, once when GitHub starts refusing a watched repo (until it recovers) and once when Carrier stops without the app having asked: Stop in the menu and the chat host's own start (`ChatHostStarter`) call `NotificationWatcher.expectStop()`, which lapses after 30 seconds.
Delivery: Only when Carrier is not in front (`notify.onlyWhenAway`, on by default), which holds the banner back while the app is active (`shouldPresent`; the test notification always shows).
Play a sound (`notify.sound`, on by default) sets whether a banner plays the notification sound; the style of the banner belongs to macOS, per app, in System Settings › Notifications › Carrier.
Permission shows what macOS says (`UNNotificationSettings`: allowed with banners, alerts or None and the sound on or off, denied, not asked, or only from `Carrier.app`), Open System Settings (always, to change those), Allow (when it has not been asked) and Send a test, which says why instead when macOS would swallow it.
A click on a notification opens the window, on the epic when it is about one (the repo and issue travel in the notification's `userInfo`; the delegate is attached at launch so a click on an older notification works too).

## Terminal

The Terminal page (`Carrier/Features/Terminal/TerminalTabView.swift`, `SettingsPage.terminal`, in the Workspace group after Sidebar) configures the embedded Ghostty terminal via `AppPreferences.terminal` (`terminal.*` keys) with the toolbar's Reset (`AppPreferences.reset(.terminal)`).
Appearance lets you keep the global app theme or choose a terminal-only `Theme` override, adjust Ghostty's `minimumContrast` (`1.0...21.0`) and horizontal/vertical padding (`0...32 pt`) and inspect a live `SettingsPreview` rendered from `TerminalAppearanceProfile`.
Typography inherits `Appearance > Code and output` by default ("Same as Appearance") or overrides font family (`MonospaceStyle.installedFamilies`, preserving any saved custom family), point size (`9...24 pt`), ligatures and font thickening (`fontThicken`).
Cursor sets `cursorStyle` (`Block`, `Bar`, `Underline` via `SegmentedChoice`) and `cursorBlink`.
Panes toggles `dimInactivePanes` (dimming unfocused panes in a split) and `focusFollowsMouse` (moving active focus as the pointer hovers across split panes).
Input and scrollback sets `optionAsAlt` (`Off`, `Left Option`, `Right Option`, `Both`), `copyOnSelect` (automatically copying highlighted text to the clipboard) and `scrollbackLimit` (`1 MB`, `10 MB`, `50 MB`, `100 MB`).
Shell and closing controls `pinPromptToBottom` (for new Zsh tabs) and `confirmCloseRunningProcess`.
