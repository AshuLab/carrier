# The app checks that Carrier has what it needs

Status: spec

## Problem

A person who installs Carrier and opens the app can fail in ways the app does not explain. A provider CLI without a login makes a session fail after the first message is sent, with the provider's own error. `gh` without a login breaks the list of the person's repositories and cloning. A broken `git` breaks worktrees. An engine that has a config but a wrong identity, a repo without its labels or an unreachable socket is explained only by `carrier doctor`, in a terminal, and only to someone who knows it exists. The author has diagnosed all of these by hand for himself; nobody else can.

Pieces of the answer exist and do not add up. The chat host reports whether each agent's binary was found, and the new-session draft lists a provider whose binary is missing as "not installed", disabled. The app says when `carrier` is missing and when the engine is not configured. `carrier doctor` reads the login of `claude` and `codex` and runs many checks, but needs the engine's config. Nothing says whether a provider is logged in, nothing covers `gh` and `git`, and nothing gathers it in one place.

The Homebrew epic will install `git`, `gh` and `node`, and will never log anyone in or install a provider CLI. The check is what turns "installed" into "working".

We know it is solved when a person who opens the app can see in one place whether everything Carrier needs is ready, can see for each thing that is not what to do about it and press a button that opens Terminal with the command, and cannot start a session that is bound to fail for a reason the app already knew.

## Solution

