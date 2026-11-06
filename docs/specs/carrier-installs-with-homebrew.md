# Carrier is installed with Homebrew

Status: spec

## Problem

Nobody but the author can run Carrier. To get it a person clones the repo, runs `pnpm`, builds the app with Xcode and then types into Settings where `node`, `carrier` and the `PATH` are, because nothing tells the app where Carrier lives. The npm package `@ashulab/carrier` is not published (the registry answers 404), there is no release workflow (the repo has no `.github`), and the app is only ever built on the author's machine, signed ad hoc.

The people Carrier is for are developers who already have `git`, `gh` and a provider CLI, and who install their tools with Homebrew. For them the whole install should be one command, and the app should find Carrier by itself.

We know it is solved when, on a Mac with only Homebrew, `brew install ashulab/tap/carrier` leaves a working `carrier` on the `PATH`, the cask leaves an app that opens with a double click and finds that `carrier` without being told, and a release is something a tag does and not something the author does by hand.

## Solution

The distribution is a Homebrew tap, `AshuLab/homebrew-tap`, with a formula `carrier` (the engine and the chat host: `depends_on` `node`, `git` and `gh`, installing the npm package `@ashulab/carrier`) and a cask `carrier` (the app: depends on the formula, on Apple Silicon and on macOS 26 or later). The install is `brew install ashulab/tap/carrier`; the full name trusts only that formula under Homebrew 7's tap trust, so the person runs no `brew trust`. The decision and what lost are in [0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md); the terms are in the glossary (Homebrew tap, Release).

One release, started by a tag, publishes everything with one version. The tag is the version: the workflow sets it in the runner's copy of `package.json` and in the app's `Info.plist` (`build-app.sh` takes it instead of the `0.1.0` it has written in), and nothing is committed back to this repo. A workflow in `.github/workflows` on the `macos-26` runner typechecks and tests, publishes `@ashulab/carrier` to npm (the `@ashulab` scope already exists and is the author's), builds the app and signs it ad hoc, puts its zip and sha256 on the GitHub Release, and commits the new version and checksums to the formula and the cask in the tap. The secrets are an npm token and a token that can push to the tap. The signing is its own step before the zip, so a Developer ID can replace the ad hoc signature later without touching the rest. The workflow also runs by hand with a dry-run input that does everything up to the publishing and pushes nothing, which is how it is tested before the first tag.

The app is not notarized, because the owner's Apple account is the free one. Homebrew puts the quarantine attribute on the downloaded app and Gatekeeper would stop it, so the cask clears it in a `postflight` step. We tried it on Homebrew 7.0.11: without the step the app arrives quarantined, with it the attribute is gone. This is the weak point of the plan and the ADR says why it is acceptable now: the audience is the author's own people.

The app finds `carrier` in this order: the advanced setting "use this carrier" when it is set, else `/opt/homebrew/bin/carrier` when it is there, else it is missing. It runs the Homebrew one as the program it is, instead of `node <carrier>`: the formula's `bin/carrier` is a symlink to the package's JavaScript with the absolute path of Homebrew's `node` on its first line, and it ran with a `PATH` of only `/usr/bin:/bin`. The Settings fields `node`, `carrier` and `PATH` go away. "Use this carrier" stays under an advanced heading, and it is how the author develops from the repo (a path to `src/terminal/cli/main.ts` still needs a `node`, so the app keeps finding `node` and the `PATH` from the person's login shell, silently, as it does now, without asking for them). The `PATH` the engine and the chat host start with is that detected one with `/opt/homebrew/bin` added when it is not in it, so the `gh` that the formula declared is found even from a shell that never loaded Homebrew. When `carrier` is missing, the Sessions notice and the Health tab ([the epic before this one](health-check-in-the-app.md)) say so, and the Health tab's fix is `brew install ashulab/tap/carrier` in Terminal, in the same list and with the same button as the other fixes.

The app and `carrier` are two things `brew upgrade` can move at different moments. They are told apart by the protocol in the hello of the sockets, not by version. The app has one number it supports and one place that compares it with a hello's: equal, it works as it does today (the chat host is replaced only when no session is working, [E1](chat-in-the-carrier-folder.md)); a hello with a lower number means `carrier` is older and the app says to run `brew upgrade carrier`; a higher one means the app is older and it says to run `brew upgrade --cask carrier`; in both it does not connect.

`brew uninstall` removes the formula and the cask and leaves `~/.carrier` (config, sessions, clones). `brew uninstall --zap` removes only the app's own preferences (`dev.ashulab.carrier`). The documentation says how to delete the Carrier folder by hand.

