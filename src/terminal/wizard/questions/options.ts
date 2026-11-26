import { basename } from 'node:path';
import { styleText } from 'node:util';
import { optionNamePattern } from '../../../config/providers.ts';
import type { LocalProvider } from '../../../harnesses/local.ts';
import type { HarnessName } from '../../../harnesses/names.ts';
import type { Ui } from '../../prompts/types.ts';
import { parseHarnessModel, parseProvider, type AIProvider, type Role } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import { roleName, type RoleSlot } from '../roles.ts';
import { providerLine, stepsLine } from '../summary.ts';
import { askAIProvider, askModel } from './agent.ts';

export type Providers = Record<string, AIProvider>;
export type Steps = { provider: string; model?: string }[];

const uniqueName = (items: Record<string, unknown>, base: string) => {
  let name = base;
  for (let n = 2; name in items; n += 1) name = `${base}-${n}`;
  return name;
};

/** Turn a user-typed name into a valid option code: lowercase, hyphens instead of spaces/symbols, no leading/trailing hyphens. */
export function normalizeOptionName(raw: string): string {
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/, '');
}

export function suggestProviderName(providers: Providers, provider: AIProvider) {
  const folder = (provider.configDir ? basename(provider.configDir) : '').replace(/^\.+/, '');
  const raw = folder === '' ? provider.harness : folder.startsWith(provider.harness) ? folder : `${provider.harness}-${folder}`;
  const slug = normalizeOptionName(raw).slice(0, 30);
  return uniqueName(providers, optionNamePattern.test(slug) ? slug : provider.harness);
}

/** The accounts Carrier starts from: the ones `providers.json` already holds, untouched, plus one per agent CLI found that has none, under the harness's name. Never replaces and never removes. */
export function mergeAccounts(held: Providers, harnesses: readonly HarnessName[]): Providers {
  const merged = { ...held };
  for (const harness of harnesses) if (!Object.values(held).some((account) => account.harness === harness)) merged[uniqueName(merged, harness)] = { harness };
  return merged;
}

/** The accounts section: CLI, config folder, and local provider. No models. `held` says which of `start` were there before this run. */
export async function askProviders(ui: Ui, start: Providers, installed: readonly HarnessName[], locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps, held: readonly string[]): Promise<Providers> {
  const line = (name: string) => `${name}: ${providerLine(start[name]!)}`;
  const added = Object.keys(start).filter((name) => !held.includes(name));
  const intro = [
    ...(held.length > 0 ? ['Your accounts, kept as they are:', ...held.map(line), ''] : []),
    ...(added.length > 0 ? [`${styleText('bold', added.length === 1 ? '1 account was added' : `${added.length} accounts were added`)} for the agent CLIs found on this Mac that had none, using the login each CLI already has:`, ...added.map(line), ''] : []),
    'Next you choose which account each role uses; roles can share one.',
    'Add another account only if you want a different login (a second Claude account, say) or a local model server.',
  ];
  ui.note(intro.join('\n'), 'AI accounts');
  let providers = start;
  while (Object.keys(providers).length === 0 || (await ui.confirm('Add another account?', false))) {
    const provider = await askAIProvider(ui, installed, Object.values(providers).map((p) => p.harness), locals, deps);
    const raw = await ui.text({
      message: 'Name of this account',
      defaultValue: suggestProviderName(providers, provider),
      validate: (v) => {
        const slug = normalizeOptionName(v);
        if (!optionNamePattern.test(slug)) return 'A name starting with a letter: letters, digits and hyphens, up to 40 characters';
        if (slug in providers) return 'Another provider has this name';
        return undefined;
      },
    });
    const name = normalizeOptionName(raw);
    providers = { ...providers, [name]: provider };
  }
  return providers;
}

export async function askRoleProvider(ui: Ui, slot: RoleSlot, providers: Providers, current?: string, other?: string): Promise<string> {
  const names = Object.keys(providers);
  if (names.length === 1) return names[0]!;
  return ui.select({
    message: `Which account runs the ${roleName(slot)}?`,
    options: names.map((name) => ({ value: name, label: name, hint: providerLine(providers[name]!) })),
    initialValue: [current, names.find((name) => name !== other)].find((name) => name !== undefined && name in providers) ?? names[0]!,
  });
}

/** The provider and model a `--author` or `--reviewer` flag declares: reuses an existing matching provider, or adds a new one. */
export function declareFlaggedProvider(providers: Providers, role: string, flag: string, providerFlag?: string): { providers: Providers; providerName: string; model: string } {
  const { harness, model } = parseHarnessModel(flag);
  const localProvider = providerFlag ? parseProvider(providerFlag) : undefined;
  const existing = Object.keys(providers).find((name) => providers[name]!.harness === harness && providers[name]!.provider === localProvider);
  if (existing !== undefined) return { providers, providerName: existing, model };
  const name = uniqueName(providers, harness in providers ? `${harness}-${role}` : harness);
  return { providers: { ...providers, [name]: { harness, ...(localProvider && { provider: localProvider }) } }, providerName: name, model };
}

const done = '\0done';
const ordinal = ['first', 'second'];

/** A role's failover, inside its block: with two or more accounts, up to two steps, each an account and a model, that the role moves through when its credits run out or errors occur; a step may not repeat another or be the role's own account and model. With fewer accounts there is nowhere to move: one line says so and nothing is asked. A failover the file has is offered first ("keep the failover you have?"). */
export async function askRoleFailover(ui: Ui, providers: Providers, slot: RoleSlot, own: Pick<Role, 'provider' | 'model'>, locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps, current?: Steps): Promise<Steps | undefined> {
  const role = roleName(slot);
  const names = Object.keys(providers);
  if (names.length < 2) {
    ui.note(`Failover needs a second account, so the ${role} has none.`, `Failover for the ${role}`);
    return undefined;
  }
  if (current !== undefined && current.length > 0 && (await ui.confirm(`Keep the failover you have? ${role}: ${stepsLine(current)}`, true))) return current;
  if (!(await ui.confirm(`Turn failover on for the ${role}? When it runs out of credits it moves to the steps you list, each an account and a model.`, false))) return undefined;
  const steps: { provider: string; model: string }[] = [];
  while (steps.length < ordinal.length) {
    const pick = await ui.select({
      message: `Failover for the ${role}: which account goes ${ordinal[steps.length]}?`,
      options: [
        ...names.map((name) => ({ value: name, label: name, hint: providerLine(providers[name]!) })),
        ...(steps.length > 0 ? [{ value: done, label: 'That is all' }] : []),
      ],
    });
    if (pick === done) break;
    const model = await askModel(ui, providers[pick]!.harness, providers[pick]!.provider, locals, deps, `${role}'s ${ordinal[steps.length]} failover step`);
    if ([own, ...steps].some((step) => step.provider === pick && step.model === model)) ui.warn(`${pick} · ${model} is already the ${role}'s own or an earlier step, so it would move nowhere: pick another.`);
    else steps.push({ provider: pick, model });
  }
  return steps.length > 0 ? steps : undefined;
}
