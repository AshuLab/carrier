import { resolve } from 'node:path';
import { defaultConfigPath } from '../../config/default-path.ts';
import { defaults, loadConfig } from '../../config/load.ts';
import { installFix } from '../../doctor/fixes.ts';
import { localKinds, type LocalProvider } from '../../harnesses/local.ts';
import { harnessNames } from '../../harnesses/names.ts';
import { Cancelled, type Ui } from '../prompts/types.ts';
import { buildConfig, parseIdentity } from './build-config.ts';
import { realDeps, type InitDeps } from './deps.ts';
import type { InitFlags } from './flags.ts';
import type { ForgeAgent } from './forge-registry.ts';
import { priorFrom, type Prior } from './prior.ts';
import { askAgent } from './questions/agent.ts';
import { askIdentities } from './questions/identities.ts';
import { askIdentity } from './questions/identity.ts';
import { askOut } from './questions/out.ts';
import { askRepos } from './questions/repos.ts';
import { summary, tilde } from './summary.ts';

const ghIdentity = { kind: 'gh' } as const;

/** The setup flow: look at the machine, ask what is missing, recap, save, check, offer to start. */
export async function runInit(flags: InitFlags, ui: Ui, deps: InitDeps = realDeps) {
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

  const identities = await askIdentities(ui, flags, login, interactive, prior?.identities);
  const shared = identities === 'shared'; // both roles are the gh login: no identity to ask, and Agent Forge is never read
  if (!shared) readForge();

  // One role at a time (who it acts as, which CLI, which model), each under its own box, so the two read as separate things.
  if (!(flags.authorProfile && flags.author)) ui.note('Implements the epic: runs ship, then answers the reviewer.', 'Author');
  const authorIdentity = shared ? ghIdentity : flags.authorProfile ? parseIdentity(flags.authorProfile) : await askIdentity(ui, 'author', forge, readForge, login, [], deps, interactive, prior?.author.identity);
  const author = { identity: authorIdentity, ...(await askAgent(ui, 'author', { flag: flags.author, provider: flags.authorProvider }, harnesses, locals, deps, 'claude', prior?.author)) };

  if (!(flags.reviewerProfile && flags.reviewer)) ui.note(`Reviews the final PR. ${shared ? 'Acts as the same gh login.' : 'Needs a different GitHub identity from the author.'}`, 'Reviewer');
  const reviewerIdentity = shared ? ghIdentity : flags.reviewerProfile ? parseIdentity(flags.reviewerProfile) : await askIdentity(ui, 'reviewer', forge, readForge, login, [authorIdentity], deps, interactive, prior?.reviewer.identity);
  const reviewer = { identity: reviewerIdentity, ...(await askAgent(ui, 'reviewer', { flag: flags.reviewer, provider: flags.reviewerProvider }, harnesses, locals, deps, harnesses.includes('codex') ? 'codex' : 'claude', prior?.reviewer)) };

  const user = buildConfig({ repos, author, reviewer, identities });
  const loaded = loadConfig(defaults, user);
  if (!loaded.ok) throw new Error(`the answers do not make a valid config:\n${loaded.errors.map((e) => `  ${e.path}: ${e.message}`).join('\n')}`);

  out ??= resolve(await askOut(ui, fallback));
  if (!settled && deps.exists(out) && !flags.yes && !(await ui.confirm(`${out} exists. Overwrite it?`))) throw new Error(`${out} already exists`);
  if (interactive) {
    ui.note(summary(repos, author, reviewer, out, identities), 'This is what will be saved');
    if (!(await ui.confirm('Save it?'))) throw new Cancelled();
  }
  deps.write(out, `${JSON.stringify(user, null, 2)}\n`);
  ui.note(tilde(out), 'Config written');

  const checks = await deps.doctor(loaded.config, {}, ui.check, ui.checkStart);
  const use = out === fallback ? '' : ` --config ${out}`; // the default location needs no flag
  const failed = checks.filter((c) => c.status === 'fail').length;
  ui.checksEnd(checks.length, failed);
  if (failed > 0) {
    ui.outro(`${failed} check${failed === 1 ? '' : 's'} failed. Fix them and run: carrier doctor${use}`);
    return { path: out, checks, config: loaded.config, start: false };
  }

  const ready = await deps.readyEpics(loaded.config);
  const waiting = Object.entries(ready).map(([repo, count]) => `${repo}: ${count === undefined ? 'could not read' : `${count} epic${count === 1 ? '' : 's'} marked ready`}`);
  ui.note(waiting.join('\n'), 'Waiting for Carrier');
  const start = interactive && (await ui.confirm('Start Carrier now? (Ctrl+C stops it)'));
  if (!start) ui.outro(`Ready. Start it with: carrier${use}\nThen mark an epic of ${repos[0]} as solve:epic:ready.`); // otherwise the caller carries on in the same frame
  return { path: out, checks, config: loaded.config, start };
}
