import type { LocalProvider } from '../../../harnesses/local.ts';
import type { Ui } from '../../prompts/types.ts';
import { parseIdentity, type Effort, type Role } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import type { InitFlags } from '../flags.ts';
import type { ForgeAgent } from '../forge-registry.ts';
import { roleBlurb, roleKey, roleName, type Block } from '../roles.ts';
import { askModel, defaultsFor } from './agent.ts';
import { askEffort } from './effort.ts';
import { askIdentity } from './identity.ts';
import { askRoleFailover, askRoleProvider, type Providers, type Steps } from './options.ts';
import { askPersona } from './persona.ts';
import { failoverProblem, failoverSteps, stepsOf, type ExtraFlags } from '../validate-flags.ts';

/** What every role block shares: the terminal, the machine and what was answered before any role. */
export type RoleContext = {
  ui: Ui;
  deps: InitDeps;
  flags: InitFlags;
  interactive: boolean;
  /** `--author` and `--reviewer` both given: the file's failover is kept and none is asked. */
  unattended: boolean;
  providers: Providers;
  locals: Partial<Record<LocalProvider, string[]>>;
  forge: { agents: ForgeAgent[] };
  readForge: () => void;
  login: string | undefined;
  /** What a note already said in this run, so a note meant for the whole run is printed once, not in every block. */
  said: { failover: boolean };
};

/** Where a block starts: the file's answers for the slot (edit mode), the role asked just before it, and the account and model a `--<role>` flag named. `given` is what the flags of an extra reviewer answered; a slot's flags are read from the context. */
export type RoleStart = { given?: ExtraFlags; from?: Role; steps?: Steps; after?: Role; flagged?: { provider: string; model: string }; /** What the block's box is headed with: an extra reviewer's name; a slot's is its own name. */ title?: string };

/** One role, closed: its GitHub profile, its account, whether to change the model and effort it starts on, whether to customise the persona, and its failover. The same piece serves every slot; with every default accepted it costs the profile and the account and Enter for the rest. */
export async function askRole(ctx: RoleContext, slot: Block, { given, from, steps, after, flagged, title }: RoleStart = {}): Promise<{ role: Role; failover?: Steps }> {
  const { ui, deps, interactive } = ctx;
  const name = roleName(slot);
  const key = roleKey(slot);
  const flag = (suffix: string) => {
    const value = (ctx.flags as Record<string, unknown>)[`${key}${suffix}`];
    return typeof value === 'string' ? value : undefined;
  };
  const [profileFlag, effortFlag] = given ? [given.profile, given.effort] : [flag('Profile'), flag('Effort')];

  if (interactive && !(profileFlag && flagged)) ui.note(roleBlurb(slot), title ?? `${name[0]!.toUpperCase()}${name.slice(1)}`);
  const identity = profileFlag ? parseIdentity(profileFlag) : await askIdentity(ui, slot, ctx.forge, ctx.readForge, ctx.login, after?.identity, deps, interactive, from?.identity);
  const provider = flagged?.provider ?? (await askRoleProvider(ui, slot, ctx.providers, from?.provider, after?.provider));
  const account = ctx.providers[provider]!;

  // The file's model and effort when the account is still the file's, else what the harness starts on.
  const start = from?.provider === provider ? { model: from.model, effort: from.effort } : await defaultsFor(ui, account.harness, account.provider, ctx.locals, deps);
  let model = flagged?.model ?? start.model;
  let effort: Effort | undefined = start.effort;
  if (effortFlag !== undefined) effort = await askEffort(ui, slot, effortFlag, interactive);
  const answered = flagged !== undefined || effortFlag !== undefined || !interactive;
  if (!answered && (model === undefined || (await ui.confirm(`Model and effort: ${model}${effort ? ` at ${effort}` : ''}, change ${effort ? 'them' : 'it'}?`, false)))) {
    model = await askModel(ui, account.harness, account.provider, ctx.locals, deps, name, model);
    effort = await askEffort(ui, slot, undefined, true, effort);
  }
  model ??= await askModel(ui, account.harness, account.provider, ctx.locals, deps, name);

  const persona = await askPersona(ui, slot, given ? { name: given.personaName, prompt: given.personaPrompt } : { name: flag('PersonaName'), prompt: flag('PersonaPrompt') }, interactive, from?.persona);
  const role: Role = { identity, provider, model, ...(effort && { effort }), ...(persona && { persona }) };
  // Failover flags answer the question: the role is not asked, and the steps are the ones given, in order. An extra reviewer's steps were checked against the accounts before the first question (`extraFailoverProblem`).
  const flagSteps = given ? stepsOf('--extra-reviewer-failover', given.failover) : failoverSteps(ctx.flags, slot);
  if (flagSteps !== undefined && given === undefined) {
    const problem = failoverProblem(ctx.flags, Object.keys(ctx.providers), { [slot]: role });
    if (problem !== undefined) throw new Error(problem);
  }
  const failover = flagSteps ?? (interactive && !ctx.unattended ? await askRoleFailover(ui, ctx.providers, slot, role, ctx.locals, deps, steps, ctx.said) : steps);
  return { role, ...(failover && { failover }) };
}
