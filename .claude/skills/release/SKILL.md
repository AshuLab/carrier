---
name: release
description: Release Carrier by hand from a Mac, without GitHub Actions - the app, the npm package, the GitHub Release and the Homebrew tap. Use when Actions is unavailable (no minutes, outage) or a release run must be finished locally. The normal way is pushing a tag, which runs `.github/workflows/release.yml`.
disable-model-invocation: true
---

# release - ship Carrier without GitHub Actions

The normal release is a pushed tag `vX.Y.Z`: `.github/workflows/release.yml` builds, publishes and updates the tap, with npm trusted publishing and no token. **Use it whenever Actions works.** This is the same procedure by hand. `release.yml` is the source of truth: if it changes, change this file in the same PR.

Every step that is public (npm, the Release, the tap) needs the person's yes first: say what it will publish, then run it. Never run one step "to see".

## Before

- A Mac with macOS 26 and Xcode, Node 26, pnpm, Homebrew, `gh` logged in with push access to `AshuLab/carrier` and `AshuLab/homebrew-tap`, and `npm login` done (it asks for 2FA: trusted publishing only works from GitHub).
- The update key's private half, the base64 line `generate_keys -x <file>` exports (the same one as the repository secret `SPARKLE_PRIVATE_KEY`), in the environment variable `SPARKLE_PRIVATE_KEY` of the shell that runs steps 4 to 6. Never write it to a file in the checkout, put it on a command line or echo it.
- `VERSION` is `X.Y.Z`, higher than the last one on npm (`npm view @ashulab/carrier version`). A version cannot be published twice, even after a failure.
- Work in a clean checkout of the commit to release, not in a tree with changes: `git worktree add /tmp/carrier-release origin/main && cd /tmp/carrier-release`.
- **Creating the GitHub Release creates the tag, and a tag runs `release.yml`.** If Actions is back by then, a second run starts: it skips npm and replaces the Release's files and the tap's commit with its own build. Cancel it (`gh run cancel`) unless that is what you want.

## Steps

1. **Version.** Set it in this checkout only, never commit it: `npm pkg set version=$VERSION`.
2. **Check.** `pnpm install --frozen-lockfile && pnpm typecheck && pnpm test && pnpm build`.
3. **Pack.** `mkdir out && pnpm pack --pack-destination out && mv out/*.tgz out/carrier-$VERSION.tgz`.
4. **The app.** `./macos/build-app.sh $VERSION`, then `codesign --force --sign - macos/Carrier.app`, then `ditto -c -k --sequesterRsrc --keepParent macos/Carrier.app out/Carrier-$VERSION.zip` and `(cd out && shasum -a 256 Carrier-$VERSION.zip > Carrier-$VERSION.zip.sha256)`. Check the zip like the workflow: unzip it into an empty folder (`ditto -x -k`), the plist's `CFBundleShortVersionString` is `$VERSION`, `codesign --verify --deep --strict` passes. It is built with this Mac's Swift, not the runner's.
5. **Sign the zip.** `[ -n "$SPARKLE_PRIVATE_KEY" ] && SIGNATURE="$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | macos/.build/artifacts/sparkle/Sparkle/bin/sign_update -p --ed-key-file - out/Carrier-$VERSION.zip)"`. The tool comes with the app build (SwiftPM's artifacts); `printf` is a shell builtin, so the key is on no command line.
6. **The appcast, and its check.** `node .github/scripts/appcast.mjs write macos/Carrier.app out/Carrier-$VERSION.zip "$SIGNATURE" out/appcast.xml`, then `node .github/scripts/appcast.mjs check out/appcast.xml <the unzipped Carrier.app> out/Carrier-$VERSION.zip`. The check fails unless the appcast parses, has one item, its version and short version are the unzipped app's `CFBundleVersion` and `CFBundleShortVersionString`, its length is the zip's size, its signature verifies with the public key derived from `SPARKLE_PRIVATE_KEY`, and that key is the app's `SUPublicEDKey`. Read `out/appcast.xml` once. Nothing is attached or published by these three steps.
7. **The tap files.** `git clone https://github.com/AshuLab/homebrew-tap /tmp/tap`. In `Formula/carrier.rb` set `url` to `https://registry.npmjs.org/@ashulab/carrier/-/carrier-$VERSION.tgz` and `sha256` to the tarball's; in `Casks/carrier.rb` set `version` and `sha256` (the zip's). Change only those lines; macOS `sed` needs `-i ''`.
8. **Try them.** In a throwaway tap: `brew tap-new --no-git local/ci && brew trust local/ci`, copy both files in, `brew audit --strict local/ci/carrier`, `brew audit --cask --strict local/ci/carrier`. Install the formula from the packed file by pointing its `url` at `file://$PWD/out/carrier-$VERSION.tgz`, check `carrier --version`, uninstall.
9. **npm** (confirm first). `npm publish out/carrier-$VERSION.tgz --access public`. npm then validates the version: it stays unavailable (404, "Validating" on the package page, nothing in `npm stage list`) for minutes or hours. Wait until `npm view @ashulab/carrier@$VERSION version` answers; do not publish again.
10. **The formula's sha.** Download the published tarball, `shasum -a 256` it, put that in the formula's `sha256` (npm can serve different bytes than the packed file).
11. **The Release** (confirm first). `gh release create v$VERSION out/Carrier-$VERSION.zip out/Carrier-$VERSION.zip.sha256 --title v$VERSION --generate-notes --target <the commit's sha>`. If it exists: `gh release upload ... --clobber`.
12. **The tap** (confirm first). Commit both files in `/tmp/tap` as `carrier $VERSION` and push. Nothing to commit means it is already there.
13. **Check it.** `brew update && brew upgrade carrier && brew upgrade --cask carrier`; `xattr /Applications/Carrier.app` lists no `com.apple.quarantine`; open the app and see the sessions with their provider icons.

A step that fails is repeated from that step, not from the start: 9 onward are safe to repeat.

## Known traps

- `carrier --version` can print the pnpm one: `which -a carrier`; the brew one is `/opt/homebrew/bin/carrier`.
- Homebrew 7 asks to trust a tap's formula: `brew trust --formula ashulab/tap/carrier`; `brew install --cask` alone does not trust the formula it depends on.
- The app's ad-hoc signature changes on every build, so `brew upgrade --cask` warns "signer changed".
- A pushed tag cannot be moved once something was published from it.
