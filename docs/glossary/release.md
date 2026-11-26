# Release

**Homebrew tap** - Our repository of Homebrew recipes, `AshuLab/homebrew-tap`: the formula `carrier` (the engine and the chat host, from the npm package) and the cask `carrier` (the app). A person installs with `brew install ashulab/tap/carrier`. Homebrew loads a tap's code only once it is trusted, and the full name trusts just that item ([0017](../adr/release/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)).
_Avoid_: repo (it is not where the code lives), registry, package (the npm package is what the formula installs).

**Release** - One version of Carrier put out at once from a tag: the npm package, the formula, the app's zip on a GitHub Release, its appcast and the cask, all with the same version. The app is signed ad hoc and its cask clears the quarantine; the app and `carrier` are matched by the sockets' protocol, not by version, and the app also brings `carrier` up to date after it updates itself ([releasing](../releasing.md)).
_Avoid_: build (that is one step of it), deploy, publish (that is one step of it).

**Appcast** - The small `appcast.xml` file that tells the app which version is the latest, where its zip is and its signature. It is attached to the GitHub Release while that is still a draft, and publishing the release is the last thing a release does, so the feed never names a version the tap does not have; the app reads it at one fixed address, `releases/latest/download/appcast.xml` ([0022](../adr/release/0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md)).
_Avoid_: update feed, manifest, version file.

**Update key** - The EdDSA key pair that proves an update is ours: the private half signs each release's zip and lives in a secret of the repository, the public half is written in every app and checks the signature. It is not an Apple certificate and cannot be rotated; if the private half is lost, the person reinstalls with `brew reinstall --cask carrier` ([0022](../adr/release/0022-the-app-updates-itself-with-sparkle-and-the-engine-through-homebrew.md)).
_Avoid_: signing key (that word is for the code signature), certificate, license key.

**Free to replace** - The moment a running process of an older version may be swapped for the new one without losing work. The chat host is free when no session is working or waiting for an approval (an idle session is closed and resumes by its id); the engine is free when it has no execution in flight. A process that is not free is left alone and replaced when it becomes free, never forced.
_Avoid_: idle (that is one state of a chat session), quiet, safe to restart.
