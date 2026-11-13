# Providers in Settings

Status: implemented (v0.2.0)

Source: AshuLab/carrier#749

## Problem

The AI tools Carrier runs agents with, Claude Code, Codex and Antigravity, have no home in the app. Whether they are installed, which version, whether each login is signed in and which accounts exist are known to a person only by running `carrier doctor` or editing `config.json` by hand. The one place an account is declared, the engine's `providers`, is invisible to the chat: the chat's agents name a harness and an optional binary, so a second login such as `claude-work` cannot be used in a chat, and the binary a person points Carrier at is a key that only the chat reads. Anything more about how a CLI runs for an account, where its binary is, when it compacts, which extra arguments it starts with, would have to be written twice and kept in step.

It is felt by whoever sets Carrier up on a Mac and by anyone with more than one login. Setting up today means answering the provider questions of `carrier init` for tools the Mac already has, then typing JSON when something changes.

We know it is solved when the app's Settings shows the tools found on this Mac with their version and state, when an account can be added, edited and removed there, when the engine and a chat use the same account with the same login and binary, and when a Mac with the CLIs installed has its accounts without anybody typing them.

## Solution

The accounts move out of `config.json` into one optional file in the Carrier folder, `providers.json`, which the engine and the chat host both read and the app writes ([0020](../adr/0020-accounts-live-in-a-file-both-processes-read.md), which has the alternatives that lost). It holds one key, `providers`, the map the engine already has, with the existing keys of an account kept (`harness`, `configDir`, `provider` for a local server, `model`) and these added: `displayName`, `command` (the binary, an absolute path), `autoCompact`, `idleCompaction`, `launchArgs` (a list of strings) and `enabled`.

`autoCompact` is `"auto"` or a token count from 100000 to 1000000 for Claude, applied as `--autocompact`, and a positive token count for Codex, applied as `-c model_auto_compact_token_limit=N`. `idleCompaction` is Claude's only, a boolean passed per run as `--settings '{"idleCompaction":…}'` so nothing in the person's own `settings.json` changes; the field offers "Use default" (nothing is passed) and "Never" (`false`). `enabled` says whether the account is offered when an epic's agent option is chosen. It is what keeps detection from changing how an epic starts: the engine makes an epic wait `limits.optionChoiceSeconds` when two or more accounts are offered, and detection writes accounts nobody asked to offer. Detection and the defaults write it `false`; it reads as `true` when absent, so a block moved by hand keeps behaving as it does today. A role, a failover list, a repo override and a chat agent may name any account, enabled or not.

`launchArgs` are appended to what Carrier already passes. When the file is read, Carrier refuses, naming the key, the flags it sets itself, because repeating them would change the permission mode or break the parsing of events. A token is judged by its flag name, so `--model=x` and `--model x` are the same. For Claude: `-p`, `--model`, `--permission-mode`, `--output-format`, `--resume`, `--name`, `--add-dir`, `--settings` and `--autocompact`. For Codex: `--model`, `--json`, `--dangerously-bypass-approvals-and-sandbox`, `--sandbox`, and the key of any `-c`/`--config` pair (in each form the CLI takes) when it is `model_provider`, `carrier_marker` or `model_auto_compact_token_limit`. A denylist is the right shape because the value is free-form and comes from the person's own file: it protects the run, not a boundary. The file holds no secret, and a log names an account and a flag, never an argument's value.

