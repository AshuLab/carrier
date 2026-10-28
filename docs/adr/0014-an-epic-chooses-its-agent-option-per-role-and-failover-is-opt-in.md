# 0014 - An epic chooses its agent option per role, and failover is opt-in

- Status: proposed
- Date: 2026-10-27

## Context

Carrier runs every agent with the environment of the process that started it, so a whole run, however many epics, uses one Claude login. The real failure is that an epic stops when that login runs out of credits: the execution ends as `usage_limit`, the engine retries it in seconds and burns every retry, and the epic stops in needs-human. Someone who has credits on another login, or on Codex or Antigravity, cannot use them without restarting Carrier under another environment, and cannot move a running epic.

The agents' session lives in the folder of the harness that ran them, so a session cannot be resumed under another login or another harness. The engine already rebuilds a lost session, with a new one, the same profile and the context read from SQLite and GitHub (`session_lost`), and the epic's worktree and pull request are reused.

## Decision

The config declares a directory of agent options, `agentOptions`, each with a harness, the harness's config folder when it has one, a model and optionally a provider, and each role points at one by name the way it points at a profile. The harness, model and provider leave `agents.<role>`; the old shape is refused with a message and is not migrated. The author and the reviewer of an epic each run on one option, stored on the epic and recorded on every execution, so resume, retention and Continue in Terminal read the folder the session was written to. Before the first agent of an epic starts, and only when there are two or more options, the terminal panel asks which option each role should use, and a timer, set in the config, picks the defaults when no one answers, including when no panel is open. `carrier restart` asks again for a stopped epic, with no timer, and marks the role that failed. Both go through the control socket, so any client, the macOS app included, can offer the same choice later.

An execution is resumed with `--resume` only when its session was written by the option the role runs on now. Any other change of option rebuilds the session as `session_lost` does, and the new agent works in the epic's existing worktree.

A `usage_limit` failure no longer burns the retries: the epic stops in needs-human at once, naming the option that ran out, unless failover is on. Failover is a `failover` block in the config with `enabled`, off by default, and `order`, a list of option names. When it is on and an execution of a role ends as `usage_limit`, the engine moves that role to the next option in `order` that has not already ended that way in this epic and runs the stage again as a rebuilt session. When none is left, the epic stops in needs-human and names each option that ran out. The engine remembers nothing about an option across epics.

## Alternatives considered

A global "active account" that every new execution uses. Simpler, but a running epic would change account in silence at its next execution, and two concurrent epics could not use different accounts.

Keeping the harness and model in `agents.<role>` and adding the directory beside them. It avoids editing one config file and leaves two ways to say the same thing.

Choosing a Claude config folder only. It solves the first login running out but not the case that moved the design: no credits on Claude and credits on Codex or Antigravity, and every harness already has the same session-lost behaviour.

Failover to any configured option. It would send a private repo's code to another provider and spend another account without the person ever having said so; the explicit `order` is an allowlist, and turning it on is a choice.

Copying the session file into the other login's folder to keep the conversation. It does not cross harnesses, and the rebuild already exists.

Remembering which option is out of credits across epics. The reset time is only text in the failure detail, so the memory would go stale; the cost of forgetting is one failed attempt at the start of the next epic.

## Consequences

An epic and every execution now carry the option they ran on, a schema change that retention and the resume descriptor depend on, and the config changes shape: an existing config has to be edited once by hand, and `carrier init`, the schema and the docs change with it. The conversation of the agent is lost when the option changes; what the epic did is not, because it is in the worktree, the pull request and SQLite. With failover on, code can reach a provider the person did not pick for that epic, which is why it is off by default and bounded by `order`. Codex has no structured signal for exhausted credits, only the text of its final failure, and Antigravity's has not been seen on a real exhaustion, so their detection is a match on messages and can miss a reworded one; a miss is retried as an ordinary failure, as today. A usage limit that resets in minutes now stops the epic where it used to retry, so the retry that happened to work after a reset is gone and the person resumes by hand.
