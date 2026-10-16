# Claude and Codex inside containers on macOS

> **Status: discarded for this version (2026-10-15).** Diego decided that agents run on the host with the terminal's preferences ([ADR 0004](../adr/0004-agents-run-on-host-with-terminal-preferences.md), which replaces ADR 0003). This document is kept as starting material for the security of unattended (AFK) agents; the unchecked boxes will not be closed for now.

> Spike from 2026-10-15 (issue #6, epic #3). Answers the open question "Agents in containers" of the [spec](../specs/autonomous-orchestrator.md) and tests [ADR 0003](../adr/0003-agents-in-containers.md). Everything was run in a temporary folder under `/tmp`, with a disposable repo and a local Git remote (`git init --bare`), with no real credentials inside any container and without touching GitHub. The scripts are disposable: [`spike-agent-containers/`](spike-agent-containers/) (`Dockerfile`, `mock-llm.mjs`, `proxy.mjs`).

## Verdict

**Viable with conditions.** What depended on the container works: consistent Solve worktrees inside and outside, both CLIs run on Linux and do `git status`/commit/push from their shell tool, the session is resumed in a new container, `pnpm test` runs, the network can be restricted with an allowlist and `docker kill` leaves no processes behind. Three things that need real credentials remain **unverified**, and that is why the spike is not fully closed (detail in [Unverified](#unverified-and-what-would-close-it)):

1. Claude and Codex truly authenticated inside the container, and push to a test GitHub repo. The CLIs were tested against a simulated model.
2. An execution of more than 70 minutes with `gh` authenticated and the token renewed by Forge.
3. The network list with a real login (ChatGPT account, Claude OAuth): it was only observed with fake keys.

No result contradicts ADR 0003. There are three new conditions for the runner: mount with paths identical to the host's, run `codex` without its own sandbox (the container is the boundary) and resolve the login without mounting `~/.claude*` (see [Sessions and login](#3-sessions-and-login)).

| Definition of done criterion | Result |
|---|---|
| 1. Document with runtimes tested, versions and recommended one | pass, but only Docker Desktop was installed; OrbStack and Colima were not tested |
| 2. Claude and Codex in a container: `git status`, commit and push; consistent `git worktree list` | partial: consistency, commit and push (to a local remote) pass with a simulated model; real login and push to GitHub are missing |
| 3. Session resumed in a new container and where it is on the host | pass (simulated model) |
| 4. More than 70 minutes with `gh` authenticated and a renewal mechanism | **not verified**; the mounted-file mechanism was tested with fake tokens |
| 5. `pnpm test` in the container and toolchain strategy | pass |
| 6. Minimal network egress and whether it can be restricted | pass for use with an API key; with a real login it remains unobserved |
| 7. Stopping the container with a running process tree leaves no processes | pass |
| 8. Verdict | viable with conditions |

## Environment and runtimes

| | |
|---|---|
| System | macOS 27.0 (Darwin 27.0.0), arm64 |
| Runtime tested | **Docker Desktop 4.95.0**: Engine 29.8.2, containerd v2.3.6, runc 1.5.1, VM kernel `7.0.14-linuxkit`, `overlayfs` driver, cgroup v2; client 29.8.2 |
| VM | 12 CPU, 7.75 GiB of memory (installation defaults) |
| OrbStack, Colima | **not installed** on this machine (`which orb colima` returns nothing). They were neither tested nor installed so as not to modify it |

Recommendation: **Docker Desktop**, because it is the only one that could be tested and everything below was measured with it. There is no evidence that OrbStack or Colima fail; the design only uses `docker run/kill/stop`, folder mounts, networks and `--init`, which all of them expose, but this was not verified. Two considerations that were not measured: the VM has fixed memory (7.75 GiB) that has to be shared among the parallel epics, and Docker Desktop has license terms for companies that are worth reviewing before adopting it as a requirement.

Test image ([`Dockerfile`](spike-agent-containers/Dockerfile)): `node:26-bookworm-slim` + `git` 2.39.5 + `gh` 2.23.0 (Debian package, old; for production the official `gh` repository is preferable) + `pnpm` 12.4.1 + Claude Code 2.1.301 + Codex CLI 0.153.4, both installed with `npm i -g` and running as `linux-arm64` binaries. Docker reports ~2 GB on disk. Startup and exit of an empty container: 0.15-0.16 s (3 measurements).

## 1. Mounts and Solve worktrees

Test layout, the same as Solve's: clone in `<root>/repos/acme/demo`, worktree in `<root>/worktrees/demo/feat-demo` and bare remote in `<root>/remote/demo.git`. The worktree's `.git` file contains the **absolute** path of the clone (`gitdir: <root>/repos/acme/demo/.git/worktrees/feat-demo`), which is why the path matters. All cases run as `-u 1000:1000`.

| Mount | Result inside |
|---|---|
| clone and worktree at the **same path** as on the host | `git worktree list` identical to outside; `git status -sb` correct |
| only `<clone>/.git` and the worktree, at the same paths | identical; the clone's `.git` folder is enough |
| worktree at `/work`, clone at its path | `git status` works, but `git worktree list` marks the worktree `prunable` (the clone registers it at the host path): a `git worktree prune` inside would delete it |
| only the worktree, without the clone | `fatal: not a git repository: <clone>/.git/worktrees/feat-demo` |

Output of the good case, inside (outside is identical):

```
/private/tmp/carrier-spike6/solve/repos/acme/demo           e037b92 [main]
/private/tmp/carrier-spike6/solve/worktrees/demo/feat-demo  e037b92 [feat/demo/epic]
```

Details the runner has to respect:

- **Identical paths.** Mount `-v <path>:<path>` with the resolved path (`/tmp` is `/private/tmp` on macOS; the worktree's `.git` stores the resolved one).
- **`safe.directory`.** With a non-root user, Git rejects the repo with `detected dubious ownership`, because the mount folder appears as owned by root inside the container. `GIT_CONFIG_COUNT/KEY/VALUE` with `safe.directory=*` did not fix it in Git 2.39.5; `git config --system safe.directory '*'` in the image did (last line of the `Dockerfile`).
- **Owner.** Files created inside by uid 1000 appear on the host with the user's uid (501): Docker Desktop translates, no `chown` is needed.
- **What else gets mounted.** The experiment's remote (`<root>/remote`) only exists because it is local; in production the remote is GitHub. The `.git` folder mounted writable exposes to the agent all the refs and the clone's configuration (including other epics' branches); that is the cost of making `git commit` work from a worktree. A reviewer with a separate checkout ([spec](../specs/autonomous-orchestrator.md)) needs its own worktree and the same mount.

## 2. Claude and Codex run Git inside the container

**How it was tested.** There are no model credentials available in a safe way, so the CLIs point to a simulated model ([`mock-llm.mjs`](spike-agent-containers/mock-llm.mjs)) that speaks the Anthropic API (`ANTHROPIC_BASE_URL`) and OpenAI's (`mock` provider in Codex's `config.toml`). If the prompt carries `GITFLOW:<command>`, the mock replies with a call to the CLI's shell tool (`Bash` in Claude, `exec_command` in Codex); then it replies `DONE`. What is tested is what matters to the spike: the real CLI, on Linux, running real Git commands through its own tool against the mount. It does **not** test the login or the behavior of a real model.

Claude (`stream-json`, trimmed):

```
$ docker run --rm -u 1000:1000 -e CLAUDE_CONFIG_DIR=/state/claude -e ANTHROPIC_BASE_URL=http://host.docker.internal:18080 -e ANTHROPIC_API_KEY=sk-ant-mock-not-real \
    -v <state>:/state -v <clone>/.git:<clone>/.git -v <worktree>:<worktree> -v <root>/remote:<root>/remote -w <worktree> carrier-spike6:base \
    claude -p 'GITFLOW:git status -sb && ... git commit ... && git push origin HEAD && git worktree list' --permission-mode bypassPermissions --output-format stream-json --verbose --model haiku </dev/null
TOOL_RESULT ## feat/demo/epic
To <root>/remote/demo.git
 * [new branch]      HEAD -> feat/demo/epic
<root>/repos/acme/demo           e037b92 [main]
<root>/worktrees/demo/feat-demo  fdd6153 [feat/demo/epic]
RESULT DONE false
```

Codex (`--json`, `command_execution` event with `exit_code: 0`): same flow, push to `feat/demo/codex`, `git worktree list` inside with the worktree at `0d69e89`.

Outside, after the two containers: the worktree's `git log` shows both agents' commits (`fdd6153`, `0d69e89`), `git worktree list` shows them at those SHAs, and `git branch -a` of the bare remote lists `feat/demo/epic` and `feat/demo/codex`. The commits made inside are visible outside without copying anything.

Conditions of each CLI in a container:

- **Codex: its own sandbox does not work inside the container.** With `--sandbox workspace-write` the command fails: `bwrap: No permissions to create a new namespace, likely because the kernel does not allow non-privileged user namespaces` (`exit_code: 1`). With `--sandbox danger-full-access` it runs. This is consistent with the ADR: the boundary is the container, not the CLI's sandbox. The adapter must pass `danger-full-access` (or `-c 'sandbox_mode="danger-full-access"'` in `exec resume`). Getting `bwrap` to work with extra capabilities was not tried: it would widen the container's privileges needlessly.
- **Claude: does not run `bypassPermissions` as root.** As uid 0 it prints `--dangerously-skip-permissions cannot be used with root/sudo privileges for security reasons`. Running as `-u 1000:1000` it works without further ado. With uid 0 and `IS_SANDBOX=1` it also runs, but it is better not to use root.
- Claude needed no sandbox adjustments: its `Bash` tool ran the full Git flow with `bypassPermissions`.
- Both are launched with stdin closed (`</dev/null`), as in the [headless spike](headless-agents.md).

## 3. Sessions and login

With each CLI's state in a host folder mounted as `CLAUDE_CONFIG_DIR` / `CODEX_HOME`, the session survives destroying the container.

| | Claude | Codex |
|---|---|---|
| Where it ends up on the host | `<state>/claude/projects/<cwd with / and . as ->/<session_id>.jsonl` (e.g. `.../projects/-private-tmp-carrier-spike6-solve-worktrees-demo-feat-demo/5e3af7a0-...jsonl`) | `<state>/codex/sessions/YYYY/MM/DD/rollout-<date>-<thread_id>.jsonl` |
| Resume in a new container | `claude -p "<prompt>" --resume <id> ...` | `codex exec resume <id> "<prompt>" -c 'sandbox_mode="danger-full-access"' ...` |

Evidence: the first container received "Remember the codeword TANGERINE-93"; it was destroyed (`--rm`); a new container, with the same mount, resumed the session and was asked `RECALL`. The simulated model returns `RECALLED:<codes present in what it received>`, so what is tested is that the CLI rebuilt the history from the persisted file and sent it to the model:

```
claude --resume 5e3af7a0-...   (new container)  -> session_id 5e3af7a0-... (the same)  result "RECALLED:TANGERINE-93"
claude without --resume        (control)         -> new session_id                     result "RECALLED:NONE"
codex exec resume 01a14244-7792-... (new container) -> thread_id the same              agent_message "RECALLED:TANGERINE-93"
codex exec without resume      (control)         -> new thread_id                      agent_message "RECALLED:NONE"
```

For the runner:

- **The `cwd` is part of Claude's key.** The sessions folder is the `cwd` with `/` and `.` as `-`; that is why the worktree paths must be the same across containers (point 1 already requires it). The [headless spike](headless-agents.md) saw that resuming from another `cwd` also works on the host; it was not repeated here.
- **One state directory per execution or per agent of an epic, not a global one.** It prevents two parallel containers from writing the same `.claude.json` or the same `auth.json`, and it is what the [spec](../specs/autonomous-orchestrator.md) asks for ("without mixing them with those of another parallel one"). It must be under the shared root (`orchestrator/`), where the logs and sessions already are.
- **Login: `~/.claude*` cannot be mounted.** On this machine Claude's login is not in a file in the configuration directory (`~/.claude-ashu-lab/.credentials.json` does not exist); `security find-generic-password -s "Claude Code-credentials"` finds an entry in the macOS keychain, which a container does not see. Codex's login is the file `~/.codex/auth.json`, which could be copied, but it contains refresh tokens that rotate: copying it to several parallel executions risks invalidating the original. Alternatives to try with real credentials: `claude setup-token` ("Set up a long-lived authentication token" according to its help) or `ANTHROPIC_API_KEY` for Claude, and `codex login --with-api-key` / `OPENAI_API_KEY` for Codex. This was **not verified**: no real credential was mounted or read. It is the most important product decision the spike leaves: what kind of credential each agent uses in the container.

## 4. `gh` authenticated for more than 70 minutes

**Not verified.** It requires a disposable test GitHub repo and a Forge bot identity, which do not exist yet (slice #7 is paused because of that), and none was improvised.

What was measured, with fake tokens: the file-based renewal mechanism. `GH_CONFIG_DIR` points to a **read-only** mounted folder; `gh` reads `hosts.yml` on every invocation, so if the outside process rewrites it (with an atomic `mv`, and the mount is of the folder, not the file) the container sees the new token without restarting:

```
before: ghs_FAKE_TOKEN_ONE
after host rewrite (same running container, ro mount): ghs_FAKE_TOKEN_TWO
GH_TOKEN env wins and is fixed per process: ghs_FAKE_ENV
sh: 1: cannot create /ghcfg/x: Read-only file system      (the agent cannot write there)
```

Design consequences, to validate in the Agent Forge spike:

- `GH_TOKEN` in the environment is **not suitable** for executions of up to four hours: it is fixed per process and GitHub App installation tokens last one hour.
- Recommended: a process outside (Carrier, via `agent-forge token`) renews `hosts.yml` in that folder before it expires, and `git` uses `gh auth setup-git` as the credential helper so the push also reads the current token on every call. The alternative is a credentials proxy outside the container, at the cost of more moving parts.
- What would close the criterion: with the repo and the bot from slice #7, an execution of more than 70 minutes that does `gh auth status` and a push after minute 70, with the renewal running from outside.

## 5. `pnpm test` and toolchains

```
$ docker run --rm -u 1000:1000 -e HOME=/home/node -v <repo>:/w -w /w carrier-spike6:base sh -c 'node -v && pnpm install && pnpm test'
v26.12.0
+ zod 4.6.7   Done in 799ms using pnpm v12.4.1
$ node --test     ✔ zod   ℹ tests 1  ℹ pass 1  ℹ fail 0
```

Also `pnpm test` in the mounted Solve worktree (`demo` repo, `node --test`): passes. pnpm 12 respects the repo's `packageManager` field.

Recommended strategy: **one common base image** (Node, pnpm, git, `gh` and the two CLIs) and, only for the repo that needs it (another Node version, Python, databases, system dependencies), a derived image `FROM` the base declared in the repo's configuration. The base covers AshuLab's Node/pnpm repos with no per-repo work; one image per repo from day one would duplicate the CLI installation and its updates. A derived image and another real repo were not tested.

Risks the spike did not measure:

- `pnpm test` created untracked `node_modules/` and `pnpm-lock.yaml` inside the mounted worktree. A `node_modules` installed in the container is compiled for Linux; if the same worktree is later used from macOS (Diego testing the PR), native dependencies (e.g. `better-sqlite3`) would fail. It would be advisable for the container to install into its own volume or for Diego to reinstall.
- Tests of repos that need services (database, browser) were not tested.

## 6. Network egress

It was measured from containers on an `--internal` network (no route to the internet) and a purpose-built proxy ([`proxy.mjs`](spike-agent-containers/proxy.mjs), CONNECT with an allowlist) connected to that network and to a normal one. Both CLIs respect `HTTPS_PROXY`. Without the proxy, from the internal network: `curl https://api.github.com` fails (`000`); with the proxy: `200`.

Destinations observed at the proxy with **fake keys** (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`), one minimal question:

| Destination | Who | Needed |
|---|---|---|
| `api.anthropic.com` | Claude (13 connections) | yes; with the fake key it answers `Invalid API key`, that is, it got there |
| `http-intake.logs.us5.datadoghq.com` | Claude | no: telemetry; denied, Claude answered anyway. With `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` it does not appear and only `api.anthropic.com` remains |
| `api.openai.com` | Codex (`wss://.../v1/responses`, 13 connections) | yes (API key mode) |
| `chatgpt.com`, `github.com`, `api.github.com` | Codex | not in key mode: denied, Codex kept trying only with `api.openai.com`. `chatgpt.com` is indeed the ChatGPT login destination |
| `api.github.com` | the execution's `gh`/`git` | yes: proven reachable through the proxy (`200`) |
| `registry.npmjs.org` | `pnpm install` | yes if the repo installs dependencies. The point 5 installation ran on the normal network; through the proxy it was not tested (with the restricted list below it was denied) |

Proposed minimal list, restrictable: `api.anthropic.com` and/or `api.openai.com` depending on the profile's provider, `github.com` and `api.github.com`, and the repo's package registry, plus whatever is needed for the real login (see below). **It can be restricted**: with `ALLOW=api.anthropic.com,api.openai.com`, Claude and Codex worked the same and the proxy logged `DENY` for Datadog, `chatgpt.com`, `github.com`, `api.github.com`; `curl https://example.com` from the internal network failed. A container on an `--internal` network plus a proxy with a list is the way to enforce it; the network enforces the rule, not `HTTPS_PROXY`: an agent that ignores the variable has no direct route to the internet.

Pending: with a real login, Claude (OAuth) and Codex (ChatGPT) also use authentication hosts (`claude.ai`, `platform.claude.com`, `auth.openai.com` according to their documentation) that were not observed here. Observe the list with real credentials before fixing it in the configuration. It was not tested whether `pnpm install` or `gh` work fully through the proxy.

## 7. Stopping the container

Test: Claude and Codex inside a container run through their shell tool a tree that includes children, grandchildren and a process that leaves the group (`setsid nohup`):

```
sleep 300 & setsid nohup sleep 301 >/dev/null 2>&1 & sh -c 'sleep 302 & sleep 303 & wait' & sleep 304
```

Tree inside the container before killing (`docker exec ps`, Codex, 8 s after starting):

```
  PID  PPID  PGID STAT  COMMAND
    1     0     1 Ssl   node /usr/local/bin/codex exec GITFLOW:sleep 300 & setsid ...
   14     1     1 Sl    .../codex-linux-arm64/vendor/a...
  114    14   114 Ss    /bin/bash -c sleep 300 & setsid nohup sleep 301 ...
  115   114   114 S     sleep 300
  116   114   116 Ss    sleep 301          <- setsid: another group
  117   114   114 S     sh -c sleep 302 & sleep 303 & wait
  118   114   114 S     sleep 304
  119   117   114 S     sleep 302
  120   117   114 S     sleep 303
```

Claude's was equivalent (`claude` PID 1 → `bash` → 3 `sleep` and one `sh` with 2 grandchildren; the `setsid` `sleep 301` with `ppid` 1).

Result of `docker kill` (SIGKILL), measured with Python's `time.time()` around the call:

| Agent | `docker kill` | State | Remaining processes |
|---|---|---|---|
| Claude | 0.09 s | `Exited (137)` | none |
| Codex | 0.09 s | `Exited (137)` | none |

"No processes" was checked with `docker run --rm --pid=host carrier-spike6:base ps -eo pid,ppid,args | grep -E 'sleep 30|claude|codex'` (it sees the processes of the whole VM): no matches (`exit 1` from `grep`). Positive control: with a live `sleep 305` container, that same command does list it (`13690 13666 sleep 305`).

`docker stop` (SIGTERM, 10 s grace period), same tree:

| Agent | `--init` | Time | Exit code | Orphans |
|---|---|---|---|---|
| Claude | no | 1.68 s | 143 | none |
| Claude | yes | 0.26 s | 143 | none |
| Codex | no | 0.15 s | 0 | none |
| Codex | yes | 0.14 s | 0 | none |

This closes the [headless spike](headless-agents.md)'s assumption ("killing the container terminates all processes"): on the host Codex leaves the command orphaned even with `SIGTERM`; inside the container nothing remains, not even the process outside the group. `docker kill` is enough for `Ctrl+C`; `docker stop` gives the CLI the chance to close its session. `--init` is recommended to reap zombie processes (it reduces Claude's `stop` from 1.68 s to 0.26 s).

## Impact on the spec and the ADR

No result contradicts ADR 0003: the consistent mounts, the persistent session and stopping via the container work as it assumes. The detail of how changes, and the spec receives a short result paragraph in the open question "Agents in containers" with the runner's conditions and what is missing. It was not commented on in epic #3 because the verdict is not "not viable"; what is pending (real credentials and token renewal) depends on slice #7 and is reported in this slice's report.

## Unverified and what would close it

| Pending | What would close it |
|---|---|
| Claude and Codex truly authenticated inside the container (which credential, how it is injected, that a real model uses the shell tool without interaction) | Decide the credential type (API key, `setup-token`, `auth.json`) and run a real minimal prompt in the container with a disposable credential |
| Push to a test GitHub repo from each CLI in a container | The disposable repo and the Forge bot identity from slice #7; repeat the point 2 flow with a GitHub remote |
| `gh` authenticated for more than 70 minutes with renewal | The same, plus an execution of more than 70 minutes with `hosts.yml` renewal from outside (point 4) |
| Network list with a real login | Observe the proxy with a real Claude and Codex login and fix it in the configuration |
| OrbStack and Colima | Install them and repeat points 1, 2 and 7; only if Docker Desktop does not work because of license or resources |
| Linux vs macOS `node_modules`; tests with services; derived image per repo | A real AshuLab repo with its native dependencies |
| Four-hour executions and several parallel containers | Load test with the VM's memory limit |

## Limitations

- The model was simulated: the session, the tools and the mount are real, but there is no evidence of how Claude and Codex behave with real credentials and a real model in the container.
- A single run per case, on a single machine (macOS 27.0, arm64, Docker Desktop 4.95.0). Only `claude` 2.1.301 and `codex` 0.153.4 were tested.
- Local Git remote, not GitHub: HTTPS authentication, `gh` against the API and branch protection were not tested.
- Everything created was cleaned up: containers, networks, images, the simulator and the temporary folder. The images that already existed in Docker were not touched.
