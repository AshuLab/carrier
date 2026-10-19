# Antigravity (`agy`) as a third harness

> Spike from 2026-10-17. Answers whether the Antigravity CLI can sit next to Claude Code and Codex as a Carrier harness (the CLI that runs the author or the reviewer). Same questions as [headless-agents.md](headless-agents.md), checked against what a Carrier adapter has to provide (`src/harnesses/claude.ts`, `codex.ts`, `common.ts`, `host-runner.ts`). Everything was run in a disposable repo under the job's tmp folder (no remote, no real repo), with the cheapest models and minimal prompts. `ship` and no real Solve skill were run.

## Result

| What an adapter needs | Result |
|---|---|
| 1. Headless run with a machine-readable stream and a session id **while it runs** | pass: `--output-format stream-json`, first line is `init` with `conversation_id` |
| 2. Resume restoring context, and a signal for "session not found" | pass for resume; the "not found" signal is **only a stderr warning and the run goes on in a new conversation** (see point 2) |
| 3. Unattended: shell, git, network, no prompts | pass with `--dangerously-skip-permissions`; no sandbox by default |
| 4. Auth failure detection | observed, but it takes ~60 s and `--print-timeout` does not shorten it |
| 5. Marker in argv, stop, orphans | pass: `--log-file` carries the marker; SIGTERM and SIGINT leave **no** orphans (better than Codex); SIGKILL does, like Claude |
| 6. Runs Solve skills headless | pass with conditions: `/name args` works; Solve skills have to be made visible to `agy` |
| 7. Model list and `--model` | pass: `agy models`, id is the first column |
| 8. Env and per-execution credentials | env reaches the commands; there is no `CLAUDE_CONFIG_DIR`-style variable (only `HOME`) |

Verdict: **yes, with conditions**. It can have the same guarantees as Claude and Codex, but two behaviors need explicit handling in the adapter: a lost conversation id silently starts a new conversation, and a missing login waits about a minute before failing.

## Environment

- macOS (Darwin 27.0.0), `agy` **1.4.0** at `~/.local/bin/agy` (a single 185 MB executable, the language server runs inside the same process), logged in with the operator's Google account. Config and state live in `~/.gemini/antigravity-cli/` (`settings.json`, `skills/`, `conversations/`, `cli.log`, the OAuth token file) and `~/.gemini/config/` (global customization: agents, `skills.json`).
- Models used: `gemini-3.8-flash-low` and `gemini-3.8-flash-medium`.
- The operator's `settings.json` has `toolPermission: "always-proceed"` and `allowNonWorkspaceAccess` keys, so two results below (no prompt without the flag, writing outside the workspace without `--add-dir`) are partly the operator's configuration, not the CLI's default. The adapter must not depend on them.
- Shell trap: in zsh an unquoted `$F` holding several flags is one argument; `agy` then fails with `Error: unexpected argument "stream-json". Prompts are read only from -p/--print, -i/--prompt-interactive, or stdin` and exit 2. Not an issue for `spawn` with an argv array.

## 1. Headless run and event shapes

```sh
cd <repo> && agy -p "Reply with exactly: pong" --output-format stream-json --model gemini-3.8-flash-low --dangerously-skip-permissions </dev/null
```

Observed (exit 0, 8 s, nothing on stderr). One JSON object per line:

```
{"event":"init","conversation_id":"59371104-e7a2-4b6e-bdd2-fe998a94a79c","init":{"model":"gemini-3.8-flash-low","cwd":"<repo>","tools":["run_command","write_to_file",...],"permission_mode":"always-proceed"}}
{"event":"step_update","step_update":{"conversation_id":"...","step_index":0,"state":"DONE","step_type":"user_input"}}
{"event":"step_update","step_update":{"conversation_id":"...","step_index":1,"state":"ACTIVE","step_type":"agent_response","text_delta":"pong"}}
{"event":"step_update","step_update":{"conversation_id":"...","step_index":1,"state":"DONE","step_type":"agent_response","text_delta":"\n","duration_seconds":2.15,"usage":{...}}}
{"event":"result","result":{"conversation_id":"...","status":"SUCCESS","response":"pong\n","duration_seconds":2.2,"num_turns":1,"usage":{"input_tokens":14408,"output_tokens":1,...}}}
```