A Health tab in Settings, next to Behavior and Repos, answers "is everything Carrier needs ready?" in three layers (the glossary's Health check). This Mac: `git`, `gh` and its login, and each chat agent's CLI (`claude`, `codex`) and its login. Carrier: the `carrier` command found and its version, the chat host running and at the installed version, the engine configured and running. The engine's setup: the checks of `carrier doctor`, shown when `<folder>/config.json` exists and replaced by a line saying it needs the config when it does not.

The checks run where the thing they check will run. The Mac layer is asked of the chat host in a new request, `health`, listed in the host's capabilities so an older host keeps working, because a session runs in the host's environment and not in the app's: a `claude` that the app's shell finds and the host's `PATH` does not would pass in the app and fail in the session. The engine's layer runs `carrier doctor --json` as a process with `CARRIER_HOME`, because the doctor needs the config and not a running engine. The app answers what only it knows: whether `carrier` is found, its version (the one it already asks for to decide on replacing a host), and whether the engine's socket answers.

Every check ends in one of four states: `ready`, `missing`, `signedOut`, or `unknown` when the probe could not answer (it timed out or failed). Unknown is shown as such and never blocks. The probes are the doctor's (`cliLoggedIn`: `claude auth status` read for its `loggedIn` field, `codex login status` read for its exit code) plus `gh auth status --hostname github.com` read for its exit code, and only the verdict leaves a probe, never the email or the organisation its output holds. A signed-out `claude`, `codex` and `gh` were observed to return a non-zero exit code and, for `claude`, `loggedIn` false in the same JSON; a probe takes under a second on a normal machine, so each is given five seconds, not the doctor's twenty, and the probes of a request run in parallel.

`git` is probed so that it never opens the system's installer dialog: when the `git` on the `PATH` is the system's `/usr/bin/git`, which on a Mac without the Command Line Tools is a stub that opens that dialog, the check is `xcode-select -p`; any other `git` is run with `--version`.

What a failure blocks is what it breaks and nothing else. A provider that is `missing` or `signedOut` cannot be chosen, with the reason, extending the "not installed" treatment the draft already has. `gh` `missing` or `signedOut` switches off the person's repositories and cloning in the workspace sheet, with the reason, and opening a local folder keeps working. `git` `missing` switches off the New worktree choice in the draft and shows the reason where a folder's branch would be. The reasons point to the Health tab. An open session is never blocked by the check: if its provider loses the login, it fails with the provider's own message as it does today.

Each failure that Carrier knows how to fix shows what to do and a button that opens Terminal with the command: `claude auth login`, `codex login`, `gh auth login` and `xcode-select --install`. The commands come from a fixed list in the app and never from what a probe returned, and Terminal is opened the way Continue in Terminal does it (ADR 0007): a one-use script file with each value quoted, opened by the system. A missing CLI has no button: its row says what is missing and links to the provider's installation page. The doctor's own fix texts are shown as text.

The checks run when the app opens, when it becomes active again (the person comes back from Terminal), and when the person presses Check again, and the host keeps the result for thirty seconds unless the request asks to refresh, so the draft does not start a CLI at every keystroke. `carrier doctor --json` makes GitHub calls and mints tokens, so it runs only when the Health tab is opened and on Check again, never in the background.

The documentation gets a short section for the person: what the Health tab checks and what each state means. The glossary has the term.

## Scope

1. `carrier doctor --json` prints the checks as a JSON array of `{ name, status, detail?, fix? }` and exits with the code it has today.
2. The chat host answers a `health` request, listed in its capabilities, with the state of `git`, `gh` and each chat agent, run in parallel with a five-second limit per probe, kept for thirty seconds unless refresh is asked, and carrying no email, organisation or token.
3. `git` is probed with `xcode-select -p` when it is the system's stub and with `--version` otherwise, and never starts the installer dialog.
4. The app asks the host for the health when it opens, when it becomes active and on Check again, and a host without the capability is treated as before (the agent's binary found or not).
5. The Health tab shows the three layers with a state for each check and the reason or fix next to it.
6. In the new-session draft a provider that is missing or signed out cannot be chosen and says why; an unknown one can.
7. With `gh` missing or signed out the workspace sheet's repositories and clone are off with the reason, and a local folder still opens.
8. With `git` missing the draft's New worktree is off with the reason.
9. A failure with a known fix has a button that opens Terminal with its command from the fixed list, and a missing CLI shows its installation link.
10. With a config the Health tab runs `carrier doctor --json` when it opens and on Check again and shows each check with its fix text; without one it says the engine's setup needs the config.
11. The Carrier layer shows whether `carrier` is found and its version, whether the chat host runs and whether it needs a restart to be at the installed version, and whether the engine is configured and running.
12. The documentation describes the Health tab.

## Decisions

The request and its reply, as the contract (the host's other requests keep their shape):

```ts
type ToolState = 'ready' | 'missing' | 'signedOut' | 'unknown';
// request: { cmd: 'health', refresh?: boolean }
// reply:   { git: ToolState; gh: ToolState; agents: { name: string; harness: string; state: ToolState }[] }
```

`git` is never `signedOut`; `agents` lists the agents the chat can start with, as `agents` does, so the app joins them by name. `unknown` means the probe timed out, could not start or could not be read, and is never turned into `signedOut` or `missing`.

The fixed list of commands is data in `CarrierCore`, keyed by what failed (provider and state, `gh`, `git`), and the app opens Terminal from it only; nothing the host or the doctor sends is run. The script and opener of Continue in Terminal are reused, not copied.

Testing seams, per story:

- 1: `doctor.test.ts` and the CLI's `main.test.ts` for the output and the exit code.
- 2, 3: the host's `sessions.test.ts` and `server.test.ts` drive the request through the existing fakes (`binaryFound` and a replaceable probe runner), asserting the states, the parallel limit, the cache and that nothing but verdicts is in the reply; the `git` probe is a unit test over an injected runner that returns the stub's path or another one.
- 4: the pure rule that decides whether to ask (open, active, refresh, capability present) in `CarrierCore`, with its own test; the wiring in the app delegate has no automated test, like the rest of the shell.
- 5, 10, 11: a pure function that builds the rows of the three layers from the host's reply, the doctor's checks, the settings and the sockets, with its own test; the tab's view has no automated test.
- 6, 7, 8: `agentChoices` and the pure functions of the workspace sheet and the draft in `CarrierCore` (`NewSessionTests` and the workspace sources' tests), which get the new states.
- 9: the fixed list and the script it produces, tested like `ContinueInTerminalTests` (the opener is replaceable); the button has no automated test.
- 12: no tests, it is documentation.

## Out of scope

The Homebrew epic, the native setup wizard, the coexistence with Solve's worktrees: their own epics.

Installing or updating any tool, and logging anyone in without Terminal.

A sidebar page or badge for the health.

Blocking or interrupting an open session because a check failed.

Notifications of a check that changes while the app is in the background.

Antigravity in the chat (it is not offered there); the doctor's Antigravity probe stays part of the engine's layer.

## Open questions

What `xcode-select -p` reports on a Mac without the Command Line Tools and whether the system's `git` really opens its dialog there: this is believed from how macOS works and not verified, because the author's Mac has Xcode. It does not change the design, and the author checks it on a Mac without the tools before the epic lands.
