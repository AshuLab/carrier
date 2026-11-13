# src/terminal

- `cli`: only the command line.
  `main.ts` parses and dispatches, `args.ts` is the option table, `commands/` one file per command (`control.ts` serves stop, pause, resume, check and reload).
  `control-client.ts` is the client of the control socket that `status`, `watch`, `start` and the control commands use.
  `config-file.ts` reads the config, `compose.ts` wires the real engine.
  A failure to report is a `CliError`; only `main.ts` turns it into an exit code.
- `prompts`: the terminal contract (`Ui`, `Cancelled`) and its clack implementation.
  Commands depend on the contract, tests script it.
- `wizard`: `carrier init`.
  `wizard.ts` is the flow, `questions/` one file per thing asked, `deps.ts` everything that touches the machine (replaceable in tests; the agent CLIs, their logins and the local servers go through `doctor/detect.ts`, the one detector), `prior.ts` and `summary.ts` the edit mode and the recap.
- `dashboard`: the panel.
  `dashboard.ts` and `plain.ts` draw it, `history.ts` the stage history of a card and its cache, `ui-state.ts` is the pure key reducer, `interactive.ts` wires keys to actions.
