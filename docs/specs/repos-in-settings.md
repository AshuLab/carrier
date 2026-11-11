# Repos in Settings

Status: spec

Source: AshuLab/carrier#765

## Problem

The Repos tab of Settings tells a person which repos Carrier watches and how the last check went, and lets them add and stop watching one. It says nothing about the thing that most often keeps a repo from working: whether the bots can sign for its owner, whether the repo is prepared for Solve, and who works on it. A repo whose owner has not installed the author's GitHub App fails at its first epic, and the person finds out from the epic, or by running `carrier doctor` and reading a line that names an identity and a repo. And the one place to change who works on a repo, the `agents` override of a repo in `config.json`, has no page at all: it is typed by hand, so a second repo of another owner, which almost always needs its own bot, means editing JSON.

It is felt by whoever adds a repo of an organisation or a person other than the one that owns the bots, and by whoever sets Carrier up and has to learn why the first epic stopped.

We know it is solved when a repo's page shows, before any epic runs, whether Carrier can read it, whether each role's bot can sign there and whether Solve is set up in it; when the person can give a repo its own identity, provider, model, effort or persona from that page and go back to the default with one button; and when a repo added with nothing else done runs on the global roles.

## Solution

The page is the master-detail of the prototype (`docs/research/macos-app-design/explorations/settings-groups-options.html`, Carrier › Repos). It replaces the Legacy Repos tab and moves into a new Carrier group of the rail (`SettingsPage.Group` has only App and Legacy today). The list has the watched repos, each with a dot and a line, and the picker of repos to add under it. The picker is the one that exists (the engine's `availableRepos`, paged by 30, grouped by owner, search over what is loaded, a repo already watched shown as such, one whose folder name another has refused with the reason). This epic reuses its model and does not change it, and it keeps needing a running engine. Removing a repo keeps its question and the rule that the only repo cannot be removed. Changes are saved as they are made, as the tab does today, and the page says that Carrier reads them when it starts.

A repo's page has three cards. Status holds the epics ready and running and the last check (what the snapshot already gives the tab), the clone's place with Reveal, and the repo on GitHub. Ready for Carrier holds four checks: Carrier can read it, Author can sign here, Reviewer can sign here, and Solve is set up. Who works here holds the three roles, each showing what it inherits from the global `agents` or its own override, with a Reset.

The checks come from `carrier doctor`, which the app already runs as a process on the file on disk, so a repo added a minute ago is checked without restarting Carrier. The doctor's per-repo lines are plain names today, such as `forge agent x can mint a token for o/r`, and the app would have to parse them. The doctor's JSON entries gain two optional fields on the checks that are about a repo: `repo`, and `profiles`, the names under `config.profiles` that the check covers. A mint check is made once for an identity and a repo even when two profile names are the same bot, so `profiles` lists every name it stands for. Nothing else about the output changes, so an older app keeps working and the Health tab is untouched. The app maps a role to its check through the profile that role resolves to in that repo (the repo's override, else the global one). The read check carries the orchestrator's profile.

The fourth check is new, and it needs no new call: the read check already fetches the repo's labels with `listLabels`, and when it succeeds the doctor reports `<repo> has the Solve labels`, ok when `solve:epic` and `solve:epic:ready` are both there, fail otherwise, naming the missing ones and with the fix "run solve:setup in the repo, it creates them". The file `docs/agents/solve.md` is not checked, because that needs a new read of GitHub for a line that adds little over the labels. When the read check does not run or fails, there is no Solve check, and the page shows that row as waiting, as it does any check the doctor skipped because something before it failed (no `gh`, no Forge): waiting, not failed. Branch protection was in the prototype and is out: reading it needs admin rights on the repo, which the orchestrator's token probably lacks, so the page would say "not protected" when it had not been able to look.

Who works here is where the app grows. Today it never reads `profiles` or the global `agents` and edits only the keys it owns, leaving the rest of the file as it is. The page must read the profile names, the global roles (for the inherited text) and the repo's own `agents`, and write `repos[].agents.<role>`, with the same rule of keeping every key it does not know and reading the file again just before it writes. A role you change opens, inside the card, the same fields the global role has: Identity (a profile of `profiles`), Provider ([0020](../adr/0020-accounts-live-in-a-file-both-processes-read.md): the accounts of `providers.json`, or the three default accounts when the file is not there), Model (text), Effort (one of `low`, `medium`, `high`, `xhigh`, `max`, or none; [0021](../adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)) and Persona (the name and prompt the engine accepts, with its limits). Each field is its own override: a field left alone keeps the inherited value, and an override with nothing in it is not written. Reset removes the role's entry. The app checks what is cheap before it writes: the names exist. The same identity on the author and the reviewer is allowed, because an epic is shared when they resolve to the same account ([0021](../adr/0021-an-epic-starts-on-its-three-roles-and-a-roles-failover-chain-names-a-provider-and-a-model.md)): the page says the signature will show it. The engine's own validation, and `carrier doctor`, say the rest, and the page shows the doctor's reason when it refuses.

The Lead reviewer row is shown only when the global config has a Lead reviewer. A repo may in fact add one the global config lacks, but only by giving its identity, provider and model together, and this epic does not offer that. A failed "can sign here" check offers Use another identity, which opens that role's form. The button Open Agents of the prototype is not shown in this epic, because the page it opens comes from the Agents epic (`AshuLab/carrier#778`), which adds the button; until then the inherited text is read-only.

A repo just added is in the file but the running engine has not loaded it. The page says so, "Carrier reads it when it starts", in place of the epics and the last check, and its checks run from the doctor all the same. When Carrier is stopped, every repo reads like that.

What was weighed and cut: merging Repos with the page of the global roles (Agents) as an "All repos" entry at the top of the list, which keeps defaults and exceptions together but moves failover and the Lead reviewer's switch into a page whose items are repos; a pause switch per repo, which needs a new key and has no demand while a repo with no ready epic does nothing; the engine returning a structured per-repo status over the control socket, which is the best shape for a later web client but a larger change than the doctor's two fields, which the app already runs; and checking `docs/agents/solve.md` and the branch protection.

The documentation changes with it: `docs/troubleshooting.md` and the README where they show the doctor's JSON, `docs/specs/health-check-in-the-app.md` for the new fields and the Solve check, and `macos/README.md` for the new page.

## Scope

1. A person running `carrier doctor --json` gets, on each check about a repo, the `repo` and the `profiles` it covers, and nothing else is different for a reader that ignores them.
2. `carrier doctor` reports `<repo> has the Solve labels` for each watched repo it could read, failing with the missing labels named and the fix.
3. The Settings rail has a Carrier group with the Repos page, and the Legacy group no longer has it.
4. A person sees the watched repos with their dot and line, adds one from the picker, and stops watching one after the question, except the only one.
5. A person opens a repo and sees its Status: epics, last check, the clone with Reveal, and the link to GitHub.
6. A person sees the four checks of a repo, each ok, failed with its reason, or waiting, from a doctor run on opening the page and on Check again.
7. A repo that is in the file but not loaded by the running engine, or any repo while Carrier is stopped, says "Carrier reads it when it starts" instead of epics and last check.
8. A person sees, for each role of a repo, the value it inherits from the global config or its own, with the Lead reviewer row only when the global config has one.
9. A person changes a role's identity, provider, model, effort or persona for one repo, each field on its own, and the page writes only that repo's `agents` entry, leaving every other key of the file as it was.
10. A person resets a role and its entry is gone from the file.
11. The page refuses, before writing, a name that does not exist; it accepts the same identity on the author and the reviewer, saying that the signature will show it; and it shows the doctor's reason for anything else the engine refuses.
12. A failed "can sign here" check offers Use another identity, which opens that role's form.
13. The documentation lists the new doctor fields, the Solve check and the page.

## Decisions

The doctor's entry, trimmed to what changes:

```ts
export type Check = {
  name: string;
  status: 'ok' | 'warn' | 'fail';
  detail?: string;
  fix?: string;
  /** Set on the checks about one repo. */
  repo?: string;
  /** Set with `repo`: the names under `config.profiles` the check stands for, never empty. */
  profiles?: string[];
};
```

`repo` and `profiles` are both present or both absent. A mint check carries every profile name that resolves to that identity for that repo; the read check carries the orchestrator's profile; the Solve check carries the orchestrator's profile too. The Swift side decodes them as optional, so a doctor from before this change still decodes.

What the page writes for a role, trimmed to the decision. A role's entry holds only the fields the person set; an empty field is not written, and an entry that would be empty is removed:

```jsonc
// the repo, after the person changed the reviewer's identity and model only
{ "name": "vemec/encaja", "agents": { "reviewer": { "profile": "vemec-reviewer", "model": "qwen3-coder" } } }
```

The inputs it takes: a persona with only a name, or only a prompt, is written as such (the engine accepts both, trimmed, the prompt not empty); a model of only spaces is empty and is not written; an identity or account that is no longer declared is shown as missing and refused when saving, not dropped. This was run against the loader with the global config of a repo of two roles: a role with only a persona, only a model, only an account, only a profile, or no field at all loads; a profile equal to the other role's is refused ("must differ"); an unknown profile or account is refused naming the key; and a Lead reviewer for one repo with no global one is refused unless its profile, account and model are all present.

Testing seams, story by story, with the ones that exist:

- Stories 1 and 2: `runDoctor` with its injected deps in `doctor.test.ts`, asserting the fields of each check and the Solve check from a fake `listLabels` (both labels present, one missing, the read check failing so there is none); and the doctor command's JSON through the same value it prints.
- Story 3: `SettingsPageTests`, the group of each page and the order of the rail.
- Stories 4 and 7: the list's model in `RepoListTests` (`RepoRow` and the rows from the draft, the snapshot and the config), and the picker's model in `AvailableReposTests`, which stay as they are.
- Stories 5, 6 and 8: a pure model of a repo's page in CarrierCore, fed with the list's row, the doctor checks (`DoctorChecksTests` decodes them, including an output without the new fields) and the parts of the config the app reads; the rows it returns are asserted, in a test file of their own.
- Stories 9, 10 and 11: the reader and writer of the config in the style of `EngineConfigTests`, over a temporary file: unknown keys kept, the file read again before writing, a field left alone not written, an empty entry removed, a refused name not written.
- Story 12: the model of the page, asserting that a failed sign check of a role offers the action that opens that role.
- Story 13: no tests, a documentation change.
- The page's views have no unit tests; the fixture build and the smoke check cover them. The fixture mode serves a golden doctor output with the new fields so `--fixture` shows the page.

## Out of scope

The Agents and Behavior pages (Agents has its own epic and replaces the earlier Roles and Identities pages), and the buttons that lead to them. Creating a bot. The setup wizard of the app, which has no engine to list repos with and will need the chat host's `githubRepos` for that. Pausing a repo. Branch protection and the `docs/agents/solve.md` check. A way to type a repo's name by hand in the picker. A new Lead reviewer for one repo.

Moving the accounts out of `config.json`: that is [0020](../adr/0020-accounts-live-in-a-file-both-processes-read.md), its own epic, which this one comes after, because the Provider field reads `providers.json`. Its role form also writes `effort` and relies on the derived sharing of the Agents epic, so the engine tickets of that epic for them come first. The Providers epic adds a group of its own to the same list of pages, so the two should not be built at the same time.