What lost, besides what [0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md) lists: an Intel app (a second runner and a second build for few people; the formula, being JavaScript, installs on Intel anyway, building `better-sqlite3` from source if it has no prebuilt binary there); a separate version for the app and for `carrier` (it would make every upgrade a compatibility question); a `brew uninstall` that wipes the Carrier folder (it holds the engine's config, sessions and clones, and a command that looks like removing a program should not take them); looking for `carrier` in the login shell as well (it is the old guess the Homebrew prefix replaces, and "use this carrier" covers the one who has it elsewhere).

What we measured, so the spec does not have to guess: the formula installs from a packed tarball in 22 seconds and weighs 355 MB, almost all of it `node_modules`; `carrier --version` and the chat host (which creates `chat.db`, so `better-sqlite3` loads) run on Node 26 as Homebrew installs it; a formula and a cask with one name are both loaded and installed from one tap, the cask's `depends_on formula:` is satisfied; and installing the formula upgraded the machine's Homebrew `node` as a dependency, which is Homebrew's normal behavior.

## Scope

1. A person on a Mac with Homebrew runs `brew install ashulab/tap/carrier` and gets `carrier` on the `PATH`, with `git`, `gh` and `node` installed if they were missing; `carrier --version` prints the release's version and `carrier chat-host` starts.
2. The same command installs the app in `/Applications`; it opens with a double click, with no Gatekeeper dialog and no command typed by the person.
3. The app finds the Homebrew `carrier` and starts the chat host and the engine with it, without any field filled in Settings.
4. Settings no longer ask for `node`, `carrier` or the `PATH`; an advanced "use this carrier" lets the author point at the repo's `main.ts`, and then the app still finds `node` and the `PATH` by itself.
5. With no `carrier` found, the Sessions notice and the Health tab say so and the Health tab offers `brew install ashulab/tap/carrier` in Terminal; coming back from Terminal re-checks.
6. When `carrier` and the app speak different protocols, the app says which one to update with which command, and does not connect to that host or engine.
7. Pushing a tag `vX.Y.Z` publishes the npm package, the GitHub Release with the app's zip and checksum, and the updated formula and cask in the tap, all at `X.Y.Z`; running the workflow by hand with the dry-run input builds and tests everything and publishes nothing.
8. `brew upgrade` moves a person to the new release, `brew uninstall` leaves `~/.carrier`, and `--zap` removes only the app's preferences.
9. The README, the app's README and the troubleshooting guide describe the install, the upgrade, the uninstall and how to delete the Carrier folder, and no longer tell a person to build the app or to fill in `node`, `carrier` and the `PATH`.

## Decisions

The tap, the unsigned app and the `postflight` are decided in [0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md); the Carrier folder in [0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md).

Where `carrier` is. A pure function in `CarrierCore` takes the saved "use this carrier" value and a way to ask whether a file is executable, and returns the path or nothing; the shell detection keeps only `node` and the `PATH` (`Detection`, `parseDetection` and `SetupStore` lose `carrier`):

```swift
let homebrewCarrier = "/opt/homebrew/bin/carrier"
func carrierPath(override: String, isExecutable: (String) -> Bool) -> String? {
    if override.isEmpty == false { return override }   // the author's: taken as typed, the Health tab says if it fails
    return isExecutable(homebrewCarrier) ? homebrewCarrier : nil
}
```

How it is run. A path ending in `.ts` or `.js` runs as `node <path>`, anything else runs itself. `StartChatHost` and the engine start (`StartCarrier`) both go through this one decision.

The protocol rule. One function replaces the five `protocolVersion == 1` guards (`ChatHost`, `ControlMonitor`, `Commands`, `AgentOutput`); it is given the hello's number and answers one of three cases, and a hello with no number keeps being the `badLine` it is today:

```swift
let supportedProtocol = 1
enum ProtocolMatch { case match, carrierOlder, appOlder }
func protocolMatch(_ host: Int) -> ProtocolMatch {
    host == supportedProtocol ? .match : host < supportedProtocol ? .carrierOlder : .appOlder
}
```

The release. The tap's formula and cask are files the workflow rewrites (version, URL, sha256) with the tag's values; they are not generated from scratch. The cask takes the app from the GitHub Release's zip. `build-app.sh` reads the version from an argument and keeps `0.1.0` when it has none, so a local build still works.

Testing seams, per story:

- 1, 2 and 8: no automated tests; they are what Homebrew does with files this epic writes. Verified by hand once from the real tap on the first tag (install, `carrier --version`, open the app, `brew upgrade`, `brew uninstall`), and by `brew audit --strict` on the formula and cask in the workflow.
- 3 and 4: `SetupDetectionTests` (the pure `carrierPath` with a fake `isExecutable`, `parseDetection` with no `carrier` line, the `PATH` with `/opt/homebrew/bin` added once and not twice) and `StartChatHostTests` (the command built for a binary and for a `.ts` path, with the environment, as the existing tests build it). The Settings view has no automated test.
- 5: `HealthFixTests` (the fixed list gains the `carrier` entry; hostile values still run nothing) and `ChatHostNoticeTests` (the notice for a missing `carrier` names the command).
- 6: `ChatHostTests` and the control client's tests with a fake hello, through the one function: equal, lower and higher, and the sentence for each.
- 7: no unit test; the workflow's dry-run input is the test, run by hand before the first tag.
- 9: no tests; docs.

## Out of scope

Signing with a Developer ID and notarizing (the signing step is placed for it; the Developer Program is not paid). An Intel app. Linux and Windows. Submitting to Homebrew's official repository (the `postflight` would not pass its rules, and the audience does not need it). Bundling Node, a single-executable archive, a launchd service and a self-updating server, all rejected in the ADR. Installing `claude`, `codex` or their logins, which are the person's, and checking that they are there, which the Health tab does. The setup wizard that creates the engine's config (the epic after this one). An in-app updater: `brew upgrade` is the updater.

## Open questions

Does the app compile and do its tests pass on the runner's Xcode 26.6? Its README says the build needs the macOS 27 SDK for `@State`'s macro, and the `macos-26` image ships Xcode 26.6 (the author's machine has 27.2). The first slice that builds the app in the workflow answers it. If it does not, the release builds the app on another runner or on a self-hosted one, and that cost is the owner's to weigh.

Does the `postflight` run again, and clear the quarantine, on `brew upgrade` of the cask? The upgrade downloads a new zip and Homebrew quarantines it again; it should, but only an install and an upgrade from the real tap prove it, so it is checked on the second tag.
