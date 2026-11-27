# Roles and identities in Settings

Status: implemented (unreleased)

## Problem

Since 0.19.0 the engine runs up to four reviewers in parallel and a lead reviewer after them ([0048](../adr/review/0048-a-review-round-has-several-reviewers-in-parallel-and-a-lead-reviewer-closes-it.md)), set in `engine.json` with `agents.extraReviewers`, `agents.leadReviewer`, `skills.lead` and `limits.maxLeadRounds`.
The app shows almost none of it.
Settings › Agents draws three fixed roles, so a person whose file has two extra reviewers reads a page that says one reviewer runs, while three run on every epic, each with its cost.
To add, change or remove an extra reviewer they edit the file by hand.
The lead is half there: it has its switch, but its skills are not shown, `limits.maxLeadRounds` is not in Behavior, and the page still says the lead has no stage.
Watching hides the same thing per repo: a repo with its own list of reviewers, or with none, shows the Author, the Reviewer and the Lead as if nothing else ran there.

The page also mixes two things.
A role is a place in an epic with the skills it runs there; an identity is the GitHub account that signs what a role posts.
Today the identities are a group at the foot of Agents, and nothing says which roles sign as each one.

It is felt by whoever sets Carrier up and by whoever opens Settings to know who works on their epics.
We know it is solved when every role that runs on an epic is on screen, globally and per repo, the person can add, change and remove reviewers and set the lead without touching the file, and each identity says which roles sign as it.

## Solution

Agents becomes **Roles**, and **Identities** is a page of its own; the Carrier group of Settings is Roles, Identities, Watching and Behavior.
Providers stays where it is, in the App group, because the chat host reads its accounts too; a role's model is still picked from its accounts.
A role holds everything it runs with, and `engine.json` keeps its shape: each role inline, as today, plus the list of extra reviewers ([0058](../adr/app/0058-settings-splits-roles-from-identities-and-a-role-holds-everything-it-runs-with.md)).
The navigable prototype is [roles-and-identities-prototype.html](../research/macos-app-design/explorations/roles-and-identities-prototype.html); the three ways of placing the model that were compared are in [roles-and-identities-options.html](../research/macos-app-design/explorations/roles-and-identities-options.html).

### The roles

The roles are the Author, the Reviewer, each extra reviewer (`agents.extraReviewers`, up to three, each with the name the person gave it, in the order of the map) and the Lead reviewer.
Each holds its identity (a profile of `profiles`), its account and model, its effort, its persona, its failover steps and its skills.
The page reads them from `engine.json`, `providers.json` and the Agent Forge registry as the Agents page does today (`agentsPage`), with a row for each extra reviewer in the order of the map, titled by its name.

### The Roles page

The first screen is today's, with every role on it.
The status card checks what it checks today (each role has an identity, an account and a model) for every role that runs, the extra reviewers and a lead or reviewer being set up included, and names the role with what is missing and a button to open it.
How an epic runs is the rail: the Author, then "Opens the pull request · ↺ asks for changes, the author answers", then the reviewers.
With more than one reviewer they are drawn as one step in parallel, under "In parallel, on the same commit · one verdict is enough".
Add a reviewer follows them while there are fewer than four, saying how many more can run; at four it is disabled and says four is the most.
Then "When every reviewer agrees · up to N rounds with the author" (N is `limits.maxLeadRounds`) and the Lead reviewer, or a dashed stretch and "Lead reviewer is off".
Each role is a row with its picture, what it does, its model and effort over its identity, "Not saved yet" for a draft and "Off" for a lead that is off, and opens its screen.
A line under the rail says each reviewer is one more agent on every epic, and that a repo can run other roles from Watching.
Identities is no longer a group of this page.

### A role's screen

A role's screen is today's: its picture, what it does, the strip "In an epic" (Author ⇄ the reviewers → Lead reviewer) where every role is a link to its screen, then Who signs, Model (account and model, effort), Persona, When it runs out of tokens and Skills.
The Identity row opens the identity's screen.
When the identity is also another role's, a line says which, each a link; when the lead signs as the Author's identity, it warns that GitHub will not let it approve its own pull request.
Skills are read only, as today, spelled as the role's harness is told to run them.

An extra reviewer's screen is the Reviewer's with three differences.
When it runs out of tokens says "Same as Reviewer" and shows the Reviewer's steps while it has none of its own, which is the engine's rule; choosing a step gives it its own, and choosing Same as Reviewer again removes them.
Its skills say "Same as Reviewer", read only.
Its name and its type are on its screen and can be changed: the name is the screen's title, and the type is a label (`general`, `ux`, `security` or any slug).
It ends with Remove <name>, which asks first, says running epics keep it, and removes the entry and nothing else; the window goes back to Roles.

