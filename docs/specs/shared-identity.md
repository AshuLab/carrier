# Carrier runs with one GitHub identity, and every role has a persona

Status: spec

## Problem

A person who works in the repos of an organization where they are not an owner cannot run Carrier. Carrier needs the author and the reviewer to be different GitHub identities, and the only way to get a second one is an Agent Forge bot, which is a GitHub App that someone with owner rights has to install on the organization. When that owner will not, there is no way in: a second user or a machine account needs an invitation from the same people, and an App on the person's own account does not reach the organization's repos. The check is concrete: `carrier init` stops with "Author and reviewer need different identities and there is nothing left to pick", and the schema and `carrier doctor` refuse the same profile for both roles.

Next to it, the agents have no way to be told who they are. When Agent Forge launches an agent it gives it a block that names the git author identity and the token in its environment and says who it is, plus, if the bot has one, a `systemPrompt` that says how it behaves. Carrier does not launch agents through Forge: it asks Forge for a token and spawns the harness itself, so none of that reaches the agents Carrier runs, with a bot or without one. What an agent is told about itself is only the generic line of `prompts/intro.ts`, "you are the reviewer of the final integration PR of epic #N". A user who wants the reviewer to be strict about migrations, or the author to answer in a certain way, has no place to say it, and the `systemPrompt` of a bot in Forge's registry does nothing in Carrier. With the account shared this matters more, because the only thing that tells the agent's words from the person's is who the agent says it is.

## Solution

The user chooses at setup between separate identities, which is today's flow with Agent Forge and stays the default, and a shared identity, where the author and the reviewer use the same GitHub profile, normally the `gh` login of the machine ([ADR 0011](../adr/0011-author-and-reviewer-may-share-one-github-identity-signed-visibly.md), [glossary](../glossary.md)). The choice is a global setting, `identities: separate | shared`. Under `shared` the schema and `carrier doctor` accept the same profile for both roles, and a repo that wants a bot keeps the per-repo identity override it has today.

Each role, author and reviewer, has a persona in both setups: a name the user chooses and an optional prompt that says who the agent is and how it behaves, the equivalent of what Forge's `systemPrompt` does when Forge launches an agent. Carrier adds it to the role's own prompt, right after the generic line that says which role it is and before what the stage asks. The persona belongs to the role and not to a stage: what `ship`, review and fix are asked to do is a different thing and is not touched. A bot's personality is set in Carrier's config and not in Forge's registry, which Carrier does not read for it because the registry holds paths to private keys. A repo can override the persona of a role as it overrides the rest of the role.

Under a shared identity everything an agent publishes with the account ends with a visible signature, `🤖 <Role> [NAME] via Carrier`, with the persona's name in the brackets: review comments and bodies, the pull request body, replies on threads, any other comment, issue or issue body, and a last line of the body of each commit message, before any trailers. It is mandatory and the user cannot turn it off. A name left empty drops the brackets. It applies to an epic whose author and reviewer resolve to the same account (the same profile, or two names for one `gh` login or one bot), so a repo that overrides one of them with a bot does not carry it, and under separate identities there is none, because the bot's account already says who it is. Carrier does not change the git name or email of commits: they are the session's of the person using Carrier. It asks for the signature in the prompt and verifies nothing.

Under a shared identity the reviewer can only comment, since GitHub does not let the author of a pull request approve it or request changes on it. The verdict stays in the reviewer's result file, as it is today.

`carrier init` asks the setup as the first question of the identity step. Separate: the flow of today. Shared: it skips Forge and the choice of identity, uses the `gh` login for both roles, and says plainly that both roles act with everything the user's `gh` token can do, the reviewer included, before accepting. In both setups it then asks for the persona of each role, a name and a prompt, and either can be skipped. `carrier doctor` under a shared identity does not fail on the match and still checks, as it does for every profile, that the login can get a token for each repo and read it.

What was cut. A shared identity per repo: the account and its credentials are the same everywhere, and the per-repo override already covers a repo that wants a bot. A hidden marker of the role in each comment: the visible signature says it, the engine does not read who wrote a comment, and the solve skills have their own markers. Guaranteeing the signature with a hook on commits or a check of comments: the hook covers only commits and a check cannot tell the agent's unsigned comment from the user's. Letting the user turn the signature off: the colleagues in the organization would read the agent's words as the user's. Narrowing the token's reach: it is the price of having no App. A persona that is only a name for the signature: the user wants to say who the agent is, and that needs a prompt. Reading the `systemPrompt` from Forge's registry, or launching agents through Forge's launcher to get its prompt: the first reads a file with private key paths, the second changes how every execution starts, for something a few lines in the prompt builder do.

## Scope

1. A person who cannot get a second GitHub identity runs `carrier init`, chooses a shared identity, and ends with a config that loads and an engine that starts, without Agent Forge installed.
2. A person on a shared identity runs `carrier doctor` and it does not fail because author and reviewer are the same login, and it still fails when that login cannot get a token or read a repo.
3. Everything an agent publishes under a shared identity ends with the signature of its role and persona name, because its prompt says so, in the ship, review and fix stages alike.
4. A user gives a role a persona with a name and a prompt, in a config or in `carrier init`, and that role's agent is told them, under either identity setup.
5. A user on separate identities sees no change: same validation, same flow, no signature.
6. A user who runs `carrier init` over an existing config finds its identity setup and personas as the starting answers, and the recap shows them.
7. The spec, the README and the user docs say that author and reviewer must differ under separate identities and may be the same under a shared one, and document the persona.

## Decisions

