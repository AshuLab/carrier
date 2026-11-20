# 0033 - An agent delegates to another agent through child sessions, and every delegation asks the person

- Status: accepted; amended by [0036](0036-a-session-delegates-in-every-mode-and-a-child-runs-at-its-parents-permission-level.md): a delegation no longer asks and the scale covers the modes that never ask; both harnesses were observed asking for one tool of a server, Claude with a real model and Codex's approval layers with a scripted one ([research](../research/switch-and-delegate-spike.md))
- Date: 2026-11-16

## Context

[0024](0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md) put the chat MCP in the host and left a question for the first tool that changes anything: what it may do, and what a child session inherits.
The person wants to say, in a session, "launch two agents, one on this model and one on that", and have the agent that holds the conversation do it through the MCP.
A subagent of a harness lives inside that agent's own scope.
An agent of another provider is another account, another price and the repository's code going to another company, which is why [0014](0014-an-epic-chooses-its-agent-option-per-role-and-failover-is-opt-in.md) refused a failover to any option that nobody asked for.
T3 Code's `delegate_task` is the nearest prior art ([research](../research/t3-code-provider-switching.md)), and both harnesses can ask the person about one tool of a server while the others stay pre-approved ([research](../research/chat-agents-latest-versions-and-mcp-permissions.md)).

## Decision

The person asks for a delegation in words, and the agent turns it into calls of the chat MCP.
The call that starts a child, `delegate_start`, is not pre-approved: every call reaches the person as the harness's own approval, naming the agent, the model, the level and the whole task and saying that the child can read this conversation, and, on Codex, with the harness's own choice to allow it for the rest of the session.
This narrows the pre-approval of every tool that 0024 made the one exception to Carrier having no permission policy: the tools that read stay pre-approved by their access level, and the one that spends another account asks.
On Claude the tools that read are listed by name in `allowedTools` and `delegate_start` is not, so that it reaches the approval card that exists.
The allowance that the CLI suggests writes an allow rule to the project's local settings, which outlives the session, so the adapter offers instead one update with the destination `session`, which the SDK takes; when the CLI does not honour it, every call on Claude asks.
On Codex the server's default is `auto` and the tools that read have `approval_mode = "approve"`, so `delegate_start` asks and its request offers the allowance for the session, which an explicit `prompt` never does.
The adapter shows that elicitation to the person instead of accepting it as it does for the tools that read, and its `_meta` names the tool and carries its arguments.
Delegation is only offered where the harness asks the person.
A session in Claude's `dontAsk` mode, or on a Codex thread whose policy is `never`, denies what it would ask before Carrier hears of the call, so it does not receive the `act` capability below, the delegation tools are not listed to its agent and `agents` says why.
Claude's `auto` mode ran the tool without asking and its `plan` mode asks for every tool of the chat MCP, the pre-approved ones included, so a session in either does not receive `act` and, in `plan`, the tools that read ask too.
The mode is checked when the tools are listed and again when one is called, because the person can change it during the session.

A child is a real user session with a `parentSessionId`.
It runs with the options of its own agent, in the folder of its parent, which it records as a plain folder even when the parent's is a worktree, so that deleting the child never removes the parent's worktree.
It is not in the list of sessions: a client reaches it from its parent, whose summary lists its children with their agent, state and level and says when one waits for the person.
How a client shows them is not decided here.
A child has no archive of its own: archiving a parent closes its idle children and is refused while one works, deleting it deletes its children first, and restoring it restores nothing more.
The clock of [0019](0019-sessions-age-by-the-clock-and-an-automatic-delete-never-removes-unsaved-work.md) ages a parent and its children as one: a child never ages by itself, and a parent counts the activity of its children as its own.
A child belongs to its parent session and not to the agent that holds it, so the parent can be switched ([0032](0032-a-session-changes-agent-by-starting-a-new-conversation-and-the-new-agent-reads-the-old-one-through-the-chat-mcp.md)) or closed and resumed and still wait for its children, and a child cannot be switched.

A child runs one task and takes no message from the person, and the host refuses one sent to it.
It also refuses `setOption` on a child, and a child's approvals offer Allow and Deny and none of the suggestions that change the mode, add folders or write rules, so nothing raises its level once it started.
A client can read its events as they come and the person can answer its approvals and questions; to correct it they delegate again.

A child never has more privilege than its parent.
Carrier ranks what the chat lets a session do on a scale of three levels, and the table says where each option of each harness sits.

| Level | The session | Claude | Codex |
| --- | --- | --- | --- |
| 0 | reads and changes nothing | `dontAsk` | sandbox `read-only` |
| 1 | changes, and asks before each change | `default` | sandbox `workspace-write` with approval `untrusted` |
| 2 | edits without asking | `acceptEdits` | `workspace-write` with `on-request` |
Claude's `plan` and `auto` and Codex's `never` are off the scale: a session that never asks cannot delegate, `plan` is not read-only because it ran `curl` unasked, and `auto` writes outside the folder and reaches the network, which no option of Codex's chat does.
So no level is above 2, and none of these options is ever given to a child.
A level of Codex is a pair of sandbox and approval policy: `read-only` is level 0 whatever the policy, and `workspace-write` is level 1 with `untrusted`, level 2 with `on-request` and off the scale with `never`.

