# Releasing Carrier, and how an installed Carrier updates itself

This page is for the person who cuts a release. It follows one version from the tag to a Mac that already has Carrier, then says where the update key lives and what to tick after the first real release. The decision is [ADR 0022](adr/0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md), the design is [the spec](specs/carrier-updates-itself.md), the facts about Sparkle and Homebrew are in [the research](research/sparkle-auto-update.md), and the terms (Appcast, Update key, Free to replace) are in the [glossary](glossary.md). The workflow is the source of truth: [`release.yml`](../.github/workflows/release.yml). The same procedure by hand, for when Actions is unavailable, is the [`release` skill](../.claude/skills/release/SKILL.md); change one, change the other.

## 1. Cutting a release

A release is a pushed tag `vX.Y.Z`. The tag is the version: nothing is committed back, and the workflow sets the version in its own copy of `package.json`. The minor and the patch must stay below 100, because the app's build number is `X*10000 + Y*100 + Z` and `macos/build-app.sh` refuses anything else.

```bash
git tag vX.Y.Z <commit> && git push origin vX.Y.Z
```

To rehearse, run the workflow by hand from a branch: `gh workflow run release.yml --ref <branch>`. A manual run is a dry run unless it is on a tag and `dry-run` is switched off. It builds, packs, installs the formula from the tarball, builds the app, signs its zip, checks the appcast and the cask, and publishes nothing.

What the run does, in this order (each step needs the ones above it, and only the last five are public):

1. **Check and build.** `pnpm install --frozen-lockfile`, `pnpm typecheck`, `pnpm test`, `pnpm build`, then `pnpm pack`.
2. **The app.** `macos/build-app.sh` builds it with Sparkle inside, the workflow signs it ad hoc, zips it (`Carrier-X.Y.Z.zip` and its `.sha256`) and checks the zip: the plist's version and `codesign --verify --deep --strict`.
3. **The appcast.** The zip is signed with the update key (the secret `SPARKLE_PRIVATE_KEY`, which reaches the signing tool through the environment and its standard input, never a file or the log) and `.github/scripts/appcast.mjs` writes `appcast.xml`, one item. The same script then checks it against the app inside the zip: version, build number, the zip's length, the signature (verified with the public key derived from the private one), and that this key is the app's `SUPublicEDKey`.
4. **The tap files.** The formula and the cask are rewritten and tried in a throwaway tap (`brew audit --strict`, `brew audit --cask --strict`, an install of the formula from the tarball). The cask is made to declare `auto_updates true` and Sparkle's cache folder in its `zap` (`.github/scripts/cask.mjs ensure`).
5. **npm.** The package is published through trusted publishing (no token). A version that is already on npm is not published again. The formula then takes the sha of the tarball npm really serves; npm validates a new version before it serves it (about 5 minutes for 0.3.0), so the step tries for about 8 minutes, every 45 seconds, and if npm has not served it by then the step fails: re-run the failed job when `curl -I https://registry.npmjs.org/@ashulab/carrier/-/carrier-X.Y.Z.tgz` answers 200.
6. **The GitHub Release, as a draft,** with the zip and its checksum (`.github/scripts/github-release.sh draft`). A draft is never `releases/latest`, so the update feed still answers with the previous release.
7. **The tap.** The formula and the cask are pushed to `AshuLab/homebrew-tap` as `carrier X.Y.Z`. From here `brew upgrade` finds the new version.
8. **The appcast** is attached to the draft (`github-release.sh attach`). It is still invisible to the apps.
9. **Publish.** `github-release.sh publish` runs `gh release edit --draft=false`. Only now does `https://github.com/AshuLab/carrier/releases/latest/download/appcast.xml` answer with the new version. Right after the release is published that address may answer 404 for about ten seconds.

The order is the point. The moment the appcast is visible an app may update, and the app then asks Homebrew for the new `carrier`, so the tap has to have it first. A run that stops in the middle therefore never leaves the feed on a version without its formula or its appcast.

### What a run that stops leaves, and how to finish it

| It stopped | What is left | The feed |
|------------|--------------|----------|
| Before npm (steps 1 to 4) | Nothing published. | Previous release. |
| After npm, before the draft | The version is on npm, and a version cannot be published twice. | Previous release. |
| After the draft, before the tap | A draft with the zip. | Previous release. |
| After the tap, before the appcast | A draft with the zip, and the tap already on the new version: `brew upgrade` already moves people. | Previous release. |
| After the appcast, before publish | A draft with the zip and the appcast. | Previous release. |
| After publish | Nothing: it is done. | New release. |

