import { dirname, join, resolve } from 'node:path';
import { carrierHome, engineConfigPathOf, providersPathOf } from '../../config/places.ts';
import { defaults, loadConfig } from '../../config/load.ts';
import { defaultAccounts, loadProviders, providersProblem } from '../../config/providers.ts';
import { detect } from '../../doctor/detect.ts';
import { installFix } from '../../doctor/fixes.ts';
import type { LocalProvider } from '../../harnesses/local.ts';
import { harnessNames } from '../../harnesses/names.ts';
import { journaled } from '../prompts/journal.ts';
import { Back, Cancelled, type Ui } from '../prompts/types.ts';
import { buildConfig, parseIdentity, type AIProvider, type Extra, type Role } from './build-config.ts';
import { realDeps, type InitDeps } from './deps.ts';
import type { InitFlags } from './flags.ts';
import type { ForgeAgent } from './forge-registry.ts';
import { keepRest } from './keep-rest.ts';
import { priorFrom, type Prior } from './prior.ts';
import { askIdentity } from './questions/identity.ts';
import { askProviders, declareFlaggedProvider, mergeAccounts } from './questions/options.ts';
import { askRole } from './questions/role.ts';
import { askOut } from './questions/out.ts';
import { askRepos } from './questions/repos.ts';
import { extraSlots, roleKey, roleName, roleSlots, type RoleSlot } from './roles.ts';
import { failoverProblem, flagProblem, named } from './validate-flags.ts';
import { foundLines, summary, tilde } from './summary.ts';

/** The accounts `providers.json` already holds, as it keeps them (a folder under the home folder with its `~`); none when the file is not there or has no `providers` key. An unreadable or invalid file stops here: writing over it would lose its accounts. */
function heldBy(deps: InitDeps, providersPath: string): Record<string, AIProvider> {
  if (!deps.exists(providersPath)) return {};
  let raw: unknown;
  try {
    raw = deps.readConfig(providersPath);
  } catch (error) {
    throw new Error(`${tilde(providersPath)} cannot be read, and init will not write over the accounts in it: ${error instanceof Error ? error.message : String(error)}`);
  }
  const loaded = loadProviders(raw);
  if (!loaded.ok) throw new Error(`${providersProblem(dirname(providersPath), loaded.errors)}\ninit will not write over the accounts in it: fix the file first.`);
  if (typeof raw !== 'object' || raw === null || !('providers' in raw)) return {};
  return Object.fromEntries(Object.entries(loaded.providers).map(([name, account]) => [name, { ...account, ...(account.configDir && { configDir: tilde(account.configDir) }), ...(account.command && { command: tilde(account.command) }) }]));
}

/** The accounts the `--<role>` flags declare on top of `accounts` (one is reused when it matches), and the account and model each flagged role starts on. */
function declareFlagged(flags: InitFlags, accounts: Record<string, AIProvider>) {
  let providers = accounts;
  const roles: Partial<Record<RoleSlot, { provider: string; model: string }>> = {};
  for (const slot of roleSlots) {
    const key = roleKey(slot) as 'author';
    const flag = flags[key];
    if (flag === undefined) continue;
    const declared = declareFlaggedProvider(providers, slot, flag, flags[`${key}Provider`]);
    providers = declared.providers;
    roles[slot] = { provider: declared.providerName, model: declared.model };
  }
  return { providers, roles };
}

