# A bot's GitHub token does not run out in the middle of an agent execution

Status: spec

## Problem

An agent that runs as an Agent Forge bot gets one GitHub App installation token when its execution starts, in `GH_TOKEN` and `GITHUB_TOKEN`, and the git credential helper Carrier sets up answers with that same token for the whole run. GitHub expires that token after about an hour, and `maxExecutionHours` is four by default (or unlimited). Nothing renews it: the research on Forge ([agent-forge.md](../research/agent-forge.md), "Token renewal") says an injected token does not renew itself, and neither the runner nor the credentials code does anything about it. So any bot execution that goes past the hour loses `gh` and `git push` for the rest of the run, with a 401, and the agent has no instruction about what to do then.

Nobody has seen it fail yet: the case is structural, not observed. Executions may be shorter than an hour so far, or the agent may find `agent-forge` by itself. It is prevention, for the epics that will run long.

It matters to the person who leaves Carrier running unattended: a ship that drains many slices is the long run, and the failure would land late, after most of the work is done, as a push that is rejected or a PR that cannot be opened.

## Solution

Two parts, both only for `forge` profiles. A `gh` profile uses the user's own login, which does not expire the same way, and keeps today's behavior.

**git renews by itself.** The credential helper Carrier puts in the child's environment stops answering with the token the run started with. When git asks for a credential it runs `agent-forge token --agent <agent>` and answers with that fresh token, so a push after the first hour works without the agent doing anything. Git runs the helper at the root of the repo it is working in, which is a checkout whose `origin` is under the right owner, so Forge picks the right installation as it does for the engine. If Forge cannot mint (it prints nothing or fails), the helper falls back to the token the run started with, so a Forge hiccup in the first hour changes nothing, and after the hour the failure is the same 401 as today. The helper answers only the `get` operation, so git's `store` and `erase` do not mint tokens for nothing.

**gh is told how to recover.** `gh` reads the variable directly and cannot be made to renew. For a forge profile, `prompts/intro.ts` adds one rule: the token expires about an hour after the run starts, and if a `gh` call fails with 401, run it again as `agent-forge gh <agent> <the same arguments>` from inside the workspace, whose `origin` Forge needs. The rule depends on the agent following it, which is the cost of not shipping a `gh` shim.

What was cut. The three lines the idea arrived with, taken from Forge's own identity prompt, were not all worth it. "A human identity in CLAUDE.md is who drives the session, not who posts" and "commits go out as `<agent>[bot]`, do not change it" were dropped: who publishes is decided by the credentials and not by what the agent believes, git gives `GIT_AUTHOR_*` and `GIT_COMMITTER_*` priority over `git config user.name` so the agent cannot undo the authorship, and the user's own CLAUDE.md already says an injected posting identity wins. Nothing failed in a real run to justify them. "A human is driving interactively" and "say your identity in the first reply" are false or useless here. Forge's per-agent `systemPrompt` is not touched: [ADR 0011](../adr/0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md) leaves it unused on purpose. A `gh` shim earlier in the PATH, so `gh` renews without the agent: more code to keep, for the day the one rule is not enough. Renewing from the engine by killing and resuming the run at the hour: the session would lose its place for something a helper solves.

## Scope

1. An agent running as a Forge bot, past the first hour of an execution, pushes and fetches over HTTPS with a token minted at that moment, without being told anything.
2. If Forge cannot mint a token when git asks, the push or fetch goes ahead with the token the run started with, and does not fail for a reason the first token would not have.
3. The agent name that reaches the helper cannot make it run anything: it is data, never part of the shell text.
4. A run under a `gh` profile has the helper answer with its token as before, and its prompt has no mention of Forge.
5. The prompt of a Forge-bot run, in the ship, review and fix stages alike, tells the agent that its token expires after about an hour and how to run `gh` again with a fresh one on a 401.
6. A real run shows it: a token revoked in the middle of an execution (the stand-in for the hour passing) does not stop a `git push` through the helper, nor an `agent-forge gh` call from the child's environment.

## Decisions

