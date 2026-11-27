import { optionNamePattern } from '../../config/providers.ts';
import { repoNamePattern, slug } from '../../config/schema.ts';
import { parseHarnessModel, parseIdentity, parseProvider, type Role } from './build-config.ts';
import type { InitFlags } from './flags.ts';
import { effortProblem } from './questions/effort.ts';
import { nameProblem } from './questions/extra.ts';
import { personaProblem } from './questions/persona.ts';
import { camel, extraFlagSuffixes, roleFlagSuffixes, maxExtraReviewers, roleName, roleSlots, type Block, type RoleSlot } from './roles.ts';

/** A step of a role's failover chain; a step with no model uses the account's, then the harness's. */
export type FailoverStep = { provider: string; model?: string };

const text = (flags: InitFlags, slot: Block, suffix: string) => (flags as Record<string, unknown>)[camel(`${slot}${suffix}`)] as string | undefined;
const stepTexts = (flags: InitFlags, slot: Block) => ((flags as Record<string, unknown>)[camel(`${slot}-failover`)] ?? []) as string[];

/** A role is asked for when any flag names its slot. */
export const named = (flags: InitFlags, slot: Block) => roleFlagSuffixes.some((suffix) => text(flags, slot, suffix) !== undefined) || stepTexts(flags, slot).length > 0;

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

/** The steps a failover flag's texts name, in the order given; nothing when there are none. Texts that do not parse are `stepsProblem`'s, which runs first. */
export function stepsOf(flag: string, texts: string[]): FailoverStep[] | undefined {
  const steps = texts.flatMap((step) => {
    const parsed = parseStep(flag, step);
    return 'step' in parsed ? [parsed.step] : [];
  });
  return steps.length > 0 ? steps : undefined;
}

/** The steps a role's failover flags name, in the order given; nothing for a role with none. */
export const failoverSteps = (flags: InitFlags, slot: Block) => stepsOf(`--${slot}-failover`, stepTexts(flags, slot));

/** What is wrong with the texts of a failover flag: more than two, one that is malformed or one that repeats an earlier step; undefined when there is nothing. */
function stepsProblem(flag: string, given: string[]): string | undefined {
  if (given.length > maxSteps) return `${flag}: at most ${maxSteps} steps, ${given.length} were given`;
  const steps: FailoverStep[] = [];
  for (const step of given) {
    const parsed = parseStep(flag, step);
    if ('problem' in parsed) return parsed.problem;
    if (steps.some((earlier) => earlier.provider === parsed.step.provider && earlier.model === parsed.step.model)) return `${flag} "${step}": it repeats an earlier step, so it would move nowhere`;
    steps.push(parsed.step);
  }
  return undefined;
}

/** One extra reviewer as its flags name it: `name` is what `--extra-reviewer` gave (trimmed), `agent` its `<harness>:<model>`, and the rest what a field flag set, as the flag's own text. */
export type ExtraFlags = { name: string; agent: string; type?: string; profile?: string; provider?: string; effort?: string; personaName?: string; personaPrompt?: string; failover: string[] };

const typeProblem = (flag: string, type: string) => {
  const parsed = slug.safeParse(type);
  return parsed.success ? undefined : `${flag} "${type}": ${parsed.error.issues[0]?.message}`;
};

const extraTexts = (flags: InitFlags, suffix: string) => ((flags as Record<string, unknown>)[camel(`extra-reviewer${suffix}`)] ?? []) as string[];

/** A reviewer's flag text `<name>=<value>` at its first `=`, so a name holds no `=`; or what is wrong with it. */
function splitNamed(flag: string, text: string): { name: string; value: string } | { problem: string } {
  const at = text.indexOf('=');
  return at < 0 ? { problem: `${flag} "${text}": expected "<name>=<value>"` } : { name: text.slice(0, at), value: text.slice(at + 1) };
}

const sameName = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();