/** The setup flow: look at the machine, ask what is missing, recap, save, check, offer to start. */
export async function runInit(flags: InitFlags, ui: Ui, deps: InitDeps = realDeps, folder = carrierHome()) {
  // Flags that cannot work are refused before anything is shown or probed.
  const wrong = flagProblem(flags);
  if (wrong !== undefined) throw new Error(wrong);
  ui.intro('Carrier setup');
  const interactive = ui.interactive && !flags.yes; // --yes never asks, whatever the terminal
  if (interactive) ui.note('Carrier works through your GitHub epics with AI agents: one writes the code, another reviews it.\nI look at this Mac first, then ask what is missing:\n  1. Your AI accounts\n  2. Who Carrier reads GitHub as (the orchestrator\'s GitHub profile)\n  3. The author, the reviewer, any extra reviewers and an optional lead reviewer, one block each: GitHub profile, account, model and effort, persona and failover\n  4. The repos to watch\n  5. Where to save it\nBefore anything is written you see the whole picture and can change it.', 'What this does');

  const forge = { agents: [] as ForgeAgent[] };
  const readForge = () => {
    try {
      forge.agents = deps.forgeAgents();
    } catch (error) {
      ui.warn(`Could not read the Agent Forge registry: ${error instanceof Error ? error.message : String(error)}`);
    }
  };
  // One detector tells what the Mac has; a local server that is not running is shown as such, not as a failure.
  const [detected, login] = await ui.busy('Looking at this Mac…', () => Promise.all([detect(deps.machine, defaultAccounts), Promise.resolve(deps.ghLogin())]));
  const harnesses = harnessNames.filter((harness) => detected.harnesses[harness].found);
  const locals: Partial<Record<LocalProvider, string[]>> = {};
  for (const [kind, server] of Object.entries(detected.servers)) if (server.running) locals[kind as LocalProvider] = server.models;

  // Nothing is shown when the machine is fine. What cannot work at all stops here, with how to fix it.
  const lacking = [
    ...(['git', 'gh'] as const).filter((tool) => !deps.which(tool)).map((tool) => `${tool}: ${installFix[tool]!.text}`),
    ...(harnesses.length === 0 ? ['an agent CLI, any of these:', ...harnessNames.map((h) => `  ${h}: ${installFix[h]!.text}`)] : []),
  ];
  if (lacking.length > 0) throw new Error(`Carrier needs these before it can run:\n${lacking.map((line) => `  ${line}`).join('\n')}`);
  ui.note(foundLines(detected).join('\n'), 'Found on this Mac');
  if (login === undefined) ui.warn('gh is not logged in (run: gh auth login): your repos cannot be listed, and a "my own gh login" profile will not work.');

  const providersPath = providersPathOf(folder); // the accounts go here, whatever --out says (ADR 0020)
  // The accounts already in providers.json are the base of every path; what was found is added, never replacing.
  const heldAccounts = heldBy(deps, providersPath);
  // A failover step names an account of this Mac or of the file, or one a --<role> flag declares: checked as soon as they are known, before the first question.
  const known = declareFlagged(flags, mergeAccounts(heldAccounts, harnesses));
  const missing = failoverProblem(flags, Object.keys(known.providers), known.roles);
  if (missing !== undefined) throw new Error(missing);

  const fallback = engineConfigPathOf(folder);
  const journal = journaled(ui);
  // The agent-forge step that adds a bot is journalled too: going back across it does not run it again.
  const forgeDeps: InitDeps = { ...deps, forgeAdd: () => journal.once('agent-forge add', deps.forgeAdd) };

  /** Everything up to the recap, asked through the journal: after an Esc or a jump it runs again from the top with each answer taken from it, and only what was dropped is asked. */
  const settle = async () => {
    const ui = journal.ui; // from here to the recap, every question and every wait goes through the journal
    const deps = forgeDeps;
    journal.at('config');
    // A config that is already there: edit it (its answers become the starting points), start over, or leave it.
    let out = flags.out === undefined ? undefined : resolve(flags.out);
    let settled = false; // the question below settled where the config goes, and that it may be replaced
    let prior: Prior | undefined;
    let base: Record<string, unknown> | undefined; // the file being edited, as it is: an edit keeps what the wizard does not ask
    // What a file there says: its answers, or its first error. A file that cannot be read is an error too.
    const readPrior = (path: string) => {
      try {
        const raw = deps.readConfig(path);
        const found = priorFrom(raw, deps.exists(providersPath) ? deps.readConfig(providersPath) : {});
        return 'error' in found ? found : { prior: found, raw: raw as Record<string, unknown> };
      } catch (error) {
        return { error: `cannot read it: ${error instanceof Error ? error.message : String(error)}` };
      }
    };
    if (flags.out === undefined && interactive && deps.exists(fallback)) {
      let choice = await ui.select({
        message: `A config already exists at ${tilde(fallback)}`,
        options: [
          { value: 'edit', label: 'Edit it', hint: 'its answers are the starting points' },
          { value: 'fresh', label: 'Start over', hint: 'resets the answers of engine.json, keeps your accounts' },
          { value: 'elsewhere', label: 'Save a new one in another file' },
          { value: 'cancel', label: 'Leave it as it is' },
        ],
        initialValue: 'edit',
      });
      if (choice === 'edit') {
        const found = readPrior(fallback);
        if ('error' in found) {
          // Nothing is touched until the person answers.
          ui.warn(`${tilde(fallback)} does not validate, first error: ${found.error}`);
          choice = await ui.select({
            message: 'What do you want to do with it?',
            options: [
              { value: 'fresh', label: 'Start over', hint: 'resets the answers of engine.json, keeps your accounts' },
              { value: 'elsewhere', label: 'Save a new one in another file' },
              { value: 'cancel', label: 'Leave it as it is' },
            ],
            initialValue: 'cancel',
          });
        } else ({ prior, raw: base } = found);
      }
      if (choice === 'cancel') throw new Cancelled();
      if (choice === 'edit' || choice === 'fresh') {
        out = fallback;
        settled = true;
      }
    } else if (flags.yes && deps.exists(out ?? fallback)) {
      // --yes replaces the file as the flag says, and still says why a file that does not validate goes.
      const found = readPrior(out ?? fallback);
      if ('error' in found) ui.warn(`${tilde(out ?? fallback)} does not validate and is replaced, first error: ${found.error}`);
    }

    const ask = async (from: Prior | undefined, accounts: Record<string, AIProvider>, heldNames: string[]): Promise<Prior> => {
      // 1. Accounts: found on this Mac and the ones already held, then the person's own
      const declared = declareFlagged(flags, accounts);
      let providers = declared.providers;
      const unattended = declared.roles.author !== undefined && declared.roles.reviewer !== undefined;
      journal.at('accounts');
      if (!unattended) providers = await askProviders(ui, providers, harnesses, locals, deps, heldNames);

      // 2. The orchestrator's GitHub profile; the roles' come in their blocks. Picking the same one twice shares it, and the recap says so.
      readForge();
      const asking = interactive && !(flags.authorProfile && flags.reviewerProfile);
      if (asking) {
        ui.note(
          [
            'Carrier works on GitHub for you: it pushes branches, opens pull requests, labels epics and posts review comments.',
            'Every one of those actions is done as a GitHub profile. You pick one for the orchestrator, which only reads issues and PRs and changes labels, then one for each role:',
            '',
            "• Agent Forge bot: a separate GitHub App account. What it does shows under the bot's name, with access only to the repos it is installed on. The best choice: author and reviewer are different accounts, so the review is a real second look.",
            '',
            `• Your own gh login${login === undefined ? '' : ` (${login})`}: acts as you, with all your access. Simpler to set up, but what Carrier does shows as you. If both roles use it, Carrier signs what each one publishes so it is clear who wrote it.`,
          ].join('\n'),
          'GitHub profiles',
        );
      }
      journal.at('orchestrator');
      // Not asked (--orchestrator-profile, --yes or the profile flags): the flag's, else the file's own when editing, else the author's profile.
      const orchestrator = flags.orchestratorProfile !== undefined ? parseIdentity(flags.orchestratorProfile) : asking ? await askIdentity(ui, 'orchestrator', forge, readForge, login, undefined, deps, interactive, from?.orchestrator) : from?.orchestrator;

      // 3. One closed block per role
      const context = { ui, deps, flags, interactive, unattended, providers, locals, forge, readForge, login };
      const block = (slot: RoleSlot, after?: Role, held?: Extra) => {
        const key = roleKey(slot) as 'author' | 'reviewer' | 'leadReviewer'; // an extra reviewer's start is `held`, the file's entry at its place in the list
        const fromRole = held?.role ?? from?.[key];
        const steps = held === undefined ? from?.failover?.roles?.[key] : held.failover;
        journal.at(slot);
        return askRole(context, slot, { ...(after && { after }), ...(fromRole && { from: fromRole }), ...(steps && { steps }), ...(declared.roles[slot] && { flagged: declared.roles[slot] }) });
      };
      const author = await block('author');
      const reviewer = await block('reviewer', author.role);
      // The extra reviewers, up to three: the ones a flag names are not asked, then "add another?" until the person says no (the file's answer to start on when editing).
      const extraReviewers: Extra[] = [];
      for (const slot of extraSlots) {
        const held = from?.extraReviewers?.[extraReviewers.length];
        journal.at(slot);
        const add = named(flags, slot) || (interactive ? await ui.confirm(held ? `Add ${slot}?` : 'Add another reviewer?', held !== undefined) : held !== undefined);
        if (!add) break;
        const extra = await block(slot, extraReviewers.at(-1)?.role ?? reviewer.role, held);
        extraReviewers.push({ role: extra.role, ...(extra.failover && { failover: extra.failover }) });
      }
      journal.at('lead-reviewer');
      const wantLead = flags.leadReviewer !== undefined || (interactive ? await ui.confirm('Add a lead reviewer?', from?.leadReviewer !== undefined) : from?.leadReviewer !== undefined);
      const lead = wantLead ? await block('lead-reviewer', extraReviewers.at(-1)?.role ?? reviewer.role) : undefined;

      const chosen = { author: author.failover, reviewer: reviewer.failover, leadReviewer: lead?.failover };
      const roles = Object.fromEntries(Object.entries(chosen).filter(([, steps]) => steps !== undefined));
      const failover = Object.keys(roles).length > 0 ? { ...(from?.failover ?? { triggers: ['usage_limit', 'rate_limit', 'service_down'] }), roles } : undefined;

      // 4. The repos, last: nothing about a role needs them
      journal.at('repos');
      const repos = flags.repo ?? (await askRepos(ui, deps, from?.repos));
      return { repos, providers, ...(orchestrator && { orchestrator }), author: author.role, reviewer: reviewer.role, ...(extraReviewers.length > 0 && { extraReviewers }), ...(lead && { leadReviewer: lead.role }), ...(failover && { failover }) };
    };

    const make = (answers: Prior) => {
      const built = buildConfig(answers);
      const user = base === undefined ? built : keepRest(base, built);
      const loaded = loadConfig(defaults, user, answers.providers);
      if (!loaded.ok) throw new Error(`the answers do not make a valid config:\n${loaded.errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`);
      return { user, config: loaded.config };
    };
    const answers = await ask(prior, mergeAccounts(heldAccounts, harnesses), Object.keys(heldAccounts));
    const made = make(answers);

    journal.at('out');
    out ??= resolve(await askOut(ui, fallback));
    if (!settled && deps.exists(out) && !flags.yes) {
      if (!ui.interactive) throw new Error(`${out} already exists: pass --yes to replace it, or --out to write another file`);
      if (!(await ui.confirm(`${out} exists. Overwrite it?`, false))) throw new Error(`${out} already exists`);
    }
    return { answers, made, out };
  };

  // The recap is the way back: Esc goes back one question, and "Change an answer" jumps to one block and asks only its questions, from the answers it has.
  let answers: Prior, made: Awaited<ReturnType<typeof settle>>['made'], out: string;
  for (;;) {
    try {
      ({ answers, made, out } = await settle());
    } catch (error) {
      if (!(error instanceof Back)) throw error;
      if (journal.back()) continue;
      throw new Cancelled(); // the first question: Esc leaves as Ctrl+C does
    }
    const file = out;
    const recap = () => ui.note(summary(answers.repos, answers.author, answers.reviewer, answers.providers, answers.failover, file, providersPath, answers.leadReviewer, answers.orchestrator, answers.extraReviewers), 'This is what will be saved');
    recap(); // --yes asked nothing, so the recap is the only place the choices show
    if (!interactive) break;
    try {
      const next = await ui.select({
        message: 'Save it?',
        options: [
          { value: 'save', label: 'Save it' },
          { value: 'change', label: 'Change an answer', hint: 'pick the part to ask again' },
          { value: 'cancel', label: 'Cancel', hint: 'writes nothing' },
        ],
        initialValue: 'save',
      });
      if (next === 'cancel') throw new Cancelled();
      if (next === 'save') break;
      const extras = answers.extraReviewers?.length ?? 0;
      const block = await ui.select({
        message: 'Which part do you want to change?',
        options: [
          { value: 'accounts', label: 'AI accounts' },
          { value: 'orchestrator', label: 'Orchestrator GitHub profile' },
          // The roles there are, and the next extra reviewer to add while there is room.
          ...roleSlots
            .filter((slot) => extraSlots.indexOf(slot) <= extras)
            .map((slot) => ({ value: slot as string, label: `${roleName(slot)[0]!.toUpperCase()}${roleName(slot).slice(1)}`, ...((slot === 'lead-reviewer' ? answers.leadReviewer === undefined : extraSlots.indexOf(slot) === extras) && { hint: 'none yet' }) })),
          { value: 'repos', label: 'Repos to watch' },
        ],
      });
      journal.jump(block);
    } catch (error) {
      if (!(error instanceof Back)) throw error;
      if (!journal.back()) throw new Cancelled();
    }
  }
  deps.writeConfig({ engine: made.user, file: out, providers: answers.providers, folder });
  ui.note(`${tilde(out)}\n${tilde(providersPath)}`, 'Saved');

  const checks = await deps.doctor(made.config, folder, {}, ui.check, ui.checkStart);
  const use = out === fallback ? '' : ` --config ${out}`; // the default location needs no flag
  const failed = checks.filter((c) => c.status === 'fail').length;
  ui.checksEnd(checks.length, failed);
  if (failed > 0) {
    ui.outro(`Your config is saved, but ${failed} check${failed === 1 ? '' : 's'} failed. Fix ${failed === 1 ? 'it' : 'them'}, then run: carrier doctor${use}`);
    return { path: out, checks, config: made.config, start: false };
  }

  const ready = await ui.busy('Asking GitHub which epics are ready…', () => deps.readyEpics(made.config, folder));
  const waiting = Object.entries(ready).map(([repo, count]) => `${repo}: ${count === undefined ? 'could not read' : `${count} epic${count === 1 ? '' : 's'} marked ready`}`);
  if (waiting.length > 0) ui.note(waiting.join('\n'), 'Waiting for Carrier');
  let start = false;
  if (interactive) {
    try {
      start = await ui.confirm('Start Carrier now?', true);
    } catch (error) {
      if (!(error instanceof Cancelled || error instanceof Back)) throw error; // the config is saved and checked: Ctrl+C, and Esc with nothing to go back to, are a no
    }
  }
  if (!start) ui.outro(`Ready. Start it with: carrier${use}\n${answers.repos.length > 0 ? `Then add the label solve:epic:ready to an epic in ${answers.repos.join(' or ')} and Carrier picks it up.` : 'No repos yet: add one to "repos" in the config, or in the app\'s Settings, Repos.'}`); // otherwise the caller carries on in the same frame
  return { path: out, checks, config: made.config, start };
}
