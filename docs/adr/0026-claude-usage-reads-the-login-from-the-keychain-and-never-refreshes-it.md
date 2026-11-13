# 0026 - Claude's usage reads the login from the macOS Keychain, and never refreshes it

- Status: accepted
- Date: 2026-11-13

## Context

[0025](0025-usage-runs-inside-the-chat-host.md) built Claude's live quota as a file-only path: the plaintext `.credentials.json` of the account's config folder, and never the Keychain. On macOS Claude Code keeps its login in the login Keychain and writes no such file, so every Claude account on a Mac reported `missing` and the Usage page showed no limits for Claude. 0025 left asking the Claude Agent SDK (`get_usage`) as a deferred follow-up.

Two open-source tools solve it differently ([research](../research/codexbar-usage-fetching.md)). Paradev reads the Keychain item with `security find-generic-password` and calls the OAuth usage endpoint, and never refreshes the token. T3 Code asks the `claude` binary through the Agent SDK, with an API marked experimental, and needs a process per account.

## Decision

The Claude probe reads the login from the Keychain when the account has no credentials file, as Paradev does:

- **Read only, no refresh.** The probe never writes the item and never refreshes a token: a refresh rotates the refresh token and can sign Claude Code out. An expired token is reported as signed out, with the words that Claude Code renews it the next time it runs.
- **Which item.** The default login is `Claude Code-credentials`. An account with its own config folder is `Claude Code-credentials-<first 8 hex digits of the SHA-256 of the folder as a string>`; the spellings of the folder (absolute, with `~`, with a trailing slash) are each tried. A folder that is not the default never falls back to the bare item, which is another account's login. The account is the login name (`USER`), or Claude Code's placeholder when that is not a plain name. Checked on a Mac with the real items.
- **How.** A port of the usage ports (`keychain(service, account)`), whose real side runs `/usr/bin/security find-generic-password … -w` with no shell, a 5 second limit and an empty environment but `HOME`, only on macOS. Exit 44 is "no such item"; any other failure is a Keychain that did not answer, shown as `unavailable` with "check again".
- **The secret.** It stays in the probe's memory for one request: it is not logged, not stored, not copied into an error, and not sent anywhere but Anthropic's usage endpoint.
- **The first read.** macOS asks the person to allow `security` to read each item the first time; "Always Allow" is a per-binary grant. A denial is a normal state, not an error.

The Agent SDK path stays the fallback if Anthropic changes the endpoint or the Keychain layout.

## Consequences

- Claude's 5 hour and weekly windows, and its extra credits, show on a Mac.
- The engine now reads a secret of another program. The rules above are the limit of that, and a change of them is a change of this ADR.
- The layout of the Keychain items is Claude Code's and can change without notice; the probe then reports `missing` as before.