- The session id is in the **first line** (`init.conversation_id`), written before the model is called: after a `kill -9` the file still had it. This is the `session` signal. `--output-format json` prints one object at the end (`{"conversation_id","status","response",...}`), so the id would only arrive after the run: not usable for Carrier.
- Tool steps are `step_type: "tool"` with `tool_name` (`run_command`, `write_to_file`, `view_file`, ...) and `tool_info` (the call as a Python-like dict string).
- `result.status` is `SUCCESS` or `ERROR` (with `result.error`). Exit codes: 0 on success, 1 on error (unknown model, interruption, failed auth), 2 on a usage error, 137 after `SIGKILL`.
- Each fresh run creates a new conversation; the id is stable across resumes.
- Three parallel runs with the same `HOME` all succeeded (no shared-daemon conflict).
- Cost of a trivial prompt: ~14k input tokens (the CLI's system prompt and 60 tool definitions), ~8 s on a flash model.

## 2. Resume

```sh
agy -p "Remember the codeword TANGERINE-93. Reply only OK." --output-format stream-json ...      # init.conversation_id = 8b9985c9-...
agy -p "What was the codeword? Reply with only the codeword." --conversation 8b9985c9-... ...   # -> "TANGERINE-93", same id, num_turns 2
cd ../other && agy -p "Again?" --conversation 8b9985c9-... ...                                   # other cwd -> "TANGERINE-93", init.cwd is the new cwd
```

- Resume restores context and keeps the same id; it works from another folder (the process cwd wins, like Claude).
- Resuming after a cut works too: after `SIGTERM` (conversation `8a29eb55-...`) and after `SIGKILL` (`0f00f858-...`) the agent answered correctly which command it was running when it was cut.
- **Unknown id: `exit 0`, a NEW conversation, and a stderr line `warning: conversation "00000000-0000-0000-0000-000000000000" not found`.** The stream starts normally with a different `init.conversation_id`. The same happens for a malformed id (`warning: conversation "nope" not found`). So the run does not fail: it answers with no context. This is the `sessionUnavailable` signal and it must be caught, either by the stderr line (`/warning: conversation ".*" not found/`) or by `init.conversation_id !== requested id`. The runner reads both streams through `parseLine`, so the stderr line works with the existing design, but the rest of the run is not stopped; if the signal is raised, the adapter's run is classified `session_unavailable` at exit and the engine rebuilds the context in a new execution (the existing path for Codex). Cheaper: also match the id mismatch in the `init` line.

## 3. Unattended permissions

```sh
agy -p "Using your shell tool run: git rev-parse HEAD ; curl -s -o /dev/null -w 'HTTP=%{http_code}' https://api.github.com ; gh --version | head -1 ..." --dangerously-skip-permissions --output-format stream-json
```

Observed `out.txt`: `1685b7ad...` (the commit), `HTTP=200`, `gh version 2.102.0`. The `run_command` tool ran with no prompt and **with network**. `init.permission_mode` was `always-proceed`.

- `--sandbox` ("Run in a sandbox with terminal restrictions enabled") is opt-in: there is no Codex-style default sandbox that blocks the network, so nothing to bypass. The adapter must not pass `--sandbox`.
- Without the flag, on this machine the same command also ran without a prompt, but that comes from the operator's `toolPermission: "always-proceed"` setting. The adapter should pass the flag explicitly, as it does `bypassPermissions` for Claude and the bypass flag for Codex (ADR 0004).
- Writing the result file outside the workspace worked with and without `--add-dir <dir>`; the first may depend on the operator's `allowNonWorkspaceAccess`. Pass `--add-dir dirname(resultPath)` like the Claude adapter.
- `--mode` (`accept-edits`, `auto`, `plan`) was not needed.
- The model refused twice to dump the environment (`env | grep GH_TOKEN`: "I cannot execute commands designed to..."): a safety behavior around credentials. It does not matter for Carrier (the prompt only writes to `$CARRIER_RESULT_PATH`), but it means prompts must not ask the agent to print secrets.

## 4. Authentication failure

Provoked safely with an empty `HOME` (`HOME=<tmp>/fakehome BROWSER=/usr/bin/false agy -p ping ...`): the real login (`~/.gemini/antigravity-cli/antigravity-oauth-token`) was not touched.

- stderr, immediately: `Authentication required. Please visit the URL to log in:` followed by a Google OAuth URL and `Waiting for authentication (timeout...`.
- stdout, at the end: `{"event":"result","result":{"conversation_id":"","status":"ERROR","response":"","error":"authentication failed or timed out",...}}`, exit 1.
- **It waits.** Without `--print-timeout` it ended after **61 s**. With `--print-timeout 20s` it was still waiting after 60 s: that flag does not cover the login wait. So the failure is detected early by stderr (`Authentication required`) but the process only ends at ~60 s; the runner already waits for the process to close, so this works, it is just slow.
- Signals for `parseLine`: stderr `Authentication required` or the result's `error` equal to `authentication failed or timed out` (both set `authFailed`).
- Not observed: an expired token that the CLI refreshes itself, and an expiry in the middle of a long run. `AGY_CLI_NONINTERACTIVE_HEADLESS` appears in the binary's strings and might avoid the browser flow; not tested.

## 5. Marker, stop and orphans

`agy` has no flag to name a run (`--name`-like). `--log-file <path>` takes a path and is part of argv, so a path with the execution id works as the marker: `--log-file <dir>/carrier-exec-<executionId>.log`. `ps` showed the full argv and the log was written there (31 KB, language server lines). `markerRe = /carrier-exec-([\w-]+)/` in `host-runner.ts` matches it as it is.

Process tree during a foreground `python3 -c 'import time; time.sleep(N)'` (the shell tool):

```
agy -p ... --log-file .../carrier-exec-t2.log          pid 71101
  Python -c import time; time.sleep(412)               pid 72475  ppid 71101  own pgid
```

| Signal to `agy` | Stream and exit | Child after 3 s | Resume |
|---|---|---|---|
| `SIGTERM` | last line `{"event":"result",...,"status":"ERROR","error":"interrupted"}`, stderr `error: interrupted`, exit 1 | **none** (agy ends its children) | remembered the running command |
| `SIGINT` | same as SIGTERM | **none** | not repeated (same path) |
| `SIGKILL` | no `result`, exit 137 | **orphan** `Python -c ...sleep(413)` with ppid 1 | remembered the running command |

So `agy` is the cleanest of the three: Claude cleans up only on `SIGTERM`, Codex never. With the runner's `SIGTERM`, then grace, then `SIGKILL` (it signals the process group), the same residual risk as Claude remains only after `SIGKILL`. Note that `agy` exits 1 (not 143) on `SIGTERM`; the runner already decides the outcome from `reason` when it stopped the process.

## 6. Skills

- `agy` loads skills from `<workspace>/.agents/skills/<name>/SKILL.md` (the same folder Codex uses), from `~/.gemini/antigravity-cli/skills/`, from plugins (`agy plugin import claude|gemini`, `agy plugin install`) and from manifests: `.agents/skills.json` (project) or `~/.gemini/config/skills.json` (global) with `{"entries":[{"path": "<dir>", "include_only": [...], "exclude": [...]}]}`. A directory entry loads the items directly inside it.
- A test skill in `.agents/skills/spike-skill/SKILL.md` ("create `skill-ran.txt` with `SKILL-OK <arguments>`") ran headless with `agy -p "/spike-skill alpha-42"`: the stream shows one `write_to_file`, the file has `SKILL-OK alpha-42`. So `/name args` expands the skill in print mode, like Claude's. With `--disable-slash-commands` the model still found and ran the skill from its description (`SKILL-OK beta-7`), so the flag does not make skills unavailable.
- Solve skills: with `.agents/skills.json` = `{"entries":[{"path":"/Users/vemec/DG-Projects/AshuLab/skills/solve/skills"}]}` the agent answered that it had `ship` ("Take a startable ticket - or a whole epic - and carry it to done...") and `code-review` ("Adversarially reviews a pull request..."). Their names are plain (`ship`, not `solve:ship`), so the prompt would use `/ship`, like `$ship` for Codex. The real `ship` was **not** run.
- Condition: Carrier must not write `.agents/skills.json` into the user's repos. The Solve skills have to be visible to `agy` globally: `~/.gemini/config/skills.json` pointing at the Solve plugin's `skills/` folder (not tested; the project-level manifest was), or `agy plugin import claude`. `carrier doctor` should check it.

## 7. Models

`agy models` prints `id<TAB>label`, one per line, after a `Fetching available models...` line:

```
gemini-4-argon-medium	Gemini 4 Argon (Medium)
gemini-3.8-flash-low	Gemini 3.8 Flash (Low)
claude-sonnet-5-5-high	Claude Sonnet 5.5 (High)
gpt-oss-120b-medium	GPT-OSS 120B (Medium)
```

`--model <id>` takes the first column (verified with `gemini-3.8-flash-low` and `-medium`); the effort is part of the id (there is also `--effort`, not needed). An unknown id fails fast: exit 1, `result.status` `ERROR` with `invalid model selection ... Available models:` and the labels. `carrier init` can list the models by running `agy models` and skipping the first line. Note that the list includes Claude and GPT-OSS models served through Antigravity: for `agy` the provider question is "Antigravity" and the model carries the family.

## 8. Environment, config and Forge

- `GH_TOKEN`, `GIT_AUTHOR_NAME`, `GIT_CONFIG_COUNT/KEY/VALUE` and `CARRIER_RESULT_PATH` set on the `agy` process reached a script run by its shell tool (checked with a script that prints only presence/non-secret values): `GH=set AUTHOR=Bot X COUNT=1 RESULT=/some/result.json EMAIL=bot@x.test`. `childEnv()` therefore works unchanged, including the credential-helper entries.
- There is **no** variable like `CLAUDE_CONFIG_DIR` or `CODEX_HOME` (searched the binary's strings; the only relevant ones are `XDG_CONFIG_HOME` and `ANTIGRAVITY_EXECUTABLE_DATA_DIR`, not tested). A different `HOME` isolates it completely (it created its own `~/.gemini` in the fake home and asked for a login), but that also hides the user's `~/.gitconfig` and `~/.config/gh`, so it is not a per-execution isolation. As with Claude and Codex today, Carrier would use the operator's own login and config; every run shares one OAuth login (parallel runs worked).
- The operator's config has `hooks` in `~/.gemini/antigravity-cli/settings.json` and `~/.gemini/settings.json`: like Claude's hooks and Codex's plugins, they apply to the unattended run. Same trap as in the headless spike, untested here.
- Agent Forge launches `agy` differently: it has no per-process prompt flag, so Forge writes a global custom agent (`~/.gemini/config/agents/<name>/agent.md`, `agentForge: true` marker, **no** `description:` because a description makes `agy` strip `run_command` and the write tools) and passes `--agent <name>`. Carrier does not need that: it does not use Forge's launcher, it builds the environment itself and puts the identity in the prompt and in the env, and the default agent (no `--agent`) has `run_command` (verified above). So no custom agent file has to be written for Carrier runs.

## Recommendation

`agy` can be an adapter with the same guarantees as Claude and Codex: resume, stop, marker, auth detection and skills, with the two caveats above.

Proposed command (cwd = the epic's workspace, stdin ignored, `detached: true` as the runner already does):

```
agy -p <prompt>
    --output-format stream-json
    --model <model id from `agy models`>
    --dangerously-skip-permissions
    --add-dir <dirname(resultPath)>
    --log-file <logs>/carrier-exec-<executionId>.log          # the marker
    [--conversation <resumeSession>]                          # on resume
```

Env: `childEnv(ctx)` plus `CARRIER_RESULT_PATH`, optionally `AGY_CLI_DISABLE_AUTO_UPDATE=1` (the name is in the binary's strings; not tested) so a flag cannot change mid-epic.

`parseLine`, by line (stdout and stderr both go through it):

| Line | Signal |
|---|---|
| stdout JSON with `event: "init"` and a string `conversation_id` | `{ session: conversation_id }` |
| stdout JSON `event: "result"` with `result.error` equal to `authentication failed or timed out` | `{ authFailed: true }` |
| stderr text containing `Authentication required` | `{ authFailed: true }` |
| stderr text matching `warning: conversation ".*" not found` | `{ sessionUnavailable: true }` |
| anything else | nothing |

Exit semantics: 0 with `result.status` `SUCCESS` is `ok`; exit 1 is `failed` unless a signal above or the runner's own `reason` (`stopped`, `timed_out`) applies. The runner's SIGTERM-then-SIGKILL works as is.

Also needed outside the adapter: `harness: "agy"` in the config schema, a default binary resolution (`~/.local/bin/agy`, skipping wrappers, like `resolveBinary`), the prompt's skill invocation `/ship`, `/code-review`, `/code-post`, `/code-resolve` (same slash form as Claude), `carrier init` listing `agy models`, and a `carrier doctor` check that `agy` is installed, logged in and sees the Solve skills.

### Not verified

- A real `ship` or `code-review` run through `agy` (hours-long runs, many tool calls, subagents, context compaction), and whether a failing tool or a model error mid-run changes the exit code or the `result` shape.
- Global skills visibility (`~/.gemini/config/skills.json` and `agy plugin import claude`); only the project-level `.agents/skills.json` was tested. `agy plugin import` would modify the operator's config and was not run.
- Auth in the middle of a run, token refresh and expiry, quota or rate-limit errors, and the behavior with several Google accounts (`AGY_ACCOUNT` appears in the strings).
- `--print-timeout` as a replacement for Carrier's own timeout (it did not cover the login wait; not measured for a long turn).
- `AGY_CLI_NONINTERACTIVE_HEADLESS` and `AGY_CLI_DISABLE_AUTO_UPDATE` (names only seen in the binary), `--sandbox`, `--mode` and `--effort`.
- The operator's `settings.json` hooks and permissions applying to unattended runs; a clean config was not tried except for the empty-`HOME` auth test.
- The Linux behavior of signals and process groups. Only macOS, one run per case, with flash models.
- Cleanup: the 14 spike conversations whose ids were captured were deleted from `~/.gemini/antigravity-cli/` (`conversations/`, `brain/`, `annotations/`); the runs made with `--output-format json` (id not saved) and the spike's prompts in `history.jsonl` remain.
