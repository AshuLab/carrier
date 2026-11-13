# src/prompts

What the agents are told, one file per part.
`build-prompt.ts` joins `intro.ts` (role, rules, earlier turns), one stage (`ship.ts`, `fix.ts`, `review.ts`) and `result.ts` (the JSON contract).
To change what an agent is asked, edit the stage file.
