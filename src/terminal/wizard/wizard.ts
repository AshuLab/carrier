import { resolve } from 'node:path';
import { carrierHome, defaultConfigPath } from '../../config/default-path.ts';
import { defaults, loadConfig } from '../../config/load.ts';
import { installFix } from '../../doctor/fixes.ts';
import { localKinds, type LocalProvider } from '../../harnesses/local.ts';
import { harnessNames } from '../../harnesses/names.ts';
import { Cancelled, type Ui } from '../prompts/types.ts';
import { buildConfig, identityText, parseIdentity, type AIProvider, type Role } from './build-config.ts';
import { realDeps, type InitDeps } from './deps.ts';
import type { InitFlags } from './flags.ts';
import type { ForgeAgent } from './forge-registry.ts';
import { priorFrom, type Prior } from './prior.ts';
import { askIdentities } from './questions/identities.ts';
import { askIdentity } from './questions/identity.ts';
import { askFailover, askProviders, askRoleProvider, declareFlaggedProvider } from './questions/options.ts';
import { askModel } from './questions/agent.ts';
import { askPersona } from './questions/persona.ts';
import { askOut } from './questions/out.ts';
import { askRepos } from './questions/repos.ts';
import { summary, tilde } from './summary.ts';

const ghIdentity = { kind: 'gh' } as const;

