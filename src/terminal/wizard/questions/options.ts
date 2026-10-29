import { basename } from 'node:path';
import { optionNamePattern } from '../../../config/schema.ts';
import type { LocalProvider } from '../../../harnesses/local.ts';
import type { HarnessName } from '../../../harnesses/names.ts';
import type { Ui } from '../../prompts/types.ts';
import { parseHarnessModel, parseProvider, type AIProvider, type Failover } from '../build-config.ts';
import type { InitDeps } from '../deps.ts';
import { providerLine } from '../summary.ts';
import { askAIProvider } from './agent.ts';

export type Providers = Record<string, AIProvider>;
type RoleName = 'author' | 'reviewer' | 'lead reviewer';

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

/** Pure AI providers section: CLI, config folder, and local provider. No models. */
export async function askProviders(ui: Ui, start: Providers, installed: readonly HarnessName[], locals: Partial<Record<LocalProvider, string[]>>, deps: InitDeps): Promise<Providers> {
  const there = Object.entries(start).map(([name, provider]) => `${name}: ${providerLine(provider)}`);
  ui.note(['Your AI accounts and local model servers (Claude Code, Codex, Antigravity). Each role will pick one.', ...(there.length > 0 ? ['', 'Already there:', ...there] : [])].join('\n'), 'AI Providers');
  let providers = start;
  while (Object.keys(providers).length === 0 || (await ui.confirm('Add another AI provider?'))) {
    const provider = await askAIProvider(ui, installed, Object.values(providers).map((p) => p.harness), locals, deps);
    const raw = await ui.text({
      message: 'Name of this provider',
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

export async function askRoleProvider(ui: Ui, role: RoleName, providers: Providers, current?: string, other?: string): Promise<string> {
  const names = Object.keys(providers);
  if (names.length === 1) return names[0]!;
  return ui.select({
    message: `Which AI provider runs the ${role}?`,
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

/** With two or more providers: whether to move a role to another provider when its credits run out or errors occur, and in which order. */
export async function askFailover(ui: Ui, providers: Providers): Promise<Failover | undefined> {
  const names = Object.keys(providers);
  if (names.length < 2 || !(await ui.confirm('Turn failover on? A role that runs out of credits then moves to the next provider you list, so its code can reach another provider.'))) return undefined;
  const order: string[] = [];
  while (order.length < names.length) {
    const pick = await ui.select({
      message: `Failover order: which provider goes ${order.length === 0 ? 'first' : 'next'}?`,
      options: [
        ...names.filter((name) => !order.includes(name)).map((name) => ({ value: name, label: name, hint: providerLine(providers[name]!) })),
        ...(order.length > 0 ? [{ value: done, label: 'That is all' }] : []),
      ],
    });
    if (pick === done) break;
    order.push(pick);
  }
  return { enabled: true, triggers: ['usage_limit', 'rate_limit', 'service_down'], default: order };
}
