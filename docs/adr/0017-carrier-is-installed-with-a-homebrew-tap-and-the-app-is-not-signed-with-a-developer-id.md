# 0017 - Carrier is installed with a Homebrew tap, and the app is not signed with a Developer ID

- Status: accepted
- Date: 2026-10-30

## Context

Carrier is the engine, the chat host (both are the npm package `@ashulab/carrier`, which is not published yet) and a macOS app. Today a person gets it by cloning the repo, running `pnpm`, building the app with Xcode and telling the app where `node`, `carrier` and the `PATH` are. The people who would use it are developers, who already need `git`, `gh` and a provider CLI (Claude Code or Codex).

The owner has an Apple account without the paid Developer Program, so there is no Developer ID certificate and no notarization. A downloaded app that is not notarized is stopped by Gatekeeper, and Homebrew puts the quarantine attribute on every cask it downloads (verified with Homebrew 7.0.11).

## Decision

Carrier is installed with Homebrew from our own tap, `AshuLab/homebrew-tap`: `brew install ashulab/tap/carrier` installs the formula, and the cask of the same name installs the app. The formula depends on `node`, `git` and `gh` and installs the npm package, published as `@ashulab/carrier`; the cask depends on the formula and on Apple Silicon with macOS 26 or later. A formula and a cask with the same name live in one tap (verified).

The app is built in a release workflow and signed ad hoc, not with a Developer ID. The cask removes the quarantine attribute in a `postflight` step (verified: Homebrew applies it, the step clears it). Nothing else about the app's trust is asked of the person.

The npm package, the formula, the cask and the app share one version, and one release publishes all four. The app and `carrier` are told apart by the protocol of their sockets' hello, not by version: the app complains only when the protocol does not match.

`brew uninstall` removes the formula and the cask and leaves the Carrier folder; `--zap` removes only the app's own preferences.

## Alternatives considered

A setup screen in the app that runs `npm install -g` for the person. It cannot install Node, so someone without Node is stuck at the first step, and it is the thing Homebrew already does with `PATH`, upgrades and dependencies.

Bundling Node inside `Carrier.app`. It adds about 141 MB, nested binaries to sign, the JIT entitlements of the hardened runtime and a native module (`better-sqlite3`) to rebuild against it, to serve people who already have a development environment.

A Node single-executable archive, as T3 Code ships. It is right for an audience that includes Windows, Linux and people with no development environment; ours is developers on a Mac, and the archive would be arm64-only on macOS.

Paying for the Developer Program to sign and notarize. It makes the app open with no trick and is the way out if the audience grows, but it costs every year and adds a notarization step to a release that has none yet. The release leaves the place for it: the signing happens before the app is zipped.

Leaving the app out of Homebrew for now. It would keep the release to the formula, but it leaves the app, which is the point of the product, as the one thing a person still has to build.

A launchd service for the engine ([0010](0010-carrier-runs-in-the-background-as-a-detached-process.md) already rejected it), and a server updater with rollback like T3 Code's. Neither is needed while nothing starts Carrier but a person.

## Consequences

A person needs Homebrew, an Apple Silicon Mac on macOS 26 or later for the app (the formula, being JavaScript, installs on Intel too), and their own provider CLI and logins; Carrier does not install them. What is missing is the Health tab's business.

The tap is code that Homebrew runs with the person's privileges, so Homebrew 7 refuses to load a formula of a non-official tap until it is trusted. Installing by the full name (`ashulab/tap/carrier`) trusts only that item, which is the command the documentation gives; the short name needs `brew trust --formula`.

The release needs an npm token and a token that can push to the tap as secrets of the repo, and a macOS runner (`macos-26` has Xcode 26.6; the app is developed against a newer SDK, so that it compiles there is to be checked, not assumed).

The `postflight` step is a way around Gatekeeper that Homebrew discourages for its own repository; it is acceptable in our tap because the audience is the owner's own people, and it stops being acceptable the day the app is distributed to people who do not know the author.

The Settings fields `node`, `carrier` and `PATH` go away: the formula installs a `carrier` with an absolute `node` in its first line, at a known place. One advanced setting, "use this carrier", stays for development from the repo.

An Intel Mac gets the engine and the chat host but not the app.
