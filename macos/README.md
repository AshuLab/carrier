# Carrier.app

Menu bar app for Carrier.
Building needs **Xcode** (see Toolchain).

## Install

A person does not build the app: `brew install ashulab/tap/carrier` installs the `carrier` command and `brew install --cask ashulab/tap/carrier` this app in `/Applications` (an Apple Silicon Mac on macOS 26 or later), and the app finds that `carrier` by itself.
`brew upgrade carrier` moves the command and `brew upgrade --cask carrier` the app; the app says which one when their protocols differ.
The app also updates itself: it embeds Sparkle, checks for a new release by itself and asks before it installs, and when it opens at the new version it upgrades `carrier` with Homebrew (log: `<folder>/engine/logs/app-upgrade.log`) and replaces the chat host and the engine that were running when they are free to replace (see the end of [Start Carrier](../docs/macos/lifecycle.md#start-carrier)).
Whether it checks and whether it installs by itself are Sparkle's preferences and have no Settings page yet.
The whole flow is in [releasing](../docs/releasing.md#2-what-the-installed-app-does).
The app is signed ad hoc, not notarized, and the cask clears the quarantine attribute after the download; if macOS still refuses it, see [troubleshooting](../docs/troubleshooting.md#macos-will-not-open-the-app).
[Install](../docs/install.md#uninstall) has the uninstall and what it leaves.
The rest of this file is for developing the app.

## Toolchain

Xcode is required, not just the Command Line Tools.
With the macOS 27 SDK SwiftUI's `@State` is a macro whose plugin ships only with Xcode, so with only the Command Line Tools selected `swift build` fails with `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`.
Install Xcode and select it.
The app builds with the macOS 26 SDK too (the release workflow builds it on `macos-26` with Xcode 26.6; the macOS 27 menu item API is set by key, not by name, so no SDK is needed for it):

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # or: export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcode-select -p                                                  # should print the Xcode path, not .../CommandLineTools
```

`build-app.sh` checks this first: with the Command Line Tools selected it prints how to select Xcode and exits 1 without building.

Workaround, unsupported: `swift build --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk` does build the package under the Command Line Tools (verified), because the older SDK has no `@State` macro.
`swift test` that way was not verified and `build-app.sh` does not use it.

## Build and open

This is how the app is developed; it is not how it is installed.

```sh
cd macos
./build-app.sh          # release build wrapped in Carrier.app (bundle id dev.ashulab.carrier), signed ad hoc
./build-app.sh --open   # same, then opens it
./build-app.sh 1.2.3    # same, with 1.2.3 as the app's version in the plist (0.1.0 when none is given); the release workflow does this with the tag's version

`build-app.sh` also embeds Sparkle (`Contents/Frameworks/Sparkle.framework`, with an rpath so the app finds it) and writes `SUFeedURL`, `SUPublicEDKey` (the content of `update-key.pub`) and `SUEnableAutomaticChecks` into the plist. `CFBundleVersion`, the number Sparkle compares, is `X*10000 + Y*100 + Z` for the version given (1 when none is given); a minor or patch of 100 or more is refused. The app starts Sparkle's updater and asks for a background check when it opens from a bundle that has `SUFeedURL`, never under `--fixture` or `--selftest`. It also writes `NSMicrophoneUsageDescription` (dictation's microphone prompt) and fails when it is missing or empty, as it does for a missing icon.
FluidAudio, WhisperKit and `libghostty-spm` (`GhosttyTerminal`) are linked by the `Carrier` target only, pinned with `exact:`.
`build-app.sh` copies `GhosttyKit_GhosttyTerminal.bundle` into `Contents/Resources`.
`scripts/check-app.sh` builds the app and asserts all of this (the workflow runs it).
`update-key.pub` holds the update key's public half (the private half is the repository secret `SPARKLE_PRIVATE_KEY`, see [releasing](../docs/releasing.md#4-the-update-key)); change it only to start a new key pair. The build number is that `CFBundleVersion`: the same version always gives the same number, and a build with no version is `1`, so a local build is older than any release.
open Carrier.app
```

Check the signature with `codesign --verify Carrier.app` and `codesign -dv Carrier.app` (it should say `Signature=adhoc`).

## Test

```sh
cd macos
swift build && swift test
```

The shell's layers have no automated tests (`CarrierTests` only checks that the icon's layer host takes no clicks); the logic behind them is tested in `CarrierCoreTests`.
Its smoke check is the self-test flag: it runs the menu's actions from code, one a second (pause, resume and check now are sent to a running Carrier, resume putting back the pause state it found; Stop is only checked, as it would end the Carrier under test), appends a line per step to the file and ends with a line saying the process was still alive.

```sh
./Carrier.app/Contents/MacOS/Carrier --selftest /tmp/carrier-selftest.log
cat /tmp/carrier-selftest.log   # last line: "end: process still alive ..."
```

With `--fixture` the log also has `rings, window open` and `rings, window closed` (`rings=N animating=M`): the spinning rings of running epics turn only while the window is visible and Reduce Motion is off, so the second line must say `animating=0`.

The app keeps running afterwards; quit it from the menu or with `osascript -e 'tell application id "dev.ashulab.carrier" to quit'`.

## Fixture mode

`--fixture [folder]` runs the app against a fake Carrier, so the window can be looked at with no engine.
The app starts an in-process control server (`CarrierCore/FixtureServer.swift`) on a socket in a temporary folder under `/tmp`, points `CARRIER_HOME` at it and connects as to any Carrier.
It answers `snapshot`, `sessions`, `events`, `epic` and `files` from the golden files in `Tests/Fixtures`, `fileDiff` with the first reply of `reply-filediff.json` for any file (so a file row of any card in the Files changed tab, a lane's included, opens to a fragment), pause, resume, check now, stop, `resumeEpic` and `reload` with a plain ok that does nothing (so a Resume in the fixture is confirmed and the card stays on "Resuming…": the snapshot never changes), and anything else with an error.
A second socket, `<home>/chat/state/chat.sock`, is a fake chat host (the app finds it through `CARRIER_HOME` like the real one at `<folder>/chat/state/chat.sock`): it answers `agents` and `list` from `chat-agents.json` and `chat-list.json`, `events` (by cursor, in pages, as the real host does) from the `chat-events-*.json` files, each naming its session: a finished conversation with markdown, a code block, tool calls, an approval and a failed turn (`chat-events-finished.json`), one with a message streaming (`chat-events-streaming.json`), and a Codex session waiting for an approval with four choices (`chat-events-approval.json`; its card answers through `answer`, which the fixture host records as an event, and the golden finished one has Claude's three); a listed session with no file has no events, one that is not listed is an error, and the worktree requests: `workspace` (by folder, from `chat-workspace.json`; a folder it does not list is a plain one), `fetch` (`chat-fetch.json`), `cloneRepo` (`chat-clone.json`, by `owner/repo`; one it does not list is refused), `createProject` (`chat-project.json`, by name; one it does not list is refused as taken), `githubRepos` (`chat-github-repos.json`, by page, the login on page 1 only; a page it does not list is refused), `suggestName` (cycling through `chat-names.json`'s suggestions) and `checkName` (free unless that file says why not), plus `open` (a session in memory, in a worktree when asked, refused as the host does for a folder that is not a repository, a branch it did not list and an invalid or taken name) and `send` (adds the message to the session's events); anything else is an error too.
`setOption` changes the current value of an option a file lists, or is refused for one it does not list.
So the Sessions + is enabled and a selected session shows a conversation.
`folder` defaults to the copy of the golden files that `build-app.sh` puts in `Carrier.app/Contents/Resources/Fixtures`; give one when running without the bundle.
The temporary folder is removed when the app quits.
In this mode the menu also has "Empty states", a window listing the empty states (`CarrierCore/EmptyStates.swift`).
It combines with `--selftest`.
`--fixture-long-transcript` (with `--fixture`) answers `events` with a made-up transcript of 3,600 events (edits with diffs, passing and failing commands with output) instead of the golden file, to scroll a long one, and every session of the chat host with a made-up conversation of 3,500 events (`longChatEvents`).

Dictation's fixture flags are in [dictation](../docs/macos/dictation.md#under---fixture).

```sh
./Carrier.app/Contents/MacOS/Carrier --fixture
./Carrier.app/Contents/MacOS/Carrier --fixture --selftest /tmp/carrier-selftest.log
```

## Window smoke check

`--smoke-window` opens the window, selects the first epic Carrier reports, waits three seconds, prints what it sees and exits: the minimum content size (980 wide; the height is 600 plus the 52 point title band), the width of the sidebar (268) and of the inspector (316), one `scroll pocket` line per scroll pocket (the epic view's pipeline bar makes one in the centre column, at x 268, taller than the 52 point title band) the toolbar items (Sidebar, Open PR and Open issue when the epic has them, Inspector), a `sessions home:` line (what the Sessions home says under its title, and `listed` or the empty state it shows), a `transcript:` line saying how the Agent output tab is laid out (`lazy stack, pinned section headers`, read from the constants the view itself uses) and a `transcript merge:` line, the time to merge a made-up transcript of 5,004 events (a few milliseconds).
It then selects the first session the chat host lists and, a second and a half later, prints a `chat transcript:` line (how the conversation is laid out, from the constants of its view: a lazy stack, pages of 200 events, polled every 250 ms) and a `chat feed:` line (the rows the model makes of that session's events, how many of them are runs of tool calls, asked of the chat host as the view does, and the time it took).
It needs a screen and combines with `--fixture`.

```sh
./Carrier.app/Contents/MacOS/Carrier --smoke-window --fixture
```

## What the app does

How the app looks is in [macos-ui](../docs/macos-ui.md); what it does, area by area, is in `docs/macos/`; where each area lives in the code is in [AGENTS.md](AGENTS.md).

- [The app shell](../docs/macos/app-shell.md): the Dock and menu bar app, the window, the sidebar and its shortcuts, epics and file icons.
- [Starting Carrier and the chat host](../docs/macos/lifecycle.md): Start Carrier, the chat host, version checks and replacement.
- [Settings](../docs/macos/settings.md): the sheet and its rail, with a page per group: [App](../docs/macos/settings-app.md), [Chat](../docs/macos/settings.md#sessions-page), [Carrier](../docs/macos/settings-carrier.md) and [Legacy](../docs/macos/settings-legacy.md).
- [Sessions](../docs/macos/sessions.md): the Sessions home, the Archive and the conversation.
- [New session](../docs/macos/new-session.md): the plan, the workspace and the preparation.
- [Usage](../docs/macos/usage.md): the quotas and the consumption.
- [Dictation](../docs/macos/dictation.md): the recognizers, the speech models and the capture.
