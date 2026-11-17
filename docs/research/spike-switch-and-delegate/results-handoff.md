# Spike part C: does a handoff keep a conversation going, and where can it sit

Run on 2026-11-16 against Claude Code 2.1.325 (model `haiku`) and Codex 0.167.2 (model `gpt-6-luna`, the cheapest it lists: "Fast and affordable model for easier tasks").
Scripts and raw data are in [handoff/](handoff/) (`lib.ts` has the handoff builder and the toy `history` tool, `data/` the transcripts and the per-run JSON).

## Headline

**The run is half done: Codex was at its usage limit on its first turn, so every Codex turn is UNVERIFIED.**
The first real Codex turn (turn 1 of the Codex-made seed) failed with `You've hit your usage limit. Upgrade to Plus to continue using Codex (...), or try again at Nov 20th, 2026 7:11 PM.`
Per the rules of the spike the script stopped there and Codex was not retried.
What was measured is everything that needs only Claude: a Claude-made transcript handed to a **new Claude conversation** (the spec allows a switch to another account of the same harness), a Claude control, and the Claude half of C2.
The two cross-harness directions of C1 and the Codex variants of C2 still have to be run after 2026-11-20 (or on another Codex login); the scripts are ready (`node seed.ts codex 2`, then `node recall.ts claude seed-brambleglass-codex.json 2`, `node seed.ts claude 1` is done, then `node recall.ts codex seed-quillfinch-claude.json 1` and the controls).

Turns used: 32 of 45 (31 answered, plus the one Codex turn that hit the limit); see `handoff/data/turns.jsonl`.

## C1: does a handoff keep the conversation going

### Sizes (observed)

| What | Bytes |
| --- | --- |
| Seed transcript made by Claude, 8 turns, 25 events (8 user, 8 assistant, 8 turn_end, 1 reasoning) | 43,180 as JSON; 40,353 of user plus assistant text |
| Four pasted specs of about 9.6 to 10 KB each (turns 3 to 6), one fact buried at 55% of each | 9,610 / 9,996 / 9,785 / 9,912 |
| Handoff, messages part (the budget) | 16,000 |
| Handoff, whole text sent (messages + frame text + labels + the `history` sentence) | 16,860 (the frame adds about 860) |
| Handoff included | 9 messages: first message, the whole turn 6 paste, turn 7, turn 8 and their answers, and the turn 5 paste **cut** to its first 5,546 characters |
| Handoff left out (ids = positions) | `m2 m4 m5 m7 m8 m10 m11`: the first answer, turn 2 (the decision), turn 3 paste, turn 4 paste, and the answers to them |

The ADR counts the 16,000 bytes on the messages; the text that is actually sent is a few hundred bytes more, so a budget meant as a hard ceiling on the message must count the frame too (a choice for the spec, not a finding).

The handoff builder follows ADR 0032: first message, then newest backwards while the sum stays at or under 16,000 UTF-8 bytes, a message too long for what is left is cut to it and the walk stops (my reading of "a message that is longer than what is left is cut"; the ADR does not say whether the walk stops), the ids left out, and a sentence naming `history`.
The `history` tool is `defineTool` + `startMcpServer`, access `readsAsSession`, paged by `afterPosition` / `limit` (each text shown cut to 1,500 characters and its length) and by `itemId` with `textOffset` (6,000 characters per read, `nextOffset` null at the end).

### Facts and questions (invented project Quillfinch)

Included in the handoff: A (project owner, first message), F (nightly export job name, buried in the turn 6 paste), G (release tag, last message).
Omitted: B (database option rejected and why, turn 2), C (calibration interval of gauge TG-440, buried in the turn 3 paste), D (drift that raises an alert, buried in the turn 4 paste).

### Direction Claude seed to Claude receiver (new conversation, same folder shape, chat MCP injected)

Receiver and seed are both Claude here; the cross-harness direction needs Codex and is UNVERIFIED.
Run `a`: first message = handoff + "what is this project and its next step", then A B F C G D.
Run `b`: first message = handoff + "Reply with just: OK", then C D B A F G (omitted first, to see who calls `history`).
Both used a fresh conversation and a fresh `history` server; the right answer was judged by regex (all key words present) and read by hand.

