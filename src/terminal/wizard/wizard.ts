import { join, resolve } from 'node:path';
import { carrierHome } from '../../config/default-path.ts';
import { defaults, loadConfig } from '../../config/load.ts';
import { defaultAccounts, providersPathOf } from '../../config/providers.ts';
import { detect } from '../../doctor/detect.ts';
import { installFix } from '../../doctor/fixes.ts';
import type { LocalProvider } from '../../harnesses/local.ts';
import { harnessNames } from '../../harnesses/names.ts';
import { Cancelled, type Ui } from '../prompts/types.ts';
import { buildConfig, parseIdentity, type AIProvider, type Role } from './build-config.ts';
import { realDeps, type InitDeps } from './deps.ts';
import type { InitFlags } from './flags.ts';
import type { ForgeAgent } from './forge-registry.ts';
import { priorFrom, type Prior } from './prior.ts';
import { askIdentity } from './questions/identity.ts';
import { askFailover, askProviders, askRoleProvider, declareFlaggedProvider } from './questions/options.ts';
import { askModel } from './questions/agent.ts';
import { askEffort } from './questions/effort.ts';
import { askPersona } from './questions/persona.ts';
import { askOut } from './questions/out.ts';
import { askRepos } from './questions/repos.ts';
import { failoverLine, foundLines, summary, tilde } from './summary.ts';

