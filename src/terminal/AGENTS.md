# src/terminal

- `cli`: only the command line.
  `main.ts` parses and dispatches, `args.ts` is the option table, `commands/` one file per command (`control.ts` serves stop, pause, resume, check and reload).
  `control-client.ts` is the client of the control socket that `status`, `watch`, `start` and the control commands use.
  A refused reply rejects with a `ControlRefused` (its words, `code` and `params`): a command decides by the `code` and prints words of its own, never reads the words to decide ([ADR 0055](../../docs/adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)).
  `config-file.ts` reads the config, `compose.ts` wires the real engine.
  A failure to report is a `CliError`; only `main.ts` turns it into an exit code.
- `prompts`: the terminal contract (`Ui`, `Cancelled`, `Back`) and its clack implementation.
  Commands depend on the contract, tests script it.
  `keys.ts` decides what the last key means (Esc is `Back`, Ctrl+C is `Cancelled`) and `journal.ts` wraps a `Ui` so Esc and the recap's jump run the flow again with every answer already given taken from it.
- `wizard`: `carrier init`.
  `wizard.ts` is the flow, `questions/` one file per thing asked, `deps.ts` everything that touches the machine (replaceable in tests; the agent CLIs, their logins and the local servers go through `doctor/detect.ts`, the one detector), `prior.ts` and `summary.ts` the edit mode and the recap.
  `roles.ts` is the one table of the roles that have flags (author, reviewer, lead reviewer) that `questions/role.ts` (one closed block per role, the extra reviewers' too), `flags.ts` (the flags of every question) and `validate-flags.ts` (the flags refused before the machine is probed) are built from.
  The extra reviewers' flags name the reviewer (`--extra-reviewer "<name>=<harness>:<model>"` and `--extra-reviewer-<field> "<name>=<value>"`, the fields in `extraFlagSuffixes`): `parseExtras` in `validate-flags.ts` turns them into one `ExtraFlags` per reviewer, in the order given, and is the one place that refuses them.
  An extra reviewer is not a slot: its block (`questions/extra.ts` asks its name and type) is the `extra-reviewer` block, and its questions never carry its name, because the journal knows a question by its words and a new name keeps the answers already given; its key comes from `config/extra-reviewer-key.ts`.
  `keep-rest.ts` makes an edit write `engine.json` as it is, with only the keys the wizard owns replaced.
- `dashboard`: the panel.
  `dashboard.ts` and `plain.ts` draw it, `history.ts` the stage history of a card and its cache, `ui-state.ts` is the pure key reducer, `interactive.ts` wires keys to actions.