**Where the agent name travels.** The credentials of an execution gain `forgeAgent`, the Forge agent's name, set only for a forge profile. `profileCredentials` already resolves the profile, so it is where the name is known, and it reaches the harness through the `CommandContext` that `HostRunnerOptions['credentials']` already feeds. From there `childEnv` exports it as `CARRIER_FORGE_AGENT`, a name and not a secret, and `buildPrompt` receives it for the prompt rule. The engine and `AgentTask` do not change: `task.profile` stays a profile name, and what a name resolves to is the credentials' job.

```ts
// credentials result and CommandContext gain:   forgeAgent?: string
// childEnv:                                     ...(forgeAgent && { CARRIER_FORGE_AGENT: forgeAgent })
// build-prompt.ts:  buildPrompt(task: AgentTask, { forgeAgent }: { forgeAgent?: string } = {})
// the three adapters (claude, codex, agy) pass ctx.forgeAgent
```

**The helper.** The name goes through the environment and the helper reads it as a variable, so nothing from the config is ever pasted into shell text, the same way the token already travels. This one helper serves both kinds of profile: without `CARRIER_FORGE_AGENT` it answers with `$GH_TOKEN`, as today. It was run against a fake `agent-forge` that answers, fails, prints nothing, and against a hostile name, before being written here.

```ts
const gitUsesToken =
  '!f() { [ "$1" = get ] || return 0; echo username=x-access-token; ' +
  't=$([ -n "$CARRIER_FORGE_AGENT" ] && agent-forge token --agent "$CARRIER_FORGE_AGENT" 2>/dev/null); ' +
  'echo "password=${t:-$GH_TOKEN}"; }; f';
```

**The cost per git call is not cached.** Each call signs a JWT and makes two requests to GitHub, about a second by the research's timings, on every authenticated fetch and push. It is small next to an agent run and a cache would bring back the problem it solves. The integration test prints the time it measures and asserts nothing about it. The call to `agent-forge` is bounded at 10 seconds by a watchdog in the helper (`timeout` is not on a stock macOS): a Forge that hangs falls back to the starting token instead of hanging git.

**Antigravity.** Nothing in its harness stops `agent-forge` from running: it is launched with permissions skipped and, as its own comment says, there is no sandbox to turn off; Claude and Codex are launched with permissions bypassed too (ADR 0004). The rule in the prompt is the same for the three, and the integration test runs the check with the fake binaries of Claude and Codex that already exist in the repo.

**The prompt rule.** It sits in `intro.ts`, after the ground rules, only when `forgeAgent` is set:

```
Your GitHub token expires about an hour after this run starts. If a `gh` call fails with 401 (Bad credentials), run it again as `agent-forge gh <agent> <the same arguments>` from inside the workspace. git renews its own credentials.
```

**Testing seams.**

- Stories 1 to 4, the helper: the seam `claude.test.ts` already uses for the credential helper, `childEnv` plus a real `git credential fill` with a fake `agent-forge` first in the `PATH`. Cases: the fake answers and its token is the one git gets; the fake fails and prints nothing, and the starting token is the answer; no `CARRIER_FORGE_AGENT`, the starting token; a name with quotes, semicolons and `$(...)` runs nothing and is passed whole to the fake; `store` and `erase` answer nothing and do not call the fake.
- Story 4 and the credentials half of 1: `credentials.test.ts`, through `profileCredentials`: a forge profile returns `forgeAgent`, a `gh` profile does not.
- Story 5: `build-prompt.test.ts`, through `buildPrompt`: the rule, with the agent's name, in ship, review and fix when `forgeAgent` is given, and in none when it is not.
- Story 6: an integration test with the real tools, in its own file next to `host-runner.integration.test.ts`, skipped unless its `CARRIER_IT_*` variables are set (its header lists them). It mints a token, revokes it (`DELETE /installation/token`, as the research did), and shows that `git push` to a throwaway branch through the helper and `agent-forge gh` still work.

## Out of scope

The persona and the shared-identity signature, which are [the shared identity spec](shared-identity.md) (epic #350). This one shares a file with it, `prompts/intro.ts`, and nothing else; either can land first and the rule is small to merge. The identity of the engine's own `gh` calls, which already go through `agent-forge gh` and mint a fresh token on each call. Profiles of kind `gh`. A new setting: the behavior is not something a user would turn off.