/** The setup flow: look at the machine, ask what is missing, recap, save, check, offer to start. */
export async function runInit(flags: InitFlags, ui: Ui, deps: InitDeps = realDeps, folder = carrierHome()) {
  ui.intro('Carrier setup');
  const interactive = ui.interactive && !flags.yes; // --yes never asks, whatever the terminal

  const forge = { agents: [] as ForgeAgent[] };
  const readForge = () => {
    try {
      forge.agents = deps.forgeAgents();
    } catch (error) {
      ui.warn(`Could not read the Agent Forge registry: ${error instanceof Error ? error.message : String(error)}`);
    }
  };
  const harnesses = harnessNames.filter((p) => deps.which(p));
  const login = deps.ghLogin();
  // Local model servers are optional: a server that is not running is shown as such, not as a failure.
  const locals: Partial<Record<LocalProvider, string[]>> = {};
  for (const kind of localKinds) locals[kind] = await deps.localModels(kind).catch(() => undefined);

  // Nothing is shown when the machine is fine. What cannot work at all stops here, with how to fix it.
  const lacking = [
    ...(['git', 'gh'] as const).filter((tool) => !deps.which(tool)).map((tool) => `${tool}: ${installFix[tool]}`),
    ...(harnesses.length === 0 ? ['an agent CLI, any of these:', ...harnessNames.map((h) => `  ${h}: ${installFix[h]}`)] : []),
  ];
  if (lacking.length > 0) throw new Error(`Carrier needs these before it can run:\n${lacking.map((line) => `  ${line}`).join('\n')}`);
  if (login === undefined) ui.warn('gh is not logged in (run: gh auth login): your repos cannot be listed, and a "my own gh login" identity will not work.');

  // A config that is already there: edit it (its answers become the starting points), start over, or leave it.
  const fallback = defaultConfigPath();
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
        prior = priorFrom(deps.readConfig(fallback));
      } catch {
        // unreadable: handled as no prior below
      }
      if (prior === undefined) ui.warn(`${tilde(fallback)} is not a valid config, so there is nothing to start from.`);
    }
  }

  const repos = flags.repo ?? (await askRepos(ui, deps, prior?.repos));

  // 1. AI Providers: accounts and connections (pure setup, no models)
  let providers: Record<string, AIProvider> = { ...prior?.providers };
  const flagged = (roleKey: 'author' | 'reviewer' | 'leadReviewer', roleName: 'author' | 'reviewer' | 'lead reviewer') => {
    const flag = flags[roleKey];
    if (flag === undefined) return undefined;
    const declared = declareFlaggedProvider(providers, roleName.replace(/\s+/g, '-'), flag, flags[`${roleKey}Provider` as keyof InitFlags] as string | undefined);
    providers = declared.providers;
    return { provider: declared.providerName, model: declared.model };
  };
  const [flaggedAuthor, flaggedReviewer, flaggedLeadReviewer] = [flagged('author', 'author'), flagged('reviewer', 'reviewer'), flagged('leadReviewer', 'lead reviewer')];
  const unattended = flaggedAuthor !== undefined && flaggedReviewer !== undefined;

  if (!unattended) providers = await askProviders(ui, providers, harnesses, locals, deps);

  // 2. GitHub identities: shared vs separate, resolved together
  const identities = await askIdentities(ui, flags, login, interactive, prior?.identities);
  const shared = identities === 'shared';
  if (!shared) readForge();

  const authorIdentity = shared ? ghIdentity : flags.authorProfile ? parseIdentity(flags.authorProfile) : await askIdentity(ui, 'author', forge, readForge, login, [], deps, interactive, prior?.author.identity);
  const reviewerIdentity = shared ? ghIdentity : flags.reviewerProfile ? parseIdentity(flags.reviewerProfile) : await askIdentity(ui, 'reviewer', forge, readForge, login, [authorIdentity], deps, interactive, prior?.reviewer.identity);
  if (!shared && identityText(authorIdentity) === identityText(reviewerIdentity)) throw new Error('Author and reviewer identities must differ');

  // 3. Agents: Author and Reviewer (provider, model, persona)
  if (!(flags.authorProfile && flags.author)) ui.note('Implements the epic: runs ship, then answers the reviewer.\nOptionally it gets a persona at the end: a name and how it behaves.', 'Author');
  const authorProvider = flaggedAuthor?.provider ?? (await askRoleProvider(ui, 'author', providers, prior?.author.provider));
  const authorModel = flaggedAuthor?.model ?? (await askModel(ui, providers[authorProvider]!.harness, providers[authorProvider]!.provider, locals, deps, 'author', prior?.author.model));
  const authorPersona = await askPersona(ui, 'author', { name: flags.authorPersonaName, prompt: flags.authorPersonaPrompt }, interactive, prior?.author.persona);
  const author: Role = { identity: authorIdentity, provider: authorProvider, model: authorModel, ...(authorPersona && { persona: authorPersona }) };

  if (!(flags.reviewerProfile && flags.reviewer)) ui.note('Reviews the final PR.\nOptionally it gets a persona at the end: a name and how it behaves.', 'Reviewer');
  const reviewerProvider = flaggedReviewer?.provider ?? (await askRoleProvider(ui, 'reviewer', providers, prior?.reviewer.provider, authorProvider));
  const reviewerModel = flaggedReviewer?.model ?? (await askModel(ui, providers[reviewerProvider]!.harness, providers[reviewerProvider]!.provider, locals, deps, 'reviewer', prior?.reviewer.model));
  const reviewerPersona = await askPersona(ui, 'reviewer', { name: flags.reviewerPersonaName, prompt: flags.reviewerPersonaPrompt }, interactive, prior?.reviewer.persona);
  const reviewer: Role = { identity: reviewerIdentity, provider: reviewerProvider, model: reviewerModel, ...(reviewerPersona && { persona: reviewerPersona }) };

  // 4. Optional Lead Reviewer (Tech Lead role setup)
  let leadReviewer: Role | undefined;
  const wantLead = flags.leadReviewer !== undefined
    ? true
    : interactive
      ? await (async () => {
          ui.note(
            'An optional technical lead role (configuration setup).\nIt configures an evaluation role for architecture and production readiness.',
            'Lead Reviewer',
          );
          return ui.confirm('Add a Lead Reviewer to the workflow?');
        })()
      : prior?.leadReviewer !== undefined;

  if (wantLead) {
    const leadIdentity = shared
      ? ghIdentity
      : flags.leadReviewerProfile
        ? parseIdentity(flags.leadReviewerProfile)
        : await askIdentity(ui, 'lead reviewer', forge, readForge, login, [authorIdentity], deps, interactive, prior?.leadReviewer?.identity ?? reviewerIdentity);
    if (!shared && identityText(authorIdentity) === identityText(leadIdentity)) {
      throw new Error('Author and lead reviewer identities must differ');
    }

    const leadProvider = flaggedLeadReviewer?.provider ?? (await askRoleProvider(ui, 'lead reviewer', providers, prior?.leadReviewer?.provider, reviewerProvider));
    const leadModel = flaggedLeadReviewer?.model ?? (await askModel(ui, providers[leadProvider]!.harness, providers[leadProvider]!.provider, locals, deps, 'lead reviewer', prior?.leadReviewer?.model));
    const leadPersona = await askPersona(ui, 'lead reviewer', { name: flags.leadReviewerPersonaName, prompt: flags.leadReviewerPersonaPrompt }, interactive, prior?.leadReviewer?.persona);
    leadReviewer = { identity: leadIdentity, provider: leadProvider, model: leadModel, ...(leadPersona && { persona: leadPersona }) };
  }

  const failover = prior?.failover ?? (unattended || Object.keys(providers).length < 2 ? undefined : await askFailover(ui, providers));
  const user = buildConfig({ repos, author, reviewer, leadReviewer, providers, failover, identities });
  const loaded = loadConfig(defaults, user);
  if (!loaded.ok) throw new Error(`the answers do not make a valid config:\n${loaded.errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`);

  out ??= resolve(await askOut(ui, fallback));
  if (!settled && deps.exists(out) && !flags.yes && !(await ui.confirm(`${out} exists. Overwrite it?`))) throw new Error(`${out} already exists`);
  if (interactive) {
    ui.note(summary(repos, author, reviewer, providers, failover, out, identities, leadReviewer), 'This is what will be saved');
    if (!(await ui.confirm('Save it?'))) throw new Cancelled();
  }
  deps.write(out, `${JSON.stringify(user, null, 2)}\n`);
  ui.note(tilde(out), 'Config written');

  const checks = await deps.doctor(loaded.config, folder, {}, ui.check, ui.checkStart);
  const use = out === fallback ? '' : ` --config ${out}`; // the default location needs no flag
  const failed = checks.filter((c) => c.status === 'fail').length;
  ui.checksEnd(checks.length, failed);
  if (failed > 0) {
    ui.outro(`${failed} check${failed === 1 ? '' : 's'} failed. Fix them and run: carrier doctor${use}`);
    return { path: out, checks, config: loaded.config, start: false };
  }

  const ready = await deps.readyEpics(loaded.config, folder);
  const waiting = Object.entries(ready).map(([repo, count]) => `${repo}: ${count === undefined ? 'could not read' : `${count} epic${count === 1 ? '' : 's'} marked ready`}`);
  ui.note(waiting.join('\n'), 'Waiting for Carrier');
  const start = interactive && (await ui.confirm('Start Carrier now? (Ctrl+C stops it)'));
  if (!start) ui.outro(`Ready. Start it with: carrier${use}\nThen mark an epic of ${repos[0]} as solve:epic:ready.`); // otherwise the caller carries on in the same frame
  return { path: out, checks, config: loaded.config, start };
}