/** The setup flow: look at the machine, ask what is missing, recap, save, check, offer to start. */
export async function runInit(flags: InitFlags, ui: Ui, deps: InitDeps = realDeps, folder = carrierHome()) {
  ui.intro('Carrier setup');
  const interactive = ui.interactive && !flags.yes; // --yes never asks, whatever the terminal
  if (interactive) ui.note('Carrier works through your GitHub epics with AI agents: one writes the code, another reviews it.\nI look at this Mac first, then ask what is missing:\n  1. The repos to watch\n  2. Your AI accounts\n  3. For the author and the reviewer: GitHub identity, account and model\n  4. Where to save it\nBefore anything is written you see the whole picture and can change it.', 'What this does');

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
    ...(['git', 'gh'] as const).filter((tool) => !deps.which(tool)).map((tool) => `${tool}: ${installFix[tool]}`),
    ...(harnesses.length === 0 ? ['an agent CLI, any of these:', ...harnessNames.map((h) => `  ${h}: ${installFix[h]}`)] : []),
  ];
  if (lacking.length > 0) throw new Error(`Carrier needs these before it can run:\n${lacking.map((line) => `  ${line}`).join('\n')}`);
  ui.note(foundLines(detected).join('\n'), 'Found on this Mac');
  if (login === undefined) ui.warn('gh is not logged in (run: gh auth login): your repos cannot be listed, and a "my own gh login" identity will not work.');

  // A config that is already there: edit it (its answers become the starting points), start over, or leave it.
  const fallback = join(folder, 'config.json');
  const providersPath = providersPathOf(folder); // the accounts go here, whatever --out says (ADR 0020)
  let out = flags.out === undefined ? undefined : resolve(flags.out);
  let settled = false; // the question below settled where the config goes, and that it may be replaced
  let prior: Prior | undefined;
  if (flags.out === undefined && interactive && deps.exists(fallback)) {
    const choice = await ui.select({
      message: `A config already exists at ${tilde(fallback)}`,
      options: [
        { value: 'edit', label: 'Edit it', hint: 'its answers are the starting points' },
        { value: 'fresh', label: 'Start over', hint: 'replaces it' },
        { value: 'elsewhere', label: 'Save a new one in another file' },
        { value: 'cancel', label: 'Leave it as it is' },
      ],
      initialValue: 'edit',
    });
    if (choice === 'cancel') throw new Cancelled();
    if (choice === 'edit' || choice === 'fresh') {
      out = fallback;
      settled = true;
    }
    if (choice === 'edit') {
      try {
        prior = priorFrom(deps.readConfig(fallback), deps.exists(providersPath) ? deps.readConfig(providersPath) : {});
      } catch {
        // unreadable: handled as no prior below
      }
      if (prior === undefined) ui.warn(`${tilde(fallback)} (with ${tilde(providersPath)}) is not a valid config, so there is nothing to start from.`);
    }
  }

  const ask = async (from: Prior | undefined, keepAccounts: boolean): Promise<Prior> => {
    const repos = flags.repo ?? (await askRepos(ui, deps, from?.repos));

    // 1. AI Providers: accounts and connections (pure setup, no models)
    // What was found becomes the accounts; an edit starts from the file's own accounts instead.
    let providers: Record<string, AIProvider> = keepAccounts ? { ...from!.providers } : Object.fromEntries(harnesses.map((harness) => [harness, { harness }]));
    const flagged = (roleKey: 'author' | 'reviewer' | 'leadReviewer', roleName: 'author' | 'reviewer' | 'lead reviewer') => {
      const flag = flags[roleKey];
      if (flag === undefined) return undefined;
      const declared = declareFlaggedProvider(providers, roleName.replace(/\s+/g, '-'), flag, flags[`${roleKey}Provider` as keyof InitFlags] as string | undefined);
      providers = declared.providers;
      return { provider: declared.providerName, model: declared.model };
    };
    const [flaggedAuthor, flaggedReviewer, flaggedLeadReviewer] = [flagged('author', 'author'), flagged('reviewer', 'reviewer'), flagged('leadReviewer', 'lead reviewer')];
    const unattended = flaggedAuthor !== undefined && flaggedReviewer !== undefined;

    if (!unattended) providers = await askProviders(ui, providers, harnesses, locals, deps, keepAccounts ? 'file' : 'found');

    // 2. GitHub identities: one per role; picking the same one twice shares it, and the recap says so
    readForge();
    if (interactive && !(flags.authorProfile && flags.reviewerProfile)) {
      ui.note(
        [
          'Carrier works on GitHub for you: it pushes branches, opens pull requests, labels epics and posts review comments.',
          'Every one of those actions is done as a GitHub identity. You pick one for the author and one for the reviewer:',
          '',
          "• Agent Forge bot: a separate GitHub App account. What it does shows under the bot's name, with access only to the repos it is installed on. The best choice: author and reviewer are different accounts, so the review is a real second look.",
          '',
          `• Your own gh login${login === undefined ? '' : ` (${login})`}: acts as you, with all your access. Simpler to set up, but what Carrier does shows as you. If both roles use it, Carrier signs what each one publishes so it is clear who wrote it.`,
        ].join('\n'),
        'GitHub identities',
      );
    }
    const authorIdentity = flags.authorProfile ? parseIdentity(flags.authorProfile) : await askIdentity(ui, 'author', forge, readForge, login, undefined, deps, interactive, from?.author.identity);
    const reviewerIdentity = flags.reviewerProfile ? parseIdentity(flags.reviewerProfile) : await askIdentity(ui, 'reviewer', forge, readForge, login, authorIdentity, deps, interactive, from?.reviewer.identity);

    // 3. Agents: Author and Reviewer (provider, model, persona)
    if (!(flags.authorProfile && flags.author)) ui.note('Writes the code of each epic and answers the reviewer.\nThe persona at the end is optional: a name and how it behaves.', 'Author');
    const authorProvider = flaggedAuthor?.provider ?? (await askRoleProvider(ui, 'author', providers, from?.author.provider));
    const authorModel = flaggedAuthor?.model ?? (await askModel(ui, providers[authorProvider]!.harness, providers[authorProvider]!.provider, locals, deps, 'author', from?.author.model));
    const authorEffort = await askEffort(ui, 'author', flags.authorEffort, interactive, from?.author.effort);
    const authorPersona = await askPersona(ui, 'author', { name: flags.authorPersonaName, prompt: flags.authorPersonaPrompt }, interactive, from?.author.persona);
    const author: Role = { identity: authorIdentity, provider: authorProvider, model: authorModel, ...(authorEffort && { effort: authorEffort }), ...(authorPersona && { persona: authorPersona }) };

    if (!(flags.reviewerProfile && flags.reviewer)) ui.note('Reviews the pull request when the author is done.\nThe persona at the end is optional: a name and how it behaves.', 'Reviewer');
    const reviewerProvider = flaggedReviewer?.provider ?? (await askRoleProvider(ui, 'reviewer', providers, from?.reviewer.provider, authorProvider));
    const reviewerModel = flaggedReviewer?.model ?? (await askModel(ui, providers[reviewerProvider]!.harness, providers[reviewerProvider]!.provider, locals, deps, 'reviewer', from?.reviewer.model));
    const reviewerEffort = await askEffort(ui, 'reviewer', flags.reviewerEffort, interactive, from?.reviewer.effort);
    const reviewerPersona = await askPersona(ui, 'reviewer', { name: flags.reviewerPersonaName, prompt: flags.reviewerPersonaPrompt }, interactive, from?.reviewer.persona);
    const reviewer: Role = { identity: reviewerIdentity, provider: reviewerProvider, model: reviewerModel, ...(reviewerEffort && { effort: reviewerEffort }), ...(reviewerPersona && { persona: reviewerPersona }) };

    // 4. Optional Lead Reviewer (Tech Lead role setup)
    let leadReviewer: Role | undefined;
    const wantLead = flags.leadReviewer !== undefined
      ? true
      : interactive
        ? await (async () => {
            ui.note(
              'A second, optional reviewer for architecture and production readiness.',
              'Lead reviewer',
            );
            return ui.confirm('Add a lead reviewer?', from?.leadReviewer !== undefined);
          })()
        : from?.leadReviewer !== undefined;

    if (wantLead) {
      const leadIdentity = flags.leadReviewerProfile
        ? parseIdentity(flags.leadReviewerProfile)
        : await askIdentity(ui, 'lead reviewer', forge, readForge, login, authorIdentity, deps, interactive, from?.leadReviewer?.identity ?? reviewerIdentity);

      const leadProvider = flaggedLeadReviewer?.provider ?? (await askRoleProvider(ui, 'lead reviewer', providers, from?.leadReviewer?.provider, reviewerProvider));
      const leadModel = flaggedLeadReviewer?.model ?? (await askModel(ui, providers[leadProvider]!.harness, providers[leadProvider]!.provider, locals, deps, 'lead reviewer', from?.leadReviewer?.model));
      const leadEffort = await askEffort(ui, 'lead reviewer', flags.leadReviewerEffort, interactive, from?.leadReviewer?.effort);
      const leadPersona = await askPersona(ui, 'lead reviewer', { name: flags.leadReviewerPersonaName, prompt: flags.leadReviewerPersonaPrompt }, interactive, from?.leadReviewer?.persona);
      leadReviewer = { identity: leadIdentity, provider: leadProvider, model: leadModel, ...(leadEffort && { effort: leadEffort }), ...(leadPersona && { persona: leadPersona }) };
    }

    const failover =
      from?.failover !== undefined && (unattended || (await ui.confirm(`Keep the failover you have? ${failoverLine(from.failover)}`, true)))
        ? from.failover
        : unattended
          ? undefined
          : await askFailover(
              ui,
              providers,
              [
                { role: 'author', key: 'author', own: author },
                { role: 'reviewer', key: 'reviewer', own: reviewer },
                ...(leadReviewer ? [{ role: 'lead reviewer' as const, key: 'leadReviewer' as const, own: leadReviewer }] : []),
              ],
              locals,
              deps,
            );
    return { repos, providers, author, reviewer, ...(leadReviewer && { leadReviewer }), ...(failover && { failover }) };
  };

  const make = (answers: Prior) => {
    const user = buildConfig(answers);
    const loaded = loadConfig(defaults, user, answers.providers);
    if (!loaded.ok) throw new Error(`the answers do not make a valid config:\n${loaded.errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`);
    return { user, config: loaded.config };
  };
  let answers = await ask(prior, prior !== undefined && deps.exists(providersPath));
  let made = make(answers);

  out ??= resolve(await askOut(ui, fallback));
  if (!settled && deps.exists(out) && !flags.yes && !(await ui.confirm(`${out} exists. Overwrite it?`, false))) throw new Error(`${out} already exists`);
  // The recap is the way back: changing an answer asks everything again, starting from these answers.
  while (interactive) {
    ui.note(summary(answers.repos, answers.author, answers.reviewer, answers.providers, answers.failover, out, providersPath, answers.leadReviewer), 'This is what will be saved');
    const next = await ui.select({
      message: 'Save it?',
      options: [
        { value: 'save', label: 'Save it' },
        { value: 'change', label: 'Change an answer', hint: 'asks again, starting from these answers' },
        { value: 'cancel', label: 'Cancel', hint: 'writes nothing' },
      ],
      initialValue: 'save',
    });
    if (next === 'cancel') throw new Cancelled();
    if (next === 'save') break;
    answers = await ask(answers, true);
    made = make(answers);
  }
  deps.write(out, `${JSON.stringify(made.user, null, 2)}\n`);
  deps.write(providersPath, `${JSON.stringify({ providers: answers.providers }, null, 2)}\n`);
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
  const start = interactive && (await ui.confirm('Start Carrier now? (Ctrl+C stops it)', true));
  if (!start) ui.outro(`Ready. Start it with: carrier${use}\n${answers.repos.length > 0 ? `Then add the label solve:epic:ready to an epic in ${answers.repos.join(' or ')} and Carrier picks it up.` : 'No repos yet: add one to "repos" in the config, or in the app\'s Settings, Repos.'}`); // otherwise the caller carries on in the same frame
  return { path: out, checks, config: made.config, start };
}