**The config.** `identities` is a global enum with `separate` as its default, in `defaults` like the other defaults. `persona` is an optional part of an agent, global and per repo. The rule that author and reviewer differ runs only under `separate`. The name is a single trimmed line of at most 40 characters, since it ends up in GitHub text and in commit messages; the prompt is trimmed text of at most 4000. A repo override of a persona replaces the persona whole, as the existing merge of a role does for any key. Under `shared` two different profiles are still valid: that is a repo with a bot.

```ts
const persona = z.strictObject({
  name: z.string().trim().min(1).max(40).regex(/^[^\r\n]+$/).optional(),
  prompt: z.string().trim().min(1).max(4000).optional(),
});
// agent gains:        persona: persona.optional()
// configSchema gains: identities: z.enum(['separate', 'shared'])   (default 'separate' in load.ts)
// superRefine:        the author-and-reviewer-differ check runs only when config.identities === 'separate'
```

Seam: `loadConfig(defaults, raw)` and `resolveRepoConfig`, the interface the callers use, in `load.test.ts` and `resolve.test.ts`: the same profile is an error under `separate` and accepted under `shared`, with one error per field; a name with a line break, empty or of 41 characters is rejected; a per-repo persona replaces the global one.

**What the engine hands the agent.** `AgentTask` gains `persona` and `sharedIdentity`. The persona travels with the rest of the agent's config. `sharedIdentity` is true when the author and the reviewer of the epic resolve to the same account (the same profile, or two names for one `gh` login or one bot), computed where the epic's configuration is resolved and saved with it, so changing the config while an epic is running does not change it, as with the rest of that configuration. Carrier itself publishes no text on GitHub, only labels, so the signature concerns the agents alone.

Seam: the engine through its fake runner (`runner.tasks` in `engine.test.ts`): the task of each stage carries the persona and `sharedIdentity` true for a same-profile config, false for a different one, and a resumed epic keeps the value it started with.

**The prompt.** A new `src/prompts/persona.ts` renders the persona lines and, when `sharedIdentity`, the rule about the signature; `intro.ts` places them after its role line. The role of `ship` and `fix` is the author and of `review` the reviewer, as `intro.ts` already decides. The stage files and `result.ts` do not change, and nothing is added about how `code-post` or `code-resolve` behave.

```ts
export const signatureOf = (role: 'author' | 'reviewer', name?: string) =>
  `🤖 ${role === 'author' ? 'Author' : 'Reviewer'}${name ? ` [${name}]` : ''} via Carrier`;
```

Seam: `buildPrompt(task)` in `build-prompt.test.ts`: with a persona the name and prompt appear after the role line and before the stage; with `sharedIdentity` the signature rule appears with the right role and name for each of the three stages, and without a name there are no brackets; without either the prompt is as it is today.

**The doctor.** Under `shared` the check "author and reviewer are different identities" is not run; the token and read checks per profile stay as they are, and they are what proves the login works. Under `separate` nothing changes.

Seam: `runDoctor(config, deps)` in `doctor.test.ts`, with its existing `config()` helper: a same-login shared config has no failed check and no clash check in the list; the same config under `separate` still fails, and an unusable login still fails under `shared`.

**The wizard.** The first question of the identity step is `identities`, with the flag `--identities separate|shared`. Under `shared` it reads neither the Forge registry nor asks for an identity: both roles are `{kind:'gh'}` with the profile named `gh`, and so is the orchestrator's. It needs the `gh` login: without it, it stops with the fix `gh auth login`. The profile flags with `--identities shared` are an error, since the shared identity is the `gh` login. Before accepting it prints the note about the token's reach; with `--identities shared` and `--yes` the flag is the consent and the note is still printed. The persona of each role is asked after its agent, name and prompt, each skippable, with the flags `--author-persona-name`, `--author-persona-prompt`, `--reviewer-persona-name` and `--reviewer-persona-prompt`. `buildConfig` writes `identities` only when it is `shared` and a persona only when given, as it writes only what has no default. `Prior` carries both so that editing an existing config starts from them, and the recap lists them.

Seam: `wizard.test.ts` with its scripted `quietUi` and fake machine, and `build-config.test.ts` for the shape of what is written: choosing shared writes a config that loads, asks no identity question and does not touch Forge; separate asks what it asks today; every flag skips its question; an existing shared config is the starting point of an edit.

**The docs.** `docs/configuration.md` documents `identities` and `persona`, as the repo requires when the schema changes; the README, `docs/preparing-a-repo.md`, `docs/troubleshooting.md` and the original spec (`autonomous-orchestrator.md`) change the sentences that say the two identities must differ. No tests.

## Out of scope

How solve's `code-post` and `code-resolve` behave when the pull request is the account's own: it is not decided here, and what the review and fix stages are told about it is left for when they are run under a shared identity. The setup in the macOS app: identities and agents are configured outside the app, so it gets no screen for this. Different skills or instructions per stage. A tracker other than GitHub or other label names. Changing the git name or email of commits, per role or in general. Verifying that the signature is there. Narrowing the permissions of the token under a shared identity. A shared identity per repo. A hidden marker of the role.

## Open questions

Does the agent sign every kind of publication from the prompt alone, and which ones does it forget first? The first epics under a shared identity show it, and a missing signature on commits is what would bring back the hook.

Does a persona prompt placed in the text of the prompt weigh enough in every harness, or does it need the harness's own channel for system instructions, the way Forge does it with `--append-system-prompt` for Claude and `-c developer_instructions` for Codex? It goes in the text because Carrier builds one prompt for all harnesses; a short run on each harness shows whether that is enough.
