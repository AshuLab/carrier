# 0020 - The app updates itself with Sparkle, and the app brings the engine up to date through Homebrew

- Status: accepted
- Date: 2026-11-11

## Context

[0017](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md) installs Carrier from a tap: a formula (the engine and the chat host, from npm) and a cask (the app), one version, one release. After the install nothing moves a person to the next release but their own `brew upgrade`, and nothing tells them there is one. The app is signed ad hoc and not notarized, the owner's Apple account being the free one.

The apps we looked at do this with an updater of their own. T3 Code and Paradev are Electron apps that use `electron-updater` against a feed attached to the GitHub Release. CodexBar, a native Swift app, embeds Sparkle, serves an `appcast.xml` committed to its repository, and declares `auto_updates true` in its cask so that Homebrew leaves the app to Sparkle.

## Decision

The app embeds Sparkle. Its `Info.plist` carries `SUFeedURL`, which is `https://github.com/AshuLab/carrier/releases/latest/download/appcast.xml`, and `SUPublicEDKey`. Each release signs the app's zip with an EdDSA key (the update key), whose private half is a secret of the repository, and attaches a one-item `appcast.xml` to the GitHub Release. The release is created as a draft, gets its zip, pushes the formula and the cask to the tap, gets the appcast, and only then is published, so that `releases/latest` never points at a release without an appcast or at a version the tap does not have. The person chooses whether the app checks by itself and whether it installs by itself; the defaults are to check (`SUEnableAutomaticChecks` is written in the plist, or Sparkle would ask on the second launch) and to ask first. With install by itself, Sparkle installs when the app quits and does not relaunch it; the engine step below runs the next time the app opens, so it does not need the update to be immediate.

The cask declares `auto_updates true`, which tells Homebrew the app can move by itself: Homebrew does not replace an app that Sparkle has already taken past the cask's version. It is not a wall: when the app is older than the cask, `brew upgrade` upgrades it like any cask. Both paths end at the same version, because the release pushes the cask before it publishes the appcast. The formula is Homebrew's.

The app and `carrier` share a version because one tag publishes both. When the app starts after an update and finds the installed `carrier` older than itself, it runs `/opt/homebrew/bin/brew update` and then `/opt/homebrew/bin/brew upgrade --formula ashulab/tap/carrier` with `HOMEBREW_NO_ASK=1` (the app is Apple Silicon only, so the path is fixed; the bare name `carrier` is also the cask's and Homebrew warns about it), then replaces the chat host and the engine that run an older version: the chat host when no session is working or waiting for an approval, the engine, only if it was running, when it has no execution in flight. Starting the engine stays an act of the person ([0010](0010-carrier-runs-in-the-background-as-a-detached-process.md)). If Homebrew fails, the app says so and leaves everything as it was.

The build number, `CFBundleVersion`, is derived from the tag: `X.Y.Z` is `X*10000 + Y*100 + Z`. Sparkle compares it, not the short version.

## Alternatives considered

Only telling the person, and leaving them to run `brew upgrade carrier` and `brew upgrade --cask carrier`. It needs no key and no framework, and it was the first proposal. It makes the person do by hand what every app they use does for them, and the owner asked for the app to do it.

Sparkle with the appcast committed to the repository, as CodexBar does. It works, but every release then commits to `main`, so the workflow needs a token that can push there, and an appcast on `main` can describe a release that is not out yet. A release asset is published with the release and needs nothing more.

A cask without `auto_updates true`. Homebrew would not know the app moves by itself and could replace a Sparkle-updated app with the version the cask names.

An updater of our own, or `electron-updater` style manifests. Sparkle is what native Mac apps use, and it brings the checking, the download, the signature check, the replacement and the relaunch.

Updating the engine from inside Sparkle, by shipping it in the zip. The engine is a Node package that Homebrew installs with its own `node`; bundling it is what 0017 already rejected.

Delta updates and an appcast with the history of versions. The app is small and the latest is all anyone needs.

## Consequences

The update key's public half lives in every installed app and its private half in a secret. The key cannot be rotated: with an ad hoc signature Sparkle has no other signature to vouch for a new key. If the private key is lost, the apps already installed stop accepting updates, and the way out is `brew reinstall --cask carrier`, which fetches a new zip with a new public key. The private key must be kept somewhere besides the secret.

The feed URL and the public key are fixed in the apps that ship them. The URL depends only on the repository's name, and the repository has to stay public.

The appcast must never name a version the tap does not have yet, or a person would update the app and find nothing for `brew upgrade` to bring. That is why the release stays a draft until the tap has been pushed and the appcast attached, and why a draft or prerelease is never the latest one (GitHub's rule). A failed run leaves a draft and the feed on the previous release.

`brew upgrade` of the formula may also upgrade what it depends on (`node`, `git`, `gh`) and their installed dependents, so it can take a while and it can move those; the app runs `brew update` first, because Homebrew updates its taps only every 24 hours (5 minutes for a fully qualified third-party name). A pinned formula is skipped and a `brew update` running elsewhere makes ours fail on its lock: both are reported, not retried.

Homebrew itself can still upgrade the app, when it is older than the cask: it quits the running app to replace it. `HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS` turns that off, and the cask cannot set it.

The app now runs a package manager on the person's machine. It does so only after the person has accepted the app's update (or has chosen to install without asking), it uses one fixed command, and it never retries by itself.

The message that tells a person the app is older than `carrier` says that the app updates itself and, if it has not, to run `brew upgrade --cask carrier`, which upgrades an app that is older than the cask.

The research ([sparkle-auto-update](../research/sparkle-auto-update.md)) read Sparkle 2.10.1 (2026-10-25): a second ad hoc build with a different code hash passes on the EdDSA signature alone, and the installer clears the quarantine attribute recursively. Neither has been run. What the documentation does not say is whether Gatekeeper lets the relaunched ad hoc, not notarized app open without a dialog; a spike with a throwaway app settles that and the rest of the list in the brief before anything else is built, and this decision stands or falls with it.