| Question | Where the answer is | Run a: right, `history` calls in its own turn | Run b: right, `history` calls in its own turn |
| --- | --- | --- | --- |
| A owner | included | right, 0 | right, 0 |
| F export job | included | right, 0 | right, 0 |
| G release tag | included | right, 0 | right, 0 |
| B rejected option | omitted | right, 0 (see below) | right, 0 (see below) |
| C TG-440 interval | omitted | right, 3 (`itemId` m7, m10, m13, each `textOffset` 1500) | right, 5 (page `afterPosition -1, limit 40`, then whole `m7 m10 m13 m16`) |
| D drift threshold | omitted | right, 0 (see below) | right, 0 (see below) |
| First turn | n/a | 1 `history` call (its arguments were not recorded in this run), also a `ToolSearch` | none (it only said OK) |

Score: included 3/3 and omitted 3/3 in both runs.
No invented answer in either run; the server saw the same number of calls as the `tool_start` events (4 in run a, 5 in run b).

Reading of the zeros on B and D, so the table is not over-read: the model read the omitted parts once and then answered from its own context.
In run a it paged the start of the conversation in the first turn, which showed turn 2 whole (it is short), so B needed no further call; it read m7, m10 and m13 in the C turn and the D fact was in m10.
In run b the first omitted question made it page everything and read m7, m10, m13 and m16 whole, and the next two omitted questions (D, B) cost nothing.
So the per-question count says "the first omitted question triggers the reads", not "each omitted fact costs a call".
Each included fact (A, F, G) got 0 calls in its own turn, but in run b they came after the reads, and in run a the first turn had already called `history`, so whether the model would skip `history` for a fact the handoff holds is UNVERIFIED.

Also observed: Claude loaded the MCP tool through `ToolSearch` (a deferred tool) before the first `history` call, so the first use costs one more tool call.
The tool was pre-approved by the adapter's `allowedTools`: no approval event appeared.

### Control (fresh Claude conversation, no handoff, no `history` tool)

The six questions were asked in one turn, numbered (a deviation from separate turns, to save turns; the questions do not depend on each other in a fresh conversation).
0 of 6 right: every line said "Not found" and the agent said it had nothing about Quillfinch.
It tried `Bash` twice (the probe denied both, as the rules require) and then answered that it could not read the project; no invented answers.
So the facts cannot be guessed and the 6/6 above comes from the handoff plus `history`.

### Direction Codex seed to Claude receiver, and Claude seed to Codex receiver

UNVERIFIED. The Codex seed (invented project Brambleglass, fact set in `handoff/facts.ts`) never got past its first turn: usage limit, see the headline.
Nothing here says how `gpt-6-luna` behaves as a receiver, whether it calls `history`, or whether a Claude receiver does better with a Codex-written transcript (the transcripts differ in shape: Codex gives `reasoning` summaries and no `turn_end` model before the answer; nothing was compared).

## C2: where the handoff sits when the first message invokes a skill

