# 0050 - One authentication signal is a technical failure of its epic, and a profile stops when the signal repeats

- Status: accepted; amends the rule of the [orchestrator spec](../specs/autonomous-orchestrator.md) that an authentication failure stops every epic of its profile
- Date: 2026-11-23

## Context
Today one authentication signal from an agent stops every epic that uses its profile.
The signal comes from text the harness prints, and on `agy` the plain text `Authentication required` is matched on any line of stdout or stderr, so a tool's output can set it.
A false signal therefore stops every epic of a profile at once, with agents idle and a person needed to resume them.

The profile Carrier can test is the GitHub profile: the engine can mint its token.
The signals of Claude, Codex and `agy` are about the model's account, which Carrier cannot test without spending a run, so a token that mints proves nothing about an agent that is logged out.

## Decision
A first authentication signal of a profile ends that execution as a technical failure, which retries like any other, and the profile's other epics go on.
A second signal of the same profile, in the retry or in another epic, stops every epic of the profile as it does today.
Any execution of the profile that ends with no authentication signal clears the memory of the first one, and the memory lives in the engine and is not saved.
On `agy` the plain text counts only when it comes on stderr, and the structured result that says authentication failed or timed out counts wherever it comes.
The real message of the error is kept with the epic as the reason it stopped.

## Alternatives considered
Trying to mint a token for the profile before deciding lost, because it tests the GitHub identity and the signal is about the model's account, so the epic would spend its retries and end as `retries_exhausted` with the cause hidden.
Probing the model's account with a cheap run lost, because it spends credits to answer a question the second signal answers for free, and needs a probe per harness.
Keeping the rule as it is lost, because one false line of output stops the work of every epic of a profile.
Never stopping the profile lost, because a logged out account would burn the retries of every epic one after another.

## Consequences
A real authentication failure costs one more agent start before the profile stops, and each epic of the profile may spend a retry on it before the second signal arrives.
A restart of the engine forgets the first signal, so it costs at most one more.
A false signal costs one retry of one epic and stops nothing else.
The orchestrator spec's sentence about authentication is out of date, and the final spec has to say this instead.
