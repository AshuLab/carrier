# A generated `.command` script in Terminal, iTerm2, Ghostty and Warp

> Spike from 2026-10-21 for story 6 of the [macOS app redesign](../specs/macos-app-redesign.md). Closes the part of [macos-app-data-github.md](macos-app-data-github.md) (section 9) and of [ADR 0007](../adr/0007-continue-in-terminal-through-a-validated-descriptor.md) that said iTerm2, Ghostty and Warp had not been verified. Run on macOS 27.0, Terminal 2.15, Warp 0.2026.09.09 (stable).

## Short answer

Terminal and Warp opened the script through `NSWorkspace`, ran it in the right folder and it removed itself, with no click from a person. iTerm2 and Ghostty are not installed on this machine, so they were not tried. The single-quoting survived a folder name built to break it, and the function that does it now exists in the core library with tests.

## Result

| Terminal | Installed | Opened the script | Asked for any permission | Ran in the right folder | Removed itself |
|---|---|---|---|---|---|
| Terminal 2.15 | yes | yes, as the default handler and by explicit app | no blocking prompt (ran unattended) | yes | yes |
| Warp 0.2026.09.09 | yes | yes, by explicit app (it is not the handler for `.command` here) | no blocking prompt (ran unattended) | yes | yes |
| iTerm2 | not installed | not tried | not tried | not tried | not tried |
| Ghostty | not installed | not tried | not tried | not tried | not tried |

"Asked for any permission" means that nothing stopped the script waiting for a click: the script ran start to end with nobody touching the machine, `NSWorkspace` returned no error, and no Automation, Gatekeeper or file-access dialog blocked it. A dialog or banner that does not block could not be seen: this session has no screen access (`screencapture` failed with "could not create image from display"), so what each window looked like was not observed, and nor was whether the window stays open after the script ends (the script ended with `exit 0`; the research's `exec "${SHELL:-/bin/zsh}" -il` last line was not tried).

## What was run

A scratch program (under the system temp directory, compiled with `swiftc` together with the new `ShellQuote.swift`) wrote a script, set its mode and opened it, once per terminal:

- `NSWorkspace.shared.open(_:configuration:)` for the file alone (the default handler, `urlForApplication(toOpen:)` returned `/System/Applications/Utilities/Terminal.app`) and `open(_:withApplicationAt:configuration:)` with the terminal's bundle id (`com.apple.Terminal`, `dev.warp.Warp-Stable`). `activates` was false.
- The script: `cd` to a folder whose name was `sp ace 'q" $(touch PWNED) `id` \ dir <id>` (spaces, a single and a double quote, `$()`, backticks and a backslash), then wrote a marker file with `pwd -P`, `$SHELL`, the count of quarantine attributes on itself, its own mode and the names of the environment variables (names only, never values), printed the same names, then `rm -f --` itself and `exit 0`. Every path in it went through `shellQuote`.
- Checked afterwards: the marker exists, the script is gone, and the folder holds no `PWNED` file (nothing inside the folder name was executed).

Both terminals reported `pwd` equal to the folder (`/private/tmp/...`, the resolved form of `/tmp/...`), no `PWNED` file was created, and the script was gone each time.

## The script's file mode, place and attributes

- Mode 0700, set after writing with `FileManager.setAttributes([.posixPermissions: 0o700])`; the script read its own mode as `700`.
- Place: `NSTemporaryDirectory()`, the user's per-user folder under `/var/folders/.../T/`, with a random name, `carrier-spike-<8 hex>.command`.
- No quarantine attribute was set: the file is written by the app itself, and the script counted zero `com.apple.quarantine` entries on itself while running in both terminals. Gatekeeper's "downloaded from the Internet" dialog did not appear.
- `rm -f -- <script>` from inside the script worked while the shell was still reading it.

## One thing to know about the environment

When Terminal was not running, it was started by `NSWorkspace` from the spike program and its shell had the spike program's environment: the names of the variables of the parent session (the agent tooling's session variables among them) showed up in the script. Terminal was then quit and started again from `env -i ... open -a Terminal`, and the script's environment held none of the `CLAUDE_*` names nor `SUPERSET_TERMINAL_ID`. So a terminal that the app starts inherits the app's own environment, and one that was already running keeps its own. The point is that the app must never put a token in its own environment, or a terminal it launches would carry it. Values were never printed or saved.

## What was changed on the machine, and undone

- Terminal and Warp were not running at the start. Both were started by the spike and then quit at the end (`NSRunningApplication.terminate()`; neither was running afterwards). Launching them can have written their own state (window restoration, preferences, Warp's first-run files); that was not cleaned and is the apps' normal state.
- The scratch folder, the compiled spike and the markers were deleted. The scripts had deleted themselves.

## The quoting function

`shellQuote` (`macos/Sources/CarrierCore/ShellQuote.swift`) wraps the value in single quotes and writes each single quote as `'\''`. The tests in `ShellQuoteTests.swift` run the quoted value through `/bin/sh` as the argument of `printf '%s'` and compare what comes back for: an empty value, spaces and a tab, single quotes, double quotes, `$()`, `${HOME}`, backticks, backslash and shell punctuation, newlines, a leading dash (`-n`, `--help`, `-e \n`) and non-ASCII text (accents, a snowman, Japanese, an emoji). A NUL byte cannot go through a shell at all, so it is not covered: the descriptor validation that ADR 0007 already requires has to refuse it.

## Not verified

- iTerm2 and Ghostty (not installed). Whether they register for `.command` is still unknown; neither was tried through `NSWorkspace`.
- Whether Warp shows any non-blocking notice on its first launch, and what any window looked like afterwards.
- Whether the window stays open or closes when the script ends, in either terminal.
- A person opening one generated script by hand in the terminal they use every day.
