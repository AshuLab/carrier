import { optionNamePattern } from '../../config/providers.ts';
import { repoNamePattern } from '../../config/schema.ts';
import { parseHarnessModel, parseIdentity, parseProvider, type Role } from './build-config.ts';
import type { InitFlags } from './flags.ts';
import { effortProblem } from './questions/effort.ts';
import { personaProblem } from './questions/persona.ts';
import { camel, extraSlots, roleFlagSuffixes, roleName, roleSlots, type RoleSlot } from './roles.ts';

/** A step of a role's failover chain; a step with no model uses the account's, then the harness's. */
export type FailoverStep = { provider: string; model?: string };

const text = (flags: InitFlags, slot: RoleSlot, suffix: string) => (flags as Record<string, unknown>)[camel(`${slot}${suffix}`)] as string | undefined;
const stepTexts = (flags: InitFlags, slot: RoleSlot) => ((flags as Record<string, unknown>)[camel(`${slot}-failover`)] ?? []) as string[];

/** An extra reviewer exists when any flag names its slot. */
export const named = (flags: InitFlags, slot: RoleSlot) => roleFlagSuffixes.some((suffix) => text(flags, slot, suffix) !== undefined) || stepTexts(flags, slot).length > 0;

/** The wizard offers two failover steps. */
const maxSteps = 2;

const problemOf = (flag: string, parse: () => unknown) => {
  try {
    parse();
    return undefined;
  } catch (error) {
    return `${flag}: ${error instanceof Error ? error.message : String(error)}`;
  }
};

/** `<account>[:<model>]` split at the first colon, since an account never holds one and a model may (`llama3:8b`); or what is wrong with it. */
function parseStep(flag: string, step: string): { step: FailoverStep } | { problem: string } {
  const colon = step.indexOf(':');
  const account = colon < 0 ? step : step.slice(0, colon);
  const model = colon < 0 ? undefined : step.slice(colon + 1);
  if (!optionNamePattern.test(account)) return { problem: `${flag} "${step}": expected <account>[:<model>], with the account a lowercase name of letters, digits and hyphens` };
  if (model !== undefined && model.trim() === '') return { problem: `${flag} "${step}": a colon needs a model after it, or leave the colon out to use the account's model` };
  return { step: { provider: account, ...(model !== undefined && { model }) } };
}

/** The steps a role's failover flags name, in the order given; nothing for a role with none. Flags that do not parse are `flagProblem`'s, which runs first. */
export function failoverSteps(flags: InitFlags, slot: RoleSlot): FailoverStep[] | undefined {
  const parsed = stepTexts(flags, slot).map((step) => parseStep(`--${slot}-failover`, step));
  const steps = parsed.flatMap((one) => ('step' in one ? [one.step] : []));
  return steps.length > 0 ? steps : undefined;
}

/** The first thing wrong in the flags that needs no look at the machine, naming its flag; undefined when there is nothing. A value that does not parse, a level that is not one of the five, an orchestrator profile that is neither `forge:<agent>` nor `gh`, a repo that is not `owner/name`, a failover step that is malformed, a third or a repeated one, an extra reviewer's flag with none for the one before it, and `--yes` with no `--repo`. */
export function flagProblem(flags: InitFlags): string | undefined {
  for (const slot of roleSlots) {
    const [agent, profile, provider, effort, personaName, personaPrompt] = roleFlagSuffixes.map((suffix) => text(flags, slot, suffix));
    const found =
      (agent === undefined ? undefined : problemOf(`--${slot}`, () => parseHarnessModel(agent))) ??
      (profile === undefined ? undefined : problemOf(`--${slot}-profile`, () => parseIdentity(profile))) ??
      (provider === undefined ? undefined : problemOf(`--${slot}-provider`, () => parseProvider(provider))) ??
      (effort === undefined ? undefined : effortProblem(slot, effort)) ??
      (personaName === undefined ? undefined : personaProblem(slot, 'name', personaName)) ??
      (personaPrompt === undefined ? undefined : personaProblem(slot, 'prompt', personaPrompt));
    if (found !== undefined) return found;

    const flag = `--${slot}-failover`;
    const given = stepTexts(flags, slot);
    if (given.length > maxSteps) return `${flag}: at most ${maxSteps} steps, ${given.length} were given`;
    const steps: FailoverStep[] = [];
    for (const step of given) {
      const parsed = parseStep(flag, step);
      if ('problem' in parsed) return parsed.problem;
      if (steps.some((earlier) => earlier.provider === parsed.step.provider && earlier.model === parsed.step.model)) return `${flag} "${step}": it repeats an earlier step, so it would move nowhere`;
      steps.push(parsed.step);
    }
  }
  // The extra reviewers are a list: a flag for one with none for the one before it has no place to go.
  for (const [i, slot] of extraSlots.entries()) {
    if (i > 0 && named(flags, slot) && !named(flags, extraSlots[i - 1]!)) return `--${slot}: there is no place for ${slot} without --${extraSlots[i - 1]}, since the extra reviewers are a list in order`;
  }
  const orchestrator = flags.orchestratorProfile === undefined ? undefined : problemOf('--orchestrator-profile', () => parseIdentity(flags.orchestratorProfile!));
  if (orchestrator !== undefined) return orchestrator;
  const bad = flags.repo?.find((name) => !repoNamePattern.test(name));
  if (bad !== undefined) return `--repo "${bad}": must be owner/name`;
  if (flags.yes && (flags.repo === undefined || flags.repo.length === 0)) return '--yes asks nothing, so it needs --repo <owner/name> (repeat it for several repos)';
  return undefined;
}

/** What is wrong with the failover flags once the accounts are known: a step whose account is not among them, or that is a role's own account and model (a step with no model never is). `own` has the roles whose account and model are already settled, such as by `--<role>`. */
export function failoverProblem(flags: InitFlags, accounts: readonly string[], own: Partial<Record<RoleSlot, Pick<Role, 'provider' | 'model'>>>): string | undefined {
  for (const slot of roleSlots) {
    for (const given of stepTexts(flags, slot)) {
      const parsed = parseStep(`--${slot}-failover`, given);
      if ('problem' in parsed) return parsed.problem;
      const { step } = parsed;
      if (!accounts.includes(step.provider)) return `--${slot}-failover "${given}": there is no account named "${step.provider}" (accounts: ${accounts.join(', ')})`;
      const mine = own[slot];
      if (step.model !== undefined && mine !== undefined && step.provider === mine.provider && step.model === mine.model) return `--${slot}-failover "${given}": that is the ${roleName(slot)}'s own account and model, so it would move nowhere`;
    }
  }
  return undefined;
}
