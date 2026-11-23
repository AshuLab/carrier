# Where each harness finds a skill, and what it does with a missing one

Date: 2026-11-23. Versions read: Claude Code 2.1.330, Codex 0.171.0, Antigravity (`agy`) 1.5.15.
Method: official documentation, the installed binaries' strings and `--help`, commands that do not call a model, and the layout on the machine this was written on. No agent was run against a model, so what only a real run can show is listed at the end.
V is verified (documentation, binary strings or a command that calls no model); U is not verified.

## What Carrier sends

The prompts of the three stages do not start with the skill: `ship.ts`, `review.ts` and `fix.ts` put it in a sentence ("Invoke /code-review ..."), so the harness's own expansion of a leading `/name` never runs.
The model decides to call the skill. Transcripts of real runs show the model calling its Skill tool with `solve:code-review` after a prompt that said `/code-review`.

## Claude Code

- Where. User: `<configDir>/skills/<name>/SKILL.md` and `<configDir>/commands/<name>.md`. Project: `<repo>/.claude/skills/` and every parent folder up to the repo root. Plugin: `<configDir>/plugins/cache/<marketplace>/<plugin>/<version>/skills/<name>/SKILL.md`. Also managed settings, synced skills and `--add-dir`. V
- The account's folder. With `CLAUDE_CONFIG_DIR=<dir>` every `~/.claude` path lives under that directory; project skills do not move. `CLAUDE_CONFIG_DIR=<dir> claude plugin list --json` returned a different plugin set per account and calls no model. V
- Invocation. A plugin skill is `/<plugin>:<skill>`; a prompt that starts with `/name` is expanded in `-p`. In Carrier's prose form the model's own Skill tool resolves the name. V
- A skill that does not exist. In the prose form the Skill tool answers the model `Unknown skill: X. Did you mean Y?` and the harness does not fail; the model decides what to do. A prompt that starts with `/x` falls back to the model with a note that the command did not run, or, behind a remote switch, prints `Unknown command: /x` with no model call. Exit codes U.
- A check without running the agent. List the user and project folders, then `claude plugin list --json` with `CLAUDE_CONFIG_DIR` set and look in each `installPath/skills/`. A bare name matches `name` or `<plugin>:name`.
- Where it cannot tell. Plugins enabled by the repo's settings, managed or enterprise settings and an organization's skills policy, `skillOverrides`, built-ins with no folder, synced skills, and two plugins with the same skill name.

## Codex

- Where. `codex debug prompt-input` (no model call) prints the skill roots the model is given: `<CODEX_HOME>/skills` and `<CODEX_HOME>/skills/.system` (they move with `CODEX_HOME`), `~/.agents/skills` (shared by every account, it does not move), plugin caches under `<CODEX_HOME>/plugins/cache/*`, and `<cwd>/.agents/skills`. The documentation also lists `/etc/codex/skills`. A skill is a `SKILL.md` with `name` and `description`. V
- Invocation. `$name` or the name in plain text; plugin skills are namespaced in the catalog. `codex exec '$name args'` worked in the earlier spike of `headless-agents.md`. V
- A skill that does not exist. The documentation says nothing; the base prompt says to stop and tell the user when a necessary skill is not found, or to continue with the best fallback, so the model chooses and exit 0 is expected. U
- A check without running the agent. List the folders above. `debug prompt-input` also shows the catalog, but it is a debug command and may change, so it is not the way. On the machine of this research the catalog has no `ship` and no `code-review`.
- Where it cannot tell. Plugin skills, remote or orchestrator skills with no folder, and a catalog the harness cuts by a budget.

## Antigravity (`agy`)

- Where. Workspace: `<ws>/.agents/skills/<name>/SKILL.md` (legacy `.agent/skills`) and `.agents/skills.json` entries, which may only point inside the workspace. Global: `~/.gemini/config/skills/`, `~/.gemini/antigravity-cli/skills/`, `~/.gemini/skills/` and the manifest `~/.gemini/config/skills.json`. Plugins: `~/.gemini/config/plugins/<plugin>/skills/`. Built-ins: `~/.gemini/antigravity/builtin/skills`. No variable moves the config home, which matches `agy` having no `configDir` in `providers.ts`. V (documentation and layout)
- Invocation. A skill is `/<name>`; the changelog of 1.1.9 says a headless `-p "/my-skill ..."` resolves the skill. Plugin namespacing and the prose form U.
- A skill that does not exist. The binary has the text "pass --disable-slash-commands to send /%s to the model as literal text", which suggests an error in print mode for a leading `/name`. Exit code and wording U.
- A check without running the agent. List the folders and read both `skills.json`, and `agy plugin list --json`, which calls no model.
- Where it cannot tell. `include_only` and `exclude` in the manifests, plugin skills, built-ins, and name collisions, where the first found wins and the other is dropped silently.

## What it means for Carrier

No harness reports an unknown skill as an error of the run for the prose prompts Carrier sends, as far as the sources show, so a stop on "the run reported an unknown skill" has no signal to rely on; only a check before the start is solid.
Each harness has a place the check can read, and each has places it cannot, so the answer of the check has three values: present, absent and cannot tell.
The cheapest reliable reads are: folders plus `claude plugin list --json` for Claude, folders for Codex, and folders, manifests and `agy plugin list --json` for `agy`.

## Needs a real run to know

1. Claude: the exit code and result text of `-p` when the prose prompt names a missing skill, and what the model does after the Skill tool's error.
2. Claude: whether a bare `/ship` resolves to `solve:ship`.
3. Codex: the exit code and behavior of `exec` with a missing `$name`, and whether a skill omitted by the catalog's budget can still be invoked.
4. `agy`: an unknown `/name` in `-p` (error or literal text, exit code), and whether a prose "Invoke /ship" is expanded.
5. `agy`: whether `-p "/skills"` lists skills with no model turn.