/** The extra reviewers the flags create, in the order given, or the first thing wrong with them that needs no look at the machine, naming its flag: a fourth reviewer, a name that is blank, over 40 characters, with a line break or taken (without regard to case), a text with no `=`, a field flag that names no reviewer or names one twice, and a value that does not parse. */
export function parseExtras(flags: InitFlags): { reviewers: ExtraFlags[]; problem?: string } {
  const reviewers: ExtraFlags[] = [];
  const problem = (message: string) => ({ reviewers: [], problem: message });
  const created = extraTexts(flags, '');
  if (created.length > maxExtraReviewers) return problem(`--extra-reviewer: at most ${maxExtraReviewers} extra reviewers, ${created.length} were given`);
  for (const text of created) {
    const split = splitNamed('--extra-reviewer', text);
    if ('problem' in split) return problem(split.problem);
    const bad = nameProblem(split.name, reviewers.map((one) => one.name));
    if (bad !== undefined) return problem(`--extra-reviewer "${text}": ${bad}`);
    const agent = problemOf('--extra-reviewer', () => parseHarnessModel(split.value));
    if (agent !== undefined) return problem(agent);
    reviewers.push({ name: split.name.trim(), agent: split.value, failover: [] });
  }
  const fields = { '-profile': 'profile', '-provider': 'provider', '-effort': 'effort', '-type': 'type', '-persona-name': 'personaName', '-persona-prompt': 'personaPrompt' } as const;
  for (const suffix of extraFlagSuffixes) {
    const flag = `--extra-reviewer${suffix}`;
    for (const text of extraTexts(flags, suffix)) {
      const split = splitNamed(flag, text);
      if ('problem' in split) return problem(split.problem);
      const reviewer = reviewers.find((one) => sameName(one.name, split.name.trim()));
      if (reviewer === undefined) return problem(`${flag} "${text}": no --extra-reviewer is named "${split.name}"`);
      if (suffix === '-failover') {
        reviewer.failover.push(split.value);
        continue;
      }
      const field = fields[suffix];
      if (reviewer[field] !== undefined) return problem(`${flag} "${text}": "${reviewer.name}" already has one`);
      const wrong =
        suffix === '-profile' ? problemOf(flag, () => parseIdentity(split.value))
        : suffix === '-provider' ? problemOf(flag, () => parseProvider(split.value))
        : suffix === '-effort' ? effortProblem('extra-reviewer', split.value)
        : suffix === '-type' ? typeProblem(flag, split.value)
        : personaProblem('extra-reviewer', suffix === '-persona-name' ? 'name' : 'prompt', split.value);
      if (wrong !== undefined) return problem(wrong);
      reviewer[field] = split.value;
    }
  }
  for (const reviewer of reviewers) {
    const wrong = stepsProblem('--extra-reviewer-failover', reviewer.failover);
    if (wrong !== undefined) return problem(wrong);
  }
  return { reviewers };
}

/** The first thing wrong in the flags that needs no look at the machine, naming its flag; undefined when there is nothing. A value that does not parse, a level that is not one of the five, an orchestrator profile that is neither `forge:<agent>` nor `gh`, a repo that is not `owner/name`, a failover step that is malformed, a third or a repeated one, whatever is wrong with the extra reviewers' flags (`parseExtras`), and `--yes` with no `--repo`. */
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

    const steps = stepsProblem(`--${slot}-failover`, stepTexts(flags, slot));
    if (steps !== undefined) return steps;
  }
  const extras = parseExtras(flags).problem;
  if (extras !== undefined) return extras;
  const orchestrator = flags.orchestratorProfile === undefined ? undefined : problemOf('--orchestrator-profile', () => parseIdentity(flags.orchestratorProfile!));
  if (orchestrator !== undefined) return orchestrator;
  const bad = flags.repo?.find((name) => !repoNamePattern.test(name));
  if (bad !== undefined) return `--repo "${bad}": must be owner/name`;
  if (flags.yes && (flags.repo === undefined || flags.repo.length === 0)) return '--yes asks nothing, so it needs --repo <owner/name> (repeat it for several repos)';
  return undefined;
}

/** What is wrong with a failover step's text once the accounts are known: an account that is not among them, or that is the owner's own account and model (a step with no model never is); `who` is how the message calls the owner. */
function unknownStep(flag: string, given: string, accounts: readonly string[], who: string, mine?: Pick<Role, 'provider' | 'model'>): string | undefined {
  const parsed = parseStep(flag, given);
  if ('problem' in parsed) return parsed.problem;
  const { step } = parsed;
  if (!accounts.includes(step.provider)) return `${flag} "${given}": there is no account named "${step.provider}" (accounts: ${accounts.join(', ')})`;
  if (step.model !== undefined && mine !== undefined && step.provider === mine.provider && step.model === mine.model) return `${flag} "${given}": that is the ${who}'s own account and model, so it would move nowhere`;
  return undefined;
}

/** What is wrong with the failover flags once the accounts are known: a step whose account is not among them, or that is a role's own account and model (a step with no model never is). `own` has the roles whose account and model are already settled, such as by `--<role>`. */
export function failoverProblem(flags: InitFlags, accounts: readonly string[], own: Partial<Record<RoleSlot, Pick<Role, 'provider' | 'model'>>>): string | undefined {
  for (const slot of roleSlots) {
    for (const given of stepTexts(flags, slot)) {
      const found = unknownStep(`--${slot}-failover`, given, accounts, roleName(slot), own[slot]);
      if (found !== undefined) return found;
    }
  }
  return undefined;
}

/** The same for the extra reviewers' failover flags; `own[i]` is the account and model of `reviewers[i]`. */
export function extraFailoverProblem(reviewers: readonly ExtraFlags[], accounts: readonly string[], own: readonly Pick<Role, 'provider' | 'model'>[]): string | undefined {
  for (const [i, reviewer] of reviewers.entries()) {
    for (const given of reviewer.failover) {
      const found = unknownStep('--extra-reviewer-failover', given, accounts, `extra reviewer ${reviewer.name}`, own[i]);
      if (found !== undefined) return found;
    }
  }
  return undefined;
}
