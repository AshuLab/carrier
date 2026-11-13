---
name: dev-sandbox
description: Run a development build of Carrier (chat host, engine CLI, macOS app) against a throwaway Carrier folder, never the real ~/.carrier. Use to try a change in the real app, to look at a view, or when asked to run, start or screenshot Carrier from this clone.
---

# dev-sandbox - run Carrier from this clone, safely

Source of truth: CONTRIBUTING.md "Developing against a throwaway folder" and macos/README.md ("Fixture mode", "Test").
If they change, change this file in the same PR.

Never touch `~/.carrier`.
Every command runs with `CARRIER_HOME` set to the scratch folder of step 1.
Each Bash call is a new shell, so an `export` does not reach the next one: write the folder's literal path in every command, `CARRIER_HOME=/tmp/carrier.AbC123 node ...`, and start each call with the guard `[[ "$CARRIER_HOME" == /tmp/carrier.* ]] || exit 1`.

## Pick the mode

- **Look at the app, no backend**: `--fixture` (a fake engine and chat host inside the app). Fastest; use it for UI work, with the macos-ui-change skill.
- **App + real chat host from this clone**: steps 1-5.
- **Engine**: only with a config whose repos are throwaway ones. A real engine picks up `solve:epic:ready` epics and runs agents with the person's permissions. Ask first. Not covered here.

## Steps

1. **Scratch folder**: `mktemp -d /tmp/carrier.XXXXXX`, and use the path it prints. Keep it under `/tmp`: a socket path holds about 100 bytes and the host refuses a longer one.
2. **Chat host**: `CARRIER_HOME=<folder> node src/terminal/cli/main.ts chat-host` in the background. Check it: `CARRIER_HOME=<folder> node src/terminal/cli/main.ts chat --list` prints `No chat sessions.`
3. **App**: `(cd macos && ./build-app.sh)` (needs Xcode selected, not only the Command Line Tools; about 2.5 minutes from clean), then `CARRIER_HOME=<folder> macos/Carrier.app/Contents/MacOS/Carrier`.
4. **This clone's `carrier`**: Settings > Engine > Programs > "Use another…" with `src/terminal/cli/main.ts` (or `dist/terminal/cli/main.js` after `pnpm build`). Ask the person first: see the first trap.
5. **After each code change**: `CARRIER_HOME=<folder> node src/terminal/cli/main.ts chat --stop`, then reopen. The app replaces a host only when `carrier` has a newer version, and a dev build keeps the same one.
6. **Fixture mode**: `(trap '' PIPE; exec macos/Carrier.app/Contents/MacOS/Carrier --fixture)` (the golden files bundled from `macos/Tests/Fixtures`; SIGPIPE ignored, see the traps), `--fixture <folder>` for other ones, `--selftest <log>` and `--smoke-window` for the scripted checks (what each prints is in macos/README.md).

## Clean up

`CARRIER_HOME=<folder> node src/terminal/cli/main.ts chat --stop`, quit the app by its PID (`kill <pid>`), put back "Use the Homebrew one" if step 4 changed it, then `[[ "<folder>" == /tmp/carrier.* ]] && rm -rf "<folder>"`: only the folder of step 1.

## Known traps

- The app's settings are shared with the installed Carrier (same bundle id, `dev.ashulab.carrier`): "Use another…" changes the person's real app too. So does `osascript ... to quit`, which quits the installed app: quit a dev build by its PID.
- `carrier status`, `watch`, `stop` say Carrier is not running when `CARRIER_HOME` differs from the one it started with ([troubleshooting](../../../docs/troubleshooting.md#start-up-errors)).
- A host that keeps running old code: step 5.
- `swift build` fails with `SwiftUIMacros.StateMacro could not be found` under the Command Line Tools ([macos/README.md](../../../macos/README.md#toolchain)).
- `--fixture <folder>` stops with `unreadable(".../<file>.json")` when the folder lacks a file `macos/Tests/Fixtures` has (`macos/DevFixtures` did, on 2026-11-13): copy it from there.
- Under `--fixture` the app dies silently with exit 141 (SIGPIPE) about 15 seconds after start, `--selftest` and `--smoke-window` included; without `--fixture` it does not. Until that is fixed, start it with SIGPIPE ignored, as in step 6.
- Never take a full-screen capture (`screencapture` with no window): it records everything else on the person's screen. Ask the person for a screenshot.
