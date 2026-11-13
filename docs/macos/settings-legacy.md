# Settings: the Legacy group

The Legacy group of [Settings](settings.md) holds the Health tab.

## Health tab

Settings has a Health tab (last of the Legacy group) that answers "is everything Carrier needs ready?".
It has three layers, each row with a mark and a line saying what is wrong and what to do.

- **This Mac**: `git` and `gh` (and whether it is signed in to GitHub).
  These are checked by the chat host, because a session runs in the host's environment, so a tool the app finds but the host does not would pass in the app and still fail in the session.
  The agent CLIs are on the Providers page.
- **Carrier**: the `carrier` command found (and its version), the chat host running (and whether it is older than the installed `carrier`, so it needs a restart), and the engine configured and running.
- **Engine setup**: the checks of `carrier doctor`, shown only when `<folder>/config.json` exists.
  Without it the layer says the engine's setup needs the config.

Each check on This Mac ends in one of four states:

| State | Row says | Meaning | What the app switches off |
|-------|----------|---------|---------------------------|
| `ready` | Ready | It is installed and, where it needs one, signed in. | Nothing. |
| `missing` | Not installed | The command is not found where the chat host runs. | A `claude` or `codex` that is missing cannot be chosen for a new session. With `gh` missing, My GitHub repositories and From a GitHub URL are off in the workspace sheet. With `git` missing, New worktree is off in the new-session draft. Each says why and points to the Health tab. |
| `signedOut` | Signed out | The command is there but has no login (`git` is never signed out). | A signed-out `claude` or `codex` cannot be chosen for a new session, and a signed-out `gh` switches off the same two GitHub rows as a missing one, each with its reason. |
| `unknown` | Could not check | The check timed out, could not start or could not be read. | Nothing: it is shown as such and never blocks. |

Only what is broken is switched off: opening a local folder keeps working without `gh`, and a session that is already open is never blocked (if its provider loses the login it fails with the provider's own message).

A failure Carrier knows how to fix has a button that opens Terminal with the command: `claude auth login`, `codex login`, `gh auth login` or `xcode-select --install`.
A missing `claude`, `codex` or `gh` has no button: its row links to the installation page.
The doctor's own fix texts are shown as text and never run.

The checks run when the app opens, when it becomes active again (for example after coming back from Terminal) and on Check again; the chat host keeps its answer for thirty seconds, which Check again skips.
The engine's setup runs `carrier doctor --json` only when the tab opens and on Check again, never in the background, because the doctor makes GitHub calls.
A check that could not answer is "Could not check", never a pass.
The health only reads whether a login works: no email, organisation or token is shown or kept.

### How each layer is read

The Health tab (`Carrier/HealthTab.swift`; its checks are cards side by side, as many as fit, and the doctor's many checks are grouped into one card each for tools, provider logins and repository access, `groupedChecks` in `CarrierCore/HealthRows.swift`; the tab is `SettingsPage.health`, which `WindowShell.openHealth()` selects) answers whether everything Carrier needs is ready, in layers, each row with a mark (green ready, yellow warning, orange needs attention, grey not known) and a line.
"This Mac" is the chat host's `health` reply (`HealthStore.latest`): `git`, `gh` and each chat agent, as ready, not installed, signed out or could not check, each with the fix of `healthFix` (a button that opens Terminal on the command, or the installation page).
Without a reply it says, in place of the rows, that the chat host is not running, that it is too old to check this Mac (its hello does not list `health`: `CarrierFacts.hostReportsHealth`), or that the check has not answered yet or failed and Check again retries it.
"Carrier" is what only the app knows (`CarrierFacts`): `carrier` found and its version (`carrier --version`, the one that decides on replacing the host), the chat host running and whether it is older than the installed `carrier` (`hostReplacement`, so it needs a restart), and the engine not configured (no `config.json`), configured and stopped, or running.
"Engine setup" is a third section, the checks of `carrier doctor --json` (`CarrierCore/DoctorChecks.swift`): `DoctorStore` runs `node <carrier> doctor --config <folder>/config.json --json` (`doctorCommand`: the engine's `PATH` and `CARRIER_HOME`, run by the shell's `runProcess`, replaceable in the store's tests) when the tab opens and on Check again, never in the background (the doctor makes GitHub calls and mints tokens), without waiting for it (the layer says "Running carrier doctor…" and the rest of the tab stays usable), not again while a run is in progress, and only when `<folder>/config.json` exists; without one the section is a line saying the engine's setup needs the config and nothing runs.
Each check is a row with its state (green ok, yellow warn, orange fail), its detail and its fix text, shown as text and never run.
The doctor exits 1 when a check fails and still prints the checks, so its output decides; a doctor that cannot start, prints something that is not its JSON array (or an empty one), or takes longer than `doctorTimeout` (90 s, then ended) is one grey row, "Could not check" with the reason, never a pass.
Check again asks the host for a fresh health (`HealthMoment.refresh`) and reads the version and the host's socket again; the tab reads the last health the app has (it asks when the app opens and when it becomes active) and does not ask when it opens.
The reasons in the draft and the workspace sheet that point to Health (a blocked provider, `gh` or `git`) come with an "Open Health in Settings" button.

When something fails, look here first: [troubleshooting](../troubleshooting.md#start-with-the-health-tab).
