# Agents in Settings

Status: implemented (v0.2.0)

Source: AshuLab/carrier#778

## Problem

Who works on an epic is decided in a JSON file: for each of the author, the reviewer and the optional lead reviewer, a GitHub profile, a provider, a model and a persona, and, apart, a `failover` block that says what happens when a login runs out. The app has no page for it, so setting Carrier up or changing a model means editing the file and knowing which of its parts must agree: a profile has to exist in `profiles` and in Agent Forge, a provider in `providers`, a failover list has to name accounts and cannot say which model to move to, and `identities` has to say `shared` if the two roles pick the same bot. The one setting a person wants to make most often, what the author runs on and where it goes when its tokens are gone, is the hardest to find.

Two things in the engine also make the question harder than it is. An epic waits up to a minute at its start for a person to choose a provider that nobody is there to choose, because the runs are unattended, and the engine never passes the effort that all three CLIs take.

It is felt by whoever sets Carrier up and by whoever notices that their author ran out of credits and the epic stopped, or moved to a model they did not pick.

We know it is solved when the person can open one page and say, for each of the three roles, who signs, which provider, model and effort works, and where it moves when it runs out; when an epic starts at once on that; and when a login that runs out moves the role to the provider and model the person named.

## Solution

Carrier's pages are Repos, Agents and Behavior. Agents is a master-detail of three fixed roles, Author, Reviewer and Lead reviewer, and no more can be made. The prototype (`docs/research/macos-app-design/explorations/settings-groups-options.html`, Carrier › Agents) is the design. Its earlier pages Identities, Roles and the old Agents (providers on and off, reasoning, permission, binary) are gone, because the engine has no use for them: the permission mode is fixed to the unattended one, the binary belongs to each account, and the model and effort belong to a role.

A role's page has three cards. Who: Identity, Provider, Model and Effort. Details: the optional Persona, the name and prompt the engine already has. When it runs out of tokens: Switch automatically, and a first and an optional second step, each a provider and a model. Identity is a list of the bots registered in Agent Forge plus the person's own `gh` login, and next to it Create a bot…, which opens Terminal on `agent-forge add` and refreshes the list when the command ends and the app is active again, the way a sign-in in Providers does. The app never touches a key and has no wizard of its own for creating a bot: Forge makes the GitHub App and keeps the private key. Provider lists the accounts of `providers.json` ([0020](../adr/0020-accounts-live-in-a-file-both-processes-read.md)), or the three default accounts when the file is not there. The Lead reviewer has its own switch, Use a lead reviewer, at the top of its page, and while it is off the rest of its page is shown dimmed and not usable. Turning it off removes the role's `agents.leadReviewer` and its failover steps from the file, and the row says so.

[0021](../adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md) records the engine's side, which this epic builds. An epic starts at once: the wait for a person to choose a provider at reservation goes, with its time limit, its column, its prompt in the terminal panel and in `carrier watch`, the control socket's `chooseOptions` and its capability, and the `enabled` key of the accounts that the Providers epic adds to avoid it; the choice `carrier restart` offers for a stopped epic stays, with no timer, among every declared account. A role gets an `effort`, in the global role and in a repo's override, passed as `--effort` to Claude and Antigravity and as `-c model_reasoning_effort` to Codex; the CLIs of this machine list the same five levels, `low`, `medium`, `high`, `xhigh` and `max`, for every model but one, which also has a sixth that the page does not offer. Failover becomes a per-role list of steps, each a provider and optionally a model, with no global switch and no default list, and with the three triggers kept and not shown. The `identities` key goes and an epic is shared when its author and reviewer resolve to the same account, which the engine already computes; the page says, when the two roles pick the same identity, that the signature will show it. `orchestratorProfile` becomes optional and defaults to the author's profile, and the page does not show it. A config with the old `failover`, `identities` or `limits.optionChoiceSeconds`, or a `providers.json` account with `enabled`, is refused with a message that says what replaced it, and nothing is migrated: the author moves their own file.