The lead keeps its switch, Use a lead reviewer, and its draft as today (`LeadReviewerSwitch`).
Its skills are the review skills by default, shown as Lead review and Post and approve, read only, and the sentence that it has no stage goes.
Its failover says "Same as Reviewer" while `failover.roles.leadReviewer` is empty, as the engine reads it.

Add a reviewer opens the new reviewer's screen as a draft kept in the page, which says it is not saved yet: it is written whole, in one request, once it has a name, a type, an identity, an account and a model, as the lead is today, so the file never holds half a reviewer; the name must differ from the other reviewers' and the type starts on `general`.
Leaving the draft before that drops it.

### The Identities page

Identities lists every profile a role can sign as: the bots of the Agent Forge registry, each with the picture it has today (`ForgeAvatarStore`), and the person's `gh` login, each with its kind and a chip for each role that signs as it ("No role" when none does).
An identity that cannot mint a token in a watched repo says so, from the doctor's `can mint a token` check that Watching already reads.
Create a bot… is here, unchanged from today.
An identity's screen shows its picture, kind and GitHub App id; Signs as, the roles that sign as it, globally and as a repo's own role, each a link to that role's screen; Can sign in, each watched repo with whether it can mint a token; and Open on GitHub for a bot.
The page writes nothing: a role picks its identity on its own screen, and picking a bot adds its profile as today.

### Watching

A repo's screen keeps the Author and the Reviewer, each overridden field by field as today, with Same as everywhere or Own.
Below them, More reviewers here is one choice, because the engine replaces the global list with a repo's whole: Same as everywhere (no key; the list of Roles runs there), Own list (starts as a copy of the list of Roles) or None (`[]`, only the Reviewer reviews there).
With Own list each entry sets its name, its type, its identity, its model and its effort and can be removed, and Add a reviewer adds one while there are fewer than three; its persona, failover steps and skills come from the Reviewer.
The lead has its row, opening its repo role screen as today, and says Off when it is off in Roles.
The list of repos says which have roles of their own, an own list or no extra reviewers.

### Behavior

The Reviews group gets Lead rounds (`limits.maxLeadRounds`, a whole number of 1 or more, 3 by default) beside Review rounds.
While the lead is off it is dimmed, with a line that links to the lead's screen.
Review rounds says a round counts once however many reviewers it has.
The engine's `editBehavior` takes `limits.maxLeadRounds` with the same rules as `maxReviews`.

### The rename

The glossary already calls them roles and keeps "agent" for the AI that runs one, so the page is renamed everywhere it is named.
That is the page's title and line, its case of `SettingsPage` (`roles`), its search index, its copy keys (`agents*` to `roles*`, in English and Spanish), Open Agents and Use in an agent wherever they appear (Open Roles, Use in a role), the folders `Settings/Agents` (in `Carrier` and `CarrierCore`) and the types and functions named after the page (`AgentsTab`, `AgentsPage`, `agentsPage`, `AgentsReadiness`, `repoAgentsPage` and their kin), and the Agents section of `docs/macos/settings-carrier.md`.
Names that mean the AI agent, or an agent of Agent Forge, stay.
A window that remembered the Agents page opens on General, as `SettingsPage(stored:)` already does for a page it does not know.

### How the app writes

Every change is written by the engine through a request ([0053](../adr/config/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md)), one at a time through `EngineConfigQueue`.
The Author, the Reviewer and the lead keep the requests they use today (`editRole`, `editPersona`, `editFailover`, `setLeadReviewer`, `editRepoRole`), and Lead rounds goes through `editBehavior`.
Adding, changing and removing an extra reviewer, and setting a repo's list, use the requests the engine has since the epic "Extra reviewers with a name, edited through the engine" (`addExtraReviewer`, `editRole`, `editPersona` and `editFailover` pointing at a reviewer by its key, `removeExtraReviewer` and `setRepoExtraReviewers`), which the app's model layer already encodes as their golden fixtures say; the engine announces them with the capability `extraReviewers`, and an engine without it leaves these fields read only.

## Scope