A project skill `pong` (`.claude/skills/pong/SKILL.md`, "Reply with exactly the text PONG:$ARGUMENTS and nothing else. Do not call any tool.") in a temporary folder.
A handoff of 1,340 bytes (the person's first message, the answer, the decision) was used here: size does not matter to where it sits.
Recall question after each variant: "Who is the project owner?".

### How each adapter lists and invokes it

- Claude: the adapter's `commands` lists it as `{ id: 'pong', name: 'pong', kind: 'skill', argumentHint: '<word>', description: 'Answers PONG followed by the argument (project)' }`.
  The adapter's `send('ALPHA', command)` sends the string `/pong ALPHA` as the user message.
  Baseline, no handoff: the reply was exactly `PONG:ALPHA` with no tool call (the harness expanded the slash itself).
- Codex (read in `codex.ts` and run without a turn against the 0.167.2 app-server): `skills/list` for the folder lists `pong` from both `.agents/skills/pong/SKILL.md` and `.codex/skills/pong/SKILL.md` as two entries, scope `repo`, `enabled: true`, so a skill in both places would be listed twice.
  The adapter invokes a skill as an item of its own in `turn/start`'s `input`: `[{ type: 'skill', name, path }, { type: 'text', text, text_elements: [] }]`.
  Because the skill is a typed item and not a slash in the text, a handoff placed in the text item is structurally not in front of the command. That is an inference, not tested (no Codex turn).

### Claude as the new agent (observed)

| Variant | Command ran as a command | Handoff delivered | Turns for the first message after the switch | Raw |
| --- | --- | --- | --- | --- |
| baseline, no handoff | yes, `PONG:ALPHA`, 0 tool calls | n/a | 1 | |
| (a) handoff text in front of `/pong ALPHA`, one plain message | **no**: the reply was `PONG:ALPHA`, but through the model's own `Skill` tool call (`tools: ['Skill']`), not an expansion by the harness | yes ("Odalys Prewitt.") | 1 + 1 recall | one sample |
| (b) a turn of its own: handoff + "context only, reply with just OK", then `/pong BETA` through `send(text, command)` | yes, `PONG:BETA`, 0 tool calls | yes ("Odalys Prewitt.") | 2 + 1 recall | |
| (c) handoff in the SDK option `systemPrompt: { type: 'preset', preset: 'claude_code', append: <handoff> }`, then `/pong GAMMA` through `send(text, command)` | yes, `PONG:GAMMA`, 0 tool calls | yes ("Odalys Prewitt is the project owner of Quillfinch.") | **1** + 1 recall | |

- The option for (c) is `Options.systemPrompt` of SDK 0.3.325 (`sdk.d.ts`): a string, a string array, `{ type: 'custom', prompt }`, or `{ type: 'preset', preset: 'claude_code', append?, excludeDynamicSections?, snapshot? }`.
  The adapter does not pass it today; the experiment wrapped the adapter's injectable `query` dependency and added the option, with no change to `src/`.
- The SDK says that by default the rendered system prompt is recorded with the conversation and reused verbatim on later requests and `resume`, ignoring a different `append` (`snapshot`, "rolling out, no effect where not enabled"). Not tested: whether a resume of that conversation keeps the handoff. UNVERIFIED.
- In (a) the handoff did not break the answer in this sample, but the harness did not treat the message as the command: the model chose to call `Skill` itself. A second sample was not taken, so how reliably it does is UNVERIFIED. The stored event would not carry `command: 'pong'` for such a message, and the model might equally answer without the skill.

### Codex as the new agent

Not run (usage limit). What the protocol offers, from the generated schema (`codex app-server generate-json-schema` and `generate-ts` into a new empty folder under `/tmp`, removed afterwards), and what a no-turn probe of the 0.167.2 app-server accepted:

- `thread/start` and `thread/resume` take `baseInstructions` (string or null) and `developerInstructions` (string or null). `turn/start` has no instruction field (it has `input`, `personality` (deprecated), `outputSchema` and others). `baseInstructions` would replace Codex's own system prompt, so `developerInstructions` is the field a handoff would use.
- Observed: `thread/start` with `developerInstructions` set to the 1,340-byte handoff answered normally (no error), and so did a thread with `baseInstructions`.
  The response carries `instructionSources: []` (paths of instruction files loaded), so it does not show the text.
- Also in the protocol: `thread/inject_items` ("Raw Responses API items to append to the thread's model-visible history"); an inject of one user message into a thread that had not run a turn answered `{}`. Not used by Carrier today, and how it behaves in a conversation was not tested.
- UNVERIFIED for Codex: whether the model reads `developerInstructions` (a recall question was not possible), whether a skill invoked with the handoff in the same text item runs as a skill, and what each variant costs. By the shape of the protocol, (c) would cost no extra turn and (a) one, but this is inference.

## What stayed UNVERIFIED

- Everything that needs a Codex turn: both cross-harness directions of C1, the Codex control, `gpt-6-luna` as a receiver (does it call `history`, does it keep the order), and the Codex variants of C2 (`developerInstructions` delivery, skill with a handoff in the text item).
- Whether a model skips `history` when the handoff already holds the fact (the included questions came after reads or a status question that already called it).
- Per-fact cost of `history` in a cold conversation: the first omitted question triggered the reads and the others were free, in two runs of one model. Other models, a conversation where the omitted question is asked after a long gap, or a transcript of 200 KB were not tried.
- (a) on Claude with a second sample; resume of a conversation opened with `systemPrompt.append` and whether the appended handoff survives it.
- Whether the handoff of 16,000 bytes is the right size: only this one size was run, on a 40 KB transcript. A transcript where the fact is in an assistant message, a tool result, or a message cut in the middle (the turn 5 paste was cut and not asked about) was not asked about.
- The Claude control tried `Bash` twice; a Codex control with the same tools might behave differently.

## Other observations worth keeping

- The Codex usage limit arrived as `turn/completed` with an error whose text carries the reset time in words ("try again at Nov 20th, 2026 7:11 PM") and the adapter turned it into an `error` event followed by `turn_end` with `outcome: 'error'`; useful for part D, where the spec asks which signal is reliable. It does not say which kind (usage or rate) except by its words.
- With a handoff of about 17 KB the first Claude turn took about a minute on `haiku`; not measured.
- The adapter does not emit the `user` event; the host stores it. The scripts add it with the same shape, so positions here count the user events as Carrier's transcript would.