When `delegate_start` is called, the level of the parent is read from its options as they are at that moment.
The child starts with the options of its own agent, lowered to the broadest option of its harness that is at or under the parent's level when they are above it, and never raised.
The tool takes no option that the agent could use to ask for more.
The approval says the level the child will run at and that it was lowered when it was, and `agents` says the level each agent would have as a child.
An option that is not on the scale is not given to a child, and Claude's `bypassPermissions` and Codex's `danger-full-access` are not options of the chat in the first place.

`delegate_start` is an `actsAsSession` tool, the access level that exists for a tool that changes something and that needs the `act` capability, which no session receives today.
A session with no parent receives `act` when its conversation opens and a child never does, so a child cannot delegate and nothing is recursive.
`delegate_wait` only reads, so it is a `readsAsSession` tool.
A parent has at most four children running, and a child can only be one of the agents already configured; its model is checked against what that agent lists before the child opens, and a value it does not list is refused, because both harnesses accept an unknown model when they open and fail only on the first turn.

Three tools carry the delegation, all under the `carrier-chat` server like the rest.
`agents` lists the configured agents with their state and, when asked, their models and reasoning levels from the option probes the host already keeps.
`delegate_start` takes the agent, the task, an optional model and a request id that makes a retry after a lost reply return the same child, kept on the child's row so that it survives a restart of the host, and answers at once with the child's id.
`delegate_wait` takes child ids and a timeout of at most 45 seconds and answers the state of each: working, needs approval, done with its final message, error, usage limit or interrupted; the parent calls it again until nothing is working.

`history` reaches further for delegation: a session reads itself, a parent reads its children, and a child reads its parent, and nothing reads a sibling or another session.
This lifts one exclusion of the chat MCP's spec, any tool that sees a session other than the caller's, for the parent and the children of the caller and for nothing else.

## Alternatives considered

A pre-approved `delegate_start` with "only when the person asks" in its description.
The host cannot check that the model obeys, and nothing would stop an agent from spending another account.

A child that runs with the options of its own agent and nothing more.
A parent that only reads could then start an agent that writes, and the person approving would have to notice the mode in the approval.
T3 Code caps a child at its parent's mode (`runtime_mode_escalation_denied`), and the cap is what this record takes from it.

A list of agents that the person enables for delegation, empty by default.
It is a setting to keep, it says nothing of what each use sends where, and the approval of every use says it better.

Hidden sessions with no link to their parent.
The person could not answer a child's approvals, and the parent could not read what a child did.

A worktree for each child, as T3 Code's `isolation: "worktree"` offers.
It would have to be merged back when the child ends, and it can be added later; the first version shares the parent's folder.

Waking the parent when a child ends, as T3 Code does, so that it never waits.
The host would have to start turns of its own in a session while the person may be typing.
The first version has the parent call `delegate_wait`, and the wake can come later.

A wait with no cap.
The harnesses' MCP timeouts differ, Codex's own documentation and source disagree on its default, and 45 seconds fits under every figure found.

A message to a child, from the person or from a tool.
T3 Code has both; the person chose a child that is one task, so the host takes no message for it.

## Consequences

A parent and its children write into the same folder, and two children can write at once.
That is a small risk for a review or a second opinion and a larger one for two agents that implement, and the first version accepts it and says so.

The scale is a permission policy of Carrier's own, a second exception after the pre-approval of [0024](0024-the-chat-mcp-lives-in-the-chat-host-and-is-injected-per-session.md) to [0013](0013-the-chat-host-is-its-own-process-with-an-adapter-per-provider.md)'s "Carrier adds no permission policy of its own".
It only lowers what a child may do, never raises it, and it touches no session that is not a child.
It has to follow the harnesses: a new mode of Claude or a new policy of Codex has to be put on the scale before a child can run with it.
The same level is not the same guarantee, because Codex's sandbox is kept by the operating system and Claude's modes are rules of the CLI.
Codex blocks the network at every level and its `workspace-write` also writes under `/tmp`, while Claude's `acceptEdits` asks for both, so the scale is a close convention and not an identity.

Every delegation asks, so a request for two agents is two approvals unless the person allows the tool for the session, which both harnesses offer.
A Codex session with the policy `never` cannot delegate, and a Claude session in `dontAsk`, `auto` or `plan` mode cannot either.

The parent spends tokens polling with `delegate_wait`, and a parent whose turn ends while a child is still working does not hear from it until the person asks.

A person's own Claude settings can add a rule that denies, asks for or allows our tools, and an allow rule runs the tool unasked, because Carrier does not narrow the settings the SDK loads.

The schema gets a `parentSessionId` and a delete has to consider children.
A client needs a way to show a child and to take its approvals, which is another brief's and does not change the host.

The transcript of the parent and the task text go to the other provider once the person approves.
Claude's side was run with a real model on Claude Code 2.1.325 and Codex's approval layers on 0.167.2 with a scripted model, so how a real Codex model reacts to a refused tool is not known.
It needs Codex 0.122.0 or later, the floor of the pre-approval of 0024 on which a tool's own mode sits.
The approval is the harness's and the host cannot prove it to the MCP: the token of a Claude conversation sits in the environment of its process, so an agent that is allowed to run a shell command could post `delegate_start` itself, as it could start `claude` or `codex` itself, and in `default` and `acceptEdits` mode the shell command is what the harness asks about.
This record accepts that and adds no proof of approval to the MCP.
A session on an older Codex cannot delegate and says so.