Re-run the failed run: `gh run rerun <run-id> --failed`, or "Re-run failed jobs" on the run's page. It rebuilds, finds the version on npm and does not publish it again, finds the release as it was left (draft or published) and replaces its files, finds the tap either already at this version (nothing to commit) or pushes it, attaches the appcast and publishes. A half-done release finishes with the same run; there is no cleanup first. Do not delete the tag: it cannot be moved once something was published from it. By hand, the [`release` skill](../.claude/skills/release/SKILL.md) repeats from the step that failed.

Failures that are not a half-done release: a missing `SPARKLE_PRIVATE_KEY` secret stops the run at "Sign the zip", before anything is published; an appcast whose public key is not the app's stops it at "Check the appcast".

## 2. What the installed app does

For a person who installed with `brew install --cask ashulab/tap/carrier` (the app) and `brew install ashulab/tap/carrier` (the command):

1. **It checks.** The app embeds Sparkle. Sparkle reads the appcast at the fixed address above on its own schedule (once a day), and the app also asks for a check in the background every time it opens. A build with no feed (`swift run`) and the app under `--fixture` or `--selftest` never check.
2. **It asks, or installs.** By default Sparkle asks before it installs: a scheduled check that finds an update shows no window but a pill `Update X.Y.Z` in the sidebar's title bar (Sparkle's gentle reminders), and the pill opens Sparkle's window; a check the person asks for opens it directly. If the person turned on installing by itself, Sparkle installs when the app quits and does not relaunch it. The two choices (check by itself, on by default; install by itself, off by default) are Sparkle's own preferences and have no page in Settings yet. The zip is accepted only when its signature checks against the public key inside the installed app.
3. **It relaunches.** Sparkle replaces the app in `/Applications` and opens the new one. Sparkle also clears the quarantine attribute, and the app is not notarized (ADR 0017); the first real release is the check that macOS opens the relaunched app without a dialog (section 5).
4. **It brings `carrier` up to date.** When the app opens and finds the installed `carrier` (`/opt/homebrew/bin/carrier`) older than itself, it runs `brew update` and then `brew upgrade --formula ashulab/tap/carrier` with `HOMEBREW_NO_ASK=1`, one after the other, in the background and with no question: accepting the update was the consent. The output goes to `<folder>/engine/logs/app-upgrade.log` (`<folder>` is the Carrier folder, `~/.carrier` or `CARRIER_HOME`), a new log for each job. `brew upgrade` may also move `node`, `git` and `gh`, which is Homebrew's behavior.
5. **It replaces what runs, when it is free.** The chat host, when no session is working or waiting for an approval. The engine, only if it was running, once it has no execution in flight; while it waits the app pauses intake so the queue cannot keep it busy, then stops it, starts the new `carrier`, and pauses it again if the person had paused it. An engine the person had stopped stays stopped. Nothing is forced: a process that is not free keeps running its old version until it is.
6. **If Homebrew fails** (no network, no `brew`, another `brew update` holding the lock), nothing is changed, the old `carrier`, chat host and engine stay, and the Sessions home and the Sessions section of the sidebar show "Carrier could not be updated" with the reason and the last lines of the log. The app does not retry in that run; it tries again the next time it opens. [Troubleshooting](troubleshooting.md#carrier-could-not-be-updated-after-the-app-updated) says what to do.

A person on a release from before Sparkle has an app that cannot update itself. The first release with Sparkle reaches them through `brew upgrade` (their app is older than the cask, and `auto_updates true` does not stop Homebrew from upgrading an app older than the cask). From then on Sparkle moves the app. Homebrew then leaves an app that Sparkle took past the cask alone, and both paths end at the same version because the cask is pushed before the appcast is published.

## 3. What a Homebrew user who never opens the app sees

Nothing happens by itself: Homebrew does not tell anyone there is a new version. They run `brew upgrade carrier` (the command) and, if they have the app, `brew upgrade --cask carrier`. The engine and the chat host that are already running keep the old version until they are restarted (`carrier stop` and `carrier start`, `carrier chat --stop`); the next start uses the new `carrier`. The app and `carrier` are still told apart by the protocol of their sockets, so an app and a `carrier` that disagree say which one to upgrade and do not connect ([troubleshooting](troubleshooting.md#the-app-asks-to-update-carrier-or-itself)). If `carrier` is the one that is newer, the message tells them that the app updates itself and, if it has not, to run `brew upgrade --cask carrier`.

## 4. The update key

The update key is an EdDSA key pair. The private half signs every release's zip, the public half is written in every installed app and checks the signature. It is not an Apple certificate.

- **The public half** is `macos/update-key.pub`. `macos/build-app.sh` copies it into the app's plist as `SUPublicEDKey`, and the workflow's check fails if the key derived from the secret is not that one.
- **The private half** lives in the repository secret `SPARKLE_PRIVATE_KEY` (Settings, Secrets and variables, Actions), as the one base64 line that `generate_keys -x` exports, and in a second place that survives a lost laptop and a lost GitHub account (the owner's own safe storage; it must not be this repository, a log or a chat). A release by hand needs it in the environment variable of the same name. Never write it into a file of the checkout, put it on a command line or print it.
- **Generating a new pair** (only to set up or to start over): let SwiftPM fetch Sparkle once (`cd macos && swift package resolve`), then run `macos/.build/artifacts/sparkle/Sparkle/bin/generate_keys`. It stores the private key in the login Keychain and prints the public key; `generate_keys -p` prints the public key again. Put the public key in `macos/update-key.pub`. Export the private key with `generate_keys -x <file>`, store its content in the second place, set the secret with `gh secret set SPARKLE_PRIVATE_KEY < <file>`, and delete the file. Every installed app carries the public half it was built with, so a new public key only reaches the apps built after it.
- **It cannot be rotated.** Sparkle accepts an update when its signature checks with the key in the installed app, or when the new app is signed by the same code-signing identity as the old one. The app is signed ad hoc, so a build never has the same identity as the one before it, and nothing else can vouch for a new key. Moving to a Developer ID would make a rotation possible and is a decision of its own.
- **If the private half is lost,** the apps already installed keep working but can no longer be updated by Sparkle: a release signed with a new key is refused as improperly signed. The way out is a new pair, a release signed with it, and `brew reinstall --cask carrier`, which brings a zip with the new public key, only to the people who run it. Tell them to.
- **If it leaks,** anyone with it can sign an update that every installed app accepts. Treat it like a stolen signing certificate: there is no revocation, only the reinstall above.

## 5. The first real release: what only a real tag proves

Everything else is covered by the dry run, the app's build check (`macos/scripts/check-app.sh`) and the tests. These need a real tag and a real Mac. Tick each one after the release, and write what you saw if it differs.

- [ ] **The order of publication.** While the run goes, `gh release view vX.Y.Z --repo AshuLab/carrier --json isDraft` says `true` until the last step; the tap already has the commit `carrier X.Y.Z` before the release is published; and the feed (`curl -sIL https://github.com/AshuLab/carrier/releases/latest/download/appcast.xml`) keeps answering with the previous release (a 404 for the first release with Sparkle, since the previous one has no appcast) until the release is published, then answers 200 with an `appcast.xml` that names X.Y.Z (allow ten seconds).
- [ ] **A re-run of a half-done release finishes it.** The first time a run fails or is cancelled after the draft step (cancelling one on purpose proves it), `gh run rerun <run-id> --failed` ends with the release published, the tap at X.Y.Z, npm untouched and the feed on X.Y.Z.
- [ ] **A Sparkle update from the previous release on a real Mac.** It needs a previous release that already has Sparkle, so it is the second release with Sparkle that can tick it. Install the previous one with the two `brew install` commands, open the app, and see the update offered (or open it again to force a background check). Accept: the app quits and opens at the new version, no Gatekeeper dialog, `xattr -lr /Applications/Carrier.app | grep com.apple.quarantine` prints nothing, `carrier --version` prints the new version once the app has upgraded `carrier`, and `<folder>/engine/logs/app-upgrade.log` has the Homebrew output. For the first release with Sparkle the same Mac gets there with `brew upgrade --cask carrier` instead.
- [ ] **One icon in the menu bar after the relaunch (#806).** By eye: after Sparkle relaunches the app there is one Carrier icon, with the app added as a login item (System Settings, General, Login Items) and without. An icon cannot be counted from outside, which is why it is a box here and not a check.
- [ ] **The `brew upgrade` notice.** Happy path: after the update, `<folder>/engine/logs/app-upgrade.log` shows `brew update` and `brew upgrade` finishing, the chat host and the engine that were free now report the new version (`carrier status`). Failure path, with an old `carrier` and a new app and the network off, the Sessions home shows "Carrier could not be updated" with the reason and the old `carrier` keeps working; turn the network on and open the app again, and it upgrades.

The research file records what the spike already settled on a throwaway app ([the spike's result](research/sparkle-auto-update.md#spike-result-2026-11-11-sparkle-2101-on-an-ad-hoc-app-installed-by-homebrew)); these boxes are the same questions asked of the real thing.
