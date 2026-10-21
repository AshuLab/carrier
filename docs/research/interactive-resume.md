# Interactive resume of a session the engine started headless

> Spike of 2026-10-21 for the [macOS app redesign](../specs/macos-app-redesign.md) (issue #116). It closes the "not verified" part of [ADR 0007](../adr/0007-continue-in-terminal-through-a-validated-descriptor.md) and of row 8a in the [engine data inventory](macos-app-data-engine.md). Versions: claude 2.1.307, codex-cli 0.153.4, agy 1.4.4.

## Method

For each harness: a short headless session in scratch folder A, started with the engine's flags (`src/harnesses/*.ts`: `claude -p ... --output-format stream-json --verbose --permission-mode bypassPermissions --name ...`, `codex exec ... --json --dangerously-bypass-approvals-and-sandbox`, `agy -p ... --output-format stream-json --dangerously-skip-permissions`) and the config folder variable set where the harness has one. Then the interactive resume command, **run as written below inside a pseudo-terminal opened with Python's `pty.fork`** (160x50, `TERM=xterm-256color`; `script` was not used): wait for the start screen, answer a trust dialog if one appears, type one message plus Enter, wait for the reply, press Ctrl-C twice. The message was "What single word did I ask you to reply with in my first message? Answer in lowercase, one word.", and the first (headless) prompt was "Reply with the single word PONG". A lowercase `pong` in the new reply, plus the old `PONG` turn on screen before typing anything, means the resumed session was found and its context restored. A, B and a scratch config folder lived under the system temp directory and were deleted afterwards; the machine's trust and history entries that the runs wrote were removed too.

## Result

| Harness | Resume command | Folder | Configuration folder | Result |
|---|---|---|---|---|
| Claude | `claude --resume <id>` | A (where it started) | `CLAUDE_CONFIG_DIR=~/.claude-ashu-lab` (the engine's) | found |
| Claude | `claude --resume <id>` | B (another folder) | `CLAUDE_CONFIG_DIR=~/.claude-ashu-lab` | found |
| Claude | `claude --resume <id>` | A | variable unset | found (see the symlink caveat below) |
| Claude | `claude --resume <id>` | B | variable unset | found |
| Claude | `claude --resume <id>` | A | `CLAUDE_CONFIG_DIR=~/.claude` (set, never signed in) | start screen of a new install (theme, login); never reached the session |
| Claude | `claude -p hi --resume <id>` (headless, no pty) | A | `CLAUDE_CONFIG_DIR=<empty folder>` | not found |
| Claude | `claude --resume 00000000-0000-4000-8000-000000000000` | A | engine's | not found |
| Codex | `codex resume <id>` | A | `CODEX_HOME=<the engine's folder>` | found |
| Codex | `codex resume <id>` | B | `CODEX_HOME=<the engine's folder>` | found |
| Codex | `codex resume <id>` | A | variable unset (`~/.codex`) | not found |
| Codex | `codex resume <id>` | B | variable unset | not found |
| Codex | `codex resume 00000000-0000-4000-8000-000000000000` | A | engine's | not found |
| Antigravity | `agy --conversation <id>` | A | none exists | found |
| Antigravity | `agy --conversation <id>` | B | none exists | found |
| Antigravity | `agy --conversation 00000000-0000-4000-8000-000000000000` | A | none exists | not found, but see below |

The Codex "engine's folder" was a scratch `CODEX_HOME` holding only symlinks to the real `auth.json` and `config.toml` (the engine on this Mac does not set it, so a second home was the only way to show the difference without copying a credential). Codex found the session from A and from B in other later runs too, with a second headless session and three more folders.

## What the command needs, per harness

| Harness | Folder | Variable | What the user sees when the session is not found |
|---|---|---|---|
| Claude | Any folder finds it. The transcript stays at `$CLAUDE_CONFIG_DIR/projects/<folder of the headless run>/<id>.jsonl` even when resumed from B (B got no transcript file, the new turns went to the same file). | `CLAUDE_CONFIG_DIR`, the one the engine used. It decides which login and which session store are read. | The terminal prints `No conversation found with session ID: <id>` and the command exits, nothing is opened. In a config folder that was never set up it never gets that far: the first-run theme and login screen shows instead. |
| Codex | Any folder finds it. | `CODEX_HOME`, the one the engine used. Without it, the default `~/.codex` has no such session. | The screen opens and then prints `ERROR: No saved session found with ID <id>. Run `codex resume` without an ID to choose from existing sessions.` and exits. |
| Antigravity | Any folder finds it. | None. `agy --help` lists no configuration variable and conversations live in one place, `~/.gemini/antigravity-cli/conversations/<id>.db`. | The command does not fail. It prints `warning: conversation "<id>" not found` once, then opens a **new empty conversation** (new id) in the same window, and the user can start typing as if nothing were wrong. The same behaviour the engine's headless parser already relies on (`src/harnesses/agy.ts`). |

So for the descriptor of ADR 0007: the folder is not needed to find the session, but it still matters in two ways seen in these runs.

- **Trust prompt.** Headless runs never ask; an interactive start in a folder the CLI has not seen before does. Claude: "Quick safety check ... Yes, I trust this folder / No, exit", and the highlighted choice is **No, exit**, so Enter alone quits. Codex: "Do you trust the contents of this directory?" with `1. Yes, continue` first. Agy: "Do you trust the contents of this project?" with `Yes, I trust this folder` first. The folder to open is therefore best the one the session started in (the descriptor's folder), as the ADR has it, because that is the folder whose files the agent worked on; but the first time on a machine the person answers that prompt. Accepting writes a trust entry for the folder to the CLI's own state (`~/.claude.json`, `~/.codex/config.toml`, agy's settings).
- **Codex asked once which folder to use.** In the first cross-folder run Codex showed "Choose working directory to resume this session: Session = latest cwd recorded in the resumed session, Current = your current working directory". It did not appear in six later cross-folder runs (a fresh exec session, and folders A, B, C in turn), and I could not find what triggers it. The session was found either way.

## Caveat of this machine

`~/.claude-ashu-lab/projects` and `~/.claude-ashu-lab/sessions` are symlinks to `~/.claude/projects` and `~/.claude/sessions`. So here the engine's config folder and the default one share the session store, which is why Claude found the session with the variable unset. They are still two accounts (the header said "Claude Team" with the variable, "Claude Pro" without), so a resume without the variable would run as another account on the same transcript. On a machine without that symlink the empty-folder run (not found) is the expected outcome. A descriptor that carries `CLAUDE_CONFIG_DIR` is correct either way.

## Does an interactive resume of an `exec` or `-p` session work at all?

Yes, for all three, with **no extra flag**, as long as the id is given explicitly and the configuration folder is the same. Claude (`-p` session, `--resume <id>` interactive), Codex (`exec` session, `codex resume <id>`: the picker's `--all` and `--include-non-interactive` filters only matter when no id is given) and Antigravity (`-p` session, `--conversation <id>`). In every case the earlier headless turn was shown on screen and the model answered from it. The resumed turn is appended to the same session, so the app must offer it only for a session the engine is no longer running (ADR 0007).

## Not verified

- Only the one Mac above: no machine whose Claude config folder has its own, separate session store and a working login, so "Claude, wrong config folder, interactive" is shown by the headless `-p` run and the never-signed-in folder, not by an interactive "No conversation found" on a second signed-in folder.
- Terminal handler: the pseudo-terminal stands in for the terminal the `.command` file opens; iTerm2, Ghostty and Warp are untested, as in the ADR.
- The agent's long sessions (ship, with subagents) and a session that was itself resumed by the engine (`--resume` in a later round) were not tried; only one-turn sessions were.
- Antigravity trust and conversation state in `~/.gemini/antigravity-cli` could not be moved elsewhere, so there was no "wrong configuration folder" case for it.
