# 0004 - Agents run on the host with the terminal's preferences

- Status: accepted
- Date: 2026-10-15
- Supersedes: [0003](0003-agents-in-containers.md)

## Context

[0003](0003-agents-in-containers.md) set that each agent execution runs in a container. The container spike ([research](../research/agent-containers.md)) found it viable with conditions, but at a high cost for this first version: Claude's login lives in the macOS Keychain and cannot be mounted, Codex's `auth.json` cannot be copied to parallel runs without risk, Codex's own sandbox fails inside the container, Claude does not accept `bypassPermissions` as root, worktrees require paths identical to the host's, and the `gh` token has to be renewed from outside. All of that delays testing the complete flow, which is the goal of this version.

## Decision

The agents (Claude and Codex) run as the client's normal CLI, on the computer where `carrier` is invoked, just as they run from that terminal: a child process with the user, login, configuration and permissions that CLI already has. Carrier adds no isolation, containers or restrictions of its own in this version; it lets the CLI run.

Security for unattended (AFK) agents is left as later, explicit work, once the flow is working. Each execution's GitHub token still has the minimum scopes for its role and the repos keep branch protection.

## Alternatives considered

Containers per execution ([0003](0003-agents-in-containers.md)). They remain the option with the best isolation and simple stopping (`docker kill` ended the whole tree in 0.09 s), but the cost of credentials and permissions described above is deferred until the complete flow exists. The spike remains as starting material.

Native sandbox of Claude and Codex. It isolates less and differs between providers; it will be evaluated together with the rest of AFK security.

## Consequences

Simplicity is gained: no container runtime, mounts, images or external login renewal, and sessions stay where each CLI stores them. It is accepted that an unattended agent runs with the user's permissions and can touch files, credentials and other repos on that machine; this is an assumed risk until AFK security is defined. The runner invokes the real `claude` and `codex` binaries, not wrappers. Without a container, stopping an agent does not guarantee its child processes end (Codex leaves the command's process orphaned even with `SIGTERM`, [research](../research/headless-agents.md)); it remains a known limitation to review with AFK security.

## Update (2026-10-17)

Antigravity (`agy`) was added as a third harness under the same decision: its normal CLI as a child process, with `--dangerously-skip-permissions` (it has no sandbox to turn off; `--sandbox` is opt-in). Stopping it does not leave child processes behind on SIGTERM. A model served by LM Studio or Ollama through Claude Code or Codex runs the same way, with the same permissions: the model being local changes where it thinks, not what the agent can touch. See [the spike](../research/antigravity.md).
