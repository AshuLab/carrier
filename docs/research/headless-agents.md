# Claude and Codex in headless mode

> Spike from 2026-10-15 (issue #5, epic #3). Answers the open question "Claude and Codex headless" of the [spec](../specs/autonomous-orchestrator.md). Everything was run in a disposable repo in `/tmp`, with no remote, no credentials of real repos and with minimal prompts. It is not an isolation test: that is the containers spike ([ADR 0003](../adr/0003-agents-in-containers.md)).

## Result

| Definition of done criterion | Result |
|---|---|
| 1. Versions and exact non-interactive command that invokes a skill (Claude and Codex) | pass |
| 2. Session id, files, resume command and evidence that it remembers | pass |
| 3. JSON written to a given path and valid against `CallerResult` | pass |
| 4. Execution cut with `kill`: what survives, whether it resumes, child processes (`ps`) | pass |
| 5. Delegation to subagents or children and orphans when the parent is killed | pass |
| 6. Each criterion as pass/fail, options and spec/ADR | pass (see [Impact](#impact-on-the-spec-and-the-adrs)) |

Both CLIs work as a base for the runner. What the runner cannot take for granted: killing the CLI does not always kill its children (table in points 4 and 5), so stopping has to rely on the container or on killing the process group of each command, not on the signal to the CLI.

## Environment

- macOS (Darwin 27.0.0), Node v25.6.0, pnpm 12.4.1, `zod` 4.6.7 only in the validation script.
- Claude Code **2.1.301**, authenticated with the operator's claude.ai account. Model used: alias `haiku` (`claude-haiku-5-5`). `CLAUDE_CONFIG_DIR=/Users/vemec/.claude-ashu-lab`.
- Codex CLI **0.153.4**, authenticated with ChatGPT. Model: the default from `~/.codex/config.toml` (`gpt-5.6-terra`).
- Disposable repo: `git init` in `/tmp/carrier-spike5.XXXXXX/repo` with a single commit, no remote. The test skill is a `SKILL.md` in `.claude/skills/spike-skill/` and in `.agents/skills/spike-skill/` that writes `skill-ran.txt` with `SKILL-OK <arguments>`. `ship` and no real Solve skill were run (they would need GitHub).
- Environment trap: on this machine `claude` and `codex` on the `PATH` resolve to Superset wrappers (`~/.superset/bin/`). The Codex one is a bash script that adds `--enable hooks --dangerously-bypass-hook-trust` (hence the `--dangerously-bypass-hook-trust is enabled` warning in the JSONL) and intercepts signals. The kill experiments use the real binary `~/.local/bin/codex`. The runner must invoke the real binary, not a wrapper.
- Configuration trap: the CLIs load the user's configuration (Claude session hooks, Codex plugins such as Slack or Calendar, `CLAUDE.md`). A runner must isolate `CLAUDE_CONFIG_DIR` and `CODEX_HOME` per execution; this was not tested here.

## 1. Non-interactive command that invokes a skill

Claude (the skill is invoked with `/name arguments` as the prompt):

```sh
cd <repo> && claude -p "/spike-skill alpha-42" --permission-mode bypassPermissions --output-format json --model haiku </dev/null
```

Observed output (trimmed): `"is_error":false`, `"result":"DONE"`, `"session_id":"91b46ab3-3e4f-4e4d-b258-3ce035154567"`, `"terminal_reason":"completed"`, `exit=0`, and `skill-ran.txt` with `SKILL-OK alpha-42`.

Codex (the skill is invoked with `$name arguments`; it discovers skills in the repo's `.agents/skills/`):

```sh
cd <repo> && codex exec '$spike-skill alpha-42' --sandbox workspace-write --json </dev/null
```

Observed output: `exit=0`, events `thread.started` (`thread_id` `01a141eb-6773-7263-b951-dd09037967bd`), an `agent_message` "Uso `spike-skill` para crear el marcador solicitado.", a `file_change` on `skill-ran.txt`, `agent_message` `DONE` and `turn.completed`. `skill-ran.txt` contains `SKILL-OK alpha-42`.

Notes for the adapter:

- Codex, if there is a stdin that is not a terminal, prints `Reading additional input from stdin...` and waits for EOF; with `</dev/null` it does not hang. Do the same with Claude.
- `claude -p` does not ask for permissions with `--permission-mode bypassPermissions` (equivalent to `--dangerously-skip-permissions`; acceptable only inside the ADR 0003 container). Codex with `--sandbox workspace-write` writes inside the repo without asking; outside it needs `--add-dir <path>` (point 3).
- Machine-readable output: Claude `--output-format json` (one object at the end) or `stream-json --verbose` (one event per line); Codex `--json` (JSONL of events). Both CLIs also accept a structured output schema (`claude --json-schema`, `codex exec --output-schema`); not tested.
- Only versions `2.1.301` and `0.153.4` were verified; flags can change between versions, so pinning them is advisable.

## 2. Session: id, files and resume

| | Claude | Codex |
|---|---|---|
| How the id is obtained | `session_id` field of the result (`--output-format json`/`stream-json`); it can also be set in advance with `--session-id <uuid>` | first event of the JSONL: `{"type":"thread.started","thread_id":"..."}` |
| Where it lives | `$CLAUDE_CONFIG_DIR/projects/<cwd with / and . as ->/<id>.jsonl` (e.g. `~/.claude-ashu-lab/projects/-private-tmp-carrier-spike5-4J4kU3-repo/0b8e5745-6b93-4d7a-8a8b-ea52dce13c29.jsonl`) | `$CODEX_HOME/sessions/YYYY/MM/DD/rollout-<date>-<id>.jsonl` (e.g. `~/.codex/sessions/2026/10/15/rollout-2026-10-15T20-35-49-01a141ec-06ab-7c00-80b1-aa33e00f2ae9.jsonl`) |
| Resume | `claude -p "<prompt>" --resume <id> ...` | `codex exec resume <id> "<prompt>" ...` |

Claude evidence (the session was created by stating a code and resumed in a new process):

```
$ claude -p "Remember the codeword TANGERINE-93. Reply only OK." --permission-mode bypassPermissions --output-format json --model haiku
{"session_id":"0b8e5745-6b93-4d7a-8a8b-ea52dce13c29","result":"OK","is_error":false}
$ claude -p "What was the codeword? Reply with only the codeword." --resume 0b8e5745-6b93-4d7a-8a8b-ea52dce13c29 --permission-mode bypassPermissions --output-format json --model haiku
{"session_id":"0b8e5745-6b93-4d7a-8a8b-ea52dce13c29","result":"TANGERINE-93","is_error":false}
```

Codex evidence:

```
$ codex exec "Remember the codeword TANGERINE-93. Reply only OK." --sandbox workspace-write --json
{"type":"thread.started","thread_id":"01a141ec-06ab-7c00-80b1-aa33e00f2ae9"} ... agent_message "OK"
$ codex exec resume 01a141ec-06ab-7c00-80b1-aa33e00f2ae9 "What was the codeword? Reply with only the codeword." -c 'sandbox_mode="workspace-write"' --json
{"type":"thread.started","thread_id":"01a141ec-06ab-7c00-80b1-aa33e00f2ae9"} ... agent_message "TANGERINE-93"
```

Details that matter to the adapter:

- `codex exec resume` does not accept `--sandbox` or `-C`/`--cd`: the sandbox is passed with `-c 'sandbox_mode="..."'` and the cwd is that of the process. The resume keeps the same `thread_id`.
- Claude keeps the same `session_id` on resume. Resuming from another folder (`cd <other> && claude -p ping --resume <id>`) also worked: the id is found regardless of the cwd and the original file remains the one in the origin folder, so the exact cwd does not need to be preserved, but mounting the persistent sessions directory is advisable (ADR 0003).
- Each headless Claude execution with `-p` creates a new session file unless `--resume` is used; the runner must store the id of each execution.

## 3. Caller JSON validated with `CallerResult`

The prompt asks to write, to a path outside the repo (`/tmp/.../out/<agent>-result.json`), a `completed` with a real `pr.headSha` (`git rev-parse HEAD`). For Codex to be able to write outside the workspace, `--add-dir <folder>` is added; Claude with `--add-dir` too.

```sh
claude -p "<prompt with OUTPATH>" --permission-mode bypassPermissions --add-dir <out> --output-format json --model haiku </dev/null
codex exec "<prompt with OUTPATH>" --sandbox workspace-write --add-dir <out> --json </dev/null
```

Disposable validator (copy of the spec's `CallerResult`, run with `node validate.mjs <file>` in a separate folder with `zod` installed):

```js
import { z } from 'zod';
import { readFileSync } from 'node:fs';
const Sha = z.string().regex(/^[0-9a-f]{40}$/);
const Pr = z.object({ number: z.number().int().positive(), headSha: Sha });
const Common = {
  executionId: z.string().min(1),
  repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/),
  epic: z.number().int().positive(),
  stage: z.enum(['ship', 'review', 'fix']),
  summary: z.string().min(1),
};
export const CallerResult = z.discriminatedUnion('outcome', [
  z.object({ ...Common, outcome: z.literal('completed'), pr: Pr,
    verification: z.object({ ci: z.enum(['passed', 'absent']), evidence: z.string().min(1) }) }),
  z.object({ ...Common, outcome: z.literal('changes_requested'), stage: z.literal('review'), pr: Pr,
    blockers: z.array(z.object({ title: z.string().min(1), url: z.string().url().optional() })).min(1) }),
  z.object({ ...Common, outcome: z.literal('needs_human'), reason: z.string().min(1) }),
]);
const r = CallerResult.safeParse(JSON.parse(readFileSync(process.argv[2], 'utf8')));
console.log(r.success ? 'VALID outcome=' + r.data.outcome : 'INVALID ' + JSON.stringify(r.error.issues));
process.exit(r.success ? 0 : 1);
```

Observed results:

```
claude-result.json  ->  VALID outcome=completed
codex-result.json   ->  VALID outcome=completed
negative control (epic 0, headSha "abc") -> INVALID [... "path":["epic"] ... "path":["pr","headSha"] ...]
```

Claude's JSON came out formatted, with `summary` and `evidence` written by the model; Codex's came out on one line. With both, the `executionId`, `repo`, `epic` and `stage` repeat what the prompt asked for. Neither invented fields. It is a single attempt per agent with a short prompt: it does not measure the invalid-JSON rate, which the spec already covers with a retry on technical failure.

## 4. Execution cut with `kill`

Task: remember a code (`KUMQUAT-58`), create `step1.txt`, run in the foreground `python3 -c 'import time; time.sleep(31x)'` and create `step3.txt`. A few seconds after the sleep starts, the signal is sent to the CLI process (not the wrapper) and what remains is inspected with `ps`. Then the session is resumed, asking to skip the sleep and complete step 3.

Process tree before killing (Claude): `claude -p` → `codegraph-mcp` (the user's MCP server) and `/bin/zsh -c ...` (the Bash tool) → `Python -c ...sleep`. Codex: `codex exec` → `node_repl` (x2), `codex-code-mode-host` and `Python -c ...sleep` (each with its own pgid).

| Agent | Signal | Files and session | Children after `ps` | Resume |
|---|---|---|---|---|
| Claude | `SIGTERM` | `step1.txt` remained; the session `.jsonl` (`f485db74-...`) remained on disk; the stream showed the tool interrupted with `Exit code 137`; CLI exit 143 | none: shell, `python` and `codegraph-mcp` terminated | `--resume`: remembered `KUMQUAT-58`, saw `step1.txt`, created `step3.txt` |
| Claude | `SIGKILL` | same (`step1.txt`, session `4c9033c2-...`); exit 137 | **orphans**: `/bin/zsh -c ...` (pid 92565, ppid 1) and `Python -c ...sleep` (pid 92566); `codegraph-mcp` did terminate | remembered `KUMQUAT-58`, created `step3.txt` (the orphans were killed beforehand) |
| Codex | `SIGTERM` to the real CLI | `step1.txt` and the rollout (`01a141f0-f9c7-7f81-876e-a7dae35e24de`) remained; exit 143 | **orphan**: `Python -c ...sleep` (pid 2267, ppid 1); `codex`, `node_repl` and `codex-code-mode-host` terminated | `exec resume`: remembered `KUMQUAT-58`, created `step3.txt` |
| Codex | `SIGKILL` | same (`01a141f3-6884-7190-a479-7384db9b72ad`); exit 137 | **orphan**: `Python -c ...sleep` (pid 12705, ppid 1) | remembered `KUMQUAT-58`, created `step3.txt` |

Illustrative `ps` output, after `kill -KILL` of the Claude CLI:

```
92565     1 92565 01:33 /bin/zsh -c source /Users/vemec/.claude-ashu-lab/shell-snapshots/snapshot-zsh-...sh ...
92566 92565 92565 01:33 /Applications/Xcode.app/.../Python -c import time; time.sleep(312)
```

and after `kill -TERM` of the Codex CLI:

```
 2267     1  2267       02:11 /Applications/Xcode.app/.../Python -c import time; time.sleep(313)
```

Conclusions:

- What always survives: the files written before the cut and the session file (written incrementally). Resuming works with both CLIs, with any signal.
- Claude with `SIGTERM` cleans up its children; with `SIGKILL` it does not (nobody can). Codex does not clean up the command's process even with `SIGTERM`: it was left orphaned in both cases.
- The children are in their own process group, so killing the CLI's group is not enough; they were cleaned up with `kill -TERM <pid>` or `kill -TERM -<pgid>` of the orphan. In the runner, the container solves this (ADR 0003: "killing the container reaches the child processes"). Without a container, descendants would have to be recorded before killing.
- My first attempt to kill Codex was on Superset's bash wrapper: the `SIGTERM` did not terminate it (it has a `trap`) and the real CLI kept running. Killing the wrapper does not stop Codex; confirm the real pid.
- My first attempt with Claude and `sleep 311` showed that Claude 2.1.301 blocks a bare foreground `sleep` and sends it to the background; that is why the experiments use `python3 -c 'import time; time.sleep(N)'`.
- When resuming after a cut, the agent must be told to verify the real state (the session does not record the real effect of the interrupted tool), as the spec already anticipates.

## 5. Delegation to subagents or child processes

Prompt: "launch ONE subagent that runs in the foreground `python3 -c 'import time; time.sleep(N)'` and wait for it". Claude did it with the `Agent` tool (`tool_use` events `Agent` and then the subagent's `Bash`); Codex with a `collab_tool_call` (`codex features list`: `multi_agent` is `stable` and enabled). In both, the sleep ran in a grandchild process of the CLI.

| Agent | Signal to the parent | Orphans |
|---|---|---|
| Claude (`Agent` subagent) | `SIGTERM` | none (the shell and the `python` terminated with the CLI) |
| Claude (`Agent` subagent) | `SIGKILL` | `/bin/zsh -c ...` (pid 20914, ppid 1) and `Python -c ...sleep(317)` (pid 20915) |
| Codex (subagent) | `SIGTERM` | `Python -c ...sleep(318)` (pid 26052, ppid 1) |
| Codex (subagent) | `SIGKILL` | `Python -c ...sleep(319)` (pid 28408, ppid 1) |

Subagents are not processes of their own: they live inside the parent CLI; what is left orphaned are the commands they ran. It is the same behavior as in point 4. A simple subagent was used, not the real `ship` (which dispatches up to three per batch): the child mechanism is the same, but the number of orphans would grow with parallelism.

All the orphans were documented with `ps` and killed at the end; at the end no process from the experiments remained, and the temporary folder and the experiments' session files were deleted (which is why the example paths no longer exist).

## Options and recommendation

No criterion fails, but there is an operational risk: orphans. Options for the runner's stop:

1. **One container per execution, kill it on stop (ADR 0003, already decided).** It covers all the cases above with no extra code. What remains pending is testing it in the containers spike.
2. Record the process tree (recursive `pgrep -P`) before sending `SIGTERM` to the CLI and kill the remaining ones after a grace period. It serves as a safety net on the host and for tests, it does not replace the container.
3. Launch each CLI in its own session group (`setsid`) to be able to kill by group. It is not enough: the command's shell opens another group (a different `pgid` was seen) and there is no native `setsid` on macOS.

Recommendation: keep option 1 and have the runner send `SIGTERM` first (Claude cleans up its children) and leave the final cleanup to the container.

## Impact on the spec and the ADRs

No result contradicts the spec or ADR 0003. What was observed supports the ADR: killing the CLI does not reach the child processes on the host (Codex not even with `SIGTERM`), so the assumption "killing the container terminates all processes" is what the containers spike must confirm. The spec received a short paragraph in the validations section that links this document and lists the runner's traps (real binary, `</dev/null`, `--add-dir`, `exec resume` without `--sandbox`).

## Limitations

- Toy skill, not `ship`: it was not verified that the real `ship` (with `gh`, parallel subagents and sessions of hours) works without interaction.
- A single attempt per case, with no measurement of variability between runs; Claude was tested with `haiku`, not with the model the real author would use.
- `--bare`, `--ignore-user-config` and `--no-session-persistence` were not tested, nor the isolation of `CLAUDE_CONFIG_DIR`/`CODEX_HOME`, nor limits (`--max-budget-usd`, `--max-turns`).
- macOS only; the behavior of signals and process groups in the Linux container belongs to the containers spike.
