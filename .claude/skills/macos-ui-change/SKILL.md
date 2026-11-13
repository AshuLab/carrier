---
name: macos-ui-change
description: Procedure for changing a view of the Carrier macOS app - read the UI guide, build, open it against fixtures, check every state, update the guide. Use whenever a change touches macos/Sources/Carrier or the user asks to change how the app looks or behaves.
---

# macos-ui-change - change a view and prove it

How the app is drawn (buttons, rows, spacing, mistakes already made) is [docs/macos-ui.md](../../../docs/macos-ui.md).
This is only the procedure; it never repeats a rule from there.
A build that only compiles proves nothing: open the app and look.

1. **Read docs/macos-ui.md first.** Reuse the pieces it names; do not draw a new one if one exists.
2. **Data for the view**: the app's fixture mode reads the golden files in `macos/Tests/Fixtures` (copied into the app by `build-app.sh`). A reply the engine sends is written by a TypeScript test (`UPDATE_FIXTURES=1 pnpm test`); a `chat-*.json` file is written by hand. Add the long, missing and odd values the view must draw.
3. **Build**: `(cd macos && ./build-app.sh)`. Needs Xcode selected, not only the Command Line Tools.
4. **Look at it**: `(trap '' PIPE; exec macos/Carrier.app/Contents/MacOS/Carrier --fixture)` (the dev-sandbox skill says why), go to the view. Ask the person to look or to send a screenshot, naming the view and the state; never take a full-screen capture, it records everything else on their screen.
5. **Check every state**: long values, missing, error, empty, and light and dark ([docs/macos-ui.md](../../../docs/macos-ui.md) says how each is drawn).
6. **Scripted checks**, with SIGPIPE ignored as in step 4: `--fixture --selftest <log>` (last line `end: process still alive ...`, and `animating=0` on `rings, window closed`) and `--fixture --smoke-window` (widths and layout lines). What they print is in [macos/README.md](../../../macos/README.md#test).
7. **Same checks as CI**, from `macos/`: `swift build`, `scripts/test-ci.sh`, `scripts/check-app.sh`.
8. **Close the loop**: a new or changed piece updates docs/macos-ui.md in the same change; `macos/README.md` if the behavior changed; a CHANGELOG line if a user can see it.

Quit a dev build by its PID, never `osascript ... to quit`: that also quits the installed Carrier.
For a real chat host behind the app instead of fixtures, use the dev-sandbox skill.
