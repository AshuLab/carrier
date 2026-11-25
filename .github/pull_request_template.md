## What and why

<!-- One sentence per line: what changes, and why it is needed. -->

Closes #

## How it was checked

<!-- What you ran and what you saw. Say what you could not run (the app, a job only CI has, a real agent), so the reviewer knows what is still open. -->

## Checklist

Delete the lines that do not apply.

- [ ] `pnpm typecheck` and `pnpm test` pass (CI runs them too)
- [ ] A line under Unreleased in `CHANGELOG.md` if a user can see the change (if not, label the PR `no-changelog`)
- [ ] A config schema changed (`src/config/schema.ts`, `src/config/providers.ts`, `src/chat/config.ts`): `docs/configuration.md` is updated
- [ ] A storage schema changed: the migration from `pnpm db:generate` is committed, and a new table file is in the list in `drizzle.config.ts`
- [ ] A prompt changed: the snapshots are updated (`pnpm test -u`) and `src/prompts/result.ts` stays in step with `src/execution/caller-result.ts`
- [ ] Something in `design/` changed: `pnpm design` was run and its generated files are committed
- [ ] A view of the macOS app changed: I looked at it in Carrier Dev under `--fixture`, and `docs/macos-ui.md` is updated if a piece or a rule changed
- [ ] No secrets in the code, config, logs or this description
