# Starting Carrier and the chat host

How the app starts the engine and the chat host, and replaces them when `carrier` is newer.
How the app finds `carrier`, `node` and the `PATH` is on the [Engine page](settings-carrier.md#engine).

## Start Carrier

### The engine

Start Carrier (the menu item, and a button in the window while Carrier is stopped) runs `carrier` (`node <carrier>` for a `.ts` or `.js` script, the developer's "Use another…") with that `PATH` and `CARRIER_HOME=<folder>` (the engine finds its config, state and logs from the folder, so there is no config path to pass), in its own session (`posix_spawn` with `POSIX_SPAWN_SETSID`, so quitting the app leaves Carrier running), stdin from `/dev/null` and stdout and stderr in `<folder>/engine/logs/app-start.log`, which it creates (with mode 0700) when missing.
It is never started on its own when the app opens, unless the person turned on "Start Carrier when the app opens" under Starting on the Engine page (user default `engine.startOnOpen`, off by default): then, at the first state the monitor delivers after launch, the app starts Carrier once when that state is stopped and Start Carrier is enabled (so never while the engine is not configured), never under `--fixture` (`shouldStartOnOpen`; the wiring in `AppDelegate` has no automated test, as it would start the real Carrier).
When the control socket answers within 15 seconds the state becomes running (the next connect attempt shows it, within 3 seconds); when the process exits first, or 15 seconds pass without the socket, an alert shows the end of `app-start.log`.
A second press while it starts does nothing.
The self-test only checks the start (what it would run), as it does for Stop.

### The chat host

The chat host does not need the engine, so the app starts it on its own terms.
Every time the app opens, once the settings are known (and again when the Settings window closes), it looks at the host's socket, `<folder>/chat/state/chat.sock`, and starts the host when nothing answers, not only when a session is created: the host runs no agent until a session exists, and the sessions in the sidebar are what it holds.
`<folder>` is the Carrier folder: `CARRIER_HOME` from the app's own environment, else `~/.carrier`.
The host needs `carrier`, found as above (and `node` only when it is a script), and nothing else: no config path, no engine config.
It runs `carrier chat-host` (`node <carrier> chat-host` for a script) with the same `PATH` and `CARRIER_HOME=<folder>`, in its own session, stdin from `/dev/null`, output in `<folder>/chat/logs/app-start.log` (the `chat/` folder with mode 0700), waits 15 seconds for the socket and shows an alert with the end of the log when the process exits first or the socket does not come; a `chat.json` the host refuses (see [configuration](../configuration.md#chat-configuration)) is shown that way, with the host's message naming the key.
A second request while it starts does nothing, and under `--fixture` it never starts (the fake host answers).
Because the folder comes from the app's environment, a build run from a terminal with `CARRIER_HOME=/tmp/scratch` starts its host in the scratch folder and never touches the real sessions in `~/.carrier` (the guide is in the [README](../../CONTRIBUTING.md#developing-against-a-throwaway-folder)).

When `carrier` is missing (or `node`, when the carrier chosen with "Use another…" is a script) the app opens with no alert.
The Sessions section of the sidebar and the Sessions home say what is missing ("The chat host cannot start", "The app did not find carrier. Run brew install ashulab/tap/carrier in Terminal.") until the app finds it; coming back from Terminal (the app becoming active) looks for `carrier` on the disk again and starts the host, with no restart.
Creating a session while it is missing keeps the alert, which says the same as the notice, because there the person asked for something that cannot happen.

### Version checks and replacement

When a host answers, the app asks the installed `carrier` for its version (`carrier --version`) once per launch and compares it with the version in the host's hello (`CarrierCore/HostReplacement.swift`, `hostReplacement`).
If the host is older, no session is working or waiting for an approval and the sessions could be listed, the app stops it, waits up to 15 seconds for its socket to go and starts the installed one.
If a session is working or waiting, it leaves the host running and the Sessions section and the Sessions home say "The chat host is older than Carrier", to restart it when the session finishes, because stopping a host closes its agents' processes and the work in them.
A version that cannot be read on either side leaves the host alone and writes why to the app's stderr.
A build under development keeps the same version, so there the host is restarted by hand (`carrier chat --stop`).

The engine gets the same comparison (`engineReplacement`, and the sequence `replaceEngine` in `CarrierCore/EngineReplacement.swift`), right after the host, with the version read after any Homebrew upgrade.
It is replaced only if it was running: a stopped engine stays stopped.
With no execution in flight (the snapshot's `sessions`) the app stops it, waits for its socket to go and starts the installed `carrier` with the Start Carrier path (a failed start keeps its alert).
With executions in flight the app pauses intake, reads the snapshot every 5 seconds without blocking, and replaces the engine when the last one ends; intake the person had paused is paused again on the new engine, intake the person resumes during the wait is left resumed, and an engine that stops answering ends the wait.
Known edges: an execution that starts between the last read and the stop is closed with the engine, and an app that quits during the wait leaves intake paused (the next launch reads that as the person's).