In the engine, the loader reads `providers.json` from the Carrier folder, wherever `--config` points, and puts the map where `config.providers` is today, so role resolution, the doctor, the status snapshot and the configuration an epic freezes when it is reserved keep their shape. `config.json` loses `providers` and refuses it with a message that names the new file. Without the file there is one account per harness, named after it, with this Mac's login and `enabled: false`. The runners apply the new keys: `command` replaces the lookup of the harness's name on the PATH, the config folder keeps its variable, and `autoCompact`, `idleCompaction` and `launchArgs` join the arguments of the run. Wherever the engine lists accounts for a person to choose from, or counts them for the choice wait, it considers only the enabled ones; wherever it checks a name (a role, a failover list, a restart's choice) it accepts any declared account. The doctor also checks that an account's `command` exists and runs. The engine reads the file when it starts, like `config.json`.

In the chat host, `chat.json` loses `harness` and `command`, and a chat agent names an `account` (with the `model` and `options` it has). Without `chat.json` the agents are `claude` and `codex`, each on the account of the same name. The host reads `providers.json` each time it opens a session or checks health and hands the runner the account's environment, binary and arguments. The Claude adapter passes them through the SDK (`pathToClaudeCodeExecutable`, `extraArgs`, `env`); the Codex adapter, which starts `codex app-server` alone today, accepts `-c` pairs and the other arguments. An agent whose account is missing, or is Antigravity's, is refused when a session opens, naming the account. The health check stops asking only whether a harness is signed in and asks per account, with that account's folder in the environment, so `claude-work` is not judged by the login of `claude`.

One detector in the core answers what is on the Mac: for each harness, whether its binary is found, with its path (through `resolveBinary`, never `which`, because a wrapper script can come first on the PATH) and its version, and for each account whether it is signed in, with its own folder in the environment, using the check the doctor already has. It also lists the local model servers that answer and their models, without creating accounts for them; an account on LM Studio or Ollama is added by hand. The chat host exposes it as a request. `carrier init` calls it directly, and so will the app's setup wizard later.

The app's Providers page follows the prototype (`docs/research/macos-app-design/explorations/settings-groups-options.html`). A list of the tools, Claude Code, Codex, Antigravity, LM Studio and Ollama, each with its state, version and path; for each tool its accounts, each row saying which role or chat uses it, with Sign in in Terminal, Edit and Use in a role; an editor for the selected account with its runtime fields; Add account, with a name and a config folder; Remove, refused while a role or a chat names the account (the app reads `config.json` and `chat.json` for that, as it already does for its other pages). The version line is the version and the path, with an Update button that opens Terminal on `claude update`, `codex update` or `agy update`: none of the three can only check, they install, so the page cannot say "Up to date" without updating. Sign in and Update open Terminal with the script and the opener of the Health fix buttons and Continue in Terminal ([0007](../adr/0007-continue-in-terminal-through-a-validated-descriptor.md)); the app builds the command from a fixed list of harness and action, and the sign-in command carries the account's `CLAUDE_CONFIG_DIR` or `CODEX_HOME` as the doctor's fix already does, or the login would be made on the wrong account. The page reads its state from the chat host and edits `providers.json` itself, keeping the keys it does not know and writing the file whole and in one step, as it does with `chat.json`. The Health page loses its agent rows, which this page replaces, and keeps git, gh and the paths.

Detection is automatic once and then explicit. When the app opens and `providers.json` is missing, it asks the host and writes the file with one account per harness found, named after it and `enabled: false`. After that, a harness that is found and has no account shows a row "Found, not added" with an Add button; nothing is added again by itself, so removing an account is not undone. More accounts of the same harness, such as `claude-work`, are always added by hand. The detector reads the PATH of the process that asks; the app starts the host with the PATH it already keeps in Health, which comes from the login shell, because an app opened from Finder does not see Homebrew.

`carrier init` loses its provider questions: it shows what the detector found, asks only for extra accounts and local servers, and writes `providers.json` where it used to write the `providers` block, in the Carrier folder even when `--out` points the config elsewhere, and says so in its recap. The flags that declare an account (`--author-provider` and the like) add it to that file, and edit mode starts from the accounts already in it.

The documentation changes with it: the configuration guide (`providers` moves, `providers.json` and the chat agent's `account` are documented, the table of keys), the README and `AGENTS.md` where they list the config files and the schemas, and the ADRs 0013 and 0016 where they say what the chat reads.

## Scope

1. A person can write accounts in `providers.json`, and the engine starts with them as its `providers`; a file that does not match stops it with the key named.
2. Without `providers.json` the engine has one account per harness with `enabled: false`; a `config.json` that still has `providers` is refused with a message naming `providers.json`.
3. An account's `command`, `autoCompact`, `idleCompaction` and `launchArgs` reach the process the engine starts for Claude and for Codex.
4. A `launchArgs` entry that repeats a flag Carrier sets is refused when the file is read, in every form the CLI takes.
5. The engine waits for an epic's option choice only when two or more enabled accounts are offered, and lists only enabled ones; a restart or a role may still name a disabled account.
6. The doctor fails an account whose `command` does not exist or does not run.
7. A chat agent in `chat.json` names an `account`; the defaults are `claude` and `codex`; a missing account or an Antigravity one is refused when a session opens, naming it.
8. A chat on a second account uses that account's login, binary and arguments, on both Claude and Codex.
9. The chat host's health says, per account, whether its CLI is found and signed in, with that account's own folder.
10. One detector reports, per harness, the binary path and version, and, per account, whether it is signed in; and the local servers that answer, with their models.
11. The chat host answers a request with the accounts, their state and the harnesses found with no account.
12. `carrier init` uses the detector, writes `providers.json` in the Carrier folder, and keeps the accounts of an existing file when it edits.
13. The app reads and writes `providers.json` without losing the keys it does not know, and never leaves a half-written file.
14. When the app opens without `providers.json`, it creates it from what the host found; afterwards a harness found with no account shows an Add row, and nothing is added by itself.
15. The Providers page lists the tools with state, version and path, and each tool's accounts with who uses them.
16. A person can add, edit and remove an account in the page; removing one that a role or a chat names is refused and says which.
17. Sign in and Update open Terminal on the right command, and the sign-in carries the account's folder.
18. The Health page no longer lists the agents, and the Providers page does.
19. The configuration guide, the README, `AGENTS.md` and the ADRs that say what the chat reads agree with all of the above.

## Decisions

The account's schema, trimmed to the decision. It is checked against the inputs it takes, the wrong-typed and empty ones included: `autoCompact: "300000"` (a string) fails because the union takes the literal `"auto"` or an integer; `0`, `-1` and `1.5` fail as not positive integers; `launchArgs: "--chrome"` fails as not a list and `[""]` as an empty entry; `command: ""` fails on `min(1)` and `command: "claude"` as not absolute; `idleCompaction: "false"` fails as not a boolean; and a key the harness does not have is refused by name.

```ts
export const account = z.strictObject({
  harness: z.enum(harnessNames),
  displayName: z.string().trim().min(1).max(60).regex(/^[^\r\n]+$/).optional(),
  command: z.string().min(1).transform(expandHome).refine(isAbsolute, 'must be an absolute path, or start with ~/').optional(),
  configDir: z.string().min(1).transform(expandHome).optional(),
  provider: z.enum(['lmstudio', 'ollama']).optional(),
  model: z.string().min(1).optional(),
  autoCompact: z.union([z.literal('auto'), z.int().positive()]).optional(),
  idleCompaction: z.boolean().optional(),
  launchArgs: z.array(z.string().min(1)).optional(),
  enabled: z.boolean().optional(),
});
// then, per harness: claude takes autoCompact "auto" or 100000..1000000 and idleCompaction; codex takes an integer autoCompact and no idleCompaction;
// agy takes neither, nor configDir; launchArgs are checked against that harness's refused flags.
export const providersFile = z.strictObject({ providers: z.record(z.string(), account) });
```

The account names keep the pattern the engine already enforces (`optionNamePattern`). The file's reader is a function of the parsed JSON (`{}` when there is no file), like `loadChatConfig`, so the engine and the chat host share it and both stop with the key named.

`enabled` is read in two places only: where the engine counts accounts for the choice wait and where it lists them for the person to choose. Everything that validates a name does not look at it. The config an epic freezes carries the accounts as they were, `enabled` included.

The chat host reads the file per session and per health check instead of keeping it, so an edit reaches the chat with no restart; the engine does restart. The Providers page no longer says so under the accounts. The editor takes any text for the config folder: one that is not absolute and does not start with `~/` is written from the home folder (`work` as `~/work`), so the file stays one the engine reads.

The detector takes its machine as a port, like the wizard's `deps`: `resolveBinary`, a version probe, the doctor's login check and the local servers' listing. Nothing in it touches the real machine in a unit test.

The app's Terminal actions are a closed list, harness by action (`signIn`, `update`), and the account's folder is accepted only as an absolute path; nothing from the host or from `providers.json` becomes part of a shell string unquoted, which is the rule of 0007.

Testing seams, story by story. Each uses the seam that exists and the broadest one that isolates it.

- Stories 1, 2, 4: `loadConfig` and the new reader of the file, driven with objects, in `src/config` (`load.test.ts` and a test of the file's reader beside it). No tests of zod itself; of what the schema decides, the table of inputs above, the defaults and the refused flags in each form.
- Story 3: `buildClaudeCommand` and `buildCodexCommand` return the binary, arguments and environment, so the runtime keys are asserted on that value, in `claude.test.ts` and `codex.test.ts` of the harnesses.
- Story 5: the reservation in `src/orchestration` with its fake clock and fake ports, and `resolveRepoConfig` for the listing. One test with two enabled accounts, one with two where one is disabled.
- Story 6: `doctor.test.ts`, with its injected deps.
- Story 7: `loadChatConfig` in `src/chat/config.test.ts`, and `createSessions` with the fake runner in `sessions.test.ts` for the refusals.
- Story 8: the adapters' own tests with their fake spawn and recordings (`src/chat/claude.test.ts`, `codex.test.ts`) assert the environment, binary and arguments they start with. One gated integration test per provider, in the existing `*.integration.test.ts`, runs a real `app-server`/SDK with a `-c` pair.
- Stories 9, 11: `createHealth` with its `HealthProbes` fakes (`health.test.ts`), and the request union in `server.test.ts`.
- Story 10: the detector with a fake machine, in a test of its own beside it.
- Story 12: `runInit` with the scripted `Ui` and the fake `deps` of `wizard.test.ts`, asserting what is written and where.
- Stories 13, 14, 16: the Swift store that reads and writes the file, in `macos/Tests/CarrierCoreTests`, with a temporary folder, as `BehaviorSaveTests`, `SessionAges` and `NewSessionTests` do for `config.json` and `chat.json`: unknown keys kept, a failed write leaving the old file, the first-run creation, the "found, not added" rule, the refusal to remove an account in use.
- Story 17: the builder of the Terminal command, in the Swift tests of Continue in Terminal and the Health fixes (`ContinueInTerminalTests`, `HealthFixTests`): the closed list, the quoting and the account's folder in the command.
- Stories 15, 18: no unit tests, the views are thin over the stores above; the fixture build and the smoke check of the macOS workflow cover them.
- Story 19: no tests, a documentation change.

## Out of scope

The Carrier and Chat Agents pages: the defaults per tool (model, reasoning effort, permission, approvals, sandbox), the switch that turns an account on or off for epics, and more chat agents per account. This epic ships the `enabled` key and what the engine does with it; until that page exists, `enabled` is edited by hand in `providers.json`.

The Roles, Repos and Identities pages, and the setup wizard of the app. The wizard will reuse the detector; it is not built here.

Runtime fields for Antigravity and for local-server accounts beyond the keys they already have. Antigravity appears with its state, version, path and Update, and has one account with no folder.

More values for Claude's idle compaction than Use default and Never: the CLI exposes a single boolean today, and the other two values a person may expect, "After you return" and "Before the cache expires", look like the two ways the same compaction ends and may depend on `precomputeCompactionEnabled`. They come back if a `research` shows the CLI offers them as separate choices.

A Shadow home for Codex, an API key or a sign-in method in the app (Carrier keeps no secret and signing in is the CLI's), and any way to read "Up to date" without installing.

A migration of the old shape: the author moves their own `providers` block and fixes their `chat.json` by hand.

## Open questions

Whether `codex app-server` honours `-c model_auto_compact_token_limit` and the other `-c` pairs the way `codex exec` does, since the chat uses the first and the engine the second. Both helps accept `-c`, and `app-server --print-startup-config` does not echo the override, so only a real run can tell. The adapter's gated integration test answers it. If the answer is no, the Auto-compact field of a Codex account applies to the engine's runs only and the page says so in its line; the rest of the epic does not wait on it.

The `enabled` key described above was removed by [0021](../adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md): an epic starts at once on its roles, so no account is held back, and a `providers.json` that has `enabled` is refused naming the key.
