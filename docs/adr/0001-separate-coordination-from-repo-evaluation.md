# 0001 - Separate coordination from repo evaluation

- Status: accepted
- Date: 2026-10-15

## Context

The orchestrator will run Solve skills across several repos. The skills keep their current reports, and repos may have different test and CI rules, or no CI at all. Implementing those policies inside the engine would duplicate decisions the caller agent already makes when using the skills, and would tie the result contract to each repo.

## Decision

The author and reviewer agents interpret the repo's domain and rules, choose and evaluate the corresponding checks, and report their conclusions. The orchestrator manages the queue, processes, sessions, turns, limits, labels and persistence. It validates the JSON schema and the technical consistency of references to epic, execution, PR and commit. Semantic evaluation stays with the agents.

Repeated runs and fixes of tests/CI are part of the agent's internal work. The engine neither imposes nor counts those attempts; it keeps the technical execution retries and the review-round limit as coordination controls.

## Alternatives considered

Having the orchestrator identify the required checks, query their states and interpret when to enable the PR was considered. It was rejected because it brings repo rules into the engine and duplicates the author's and reviewer's responsibilities. The technical check of references and the current commit is kept so that coordination happens on the correct execution.

## Consequences

The engine keeps a common coordination contract, and the skills can evolve without having new formats imposed on their reports. Relying on the agents' interpretation for domain conclusions is accepted; JSON validation alone does not prove the code is correct. Evidence, reports and SHAs must be kept so that the reviewer and Diego can evaluate those conclusions. Integration tests must verify that the caller results are enough to drive the loop without introducing repo-specific policies into the engine.
