# The repo list is browsed a page at a time

Status: spec

## Problem

`carrier init` ("Repos to watch") and the macOS app's Add repo picker (the `availableRepos` request) list the repos the `gh` login can push to with one call, `user/repos?...&per_page=100`, no pagination. A person with more than 100 repos sees only the 100 with the latest push, and nothing says the list is partial. In the wizard the way out is "Other…" and typing `owner/name`; in the app there is no way out at all (the picker has no typing), so a repo past the first 100 cannot be added from the app. `docs/specs/macos-app-redesign.md` records "the first 100 by latest push" as the intended bound, but never as something the person is told.

What hurts is not being able to see and pick every repo, on both surfaces. On the account that raised this, the token sees 437 repos across three orgs and the picker shows 100.

## Solution

The list is read a page at a time and the person asks for more. A full read is not an option: it took over two minutes here, past the 30 second engine timeout, so the app would say "github unavailable" instead of showing anything. Searching by name is not it either: the person wants to browse, and a search is a second interface to build and keep.

**Engine.** The `availableRepos` request takes an optional `page`, GitHub's own page number (an integer from 1 to 100; anything else is the existing `invalid request`), and the reply is `{ repos, hasMore }`. The page size is 30, sort stays by latest push. The filter (archived, disabled, no push permission) is applied after paginating, so a page can come back with fewer than 30 repos or none; `hasMore` follows the raw page (it came back full), not what survived the filter. To know the raw count the `--jq` prints it as its first line and the repos after it; `parseRepos` reads that line and keeps dropping names that are not `owner/name`. A request without `page` answers page 1. `limits.githubCallTimeoutSeconds` now bounds each page, which is what the existing sentence in `docs/configuration.md` already says.

**Capability.** The hello's `capabilities` gets `availableReposPaged`. `availableRepos` stays in the list (an app that only knows it still works). The request is a strict object, so an engine without `availableReposPaged` would refuse `page`: the app checks the capability and, without it, shows the first page as it is, with no "Load more". The engine and the app ship from this repo together; an older app talking to this engine gets the first 30 repos and no way to ask for more, so the two are updated at once.

**Wizard.** `deps.listRepos` takes a page and answers `{ names, hasMore }`, and its synchronous `execFileSync` gets a timeout (the default of `limits.githubCallTimeoutSeconds`, as there is no config yet at `init`). While `hasMore` holds, the list ends with a "Load more…" entry next to "Other…"; choosing it reads the next page and shows the list again, with what was already ticked kept and the new repos added under their owner's section. A page that adds nothing after the filter is shown as it is: the entry stays while `hasMore` holds. The existing fallbacks stay (the list cannot be read: warn and type; a later page that fails: say so and keep what is loaded, with "Other…").

**App.** The picker's model (`CarrierCore/AvailableRepos.swift`) keeps the pages loaded and the next to ask for; the picker ends with a "Load more" button (not infinite scroll) and a visible "partial list" notice while there is more. The search filters what is loaded. Browsing every page reaches every repo, so the app gets no field to type a name. A page that fails after the first shows the GitHub error message of the picker but keeps what is loaded.

`docs/specs/macos-app-redesign.md` (the `availableRepos` paragraph) and `macos/README.md` (the Repos tab) are updated to say this: the first-100 bound is gone.

## Scope

1. As someone running `carrier init` with more than 30 repos, I see the first 30 and a "Load more…" entry, and each time I choose it I get the next 30, with what I had ticked still ticked.
2. As someone adding a repo in the app, I see the first 30, a notice that the list is partial and a "Load more" button that adds the next 30 until there are no more; I can search what is loaded.
3. As someone whose `gh` login can push to more repos than fit in one page, I can reach any of them from either surface by loading pages, without typing its name.
4. As someone using the app with an engine that does not know `availableReposPaged`, I see its first page as before, without a "Load more" that would fail.
5. As anyone, no single call to GitHub hangs the wizard or the engine: each page is bounded by the timeout.

## Decisions

No ADR: the request grows by one optional field and one capability, the way `resumeEpic` was added, and nothing here is hard to undo.

The shape of the engine side:

```ts
// the request
z.strictObject({ id, cmd: z.literal('availableRepos'), page: z.int().min(1).max(100).optional() })
// the reply data
{ repos: AvailableRepo[]; hasMore: boolean }
// the gh output: first line the raw count of the page, then one repo per line as today
// '(length | tostring), (.[] | select(...) | [...] | @tsv)' with per_page=30&page=N; hasMore = count == 30
export type Capability = ... | 'availableReposPaged';
```

Testing seams, per story:

- **1, 5 (wizard).** `src/terminal/wizard/questions/repos.test.ts` through `runInit` with `fakeDeps` and the scripted `quietUi`: a first page with `hasMore` lists "Load more…", choosing it asks for page 2, the ticked repos survive, the entry goes away when `hasMore` is false, an empty page keeps the entry, a failing later page keeps what is loaded. The timeout on the real `gh` call is not unit tested (`realDeps` is the one thing that touches the machine); the arguments are, below.
- **2, 3, 5 (engine).** `src/control/server.test.ts`, the socket contract: `page` is passed to the control, `page` 0, 101 or a string is `invalid request`, the reply carries `hasMore`, the hello lists `availableReposPaged`; the existing failure and slow-call cases keep their tests. A new `src/integrations/available-repos.test.ts` drives `parseRepos` with a fixed output (the count line, filtered pages that are short or empty, `hasMore` from the raw count, a bad name dropped) and checks the arguments of `ghReposArgs(page)`. `control-client.test.ts` and the other tests that list capabilities are updated.
- **2, 4 (app).** `macos/Tests/CarrierCoreTests/AvailableReposTests.swift` with `FixtureEngine`: pages are appended in order, the next request carries `page`, `hasMore` false ends it, an engine with only `availableRepos` is asked once and without `page`, a later failure keeps the loaded repos. `FixtureServerTests` learns the new capability. The SwiftUI view has no test of its own; the model carries the logic and the visual check is the usual smoke pass.
- **1 (docs).** No test: `docs/specs/macos-app-redesign.md` and `macos/README.md`.

## Out of scope

Searching GitHub by name. Typing `owner/name` in the app's picker. Caching the list between openings. Infinite scroll in the app (a button). Changing the filter or the sort. SAML SSO hidden repos, unless checking shows they are the reason repos are still missing after this.

## Open questions

How long one page takes on the account with the big orgs. Here (`vemec`, 23 repos) a page takes about a second; the 2 minutes measured for five pages on `dghersi_meli` may be about 25 seconds each, which would put even a 30-repo page near the 30 second timeout. Measure with `time gh api 'user/repos?affiliation=owner,organization_member&sort=pushed&per_page=30&page=1' --jq length` under that login; the answer may move the timeout, not the shape.

Whether orgs with SAML SSO enforcement hide repos from the token. Not checked; look after paging is in if repos are still missing.