The app reads and writes what it has never touched: the global `agents`, the `failover` and the `profiles` of `config.json`. It keeps every key it does not know, reads the file again just before it writes, and saves as the other tabs do, with the page saying that Carrier reads it when it starts. Choosing a bot writes a profile `{ kind: "forge", agent: <name> }` named after it, and the person's own login writes `{ kind: "gh" }`. The names of the bots come from the Agent Forge registry, `~/.config/agent-forge/agents.json` or what `AGENT_FORGE_CONFIG` points at, names only and never a key, with the engine's `readForgeAgents` as the reference for where and how. `carrier init` follows the schema: its failover question asks for steps with a model, it no longer asks whether the identities are shared, and it can set an effort.

A known gap: with the orchestrator's profile hidden and defaulting to the author's, a repo of another owner whose App is not installed fails the Repos page's "Carrier can read it" check, and no page can fix it. The person sets `orchestratorProfile` in the file until a page offers it.

What was weighed and cut: showing the mode separate or shared, the orchestrator's identity, the failover triggers, the per-account switch of what an epic may choose and a list of the bots with the repos each is installed on, all of which the first prototype had and which made the page a catalogue of settings a person does not make; a page for Identities of its own, which the Repos page's check for who can sign on each repo already tells better; keeping the start-time choice because the engine has it, which costs every epic a minute for a question with no one to answer; and defaults per tool (reasoning, permission) for Carrier, which would be keys no process reads.

The published text that changes with this is the Repos epic (`AshuLab/carrier#765`: its role form takes five fields with effort, and its buttons to Roles and Identities become one to Agents) and the Providers epic (`AshuLab/carrier#749`: "Use in a role" becomes "Use in an agent", and the `enabled` key it adds is removed here). The documentation changes with it: the configuration guide for the roles, `effort`, the failover steps and the keys that go; `macos/README.md` for the page; and the specs that describe the choice at the start.

## Scope

1. An epic that is reserved starts its first agent at once, with one account declared or ten.
2. The wait and everything that served it are gone: `limits.optionChoiceSeconds`, the epics' `choiceDeadline`, the choice in the terminal panel and in `carrier watch`, `chooseOptions` and the `agentOptions` capability of the control socket, and the accounts' `enabled`.
3. `carrier restart` still offers a stopped epic's roles every declared account to choose from, with no timer.
4. A person gives a role an effort, globally and for one repo, and the Claude, Codex and Antigravity processes the engine starts take it.
5. A person gives a role a list of failover steps, each a provider and a model, and when an execution of that role ends as `usage_limit`, `rate_limit` or `service_down` the engine moves it to the next step not already tried in that epic, on that step's model.
6. An epic's sharing is derived from its roles, and the config no longer has `identities` or the rule that the author and the reviewer must differ.
7. `orchestratorProfile` may be left out and is then the author's.
8. A config with a shape this epic replaces is refused naming the key and what replaced it.
9. `carrier init` writes the new shape: failover steps with a model, an effort, no `identities`.
10. The Settings rail shows Agents in the Carrier group, with the three roles.
11. A person changes a role's identity, provider, model or effort in its page, and the app writes only that role, keeping every other key of the file.
12. Choosing a bot or the person's own login writes the matching profile, and the list of bots is the Agent Forge registry's names.
13. A person edits a role's persona and sets its failover steps from the page.
14. A person turns the Lead reviewer on and off, and its page is shown dimmed while it is off.
15. The page says the signature will show it when two roles pick the same identity.
16. Create a bot… opens Terminal on `agent-forge add`, and the list of bots refreshes when the app is active again.
17. The configuration guide, the README and `macos/README.md` agree with all of the above.

## Decisions

The shape of a role and of failover, trimmed to the decision:

```ts
const effort = z.enum(['low', 'medium', 'high', 'xhigh', 'max']);
const step = z.strictObject({ provider: z.string().min(1), model: z.string().min(1).optional() });
// a role: the existing fields plus `effort`; in a repo's override each field is optional
const role = z.strictObject({ profile: z.string().min(1), provider: z.string().min(1), model: z.string().min(1), effort: effort.optional(), persona: persona.optional() });
const failover = z.strictObject({
  triggers: z.array(z.enum(failoverTriggers)).min(1).optional(),
  roles: z.strictObject({ author: z.array(step).optional(), reviewer: z.array(step).optional(), leadReviewer: z.array(step).optional() }).optional(),
});
```

Checked against the inputs it takes: `effort: "Max"` and `""` fail, being outside the five; `steps: ["codex"]`, the old form, fails as not an object and is refused with the message that names the new shape; `{ provider: "" }` fails on `min(1)`; `[]` is valid and means no failover for that role; a step that repeats another of the same list, or equals the role's own provider and model, is refused as a no-op naming its position; and `enabled`, `default` or `identities` anywhere are refused with the message that says what took their place, not with the generic unknown-key one.

A step without a model runs on the account's `model`, then the harness's default, as a failover option did. The page offers two steps and writes at most two; a file with more is read and kept.

The page writes the role it changed and nothing else: a field left alone keeps its value, a role's entry is never emptied of the fields the engine requires (`profile`, `provider`, `model`), and the lead reviewer's entry exists only while it is on. Turning it on needs its three required fields before it is written, so the page asks for them and the file never holds a half role.

The identity list is the registry's names plus the person's own login; a profile that is in `config.json` and no longer in the registry is shown as missing, kept, and refused only when it is chosen again. Sharing is shown when the two roles' profiles resolve to the same account by the engine's own rule, not by comparing names.

Testing seams, story by story, with the ones that exist:

- Stories 1 and 2: the reservation in `src/orchestration` with its fake clock and ports (no wait, one account or many), the control server's tests for the requests and capabilities, the terminal dashboard's pure key reducer, `carrier watch` and the migration of the epics table, each asserting the absence of what went. A test of the loader says `limits.optionChoiceSeconds` and an account's `enabled` are refused with their message.
- Story 3: `restart.test.ts` and the engine's restart path, with every declared account offered and no timer.
- Story 4: `buildClaudeCommand`, `buildCodexCommand` and the Antigravity builder return the arguments, so the flag and the `-c` pair are asserted on that value, and a role without effort yields none; plus the loader for an override. A gated integration test of the Codex runner confirms `-c model_reasoning_effort` is honoured by `exec` and by `exec resume`.
- Story 5: the engine's failover tests with their fake runner and clock (a step's model reaches the next execution; a step tried is not tried again; an empty list does nothing).
- Stories 6, 7 and 8: `loadConfig`, `resolveRepoConfig` for the derived sharing, and a table of the refused shapes with the message each gives.
- Story 9: `runInit` with the scripted `Ui` and the fake deps of `wizard.test.ts`, and `build-config.test.ts`.
- Stories 10 to 15: a pure model of the page in CarrierCore, fed with the config's parts and the registry's names and returning the rows, tested like the Repos page's; the reader and writer of `config.json` in the style of `EngineConfigTests`, over a temporary file: unknown keys kept, the file read again before writing, a role never left without its required fields.
- Story 16: the builder of the Terminal command, beside `HealthFixTests` and `ContinueInTerminalTests`: the closed list now has `agent-forge add`, quoted, and nothing from the registry becomes part of the command.
- Story 17: no tests, a documentation change.
- The page's views have no unit tests; the fixture build and the smoke check cover them, with a fixture `config.json` and registry that have the three roles.

## Out of scope

Chat › Agents and Behavior. More than three roles. A page for the orchestrator's profile or for the failover triggers. Listing the repos each bot is installed on, forgetting a bot, and creating one inside the app. The setup wizard of the app, which reuses these pieces. A sixth effort level that only one model has.

The Providers epic and the Repos epic are not rebuilt here. This epic comes after the store of the Providers epic (`AshuLab/carrier#758`), because Provider lists the accounts of `providers.json`, and after the Carrier group of the Repos epic (`AshuLab/carrier#769`), because the page joins that group; the three epics add pages to the same list of pages and should not be built at the same time.
