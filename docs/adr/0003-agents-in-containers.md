# 0003 - Agents run isolated in containers

- Status: superseded by [0004](0004-agents-run-on-host-with-terminal-preferences.md)
- Date: 2026-10-15

## Context

Carrier's agents work unsupervised for hours and need broad permissions to run `ship`, tests and repo commands without waiting for approvals. If they run on Diego's system with his permissions, a mistake or a malicious instruction in a repo can touch files, credentials and other repos on his machine, and nobody is watching to stop it.

## Decision

Each agent execution runs inside a container, with broad permissions inside and no access to the rest of the system. Only the epic's workspace, what Git needs to work, and the agent's sessions are mounted. The execution's GitHub token has the minimum scopes for its role, and the repos configure branch protection as a second boundary, because the container does not limit what the agent can do on GitHub with that token. Carrier does not run agents directly on the host.

## Alternatives considered

Running on the host with restricted CLI permissions. It was rejected because it leaves an unattended agent running with the permissions of the system where it runs, and the restriction depends on each CLI.

Using the native sandbox of Claude Code and Codex on the host. It was rejected as the main boundary: it isolates less than a container, differs between providers, and still shares the host's file system. It remains an alternative if the container spike is not viable.

## Consequences

The maximum damage is bounded to the workspaces and stopping is simple: killing the container reaches the child processes. A dependency on a container runtime on macOS, which runs in a Linux VM, is accepted, along with extra work: mounting worktrees and clone at consistent paths, keeping the Claude and Codex login and their sessions inside, renewing the Forge token during long executions, and providing toolchains for each repo's tests. The design depends on the container spike confirming that all this works; if not, Diego chooses among the alternatives.