1. As the person, Settings' Carrier group lists Roles, Identities, Watching and Behavior, and every place that said Agents says Roles.
2. As the person with extra reviewers in `engine.json`, Roles shows each of them on the rail, in parallel with the Reviewer and in their order, with its model and identity.
3. As the person, I open any role, an extra reviewer or the lead included, and see who signs, its model and effort, its persona, its failover steps (or Same as Reviewer) and its skills.
4. As the person, I add a reviewer from Roles, give it a name, choose its type, identity and model, and it is saved whole once all of them are set; until then it says it is not saved, and nothing is written.
5. As the person, I change an extra reviewer's name, type, identity, model, effort, persona and failover steps, each saved as it changes.
6. As the person, I remove an extra reviewer, after a confirmation, and nothing else in the file changes.
7. As the person, Roles' status card names any role, extra reviewer or lead, that lacks an identity, an account or a model.
8. As the person, a lead that is on shows its skills, read only, and the page no longer says it has no stage.
9. As the person, Identities lists each bot and my login with the roles that sign as it and whether it can sign in each watched repo, and an identity's screen links to each of those roles.
10. As the person, a role's identity row opens that identity, and Create a bot… is on Identities.
11. As the person, a repo's screen in Watching shows its extra reviewers and lets me choose Same as everywhere, an own list (identity, model and effort of each) or none.
12. As the person, Behavior sets Lead rounds, dimmed while the lead is off, and the engine saves `limits.maxLeadRounds`.

## Decisions

The split and the inline shape of the roles are [0058](../adr/app/0058-settings-splits-roles-from-identities-and-a-role-holds-everything-it-runs-with.md); writing through the owner process is [0053](../adr/config/0053-a-carrier-config-file-has-one-owner-process-and-a-front-end-writes-it-through-that-process.md).

A role is named in the app as the engine names it ([0057](../adr/review/0057-an-extra-reviewer-is-an-entry-of-a-map-with-a-key-a-name-and-a-type.md)): `author`, `reviewer`, `lead`, and an extra reviewer by its key. The app shows an extra reviewer by its name.
The page's model gains the extra reviewers as rows, so the role becomes a slot rather than one of three fixed cases:

```swift
public enum RoleSlot: Hashable, Sendable {
    case author, reviewer, lead
    case extra(key: String)   // a key of agents.extraReviewers, never one of the other three names
}
```

The settings place of a role is its slot's name, and an extra reviewer's is its key (`SettingsPlace(.roles, path: ["seguridad-api"])`); a place whose reviewer no longer exists (removed, or the file changed) goes back to Roles.

A draft reviewer lives in the page, as `LeadReviewerDraft` does, and is sent in one request only once identity, account and model are set; the check of a complete draft is shared with the lead's.

Testing seams, per story:

- 1: `SettingsPageTests` (the group's pages and their order), `SettingsIndexTests` and `SettingsIndexDriftTests` (the search finds Roles and Identities, and every row's place), and `pnpm design:check` for the copy keys.
- 2, 3, 7, 8: the page's model, `agentsPage` renamed, in its tests and `AgentsReadinessTests` renamed: a config whose `extraReviewers` is a map and has a lead gives the rows in the order of the map, titled by name and addressed by key, the failover and skills that say Same as Reviewer, and the status card's problems; a config whose `extraReviewers` is a list gives no row, as the engine refuses it. The lead's skills come from the contract fixture as the Author's and Reviewer's do. Views have no test, as today.
- 4, 5, 6: a test of the draft (complete only with name, type, identity, account and model, and refused with a name another reviewer has) beside `LeadReviewerSwitchTests`; the page model's tests for the change each edit sends; and `FixtureServerTests`, because the fixture engine answers the extra-reviewer requests as the engine does. The encodings are already tested against the engine's goldens (`EngineConfigRequestsTests`, `ContractTests`).
- 9, 10: a function from the page's model and the doctor's checks to the identities (roles that sign as each, globally and per repo, and the repos where each can sign), tested in `CarrierCoreTests/Settings` with the doctor fixture.
- 11: `RepoRolesTests`: the three states of a repo's list (no key, an own list, `[]`) read from the config, and the requests for each from the engine's goldens.
- 12: `src/config/engine-edit.test.ts` (`editBehavior` takes, refuses and drops at its default `limits.maxLeadRounds`), the golden of `engine-edit-behavior`, and `BehaviorPageTests`.

## Out of scope

- The epic view: how many reviewers gave a verdict, the stage `lead`, the two heads and the lead's approval. It is the next epic.
- The engine requests that edit the extra reviewers and a repo's list, which come from separate engine work.
- Choosing another skill for any role.
- Creating or removing identities from the app beyond today's Create a bot…, and renaming them.
- `carrier init` for extra reviewers.
- A limit on the agents running at once, and an estimate of an epic's cost.

## Open questions

- The engine's requests for the extra reviewers and a repo's list (their names, fields, replies and capability) are decided by that separate engine work, which has no issue yet; stories 4, 5, 6 and the writing half of 11 wait on its golden fixtures, and the rest of the epic does not.
